# Install on macOS (zsh)

Step-by-step setup of the NotebookLM KB System on macOS. The default shell is **zsh**, and
`research.sh` runs natively (macOS ships `bash` and Homebrew provides `jq`) — no Git Bash or
WSL needed, unlike Windows.

Every value in angle brackets is a placeholder for your own: `<YOUR_EMAIL>`,
`<NOTEBOOK_ID>`, `<SOURCE_ID>`. Don't paste real secrets into anything you commit.

> On macOS, `~` and `$HOME` are `/Users/<you>`, so `~/.kb` is your install folder.

---

## What you'll do

1. Install Python 3.11+ (Homebrew or python.org)
2. Create and activate a virtualenv (zsh)
3. Install the CLI: `pip install "notebooklm-py[browser,cookies]"`
4. Detect your browser and run `notebooklm login` with the right flag
5. Verify with a real operation
6. Create a notebook and add a source
7. Run web research with `research.sh`

---

## 1. Install Python 3.11+

Check what you already have:

```zsh
python3 --version      # 3.11 or newer? skip to §2
```

**Option A — Homebrew (recommended):**

```zsh
# Install Homebrew first if you don't have it (see https://brew.sh), then:
brew install python jq
```

`jq` is used by `research.sh` (§7) — installing it now saves a round trip. On Apple Silicon
Homebrew lives at `/opt/homebrew`; on Intel at `/usr/local`. `brew` puts `python3` on your
PATH either way.

**Option B — python.org installer:** download the macOS package from
<https://www.python.org/downloads/macos/> and run it. Then install `jq` separately with
Homebrew (`brew install jq`) if you plan to use `research.sh`.

---

## 2. Create and activate a virtualenv (zsh)

Keep the CLI and its browser automation isolated in a venv so they can't clash with the
system Python.

```zsh
mkdir -p ~/.kb
python3 -m venv ~/.kb/venv
source ~/.kb/venv/bin/activate      # do this in every new shell that runs the CLI
```

Your prompt now shows `(venv)`. Upgrade pip inside it, then leave with `deactivate` when
done:

```zsh
python -m pip install --upgrade pip
```

---

## 3. Install the CLI (with the browser extra)

```zsh
pip install "notebooklm-py[browser,cookies]"
```

> The `[browser]` extra is the optional dependency group that enables the browser-backed
> flows: **interactive login, headless re-auth, and deep research**; the `[cookies]` extra
> is what `notebooklm login --browser-cookies ...` (the Firefox/Brave path in §4) needs.
> Plain `pip install notebooklm-py` gives you only the bare CLI and fails at login/research
> later. Install the extras now.

Confirm it's on your PATH:

```zsh
notebooklm --version
notebooklm --help          # lists the verbs: notebook / source / ask / login
```

---

## 4. Detect your browser and log in

`notebooklm login` seeds a **reusable session profile** on this machine so later runs can
re-authenticate — including headless — without a visible window. Do it once per machine.

There are two login styles; the right flag depends on which browser you have:

- **`--browser chromium|chrome|msedge`** — launches that browser for an interactive Google
  sign-in.
- **`--browser-cookies chrome|firefox|brave|edge`** — reads cookies from a browser you're
  **already** signed into, instead of launching Playwright.

### 4.1 Detect what's installed

macOS apps live in `/Applications`. This block reports which browsers it finds:

```zsh
for app in \
  "Google Chrome" "Chromium" "Microsoft Edge" "Brave Browser" "Firefox"; do
  if [ -d "/Applications/$app.app" ] || [ -d "$HOME/Applications/$app.app" ]; then
    echo "FOUND  $app"
  else
    echo "-      $app (not found)"
  fi
done
```

### 4.2 Pick the login command

Choose the **first** case that matches, in this order:

| Your situation | Login command |
|---|---|
| **A.** Google Chrome / Chromium / Microsoft Edge installed | `notebooklm login --browser chrome`  ·  `--browser chromium`  ·  `--browser msedge` |
| **B.** Only Firefox or Brave | `notebooklm login --browser-cookies firefox`  ·  `--browser-cookies brave` |
| **C.** No browser at all | `playwright install chromium`, then `notebooklm login --browser chromium` |

**Case A — drive an installed browser (prefer Chrome on macOS 15+):**

```zsh
notebooklm login --browser chrome
# or:  notebooklm login --browser msedge
```

> **macOS 15 (Sequoia) and newer:** the Playwright-bundled Chromium can crash on launch. If
> `--browser chromium` fails or hangs, use a **real installed** browser instead —
> `--browser chrome` (or `--browser msedge`). This is the recommended path on current macOS.

A browser window opens; sign in with your NotebookLM Google account (`<YOUR_EMAIL>`). When
it completes, the reusable profile is saved.

**Case B — read cookies from a browser you're already signed into:**

```zsh
# Sign into Google/NotebookLM in that browser first, then:
notebooklm login --browser-cookies firefox
# or:  notebooklm login --browser-cookies brave
```

**Case C — no browser: install the Playwright Chromium, then log in with it:**

```zsh
playwright install chromium
notebooklm login --browser chromium
```

### 4.3 Headless re-auth (for long/deep runs)

Once login has seeded the profile, enable headless re-authentication so a long job (deep
research, scheduled runs) can refresh its own session mid-run instead of dying:

```zsh
export NOTEBOOKLM_HEADLESS_REAUTH=1        # this shell only
# Persist it: append the same line to ~/.zshrc
echo 'export NOTEBOOKLM_HEADLESS_REAUTH=1' >> ~/.zshrc
```

`research.sh deep` also exports this for you, so you mainly need the persistent form if you
run `add-research --deep` by hand.

> **If a later run fails with an auth error,** the stored session expired. Re-run the
> `notebooklm login ...` command from §4.2 once to re-seed it.

---

## 5. Verify with a real operation

Confirm auth actually works by hitting the service — listing notebooks is non-destructive:

```zsh
notebooklm list
```

If that returns without an auth error, you're set.

---

## 6. Create a notebook and add a source

Create one notebook per **domain** (e.g. `infra`, `apps`, `ops`). Prefer a few broad
notebooks over many tiny ones.

```zsh
# Create a notebook; note the id it prints back.
notebooklm notebook create "infra"
#   -> created notebook <NOTEBOOK_ID>

# Prepare a build-doc (the local file you edit; the notebook reads the uploaded copy).
mkdir -p ~/.kb/build
printf '# infra\n\nFirst notes.\n' > ~/.kb/build/infra__architecture.md

# Upload it as a SOURCE (what queries actually read).
notebooklm source add <NOTEBOOK_ID> ~/.kb/build/infra__architecture.md

# Confirm it ingested — wait until the source shows "ready".
notebooklm source list <NOTEBOOK_ID>
```

Record the friendly-key → id mapping so you never paste a raw UUID again — create
`~/.kb/notebooks.json`:

```json
{ "infra": "<NOTEBOOK_ID>", "apps": "<NOTEBOOK_ID>", "ops": "<NOTEBOOK_ID>" }
```

Copy the kit's docs and templates into your install (run from the repo folder):

```zsh
mkdir -p ~/.kb/memory
cp docs/MEMORY.template.md ~/.kb/memory/MEMORY.md
cp docs/KNOWLEDGE-ROUTING.md docs/OPERATIONS.md docs/RESEARCH_PROMPT_TEMPLATE.md ~/.kb/
cp research.sh ~/.kb/ && chmod +x ~/.kb/research.sh
```

Then edit `~/.kb/memory/MEMORY.md` with your own identity, projects, hard rules and keys.

Ask a question (the cheap, common operation — reading never changes the corpus):

```zsh
notebooklm ask <NOTEBOOK_ID> "<an extensive, context-rich question about your infra>"
```

> **Editing a source later** means re-uploading it: edit the build-doc, `source add` the
> new version, wait until it's **ready**, then `source delete <NOTEBOOK_ID> <OLD_SOURCE_ID>`
> — always add-new → wait-ready → delete-old, so a notebook is never left at 0 sources.
> See `docs/OPERATIONS.md`.

---

## 7. Run web research

`research.sh` drives the research, **waits** for ingestion, and **verifies** the sources
really landed (the raw CLI can exit 0 without importing anything). It runs natively on
macOS — just keep the venv active and have `jq` installed (§1):

```zsh
source ~/.kb/venv/bin/activate                                  # if not already active
~/.kb/research.sh <NOTEBOOK_ID> "<research question or topic>" fast   # quick, shallow sweep
~/.kb/research.sh <NOTEBOOK_ID> "<research question or topic>" deep   # broad, multi-source
```

On success it prints a single integer on stdout — the number of sources added — and exits
non-zero if nothing landed. `deep` exports `NOTEBOOKLM_HEADLESS_REAUTH=1` for you, so its
long headless job can refresh its own auth (needs the §4 login already seeded).

Read the imported material back with **fulltext**, not an artifact export:

```zsh
notebooklm source list <NOTEBOOK_ID>                 # find the new source id
notebooklm source fulltext <NOTEBOOK_ID> <SOURCE_ID> # the raw, usable text
```

---

## Troubleshooting

- **`notebooklm` not found** — the venv isn't active in this shell. Run
  `source ~/.kb/venv/bin/activate`.
- **Login crashes / hangs launching Chromium on macOS 15+** — use a real installed browser:
  `notebooklm login --browser chrome` (or `--browser msedge`). See §4.2, case A.
- **Login opens no window** — you have no Chromium-family browser. Either use
  `--browser-cookies firefox|brave` (§4.2 B), or `playwright install chromium` then
  `--browser chromium` (§4.2 C).
- **Auth error on a later run** — the stored session expired; re-run the `notebooklm login`
  line from §4.2 once.
- **`jq: command not found`** — install it: `brew install jq`.
- **Research seems to do nothing** — confirm auth (`notebooklm list`), then
  re-list sources; the async import can take minutes. `research.sh` waits and verifies for
  you.

---

## Quick reference (zsh)

```zsh
# One-time setup
python3 -m venv ~/.kb/venv
source ~/.kb/venv/bin/activate
python -m pip install --upgrade pip
pip install "notebooklm-py[browser,cookies]"
notebooklm login --browser chrome      # or msedge | chromium | --browser-cookies firefox|brave

# Every new shell
source ~/.kb/venv/bin/activate

# Daily
notebooklm list
notebooklm ask <NOTEBOOK_ID> "<long, contextual question>"
notebooklm source add <NOTEBOOK_ID> ~/.kb/build/<key>__<topic>.md
notebooklm source list <NOTEBOOK_ID>
notebooklm source fulltext <NOTEBOOK_ID> <SOURCE_ID>

# Research
~/.kb/research.sh <NOTEBOOK_ID> "<topic>" fast
~/.kb/research.sh <NOTEBOOK_ID> "<topic>" deep
```

---

*Part of the NotebookLM KB System. Placeholders only — no private data. See `README.md`
for the concept and `docs/OPERATIONS.md` for the full operations manual.*
