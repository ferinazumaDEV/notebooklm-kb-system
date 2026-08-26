#!/usr/bin/env bash
#
# Copyright (C) 2026 Fernando — Licensed under AGPL-3.0 (see LICENSE).
# Free software with ABSOLUTELY NO WARRANTY; redistribute under the AGPL-3.0 terms.
#
# install.sh — one-shot setup for the NotebookLM KB System on Linux / macOS.
# ---------------------------------------------------------------------------------------
#
# Part of the "local memory + NotebookLM notebooks" second-brain starter kit.
#
# What it does, in order:
#   1. Checks you have a usable Python (3.9+).
#   2. Creates an isolated virtualenv (default: ~/.kb-venv; --local uses ./.venv) and
#      activates it, so the CLI + its browser automation can't clash with system Python.
#   3. Installs the CLI WITH the browser extra:  pip install "notebooklm[browser]".
#   4. DETECTS which browser you have and picks the correct login flag:
#        - Chrome / Chromium / Edge  ->  notebooklm login --browser chrome|chromium|msedge
#        - only Firefox / Brave      ->  notebooklm login --browser-cookies firefox|brave
#        - none of the above         ->  playwright install chromium, then --browser chromium
#   5. Runs the login (skipped if you're already authenticated, unless --force-login).
#   6. VERIFIES auth with a real, non-destructive op (notebooklm notebook list).
#   7. Prints the next steps (create a notebook, add a source, run research).
#
# It is IDEMPOTENT: an existing venv is reused, pip re-runs are no-ops when satisfied, and
# a still-valid login is not disturbed. Safe to run again after a partial or failed run.
#
# Usage:
#   ./install.sh [--local] [--force-login] [--upgrade] [-h|--help]
#
#   --local         Put the venv at ./.venv (in the current directory) instead of ~/.kb-venv.
#   --force-login   Re-run `notebooklm login` even if the stored session still works.
#   --upgrade       Pass --upgrade to pip so the CLI is bumped to the newest version.
#   -h, --help      Show this help and exit.
#
# Environment overrides (all optional):
#   KB_VENV              Absolute path for the venv (overrides the default / --local).
#   PYTHON               Python interpreter to use (default: python3).
#   NOTEBOOKLM_BROWSER   Force a browser choice, skipping detection. One of:
#                          chrome | chromium | msedge   (uses --browser)
#                          firefox | brave              (uses --browser-cookies)
#
# Requirements: bash, a Python 3.9+ interpreter, and network access for pip.
# ---------------------------------------------------------------------------------------

set -euo pipefail

# ---- pretty logging (all diagnostics go to STDERR) ------------------------------------
# Colour only when STDERR is a real terminal; degrade gracefully in logs / CI.
if [ -t 2 ]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_RED=$'\033[31m'; C_CYN=$'\033[36m'; C_RST=$'\033[0m'
else
  C_BOLD=""; C_DIM=""; C_GRN=""; C_YEL=""; C_RED=""; C_CYN=""; C_RST=""
fi
log()  { printf '%s>>%s %s\n'      "$C_CYN" "$C_RST" "$*" >&2; }
ok()   { printf '%s✓%s  %s\n'      "$C_GRN" "$C_RST" "$*" >&2; }
warn() { printf '%s!%s  %s\n'      "$C_YEL" "$C_RST" "$*" >&2; }
die()  { printf '%serror:%s %s\n'  "$C_RED" "$C_RST" "$*" >&2; exit 1; }
step() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_RST" >&2; }

# ---- resolve where this script and the repo live --------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- defaults / flag parsing ----------------------------------------------------------
PYTHON_BIN="${PYTHON:-python3}"
VENV_DIR="${KB_VENV:-$HOME/.kb-venv}"   # default install location for the venv
FORCE_LOGIN=0
PIP_UPGRADE=()                          # becomes (--upgrade) when --upgrade is passed

usage() {
  # Print the header comment block (everything after the AGPL notice up to the first
  # blank comment gap) as help text, then exit.
  cat >&2 <<'EOF'
install.sh — set up the NotebookLM KB System on Linux / macOS.

Usage:
  ./install.sh [--local] [--force-login] [--upgrade] [-h|--help]

  --local         Put the venv at ./.venv instead of ~/.kb-venv.
  --force-login   Re-run `notebooklm login` even if the session still works.
  --upgrade       Bump the CLI to the newest version (pip --upgrade).
  -h, --help      Show this help.

Environment: KB_VENV, PYTHON, NOTEBOOKLM_BROWSER (chrome|chromium|msedge|firefox|brave).
EOF
  exit "${1:-0}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --local)       VENV_DIR="$(pwd)/.venv" ;;
    --force-login) FORCE_LOGIN=1 ;;
    --upgrade)     PIP_UPGRADE=(--upgrade) ;;
    -h|--help)     usage 0 ;;
    *)             warn "unknown argument: $1"; usage 2 ;;
  esac
  shift
done

IS_MACOS=0
[ "$(uname -s 2>/dev/null)" = "Darwin" ] && IS_MACOS=1

# =======================================================================================
# 1. Python
# =======================================================================================
step "1/6  Checking Python"

command -v "$PYTHON_BIN" >/dev/null 2>&1 \
  || die "'$PYTHON_BIN' not found. Install Python 3.9+ (macOS: 'brew install python'; Debian/Ubuntu: 'sudo apt install python3 python3-venv')."

# Require 3.9+. The interpreter itself is the most reliable version oracle.
if ! "$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 9) else 1)'; then
  die "Python 3.9+ is required (found $("$PYTHON_BIN" -V 2>&1)). Install a newer Python or set PYTHON=/path/to/python3.x"
fi
ok "Using $("$PYTHON_BIN" -V 2>&1) at $(command -v "$PYTHON_BIN")"

# Ensure the venv module is present (Debian/Ubuntu ship it as a separate package).
if ! "$PYTHON_BIN" -c 'import venv' >/dev/null 2>&1; then
  die "The 'venv' module is missing. On Debian/Ubuntu: sudo apt install python3-venv"
fi

# =======================================================================================
# 2. Virtualenv  (idempotent: reuse an existing one)
# =======================================================================================
step "2/6  Virtualenv"

if [ -f "$VENV_DIR/bin/activate" ]; then
  ok "Reusing existing venv at $VENV_DIR"
else
  log "Creating venv at $VENV_DIR ..."
  mkdir -p "$(dirname "$VENV_DIR")"
  "$PYTHON_BIN" -m venv "$VENV_DIR" || die "failed to create venv at $VENV_DIR"
  ok "Created venv at $VENV_DIR"
fi

# Activate it for the rest of this script. The activate script references variables that
# `set -u` would flag as unbound, so relax nounset just around the source.
set +u
# shellcheck disable=SC1090,SC1091
source "$VENV_DIR/bin/activate"
set -u
ok "Activated venv (python: $(command -v python))"

# Make sure pip is present and current inside the venv.
python -m ensurepip --upgrade >/dev/null 2>&1 || true
python -m pip install --quiet --upgrade pip >/dev/null 2>&1 || warn "could not upgrade pip (continuing)"

# =======================================================================================
# 3. Install the CLI  (WITH the browser extra — needed for login + research)
# =======================================================================================
step "3/6  Installing notebooklm[browser]"

# The [browser] extra is the optional dependency group that enables the browser-backed
# flows (interactive login, headless re-auth, deep research). Plain `notebooklm` fails
# at login/research later, so we always install the extra.
if command -v notebooklm >/dev/null 2>&1 && [ "${#PIP_UPGRADE[@]}" -eq 0 ]; then
  log "notebooklm already installed — ensuring the [browser] extra is satisfied ..."
fi
# Note: ${PIP_UPGRADE[@]+"..."} expands to nothing when the array is empty WITHOUT
# tripping `set -u` on old bash (macOS ships 3.2, where a bare "${empty[@]}" errors).
python -m pip install ${PIP_UPGRADE[@]+"${PIP_UPGRADE[@]}"} "notebooklm[browser]" \
  || die "pip install failed. Check your network / proxy and retry."

command -v notebooklm >/dev/null 2>&1 \
  || die "'notebooklm' is not on the PATH even after install — the venv may be broken. Try: rm -rf '$VENV_DIR' && re-run."
ok "Installed: $(notebooklm --version 2>/dev/null || echo 'notebooklm (version unknown)')"

# =======================================================================================
# 4. Detect the browser and choose the login flag
# =======================================================================================
step "4/6  Detecting a browser for login"

# have_browser <cli-name-in-PATH> [macOS .app name]
#   True if the CLI is on the PATH, or (on macOS) the named app bundle exists.
have_browser() {
  command -v "$1" >/dev/null 2>&1 && return 0
  if [ "$IS_MACOS" = "1" ] && [ -n "${2:-}" ]; then
    { [ -d "/Applications/$2.app" ] || [ -d "$HOME/Applications/$2.app" ]; } && return 0
  fi
  return 1
}

# Results filled in by the detection below:
BROWSER_NAME=""          # human-readable, for logging
LOGIN_FLAGS=()           # the flags handed to `notebooklm login`
NEED_PLAYWRIGHT_CHROMIUM=0   # 1 => run `playwright install chromium` before login
COOKIE_MODE=0            # 1 => --browser-cookies (user must already be signed in)

choose_browser() {
  # 0) Explicit override wins — no detection.
  if [ -n "${NOTEBOOKLM_BROWSER:-}" ]; then
    case "$NOTEBOOKLM_BROWSER" in
      chrome)   BROWSER_NAME="Google Chrome (forced)"; LOGIN_FLAGS=(--browser chrome) ;;
      chromium) BROWSER_NAME="Chromium (forced)";      LOGIN_FLAGS=(--browser chromium) ;;
      msedge)   BROWSER_NAME="Microsoft Edge (forced)";LOGIN_FLAGS=(--browser msedge) ;;
      firefox)  BROWSER_NAME="Firefox (forced)";       LOGIN_FLAGS=(--browser-cookies firefox); COOKIE_MODE=1 ;;
      brave)    BROWSER_NAME="Brave (forced)";         LOGIN_FLAGS=(--browser-cookies brave);   COOKIE_MODE=1 ;;
      *) die "NOTEBOOKLM_BROWSER='$NOTEBOOKLM_BROWSER' is invalid (use: chrome|chromium|msedge|firefox|brave)" ;;
    esac
    return
  fi

  # 1) Prefer a Chromium-family browser we can LAUNCH for an interactive sign-in.
  if have_browser google-chrome "Google Chrome" || have_browser google-chrome-stable "Google Chrome"; then
    BROWSER_NAME="Google Chrome"; LOGIN_FLAGS=(--browser chrome)
  elif have_browser chromium "Chromium" || have_browser chromium-browser "Chromium"; then
    BROWSER_NAME="Chromium"; LOGIN_FLAGS=(--browser chromium)
  elif have_browser microsoft-edge "Microsoft Edge" || have_browser microsoft-edge-stable "Microsoft Edge"; then
    BROWSER_NAME="Microsoft Edge"; LOGIN_FLAGS=(--browser msedge)

  # 2) Otherwise fall back to reading cookies from Firefox / Brave (no launch).
  elif have_browser firefox "Firefox"; then
    BROWSER_NAME="Firefox"; LOGIN_FLAGS=(--browser-cookies firefox); COOKIE_MODE=1
  elif have_browser brave "Brave Browser" || have_browser brave-browser "Brave Browser"; then
    BROWSER_NAME="Brave"; LOGIN_FLAGS=(--browser-cookies brave); COOKIE_MODE=1

  # 3) No browser at all — install the Playwright-bundled Chromium and use it.
  else
    BROWSER_NAME="none found — will install Playwright Chromium"
    LOGIN_FLAGS=(--browser chromium)
    NEED_PLAYWRIGHT_CHROMIUM=1
  fi
}

choose_browser
ok "Browser: $BROWSER_NAME"
log "Login command will be:  notebooklm login ${LOGIN_FLAGS[*]}"

if [ "$NEED_PLAYWRIGHT_CHROMIUM" = "1" ]; then
  log "No system browser detected — installing the Playwright Chromium binary (one-time download) ..."
  playwright install chromium || die "'playwright install chromium' failed. Ensure the [browser] extra installed correctly, then re-run."
  ok "Playwright Chromium installed"
fi

# =======================================================================================
# 5. Log in  (idempotent: skip if the stored session already works)
# =======================================================================================
step "5/6  Authenticating"

# is_authed: true when a real, non-destructive op succeeds — proof the session is valid.
is_authed() { notebooklm notebook list >/dev/null 2>&1; }

if [ "$FORCE_LOGIN" = "0" ] && is_authed; then
  ok "Already authenticated (a stored session is valid) — skipping login. Use --force-login to redo it."
else
  if [ "$COOKIE_MODE" = "1" ]; then
    warn "Cookie mode: make sure you are ALREADY signed in to Google / NotebookLM in $BROWSER_NAME before continuing."
  else
    log "A browser window will open — sign in with your NotebookLM Google account (<YOUR_EMAIL>)."
  fi

  # Run the detected login. On failure, give targeted guidance instead of a bare abort.
  if ! notebooklm login "${LOGIN_FLAGS[@]}"; then
    warn "Login failed with: notebooklm login ${LOGIN_FLAGS[*]}"
    if [ "$COOKIE_MODE" = "1" ]; then
      warn "Cookie import can fail if the browser is running or you're not signed in. Close $BROWSER_NAME, sign in, and retry."
    else
      warn "If the browser crashed or hung (common with the bundled Chromium on macOS 15+), retry with a real browser:"
      warn "    notebooklm login --browser chrome    # or --browser msedge"
      warn "or fall back to Playwright Chromium:"
      warn "    playwright install chromium && notebooklm login --browser chromium"
    fi
    die "authentication did not complete."
  fi
  ok "Login completed — a reusable session profile is now stored on this machine."
fi

# =======================================================================================
# 6. Verify with a real operation
# =======================================================================================
step "6/6  Verifying"

if is_authed; then
  ok "Auth verified — 'notebooklm notebook list' succeeded."
else
  die "Auth check failed after login. Re-run this script (or 'notebooklm login ${LOGIN_FLAGS[*]}') and complete the sign-in."
fi

# =======================================================================================
# Done — next steps
# =======================================================================================
ACTIVATE_HINT="source $VENV_DIR/bin/activate"

cat >&2 <<EOF

${C_GRN}${C_BOLD}Setup complete.${C_RST}

${C_BOLD}In every new shell that runs the CLI, activate the venv first:${C_RST}
    ${ACTIVATE_HINT}

${C_BOLD}Headless servers / scheduled runs:${C_RST} enable headless re-auth so long jobs can
refresh their own session (deep research needs this):
    export NOTEBOOKLM_HEADLESS_REAUTH=1
    # persist it, e.g.:  echo 'export NOTEBOOKLM_HEADLESS_REAUTH=1' >> ~/.bashrc   (or ~/.zshrc)

${C_BOLD}Create your first notebook and add a source:${C_RST}
    notebooklm notebook create "infra"           # note the <NOTEBOOK_ID> it prints
    mkdir -p ~/.kb/build
    printf '# infra\\n\\nFirst notes.\\n' > ~/.kb/build/infra__architecture.md
    notebooklm source add <NOTEBOOK_ID> ~/.kb/build/infra__architecture.md
    notebooklm source list <NOTEBOOK_ID>          # wait until it shows "ready"

${C_BOLD}Record the friendly-key -> id map${C_RST} in ~/.kb/notebooks.json:
    { "infra": "<NOTEBOOK_ID>", "apps": "<NOTEBOOK_ID>", "ops": "<NOTEBOOK_ID>" }

${C_BOLD}Copy the kit's docs + templates into your install${C_RST} (from the repo root):
    mkdir -p ~/.kb/memory
    cp "$REPO_ROOT/docs/MEMORY.template.md" ~/.kb/memory/MEMORY.md
    cp "$REPO_ROOT/docs/KNOWLEDGE-ROUTING.md" "$REPO_ROOT/docs/OPERATIONS.md" "$REPO_ROOT/docs/RESEARCH_PROMPT_TEMPLATE.md" ~/.kb/
    cp "$REPO_ROOT/research.sh" ~/.kb/ && chmod +x ~/.kb/research.sh

${C_BOLD}Ask a question (cheap, non-destructive) and run web research:${C_RST}
    notebooklm ask <NOTEBOOK_ID> "<an extensive, context-rich question>"
    ~/.kb/research.sh <NOTEBOOK_ID> "<research topic>" fast   # quick sweep
    ~/.kb/research.sh <NOTEBOOK_ID> "<research topic>" deep   # broad, multi-source

${C_DIM}Full concept in README.md; operations manual in docs/OPERATIONS.md.
If a later run hits an auth error, the session expired — re-run:
    notebooklm login ${LOGIN_FLAGS[*]}${C_RST}
EOF

# provenance-fingerprint: nbkb-ec948d2d85 — github.com/ferinazumaDEV/notebooklm-kb-system (AGPL-3.0).
# Do not remove: used to trace license compliance.
