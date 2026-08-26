#!/usr/bin/env bash
#
# Copyright (C) 2026 Fernando — Licensed under AGPL-3.0 (see LICENSE).
# Free software with ABSOLUTELY NO WARRANTY; redistribute under the AGPL-3.0 terms.
#
# research.sh — feeds a NotebookLM notebook with fresh web research and then PROVES it was saved.
# ---------------------------------------------------------------------------------------
#
# Part of the "local memory + NotebookLM notebooks" second-brain starter kit.
#
# The idea: instead of burning agent tokens re-reading huge documents, you ask NotebookLM to do the
# web research and import the results as *sources* into a notebook. Then an agent queries that
# notebook cheaply and on demand. This wrapper runs the "research the web and import it" step and,
# above all, VERIFIES that the import actually happened.
#
# Why verify? The underlying CLI can exit with 0 even when nothing was imported (a network
# outage, an empty result set, silently degraded auth, an async job that never finished). So we
# do NOT trust the exit code: we re-list the notebook's sources and compare the count.
#
# Usage:
#   ./research.sh <NOTEBOOK_ID> "<query>" [fast|deep]
#
#   <NOTEBOOK_ID>   ID of the target notebook (e.g. from your notebooks.json).
#   "<query>"       Research question / topic. Quote it: it will contain spaces.
#   fast | deep     Research depth (default: fast).
#                     fast = quick pass, fewer sources, cheaper.
#                     deep = exhaustive pass; ALSO exports NOTEBOOKLM_HEADLESS_REAUTH=1 so a
#                            long-running headless job can refresh its own auth on the fly.
#
# Output:
#   - Progress / diagnostics go to STDERR (feel free to ignore or log them).
#   - The last line of STDOUT is a single integer: the number of sources added.
#     The exit code is 0 on success, and non-zero if nothing was imported or the args are invalid.
#
# Examples:
#   ./research.sh "$NOTEBOOK_ID" "latest best practices for X" fast
#   added=$(./research.sh "$NOTEBOOK_ID" "deep dive into Y architecture" deep)
#   echo "imported $added sources"
#
# Environment overrides (all optional):
#   NOTEBOOKLM_CLI       name/path of the CLI executable (default: notebooklm)
#   KB_POLL_INTERVAL     seconds between status checks (default: 5)
#   KB_POLL_TIMEOUT      stop waiting after N seconds (default: 600)
#   KB_PREPARING_STATUS  status string meaning "still importing" (default: preparing)
#
# Requirements: bash, jq and the `notebooklm` CLI on the PATH.
#
# ---- ADAPT IT HERE --------------------------------------------------------------------
# This script assumes the following CLI shape. If your CLI differs, change the two
# list_sources() invocations and the main block below to match:
#   notebooklm source add-research <NOTEBOOK_ID> "<query>" --from web --import-all [--deep]
#   notebooklm source list         <NOTEBOOK_ID> --json
# The JSON parsing tolerates both a top-level array and an object wrapping the list, and
# accepts either a `status` or `state` field per source, so minor schema differences don't matter.
# ---------------------------------------------------------------------------------------

set -euo pipefail

# ---- configuration (env override) -----------------------------------------------------
CLI="${NOTEBOOKLM_CLI:-notebooklm}"
POLL_INTERVAL="${KB_POLL_INTERVAL:-5}"        # seconds between "still preparing?" checks
POLL_TIMEOUT="${KB_POLL_TIMEOUT:-600}"        # stop waiting after this many seconds
PREPARING_STATUS="${KB_PREPARING_STATUS:-preparing}"

# ---- usage ----------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
Usage: research.sh <NOTEBOOK_ID> "<query>" [fast|deep]

  <NOTEBOOK_ID>   id of the target notebook
  "<query>"       research topic (quote it)
  fast | deep     research depth (default: fast; deep also enables headless re-auth)

Prints the number of sources added to STDOUT. Diagnostics go to STDERR.
EOF
  exit 2
}

# ---- argument parsing -----------------------------------------------------------------
[ "$#" -ge 2 ] || usage
NOTEBOOK_ID="$1"
QUERY="$2"
MODE="${3:-fast}"

case "$MODE" in
  fast|deep) ;;
  *) echo "error: mode must be 'fast' or 'deep' (got '$MODE')" >&2; usage ;;
esac

# ---- preflight checks -----------------------------------------------------------------
command -v jq  >/dev/null 2>&1 || { echo "error: 'jq' is required but not found on the PATH" >&2; exit 1; }
command -v "$CLI" >/dev/null 2>&1 || { echo "error: '$CLI' not found on the PATH (set NOTEBOOKLM_CLI)" >&2; exit 1; }

# Deep research can be a long headless job; let it refresh its own auth if the session
# expires mid-run instead of failing halfway through.
if [ "$MODE" = "deep" ]; then
  export NOTEBOOKLM_HEADLESS_REAUTH=1
fi

# Extra flags passed to `source add-research` depending on depth.
RESEARCH_FLAGS=(--from web --import-all)
if [ "$MODE" = "deep" ]; then
  RESEARCH_FLAGS+=(--deep)
fi

# ---- JSON helpers ---------------------------------------------------------------------
# The CLI may emit a human-readable preamble (e.g. a line like "Matched: <notebook>")
# before the JSON payload. Discard everything up to the first line starting with '[' or
# '{' so jq only sees valid JSON.
strip_preamble() {
  sed -n '/^[[:space:]]*[[{]/,$p'
}

# Normalize whatever the CLI returns into a flat JSON array of source objects, whether it
# hands back a bare array or an object wrapping the list under a common key.
JQ_NORMALIZE='(if type=="array" then . else (.sources // .items // .data // []) end)'

# list_sources: prints the notebook's sources as a compact JSON array (never fails the
# script: returns "[]" on any error so the caller decides what an empty list means).
list_sources() {
  local raw
  raw="$("$CLI" source list "$NOTEBOOK_ID" --json 2>/dev/null | strip_preamble)" || true
  if [ -z "$raw" ]; then
    printf '[]'
    return 0
  fi
  printf '%s' "$raw" | jq -c "$JQ_NORMALIZE" 2>/dev/null || printf '[]'
}

# count_total <json-array> -> number of sources
count_total() {
  printf '%s' "$1" | jq 'length'
}

# count_preparing <json-array> -> number of sources still importing (case-insensitive,
# comparing a `status` or `state` field against $PREPARING_STATUS).
count_preparing() {
  printf '%s' "$1" | jq --arg s "$PREPARING_STATUS" \
    '[ .[] | select( ((.status // .state // "") | ascii_downcase) == ($s | ascii_downcase) ) ] | length'
}

# ---- baseline: how many sources exist BEFORE researching --------------------------------
before_json="$(list_sources)"
before_count="$(count_total "$before_json")"

echo ">> [$MODE] researching \"$QUERY\" in notebook $NOTEBOOK_ID (baseline: $before_count source(s)) ..." >&2

# ---- run the research/import ----------------------------------------------------------
# We record the exit code for the log only. The proof of success comes from re-listing the
# sources below, NOT from this return value.
set +e
"$CLI" source add-research "$NOTEBOOK_ID" "$QUERY" "${RESEARCH_FLAGS[@]}"
add_rc=$?
set -e
if [ "$add_rc" -ne 0 ]; then
  echo ">> note: add-research exited with $add_rc — verifying anyway via 'source list'" >&2
fi

# ---- wait until nothing is still 'preparing' ------------------------------------------
deadline=$(( $(date +%s) + POLL_TIMEOUT ))
while :; do
  cur_json="$(list_sources)"
  preparing="$(count_preparing "$cur_json")"
  total="$(count_total "$cur_json")"

  # Everything settled — stop waiting.
  [ "$preparing" -eq 0 ] && break

  # Timed out — warn and continue to report whatever arrived.
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo ">> warning: timed out after ${POLL_TIMEOUT}s with $preparing source(s) still in '$PREPARING_STATUS'" >&2
    break
  fi

  echo ">> waiting: $preparing/$total source(s) still in '$PREPARING_STATUS' (re-checking in ${POLL_INTERVAL}s) ..." >&2
  sleep "$POLL_INTERVAL"
done

# ---- verify: compare the source count -------------------------------------------------
after_json="$(list_sources)"
after_count="$(count_total "$after_json")"

added=$(( after_count - before_count ))
[ "$added" -lt 0 ] && added=0   # guard against concurrent deletions skewing the diff

echo ">> done: $added source(s) added ($before_count -> $after_count total)" >&2

if [ "$added" -eq 0 ]; then
  echo "error: no source was imported — the research was not saved (check auth / query / notebook id)" >&2
  exit 1
fi

# Machine-parseable result: the number of sources added, on stdout.
echo "$added"

# provenance-fingerprint: nbkb-ec948d2d85 — github.com/ferinazumaDEV/notebooklm-kb-system (AGPL-3.0).
# Do not remove: used to trace license compliance.
