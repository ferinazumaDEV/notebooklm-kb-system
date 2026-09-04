#!/usr/bin/env bash
#
# Copyright (C) 2026 Fernando — Licensed under AGPL-3.0 (see LICENSE).
# Free software with ABSOLUTELY NO WARRANTY; redistribute under the AGPL-3.0 terms.
#
# healthcheck.sh — make the NotebookLM auth NEVER fail silently.
# ---------------------------------------------------------------------------------------
#
# Part of the "local memory + NotebookLM notebooks" second-brain starter kit.
#
# THE PROBLEM. NotebookLM auth is a browser session (Google cookies). It rots on TWO clocks:
#   1. The short cookie (`__Secure-1PSIDTS`) rotates in minutes-to-hours; too-infrequent a
#      keepalive crosses that window and the session dies. A frequent `auth refresh` fixes THIS.
#   2. The device-bound tokens (Google DBSC + the refresh-token family) age out over DAYS and
#      can only be renewed by a REAL browser exercising the profile — a POST keepalive can't, so
#      the session still dies server-side even under a perfect 15-min keepalive. A dead session
#      is then discovered days later by a naive cron that just logs a warning nobody reads.
#   And `doctor` / `auth check` LIE: they report "valid" (cookies present) while every real
#   RPC bounces to accounts.google.com. Only a real operation detects the outage.
#   (Full model + the warm-profile / host-local-device-key prevention: docs/AUTH-RESILIENCE.md.)
#
# THE FIX (this script + a frequent keepalive + a warm-profile pass; see docs/AUTH-RESILIENCE.md):
#   - Probe with a REAL, cheap operation (`source list` on a small notebook), not `doctor`.
#   - If auth is down: try an unattended re-auth cascade (keepalive -> headless warm-profile
#     re-mint), verifying with a real op after each step.
#   - If it's still down: EMAIL the operator with the exact recovery steps, once per
#     cooldown window (so a multi-day outage is a single early alert, not silence).
#   - Clears the alert stamp on recovery so the next outage alerts immediately.
#
# NOTE ON DURABLE AUTH: it is tempting to install a Google "master token" so the box can
# re-mint sessions forever with no human login. DON'T. A master token is full-account,
# non-revocable-without-password access — malware-grade. This system stays on short-lived
# browser cookies and accepts a rare human re-login, surfaced early by this alert.
#
# CONFIG via env (placeholders — set to your own):
#   KB_HOME                 default: $HOME/.kb        (where the venv/profile live)
#   NB_BIN                  default: notebooklm       (the CLI on your PATH)
#   KB_HEALTHCHECK_NOTEBOOK (required) a small notebook id to probe cheaply
#   KB_ALERT_EMAIL          default: you@example.com  where the alert goes
#   KB_MAIL_CMD             a command that reads the body on stdin and takes: <to> <subject>
#                           e.g. export KB_MAIL_CMD="$HOME/.mail/send"   (adapt to your mailer)
#   HC_DRY_RUN=1            don't send the email; print the preview
#   HC_SKIP_REAUTH=1        skip the (slow) unattended re-auth; just probe + alert
#   HC_COOLDOWN=<seconds>   min seconds between emails while still down (default 21600 = 6h)
#
# Cron (see docs/AUTH-RESILIENCE.md): keepalive every ~15 min + this every ~30 min.
set -u

KB_HOME="${KB_HOME:-$HOME/.kb}"
NB="${NB_BIN:-notebooklm}"
NB_ID="${KB_HEALTHCHECK_NOTEBOOK:?set KB_HEALTHCHECK_NOTEBOOK to a small notebook id to probe}"
ALERT_TO="${KB_ALERT_EMAIL:-you@example.com}"
MAIL_CMD="${KB_MAIL_CMD:-}"
LOG="$KB_HOME/healthcheck.log"
STAMP="$KB_HOME/.hc_alert_stamp"
COOLDOWN="${HC_COOLDOWN:-21600}"
PROBE_TIMEOUT=60
REAUTH_TIMEOUT=150

# Auth-failure signature (case-insensitive). Covers the CLI's real text:
#   "Authentication expired or invalid. Redirected to: https://accounts.google.com..."
#   "Authentication required. Run 'notebooklm login' to re-authenticate."
#   {"error": true, "code": "AUTH_ERROR", ...}      (expired/invalid session, --json)
#   {"error": true, "code": "AUTH_REQUIRED", "message": "Auth not found. Run 'notebooklm login' first."}
#     (missing/empty stored session — e.g. a half-closed login window; notebooklm-py 0.8.2)
#   "Not logged in."                                  (same case, without --json)
AUTH_RE='authentication (expired|required|error)|re-authenticate|redirected to[^"]*accounts\.google|UNAUTHORIZED|AUTH_ERROR|AUTH_REQUIRED|auth not found|not logged in'

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '%s %s\n' "$(ts)" "$*" >> "$LOG"; }

# probe(): 0 = healthy | 10 = auth failure | 20 = other failure (network, etc.)
probe() {
  local out rc
  out=$(timeout "$PROBE_TIMEOUT" "$NB" source list -n "$NB_ID" --json 2>&1); rc=$?
  LAST_OUT="$out"
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -qiE '"error"[[:space:]]*:[[:space:]]*true'; then
    return 0
  fi
  printf '%s' "$out" | grep -qiE "$AUTH_RE" && return 10
  return 20
}

# reauth(): fully unattended. Keepalive (rotates the cookie), then a headless re-mint by
# re-running the real op with NOTEBOOKLM_HEADLESS_REAUTH=1. If the Google session is dead
# (redirect to accounts.google.com) this CANNOT fix it — hence the email.
reauth() {
  log "auth down -> keepalive (auth refresh)"
  timeout "$REAUTH_TIMEOUT" "$NB" auth refresh >/dev/null 2>&1
  probe && { log "recovered via keepalive"; return 0; }
  log "keepalive not enough -> headless re-mint (NOTEBOOKLM_HEADLESS_REAUTH=1)"
  NOTEBOOKLM_HEADLESS_REAUTH=1 timeout "$REAUTH_TIMEOUT" "$NB" source list -n "$NB_ID" --json >/dev/null 2>&1
  probe && { log "recovered via headless re-mint"; return 0; }
  return 1
}

send_alert() {
  if [ -f "$STAMP" ]; then
    local age=$(( $(date +%s) - $(stat -c %Y "$STAMP" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$COOLDOWN" ]; then
      log "still down; alert muted by cooldown (${age}s < ${COOLDOWN}s)"; return 0
    fi
  fi
  local subject="[KB][ALERT] NotebookLM auth down — manual re-login needed"
  local body
  body=$(cat <<EOF
NotebookLM auth is DOWN and unattended re-auth did NOT fix it.
When: $(ts)  ·  host: $(hostname)  ·  probe notebook: $NB_ID

Symptom:
$(printf '%s' "${LAST_OUT:-}" | head -3)

Already tried (no luck): auth refresh (keepalive) + headless re-mint.

=> Manual re-login required (the Google session died server-side; importing cookies does
   NOT fix this). On a machine with a browser, signed into the notebook's Google account:

  1. Run:  $NB login --browser chrome --storage ./nblm_state.json
     Complete the Google login WITHOUT closing the window (a half-closed window leaves an
     empty state).
  2. Copy nblm_state.json onto this host, back up the old profile state, and replace it:
       cp <profile>/storage_state.json <profile>/storage_state.json.bak-\$(date +%F)
       cp nblm_state.json <profile>/storage_state.json && chmod 600 <profile>/storage_state.json
  3. Verify with a REAL op (not 'doctor', it lies):
       $NB source list -n $NB_ID

This check keeps watching: it re-alerts at most every $((COOLDOWN/3600))h while down, and
goes quiet the moment auth answers again.
EOF
)
  if [ -n "${HC_DRY_RUN:-}" ]; then
    log "DRY_RUN: email not sent; preview below."
    printf '\n--- TO: %s\n--- SUBJECT: %s\n%s\n--- (end)\n' "$ALERT_TO" "$subject" "$body"
  elif [ -z "$MAIL_CMD" ]; then
    log "auth DOWN but KB_MAIL_CMD not set -> cannot email. Set KB_MAIL_CMD. Body logged below."
    printf '%s\n' "$body" >> "$LOG"
  else
    if printf '%s' "$body" | $MAIL_CMD "$ALERT_TO" "$subject" >/dev/null 2>&1; then
      log "alert emailed to $ALERT_TO"
    else
      log "FAILED to send alert (check KB_MAIL_CMD)"
    fi
  fi
  touch "$STAMP"
}

# ---- main ----
probe; st=$?
case "$st" in
  0)  log "OK: NotebookLM answers"
      [ -f "$STAMP" ] && { rm -f "$STAMP"; log "service recovered -> alert stamp cleared"; }
      exit 0 ;;
  10) log "auth failure detected"
      if [ -z "${HC_SKIP_REAUTH:-}" ] && reauth; then
        [ -f "$STAMP" ] && { rm -f "$STAMP"; log "recovered via re-auth -> stamp cleared"; }
        exit 0
      fi
      log "unattended re-auth did not resolve -> escalating by email"
      send_alert; exit 1 ;;
  *)  log "WARN: probe failed for a NON-auth reason: $(printf '%s' "${LAST_OUT:-}" | head -1)"
      exit 2 ;;
esac
