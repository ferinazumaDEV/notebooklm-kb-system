# Install & setup on Windows (Command Prompt / `cmd.exe`)

This walks you through installing the NotebookLM KB system on **classic Windows Command
Prompt** (`cmd.exe`) — the same steps as any other platform (Python, a virtualenv, the CLI,
browser login, a first notebook, first research), but with the paths, activation and
environment-variable syntax that CMD actually uses.

> Using **PowerShell** instead? See [`windows-powershell.md`](./windows-powershell.md).
> The steps are identical; only the shell syntax differs. The
> [**CMD vs PowerShell**](#cmd-vs-powershell-quick-reference) table at the bottom lists every
> line that changes between the two.

> Everything here uses placeholders — `<YOUR_EMAIL>`, `<NOTEBOOK_ID>`, `%USERPROFILE%\.kb`.
> Put your real values only in your local install, never in anything you publish.

The `notebooklm` commands below are tested with **notebooklm-py 0.8.2**. They pass the notebook
explicitly with `-n <NOTEBOOK_ID>`; run `notebooklm use <NOTEBOOK_ID>` once to set a current
notebook and you can omit `-n`.

Throughout, `%USERPROFILE%` is your home folder (e.g. `C:\Users\you`), and the install lives
in `%USERPROFILE%\.kb` — the Windows equivalent of the `~/.kb/` used elsewhere in the docs.

---

## 0. Prerequisites

- **Windows 10 or 11** with **Command Prompt** (`cmd.exe`).
- **Python 3.10+**. If you don't have it, install from
  [python.org](https://www.python.org/downloads/windows/) and **tick "Add python.exe to
  PATH"** in the installer. Windows ships the `py` launcher with it, which this guide uses.
- A **Google account** that can open NotebookLM.
- **`jq`** *only if* you want to run the bash `research.sh` wrapper under Git Bash / WSL.
  Pure-CMD users don't need it — §7 gives a CMD-native research call that skips both.

Open a **fresh** Command Prompt (Start → type `cmd` → Enter) so any freshly-installed PATH
entries are picked up, then check Python:

```bat
py --version
```

If `py` isn't found, try `python --version`. If neither works, Python isn't on your PATH —
reinstall it with the "Add to PATH" box ticked, then open a new Command Prompt.

---

## 1. Create the install folder and a virtualenv

Keep the CLI and its browser automation in a venv so they can't collide with your system
Python.

```bat
mkdir "%USERPROFILE%\.kb"
py -m venv "%USERPROFILE%\.kb\venv"
```

**Activate it.** On CMD you run the `.bat` activator (this is the biggest day-to-day
difference from PowerShell, which uses a `.ps1` script):

```bat
"%USERPROFILE%\.kb\venv\Scripts\activate.bat"
```

Your prompt now shows `(venv)` at the start. **Re-activate in every new Command Prompt**
before running the CLI — activation lasts only for the current window.

To leave the venv later, just run `deactivate`.

> **Note — CMD vs PowerShell:** CMD activates with `Scripts\activate.bat`; PowerShell uses
> `Scripts\Activate.ps1` (and may need `Set-ExecutionPolicy -Scope Process RemoteSigned`
> first). Do **not** run the bare `activate` (no extension) or the Unix `activate` script in
> CMD.

---

## 2. Install the CLI (with the browser extra)

With the venv active:

```bat
pip install "notebooklm-py[browser,cookies]>=0.8.2,<0.9"
```

The `[browser]` extra is the optional dependency group that enables every browser-backed
flow: interactive login, headless re-auth, and deep research; the `[cookies]` extra is what
`notebooklm login --browser-cookies ...` (the Firefox/Brave path in §3) needs. Plain
`pip install notebooklm-py` gives you a CLI that can `ask` but **fails at login and research**
— install the extras now to avoid that confusing half-working state later.

Confirm it landed:

```bat
notebooklm --version
where notebooklm
```

`where notebooklm` should point inside `%USERPROFILE%\.kb\venv\Scripts\`. If it points
somewhere else, the venv isn't active — re-run the activate line from §1.

---

## 3. Detect your browser (do this before logging in)

The CLI can log in **two** ways, and which one you use depends on what browser you already
have. **Do not force a browser** — pick the flag that matches what's installed.

- **`notebooklm login --browser chromium|chrome|msedge`** — launches that browser so you can
  sign in to Google interactively (uses Playwright).
- **`notebooklm login --browser-cookies chrome|firefox|brave|edge`** — reads the Google
  cookies from a browser you're *already* signed into, instead of launching one.

### Which one? — detection order

1. **Chrome / Chromium / Edge installed?** → use `--browser chrome` (or `chromium` /
   `msedge`). On Windows, **Microsoft Edge is preinstalled on 10/11**, so `--browser msedge`
   is a safe default if you're unsure.
2. **Only Firefox or Brave?** → use `--browser-cookies firefox` (or `brave`). Make sure
   you're signed into Google in that browser first.
3. **No supported browser at all?** → install the Playwright-managed Chromium and use it:
   ```bat
   playwright install chromium
   notebooklm login --browser chromium
   ```

### Check what you have (CMD)

`if exist` tests for each browser's executable. Run these and see which print `FOUND`:

```bat
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" echo FOUND chrome
if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" echo FOUND chrome (x86)
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" echo FOUND msedge
if exist "%ProgramFiles%\Mozilla Firefox\firefox.exe" echo FOUND firefox
if exist "%LocalAppData%\BraveSoftware\Brave-Browser\Application\brave.exe" echo FOUND brave
```

(Brave and some Chrome installs live under `%LocalAppData%` for per-user installs — check
there too if the `%ProgramFiles%` line comes up empty.)

---

## 4. Log in once (seed the reusable profile)

Run the login line that matches §3. For a typical Windows box with Edge:

```bat
notebooklm login --browser msedge
```

or, reading cookies from an already-signed-in Firefox:

```bat
notebooklm login --browser-cookies firefox
```

Sign in to Google when prompted. This **saves a reusable session profile on this machine** —
that stored profile is what later lets runs re-authenticate **headless** (no visible window),
which is what deep research needs. Do it once per machine.

### Headless re-auth for long / unattended runs

So a long research job can refresh its own session mid-run instead of dying, set this
environment variable. In CMD there are two forms — pick based on how long you want it to
stick:

```bat
:: current window only (gone when you close this Command Prompt)
set NOTEBOOKLM_HEADLESS_REAUTH=1

:: OR persist it for all FUTURE Command Prompts (note: no '=', and NOT applied to this window)
setx NOTEBOOKLM_HEADLESS_REAUTH 1
```

> **Note — CMD vs PowerShell:** CMD sets a session variable with `set VAR=value` (no spaces
> around `=`) and reads it back as `%VAR%`. PowerShell uses `$env:VAR = "value"` and
> `$env:VAR`. `setx` works from both but is a Windows tool, not a shell builtin: it writes to
> the registry, does **not** affect the current window, and truncates values at 1024 chars.
> After a `setx`, open a **new** Command Prompt for it to take effect.

If a run later fails with an auth error, the stored session simply expired — re-run the
`notebooklm login ...` line once to re-seed it, then continue.

---

## 5. Create a notebook and add a source

Create one notebook per **domain** (e.g. `infra`, `apps`, `ops`) — prefer a few broad
notebooks over many tiny ones.

```bat
notebooklm create "infra"
:: -> prints: created notebook <NOTEBOOK_ID>   (copy that id)
```

Upload a local Markdown/text file as a **source** (sources are what queries actually read):

```bat
notebooklm source add -n <NOTEBOOK_ID> "%USERPROFILE%\.kb\build\infra__architecture.md"
notebooklm source list -n <NOTEBOOK_ID>
:: wait until the source shows "ready" before querying it
```

Record the friendly-key → id mapping so you never paste a raw UUID again. Create
`%USERPROFILE%\.kb\notebooks.json` (Notepad is fine: `notepad "%USERPROFILE%\.kb\notebooks.json"`)
with:

```json
{ "infra": "<NOTEBOOK_ID>", "apps": "<NOTEBOOK_ID>", "ops": "<NOTEBOOK_ID>" }
```

### Copy the kit's docs and templates into your install

From the repo folder (adjust the source path to wherever you cloned this repo):

```bat
mkdir "%USERPROFILE%\.kb\memory"
copy "docs\MEMORY.template.md" "%USERPROFILE%\.kb\memory\MEMORY.md"
copy "docs\KNOWLEDGE-ROUTING.md" "%USERPROFILE%\.kb\"
copy "docs\OPERATIONS.md" "%USERPROFILE%\.kb\"
copy "docs\RESEARCH_PROMPT_TEMPLATE.md" "%USERPROFILE%\.kb\"
copy "research.sh" "%USERPROFILE%\.kb\"
```

Then edit `MEMORY.md` and fill in your own identity, projects, hard rules and notebook keys.

---

## 6. Verify the install

A quick end-to-end sanity check, all from CMD:

```bat
:: 1. venv + CLI present
notebooklm --version

:: 2. auth works and the notebook exists (lists your notebooks)
notebooklm list

:: 3. the source ingested (look for "ready")
notebooklm source list -n <NOTEBOOK_ID>

:: 4. a real query returns a grounded answer
notebooklm ask -n <NOTEBOOK_ID> "Summarize what this notebook currently covers, in 3 bullets."
```

If `ask` returns a grounded answer, the install is good. If step 2 or 4 fails with an auth
error, re-run the §4 login line.

---

## 7. Run web research (grow the corpus)

The kit ships `research.sh`, which drives the research **and verifies the sources actually
landed** (the raw CLI can exit 0 without importing anything). It's a **bash** script, so on
Windows you have two options.

### Option A — run the wrapper under Git Bash or WSL (recommended)

If you have [Git for Windows](https://git-scm.com/download/win) (Git Bash) or WSL, run it
there — you get the built-in wait-and-verify. From a Git Bash / WSL shell:

```bash
cd /c/Users/you/.kb          # Git Bash path form of C:\Users\you\.kb
./research.sh <NOTEBOOK_ID> "<research question or topic>" fast   # quick, shallow
./research.sh <NOTEBOOK_ID> "<research question or topic>" deep   # broad, multi-source
```

`deep` needs `jq` on the PATH and the §4 login already seeded; it exports
`NOTEBOOKLM_HEADLESS_REAUTH=1` for you. On success it prints a single integer (sources
added) and exits non-zero if nothing landed.

### Option B — call the CLI directly from CMD (no bash, no jq)

If you're staying in pure CMD, run the underlying command the wrapper wraps. You lose the
automatic verification, so **verify manually** afterwards:

```bat
:: for a deep run, enable headless re-auth in this window first
set NOTEBOOKLM_HEADLESS_REAUTH=1

:: fast pass
notebooklm source add-research -n <NOTEBOOK_ID> "<research question or topic>" --from web --import-all --mode fast

:: deep pass (--mode deep)
notebooklm source add-research -n <NOTEBOOK_ID> "<research question or topic>" --from web --import-all --mode deep

:: VERIFY it actually imported — the count should have gone up, and the new source "ready"
notebooklm source list -n <NOTEBOOK_ID>
```

Then read the imported material as **fulltext** (not an artifact export):

```bat
notebooklm source list -n <NOTEBOOK_ID>
notebooklm source fulltext -n <NOTEBOOK_ID> <SOURCE_ID>
```

> Because Option B skips the wrapper's count-before/count-after check, don't trust a clean
> exit — always run the `source list` step and confirm a new **ready** source appeared before
> assuming the research saved.

---

## 8. Daily reminders

- **Activate the venv in every new Command Prompt** before using the CLI:
  `"%USERPROFILE%\.kb\venv\Scripts\activate.bat"`.
- **Query before you act.** `notebooklm ask -n <NOTEBOOK_ID> "<long, specific question>"` — ask
  extensively; NotebookLM answers a well-framed question far better than a keyword.
- **Editing a notebook = re-uploading the source.** The safe order is **add-new →
  wait-ready → delete-old** (never delete first, never leave a notebook with 0 sources):
  ```bat
  notebooklm source add -n <NOTEBOOK_ID> "%USERPROFILE%\.kb\build\<key>__<topic>.md"
  notebooklm source list -n <NOTEBOOK_ID>            :: wait for "ready"
  notebooklm source delete -n <NOTEBOOK_ID> <OLD_SOURCE_ID>
  ```
- The full runbook (paths, gotchas, dedup, maintenance) is in
  `%USERPROFILE%\.kb\OPERATIONS.md`; the routing rule is in `KNOWLEDGE-ROUTING.md`.

---

## CMD vs PowerShell quick reference

Every line that differs between the two Windows shells:

| Step | Command Prompt (`cmd.exe`) | PowerShell |
|---|---|---|
| Activate venv | `"%USERPROFILE%\.kb\venv\Scripts\activate.bat"` | `& "$env:USERPROFILE\.kb\venv\Scripts\Activate.ps1"` (may need `Set-ExecutionPolicy -Scope Process RemoteSigned` once) |
| Home folder variable | `%USERPROFILE%` | `$env:USERPROFILE` |
| Read an env var | `%VAR%` | `$env:VAR` |
| Set env var (this session) | `set VAR=value` (no spaces around `=`) | `$env:VAR = "value"` |
| Set env var (persistent) | `setx VAR value` (no `=`; new window needed) | `setx VAR value` **or** `[Environment]::SetEnvironmentVariable("VAR","value","User")` |
| Headless re-auth (session) | `set NOTEBOOKLM_HEADLESS_REAUTH=1` | `$env:NOTEBOOKLM_HEADLESS_REAUTH = "1"` |
| Copy a file | `copy src dst` | `Copy-Item src dst` |
| Make a folder | `mkdir "%USERPROFILE%\.kb"` | `mkdir "$env:USERPROFILE\.kb"` |
| Test a file exists | `if exist "path" echo FOUND` | `if (Test-Path "path") { "FOUND" }` |
| Comment in a script | `:: comment` (or `rem`) | `# comment` |
| Find a command | `where notebooklm` | `Get-Command notebooklm` |

Everything else — `pip install "notebooklm-py[browser,cookies]>=0.8.2,<0.9"`, `playwright install chromium`, and all
the `notebooklm ...` subcommands — is **identical** in both shells.

---

*Generic starter kit. Placeholders only — no private data. Adapt paths, keys and CLI names to
your own install.*
