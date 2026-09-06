#!/usr/bin/env bash
#
# Copyright (C) 2026 Fernando Aporta Franco — Licensed under AGPL-3.0 (see LICENSE).
# Free software with ABSOLUTELY NO WARRANTY; redistribute under the AGPL-3.0 terms.
#
# tests/run.sh — behavioural tests for research.sh and healthcheck.sh.
#
#   bash tests/run.sh
#
# Requirements: bash and jq (the same two things research.sh needs). No network.
#
# What it checks:
#   1. `bash -n` on the three shipped shell scripts.
#   2. research.sh against a STRICT mock CLI (tests/bin/notebooklm): the count-before/after
#      proof, polling until nothing is "preparing", the KB_POLL_TIMEOUT warning, the JSON
#      envelope tolerance, deep-mode env export, argument validation, and — the regression
#      that let a broken wrapper ship — that the CLI is invoked with the shape
#      notebooklm-py 0.8.2 accepts (`-n <id>`, `--mode fast|deep`, `--` before the query).
#   3. healthcheck.sh against the same mock: required config, healthy path, auth-down alert
#      + stamp, cooldown mute, the re-auth cascade order, non-auth failures, recovery, and
#      the AUTH_REQUIRED envelope.
#   4. Optional, only when a real notebooklm-py CLI is available — set
#      NOTEBOOKLM_REAL_CLI=/path/to/venv/bin/notebooklm, or have `notebooklm` on PATH before
#      this script runs: the exact commands the scripts issue must be REJECTED ON AUTH
#      (rc=1, "Not logged in." / AUTH_REQUIRED) and never on argument parsing (rc=2).
#      These run with an empty HOME, so your real profile is never touched or used.
#
# Exit code: 0 when every executed test passes; 1 otherwise. Prints the counts at the end.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESEARCH="$ROOT/research.sh"
HC="$ROOT/healthcheck.sh"

# Detect a real CLI BEFORE the mock is put on PATH.
REAL="${NOTEBOOKLM_REAL_CLI:-$(command -v notebooklm 2>/dev/null || true)}"
case "$REAL" in "$ROOT/tests/bin/"*) REAL="" ;; esac

command -v jq >/dev/null 2>&1 || { echo "tests/run.sh: jq is required" >&2; exit 1; }

export PATH="$ROOT/tests/bin:$PATH"          # `notebooklm` now resolves to the strict mock
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT

pass=0; fail=0; skip=0
ok()   { pass=$((pass+1)); printf 'PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }
note() { skip=$((skip+1)); printf 'SKIP  %s\n' "$1"; }
fresh() { d="$(mktemp -d "$TMPROOT/XXXXXX")"; export MOCK_DIR="$d"; }   # new mock state
kb()    { k="$(mktemp -d "$TMPROOT/kbXXXXXX")"; }                          # new KB_HOME

section() { printf '\n== %s ==\n' "$1"; }

# ---------------------------------------------------------------------------------------
section "1. syntax"
for s in "$RESEARCH" "$HC" "$ROOT/install/install.sh"; do
  if bash -n "$s" 2>"$TMPROOT/synerr"; then ok "bash -n $(basename "$s")"; else bad "bash -n $(basename "$s")" "$(cat "$TMPROOT/synerr")"; fi
done

# ---------------------------------------------------------------------------------------
section "2. research.sh (mock CLI)"
RS() { KB_POLL_INTERVAL=0 bash "$RESEARCH" "$@"; }

# R1 happy path: baseline 1 -> 3 prints 2, rc 0
fresh; printf '[{"id":"a"}]' > "$d/list.1.json"; printf '[{"id":"a"},{"id":"b"},{"id":"c"}]' > "$d/list.2.json"
out=$(RS nb1 "topic" fast 2>"$d/err"); rc=$?
[ "$rc" -eq 0 ] && [ "$(tail -1 <<<"$out")" = "2" ] && ok "R1 happy path: 1 -> 3 sources prints 2, rc 0" || bad "R1" "rc=$rc stdout='$out' $(cat "$d/err")"

# R2 CLI rc 0 but nothing imported -> rc 1
fresh; printf '[{"id":"a"}]' > "$d/list.1.json"
out=$(RS nb1 "topic" fast 2>"$d/err"); rc=$?
[ "$rc" -eq 1 ] && grep -q "no source was imported" "$d/err" && ok "R2 CLI rc 0 but nothing imported -> rc 1" || bad "R2" "rc=$rc $(cat "$d/err")"

# R3 CLI rc 1 but sources landed -> rc 0 (the exit code is not trusted either way)
fresh; printf '[]' > "$d/list.1.json"; printf '[{"id":"a","status":"ready"}]' > "$d/list.2.json"
out=$(MOCK_ADD_RC=1 RS nb1 "topic" fast 2>"$d/err"); rc=$?
[ "$rc" -eq 0 ] && [ "$(tail -1 <<<"$out")" = "1" ] && grep -q "exited with 1" "$d/err" && ok "R3 CLI rc 1 but sources landed -> rc 0" || bad "R3" "rc=$rc $(cat "$d/err")"

# R4 object-wrapped {"sources":[...]} behind a human preamble line
fresh; printf 'Matched: nb1\n{"sources":[]}' > "$d/list.1.json"; printf 'Matched: nb1\n{"sources":[{"id":"a","status":"ready"},{"id":"b","status":"ready"}]}' > "$d/list.2.json"
out=$(RS nb1 "topic" fast 2>"$d/err"); rc=$?
[ "$rc" -eq 0 ] && [ "$(tail -1 <<<"$out")" = "2" ] && ok "R4 object envelope + preamble line are normalised" || bad "R4" "rc=$rc stdout='$out'"

# R5 polls until nothing is "preparing" (accepts `state` too)
fresh; printf '[]' > "$d/list.1.json"; printf '[{"id":"a","status":"preparing"}]' > "$d/list.2.json"; printf '[{"id":"a","state":"Preparing"}]' > "$d/list.3.json"; printf '[{"id":"a","status":"ready"}]' > "$d/list.4.json"
out=$(RS nb1 "topic" fast 2>"$d/err"); rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c 'waiting: 1/1' "$d/err")" -eq 2 ] && [ "$(tail -1 <<<"$out")" = "1" ] && ok "R5 polls while a source is preparing, then reports" || bad "R5" "rc=$rc $(cat "$d/err")"

# R6 KB_POLL_TIMEOUT expiry: warns, still reports what arrived
fresh; printf '[]' > "$d/list.1.json"; printf '[{"id":"a","status":"preparing"}]' > "$d/list.2.json"
out=$(KB_POLL_TIMEOUT=1 RS nb1 "topic" fast 2>"$d/err"); rc=$?
[ "$rc" -eq 0 ] && grep -q "timed out after 1s" "$d/err" && [ "$(tail -1 <<<"$out")" = "1" ] && ok "R6 KB_POLL_TIMEOUT expiry warns and reports" || bad "R6" "rc=$rc $(cat "$d/err")"

# R7 deep exports NOTEBOOKLM_HEADLESS_REAUTH=1 for the CLI; fast does not
fresh; printf '[]' > "$d/list.1.json"; printf '[{"id":"a"}]' > "$d/list.2.json"
env -u NOTEBOOKLM_HEADLESS_REAUTH bash -c 'KB_POLL_INTERVAL=0 bash "$1" nb1 "topic" deep' _ "$RESEARCH" >/dev/null 2>&1
deep_env="$(cat "$d/env.headless" 2>/dev/null)"
fresh; printf '[]' > "$d/list.1.json"; printf '[{"id":"a"}]' > "$d/list.2.json"
env -u NOTEBOOKLM_HEADLESS_REAUTH bash -c 'KB_POLL_INTERVAL=0 bash "$1" nb1 "topic" fast' _ "$RESEARCH" >/dev/null 2>&1
fast_env="$(cat "$d/env.headless" 2>/dev/null)"
[ "$deep_env" = "1" ] && [ "$fast_env" = "unset" ] && ok "R7 deep exports NOTEBOOKLM_HEADLESS_REAUTH=1, fast leaves it unset" || bad "R7" "deep='$deep_env' fast='$fast_env'"

# R8 argument validation: invalid mode, missing args, empty query -> rc 2 + usage
fresh; printf '[]' > "$d/list.1.json"
RS nb1 "topic" medium >/dev/null 2>"$d/e1"; r1=$?; RS >/dev/null 2>"$d/e2"; r2=$?; RS nb1 "" fast >/dev/null 2>"$d/e3"; r3=$?
[ "$r1" -eq 2 ] && grep -q "mode must be" "$d/e1" && [ "$r2" -eq 2 ] && grep -q "Usage:" "$d/e2" && [ "$r3" -eq 2 ] && grep -q "must not be empty" "$d/e3" \
  && ok "R8 invalid mode / no args / empty query -> rc 2 with usage" || bad "R8" "rc=$r1/$r2/$r3"

# R9 CLI shape: the notebook goes through -n, depth through --mode, never --deep or positional id
fresh; printf '[]' > "$d/list.1.json"; printf '[{"id":"a"}]' > "$d/list.2.json"
RS nb1 "topic" deep >/dev/null 2>&1
if grep -q '^nb=nb1 mode=deep from=web import_all=1 query=topic$' "$d/add.calls" 2>/dev/null \
   && grep -q '^source list -n nb1 --json$' "$d/all.argv" && ! grep -q -- '--deep' "$d/all.argv"; then
  ok "R9 CLI invoked as notebooklm-py 0.8.2 expects (-n, --mode deep, no --deep)"
else bad "R9 CLI shape" "argv: $(tr '\n' '|' < "$d/all.argv") add: $(cat "$d/add.calls" 2>/dev/null)"; fi

# R10 a query that starts with '-' is passed literally (options are closed with --)
fresh; printf '[]' > "$d/list.1.json"; printf '[{"id":"a"}]' > "$d/list.2.json"
RS nb1 "--help" fast >/dev/null 2>&1
grep -q '^nb=nb1 mode=fast from=web import_all=1 query=--help$' "$d/add.calls" 2>/dev/null && ok "R10 query '--help' reaches the CLI as a literal query" || bad "R10" "$(cat "$d/add.calls" 2>/dev/null; cat "$d/all.argv")"

# ---------------------------------------------------------------------------------------
section "3. healthcheck.sh (mock CLI)"
# shellcheck disable=SC2120  # forwards "$@" on purpose: callers may pass extra
# healthcheck flags, even though every current case runs it bare.
HCR() { KB_HOME="$k" KB_HEALTHCHECK_NOTEBOOK=nb1 bash "$HC" "$@"; }

# H1 missing KB_HEALTHCHECK_NOTEBOOK
fresh; kb; out=$(KB_HOME="$k" bash "$HC" 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q "KB_HEALTHCHECK_NOTEBOOK" <<<"$out" && ok "H1 refuses to run without KB_HEALTHCHECK_NOTEBOOK" || bad "H1" "rc=$rc $out"

# H2 healthy -> rc 0
fresh; kb; printf '{"sources":[{"id":"a"}]}' > "$d/list.1.json"
HCR >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && grep -q "OK: NotebookLM answers" "$k/healthcheck.log" && ok "H2 healthy probe -> rc 0" || bad "H2" "rc=$rc $(cat "$k/healthcheck.log" 2>/dev/null)"

# H3 auth down, re-auth skipped, dry run -> rc 1, e-mail preview, stamp written
fresh; kb; printf '{"error": true, "code": "AUTH_ERROR", "message": "Authentication expired or invalid. Redirected to: https://accounts.google.com/x"}' > "$d/list.1.json"; echo 1 > "$d/list.rc"
out=$(HC_SKIP_REAUTH=1 HC_DRY_RUN=1 HCR 2>&1); rc=$?
[ "$rc" -eq 1 ] && grep -q -- "--- SUBJECT: \[KB\]\[ALERT\]" <<<"$out" && [ -f "$k/.hc_alert_stamp" ] && ok "H3 auth down -> alert preview + stamp, rc 1" || bad "H3" "rc=$rc $out"

# H4 cooldown: a fresh stamp mutes the alert
fresh; kb; printf '{"error": true, "code": "AUTH_ERROR"}' > "$d/list.1.json"; echo 1 > "$d/list.rc"; touch "$k/.hc_alert_stamp"
out=$(HC_SKIP_REAUTH=1 HC_DRY_RUN=1 HCR 2>&1); rc=$?
[ "$rc" -eq 1 ] && ! grep -q -- "--- SUBJECT:" <<<"$out" && grep -q "muted by cooldown" "$k/healthcheck.log" && ok "H4 cooldown mutes a repeat alert" || bad "H4" "rc=$rc $(cat "$k/healthcheck.log")"

# H5 re-auth cascade order: keepalive fails, headless re-mint recovers
fresh; kb; printf '{"error": true, "code": "AUTH_ERROR"}' > "$d/list.1.json"; echo 1 > "$d/list.rc"; printf '[]' > "$d/list.fixed.json"; touch "$d/headless_fixes"
HCR >/dev/null 2>&1; rc=$?
seq="$(tr '\n' '|' < "$d/all.argv")"
if [ "$rc" -eq 0 ] && [ -f "$d/refresh.called" ] \
   && [ "$seq" = "source list -n nb1 --json|auth refresh|source list -n nb1 --json|source list -n nb1 --json|source list -n nb1 --json|" ] \
   && grep -q "keepalive not enough -> headless re-mint" "$k/healthcheck.log" && grep -q "recovered via headless re-mint" "$k/healthcheck.log"; then
  ok "H5 cascade: probe -> auth refresh -> probe -> headless re-mint -> probe, recovers"
else bad "H5" "rc=$rc seq=$seq log=$(tr '\n' '|' < "$k/healthcheck.log")"; fi

# H6 non-auth failure -> rc 2, no alert
fresh; kb; printf 'Connection refused' > "$d/list.1.json"; echo 1 > "$d/list.rc"
HC_DRY_RUN=1 HCR >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && grep -q "NON-auth reason" "$k/healthcheck.log" && [ ! -f "$k/.hc_alert_stamp" ] && ok "H6 non-auth failure -> rc 2, no alert" || bad "H6" "rc=$rc"

# H7 recovery clears the stamp
fresh; kb; printf '[]' > "$d/list.1.json"; touch "$k/.hc_alert_stamp"
HCR >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ ! -f "$k/.hc_alert_stamp" ] && grep -q "stamp cleared" "$k/healthcheck.log" && ok "H7 recovery clears the alert stamp" || bad "H7" "rc=$rc"

# H8 the AUTH_REQUIRED envelope (missing/empty session) is an auth failure, not "NON-auth"
fresh; kb; printf '{"error": true, "code": "AUTH_REQUIRED", "message": "Auth not found. Run '"'"'notebooklm login'"'"' first."}' > "$d/list.1.json"; echo 1 > "$d/list.rc"
HC_SKIP_REAUTH=1 HC_DRY_RUN=1 HCR >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q "auth failure detected" "$k/healthcheck.log" && ok "H8 AUTH_REQUIRED envelope is classified as an auth failure" || bad "H8" "rc=$rc $(cat "$k/healthcheck.log")"

# ---------------------------------------------------------------------------------------
section "4. real CLI parse tests"
if [ -n "$REAL" ] && [ -x "$REAL" ]; then
  H="$(mktemp -d "$TMPROOT/homeXXXXXX")"
  echo "using: $REAL ($(HOME="$H" "$REAL" --version 2>/dev/null | head -1))"
  # P1 source list -n --json: auth-gated JSON envelope, not a usage error
  out=$(HOME="$H" "$REAL" source list -n nb1 --json 2>&1); rc=$?
  [ "$rc" -eq 1 ] && grep -q 'AUTH_REQUIRED' <<<"$out" && ok "P1 source list -n <id> --json -> AUTH_REQUIRED (rc 1)" || bad "P1" "rc=$rc $(head -3 <<<"$out")"
  # P2 add-research in the deep form the wrapper uses: parses, fails only on auth
  out=$(HOME="$H" "$REAL" source add-research -n nb1 --from web --import-all --mode deep -- "q" 2>&1); rc=$?
  [ "$rc" -eq 1 ] && grep -qiE 'Not logged in|AUTH_REQUIRED' <<<"$out" && ok "P2 source add-research -n ... --mode deep -- \"q\" -> auth-gated (rc 1)" || bad "P2" "rc=$rc $(head -3 <<<"$out")"
  # P3 the installer's auth probe
  HOME="$H" "$REAL" list >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 1 ] && ok "P3 notebooklm list -> auth-gated (rc 1)" || bad "P3" "rc=$rc"
  # P4 research.sh end-to-end against the real CLI: reaches auth, zero parse errors
  out=$(HOME="$H" NOTEBOOKLM_CLI="$REAL" KB_POLL_TIMEOUT=1 KB_POLL_INTERVAL=0 bash "$RESEARCH" nb1 "q" deep 2>&1); rc=$?
  if grep -qiE 'Not logged in|AUTH_REQUIRED' <<<"$out" && ! grep -qE 'unexpected extra argument|No such option|No such command' <<<"$out"; then
    ok "P4 research.sh deep reaches the auth check with no parse errors"
  else bad "P4" "rc=$rc $(grep -E 'Error|error' <<<"$out" | head -3)"; fi
  # P5 a query of '--help' must not print the CLI's help
  out=$(HOME="$H" NOTEBOOKLM_CLI="$REAL" KB_POLL_TIMEOUT=1 KB_POLL_INTERVAL=0 bash "$RESEARCH" nb1 "--help" fast 2>&1)
  ! grep -q 'Usage: notebooklm source add-research' <<<"$out" && ok "P5 query '--help' is not parsed as the CLI's --help" || bad "P5" "CLI help was printed"
else
  note "real-CLI parse tests (set NOTEBOOKLM_REAL_CLI=/path/to/venv/bin/notebooklm, or put notebooklm-py on PATH)"
fi

# ---------------------------------------------------------------------------------------
printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
