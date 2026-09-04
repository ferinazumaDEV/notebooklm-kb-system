# Install on Windows (PowerShell)

Step-by-step setup of the NotebookLM KB System on Windows, using **PowerShell** for
everything except the bash-only `research.sh` wrapper (which you run under Git Bash or
WSL — see §8).

Every value in angle brackets is a placeholder for your own: `<YOUR_EMAIL>`,
`<NOTEBOOK_ID>`, `<SOURCE_ID>`. Don't paste real secrets into any file you commit.

The `notebooklm` commands below are tested with **notebooklm-py 0.8.2**. They pass the notebook
explicitly with `-n <NOTEBOOK_ID>`; run `notebooklm use <NOTEBOOK_ID>` once to set a current
notebook and you can omit `-n`.

> **Paths.** In PowerShell, `$HOME` is `C:\Users\<you>`. In Git Bash, `~` maps to the
> **same** folder. So `$HOME\.kb` (PowerShell) and `~/.kb` (Git Bash) are the same
> directory — you can drive the install from either shell.

---

## What you'll do

1. Install Python 3.11+
2. Create and activate a virtualenv (PowerShell syntax)
3. Install the CLI: `pip install "notebooklm-py[browser,cookies]"`
4. Install a Playwright browser — **only if you have no system browser** (§4)
5. Detect which browser you have and run `notebooklm login` with the right flag
6. Verify with a real operation
7. Create a notebook and add a source
8. Run web research (`research.sh` under Git Bash/WSL, or the CLI directly in PowerShell)

---

## 1. Install Python 3.11+

Check whether a suitable Python is already present (the Windows launcher is `py`):

```powershell
py --version
# or:
python --version
```

If it prints **3.11** or newer, skip ahead to §2. Otherwise install it.

**Option A — winget (recommended, ships with Windows 10/11):**

```powershell
winget install --id Python.Python.3.11 -e --source winget
```

**Option B — installer:** download from <https://www.python.org/downloads/windows/> and,
in the installer, tick **"Add python.exe to PATH"**.

After installing, **open a new PowerShell window** so the updated PATH is picked up, then
confirm:

```powershell
py -3.11 --version      # -> Python 3.11.x
```

---

## 2. Create and activate a virtualenv (PowerShell)

Keep the CLI and its browser automation isolated in a venv so they can't clash with the
system Python.

```powershell
# Create the KB root and a venv inside it.
New-Item -ItemType Directory -Force -Path "$HOME\.kb" | Out-Null
py -3.11 -m venv "$HOME\.kb\venv"

# Activate it (PowerShell activation script).
& "$HOME\.kb\venv\Scripts\Activate.ps1"
```

Your prompt now shows `(venv)`. **Activate the venv in every new shell that runs the CLI.**

> **If activation is blocked** with *"running scripts is disabled on this system"*, allow
> signed local scripts for the current session only, then re-run the activate line:
>
> ```powershell
> Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
> & "$HOME\.kb\venv\Scripts\Activate.ps1"
> ```
>
> This affects only the current PowerShell process — it is not a machine-wide change.

Upgrade `pip` inside the fresh venv:

```powershell
python -m pip install --upgrade pip
```

To leave the venv later: `deactivate`.

---

## 3. Install the CLI (with the browser extra)

```powershell
pip install "notebooklm-py[browser,cookies]"
```

> The `[browser]` extra is the optional dependency group that enables the browser-backed
> flows: **interactive login, headless re-auth, and deep research**; the `[cookies]` extra
> is what `notebooklm login --browser-cookies ...` (the Firefox/Brave path in §5) needs.
> Plain `pip install notebooklm-py` gives you only the bare CLI and will fail at
> login/research later. Install the extras now.

Confirm the CLI is on your PATH:

```powershell
notebooklm --version
notebooklm --help          # lists the available verbs (list / create / source / ask / login)
```

---

## 4. Install a Playwright browser — only if you have no system browser

**Skip this section if you have Chrome, Chromium, or Microsoft Edge** (Edge is
pre-installed on Windows 10/11, so most people skip it). Login will drive your existing
browser instead.

Only if you have **no** Chromium-family browser and only Firefox/Brave — or nothing at
all — install the Playwright-managed Chromium:

```powershell
playwright install chromium
```

You'll then log in with `--browser chromium` (§5, case C).

---

## 5. Detect your browser and log in

`notebooklm login` seeds a **reusable session profile** on this machine so later runs can
re-authenticate — including headless — without a visible window. Do it once per machine.

There are two login styles, and the right flag depends on which browser you have:

- **`--browser chromium|chrome|msedge`** — launches that browser for an interactive Google
  sign-in.
- **`--browser-cookies chrome|firefox|brave|edge`** — reads cookies from a browser you're
  **already** signed into, instead of launching Playwright.

### 5.1 Detect what's installed

Run this block; it reports which browsers it finds:

```powershell
$browsers = [ordered]@{
  "Microsoft Edge" = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
  )
  "Google Chrome"  = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
  )
  "Brave"          = @(
    "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
    "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
  )
  "Firefox"        = @(
    "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
    "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
  )
}
foreach ($name in $browsers.Keys) {
  $found = $browsers[$name] | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($found) { "FOUND  $name" } else { "-      $name (not found)" }
}
```

### 5.2 Pick the login command

Choose the **first** case that matches your result, in this order:

| Your situation | Login command |
|---|---|
| **A.** Chrome / Chromium / Edge is installed | `notebooklm login --browser chrome`  ·  `--browser chromium`  ·  `--browser msedge` |
| **B.** Only Firefox or Brave | `notebooklm login --browser-cookies firefox`  ·  `--browser-cookies brave` |
| **C.** No browser at all | `playwright install chromium` (from §4), then `notebooklm login --browser chromium` |

**Case A (most Windows machines — Edge is pre-installed):**

```powershell
notebooklm login --browser msedge
# or, if you use Chrome:
# notebooklm login --browser chrome
```

A browser window opens; sign in with your NotebookLM Google account (`<YOUR_EMAIL>`). When
it completes, the reusable profile is saved.

**Case B (only Firefox/Brave — read cookies from the browser you're already signed into):**

```powershell
# Sign into Google/NotebookLM in that browser first, then:
notebooklm login --browser-cookies firefox
# or:
# notebooklm login --browser-cookies brave
```

**Case C (no browser):** run `playwright install chromium` (§4), then:

```powershell
notebooklm login --browser chromium
```

### 5.3 Headless re-auth (for long/deep runs)

Once login has seeded the profile, enable headless re-authentication so a long-running job
(deep research, scheduled runs) can refresh its own session mid-run instead of failing:

```powershell
# Current session only:
$env:NOTEBOOKLM_HEADLESS_REAUTH = "1"

# Persist it for future PowerShell sessions (user-level env var):
[Environment]::SetEnvironmentVariable("NOTEBOOKLM_HEADLESS_REAUTH", "1", "User")
```

`research.sh deep` also exports this for you, so you mainly need the persistent form if you
run deep research directly from PowerShell (§8.2).

> **If a later run fails with an auth error,** the stored session expired. Just re-run the
> `notebooklm login ...` command from §5.2 once to re-seed it.

---

## 6. Verify with a real operation

Confirm auth actually works by hitting the service — listing your notebooks is
non-destructive:

```powershell
notebooklm list
```

If that returns without an auth error, you're set. (If your build names the verb
differently, `notebooklm --help` shows the exact subcommands — `create` in §7 is
an equally good live check.)

---

## 7. Create a notebook and add a source

Create one notebook per **domain** (e.g. `infra`, `apps`, `ops`). Prefer a few broad
notebooks over many tiny ones.

```powershell
# Create a notebook; note the id it prints back.
notebooklm create "infra"
#   -> created notebook <NOTEBOOK_ID>

# Prepare a build-doc (the local file you edit; the notebook reads the uploaded copy).
New-Item -ItemType Directory -Force -Path "$HOME\.kb\build" | Out-Null
Set-Content -Path "$HOME\.kb\build\infra__architecture.md" -Value "# infra`n`nFirst notes."

# Upload it as a SOURCE (what queries actually read).
notebooklm source add -n <NOTEBOOK_ID> "$HOME\.kb\build\infra__architecture.md"

# Confirm it ingested — wait until the source shows "ready".
notebooklm source list -n <NOTEBOOK_ID>
```

Record the friendly-key → id mapping so you never paste a raw UUID again. Create
`$HOME\.kb\notebooks.json`:

```json
{ "infra": "<NOTEBOOK_ID>", "apps": "<NOTEBOOK_ID>", "ops": "<NOTEBOOK_ID>" }
```

Ask it a question (the cheap, common operation — reading never changes the corpus):

```powershell
notebooklm ask -n <NOTEBOOK_ID> "<an extensive, context-rich question about your infra>"
```

> **Editing a source later** means re-uploading it: edit the build-doc, `source add` the
> new version, wait until it's **ready**, then `source delete -n <NOTEBOOK_ID> <OLD_SOURCE_ID>`
> — always add-new → wait-ready → delete-old, so a notebook is never left at 0 sources.
> See `docs/OPERATIONS.md` §3.

---

## 8. Run web research

`research.sh` is a **bash** script (it needs `bash` and `jq`), so it does not run in
PowerShell directly. You have two options.

### 8.1 Option A — run `research.sh` under Git Bash or WSL (recommended)

**Git Bash** ships with *Git for Windows*; **WSL** is a full Linux environment. Either
gives you `bash`. You also need `jq`.

Install Git and jq (from PowerShell, one time):

```powershell
winget install --id Git.Git -e --source winget          # provides Git Bash
winget install --id jqlang.jq -e --source winget         # provides jq
```

Then open **Git Bash** (or a **WSL** terminal), activate the same venv, and run the
wrapper. The venv and `~/.kb` are the same folder you set up in PowerShell:

```bash
# In Git Bash:
source ~/.kb/venv/Scripts/activate        # Git Bash path to the venv
cp research.sh ~/.kb/ && chmod +x ~/.kb/research.sh    # first time only

~/.kb/research.sh <NOTEBOOK_ID> "<research question or topic>" fast   # quick, shallow sweep
~/.kb/research.sh <NOTEBOOK_ID> "<research question or topic>" deep   # broad, multi-source
```

```bash
# In WSL (Ubuntu), the venv uses the Linux-style bin/ path instead:
#   source ~/.kb/venv/bin/activate
# jq in WSL:  sudo apt-get install -y jq
```

On success the script prints a single integer on stdout — the number of sources added —
and exits non-zero if nothing landed. `deep` also exports `NOTEBOOKLM_HEADLESS_REAUTH=1`
for you, so its long headless job can refresh its own auth (needs the §5 login already
seeded).

### 8.2 Option B — run the CLI directly in PowerShell (no bash)

`research.sh` is just a wait-and-verify wrapper around the CLI. You can run the same
underlying commands straight from PowerShell:

```powershell
# FAST — quick, shallow sweep:
notebooklm source add-research -n <NOTEBOOK_ID> "<research question or topic>" --from web --import-all --mode fast

# DEEP — broad, multi-source. Enable headless re-auth first (see §5.3):
$env:NOTEBOOKLM_HEADLESS_REAUTH = "1"
notebooklm source add-research -n <NOTEBOOK_ID> "<research question or topic>" --from web --import-all --mode deep

# Then WAIT until every source shows "ready" (an ingesting source can't answer):
notebooklm source list -n <NOTEBOOK_ID>
```

Read the imported material back with **fulltext**, not an artifact export:

```powershell
notebooklm source list -n <NOTEBOOK_ID>                    # find the new source id
notebooklm source fulltext -n <NOTEBOOK_ID> <SOURCE_ID>    # the raw, usable text
```

> The difference vs. `research.sh`: the script snapshots the source count, **polls** until
> nothing is still preparing, and **fails loudly** if nothing actually imported (the raw
> CLI can exit 0 without having imported anything). In PowerShell you do that check
> yourself by re-listing with `source list` and confirming the new source is present and
> ready.

---

## Troubleshooting

- **`notebooklm` not found** — the venv isn't active in this shell. Re-run
  `& "$HOME\.kb\venv\Scripts\Activate.ps1"`.
- **`Activate.ps1 cannot be loaded`** — execution policy blocks it. Run
  `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned`, then activate again
  (§2).
- **`py` not recognized after installing Python** — open a **new** PowerShell so PATH
  refreshes; if it still fails, re-run the python.org installer with *"Add python.exe to
  PATH"* ticked.
- **Login opens no window / fails to launch a browser** — you likely have no Chromium
  browser. Run `playwright install chromium` (§4), then `notebooklm login --browser chromium`.
- **Auth error on a later run** — the stored session expired; re-run the `notebooklm login`
  command from §5.2 once.
- **`research.sh: command not found` or `jq: not found`** — you're in PowerShell (bash
  only) or `jq` isn't installed. Use §8.1 (Git Bash/WSL + `winget install jqlang.jq`) or
  switch to the direct-CLI path in §8.2.
- **Research seems to do nothing** — confirm auth (`notebooklm list`), then
  re-list sources; the async import can take minutes. `research.sh` waits and verifies for
  you; in PowerShell, poll `source list` until the new source is `ready`.

---

## Quick reference (PowerShell)

```powershell
# One-time setup
py -3.11 -m venv "$HOME\.kb\venv"
& "$HOME\.kb\venv\Scripts\Activate.ps1"
python -m pip install --upgrade pip
pip install "notebooklm-py[browser,cookies]"
# playwright install chromium         # only if no system browser
notebooklm login --browser msedge     # or --browser chrome | chromium | --browser-cookies firefox|brave

# Every new shell
& "$HOME\.kb\venv\Scripts\Activate.ps1"

# Daily
notebooklm list
notebooklm ask -n <NOTEBOOK_ID> "<long, contextual question>"
notebooklm source add -n <NOTEBOOK_ID> "$HOME\.kb\build\<key>__<topic>.md"
notebooklm source list -n <NOTEBOOK_ID>
notebooklm source fulltext -n <NOTEBOOK_ID> <SOURCE_ID>

# Research (PowerShell-direct; or use research.sh under Git Bash/WSL — §8)
notebooklm source add-research -n <NOTEBOOK_ID> "<topic>" --from web --import-all --mode fast           # fast
$env:NOTEBOOKLM_HEADLESS_REAUTH = "1"
notebooklm source add-research -n <NOTEBOOK_ID> "<topic>" --from web --import-all --mode deep     # deep
```

---

*Part of the NotebookLM KB System. Placeholders only — no private data. See `README.md`
for the concept and `docs/OPERATIONS.md` for the full operations manual.*
