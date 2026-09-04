# Install on Linux (Ubuntu/Debian, bash)

Step-by-step setup of the NotebookLM KB System on Linux, using `bash` and `apt`. Tested
against Ubuntu/Debian; other distros work the same way once you translate the two `apt`
lines to your package manager.

Every value in angle brackets is a placeholder for your own: `<YOUR_EMAIL>`,
`<NOTEBOOK_ID>`, `<SOURCE_ID>`. Don't paste real secrets into any file you commit.

The `notebooklm` commands below are tested with **notebooklm-py 0.8.2**. They pass the notebook
explicitly with `-n <NOTEBOOK_ID>`; run `notebooklm use <NOTEBOOK_ID>` once to set a current
notebook and you can omit `-n`.

> **Two kinds of machine.** A **desktop** (has a graphical display) can run the one-time
> interactive `notebooklm login` directly. A **headless server** (no display — a VPS, a
> box you only reach over SSH) cannot pop a browser window, so it needs a slightly
> different login path: log in on a desktop and copy the session over. Both are covered in
> §5 — §5.2 for desktops, §5.3 for headless servers.

---

## What you'll do

1. Install prerequisites with `apt` (`python3-venv`, `pip`, `jq`)
2. Create and activate a virtualenv
3. Install the CLI: `pip install "notebooklm-py[browser,cookies]"`
4. Install a Playwright browser + its system libraries
5. Detect which browser you have and run `notebooklm login` with the right flag
   (desktop in §5.2, headless server in §5.3)
6. Verify with a real operation
7. Create a notebook and add a source
8. Run web research with `./research.sh <NOTEBOOK_ID> "<query>" fast|deep`

---

## 1. Install prerequisites (apt)

You need Python 3.10+ with the **venv** and **pip** modules (Debian/Ubuntu split these into
separate packages), plus `jq` (used by `research.sh` to parse the CLI's JSON).

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip jq
```

Confirm the versions:

```bash
python3 --version        # -> Python 3.10 or newer
jq --version             # -> jq-1.x
```

> **Why `python3-venv` separately?** On a stock Debian/Ubuntu, `python3 -m venv` fails with
> *"ensurepip is not available"* until `python3-venv` is installed. The line above installs
> it up front so §2 just works.

---

## 2. Create and activate a virtualenv

Keep the CLI and its browser automation isolated in a venv so they can't clash with the
system Python (and so you never need `sudo pip`).

```bash
# Create the KB root and a venv inside it.
mkdir -p ~/.kb
python3 -m venv ~/.kb/venv

# Activate it.
source ~/.kb/venv/bin/activate
```

Your prompt now shows `(venv)`. **Activate the venv in every new shell that runs the CLI.**

Upgrade `pip` inside the fresh venv:

```bash
python -m pip install --upgrade pip
```

To leave the venv later: `deactivate`.

---

## 3. Install the CLI (with the browser extra)

```bash
pip install "notebooklm-py[browser,cookies]"
```

> The `[browser]` extra is the optional dependency group that enables the browser-backed
> flows: **interactive login, headless re-auth, and deep research**; the `[cookies]` extra
> is what `notebooklm login --browser-cookies ...` (the Firefox/Brave path in §5) needs.
> Plain `pip install notebooklm-py` gives you only the bare CLI and will fail at
> login/research later. Install the extras now to avoid a confusing "works for ask, fails
> for research" state.

Confirm the CLI is on your PATH (it lives in the venv you just activated):

```bash
notebooklm --version
notebooklm --help          # lists the available verbs (list / create / source / ask / login)
```

---

## 4. Install the Playwright browser + system libraries

The `[browser]` extra pulls in Playwright, but Playwright still needs a **browser binary**
and a set of **shared libraries** the browser links against. On a fresh server both are
missing.

```bash
# Install the browser binary Playwright drives.
playwright install chromium

# Install the OS libraries Chromium needs (fonts, X/GTK libs, etc.).
# This runs apt under the hood, so it needs sudo.
sudo ~/.kb/venv/bin/playwright install-deps chromium
```

> **Why the full path to `playwright` in the second line?** `sudo` runs with root's PATH,
> not your venv's, so a bare `sudo playwright ...` would not find the venv's `playwright`.
> Calling `~/.kb/venv/bin/playwright` explicitly points `sudo` at the right binary.
>
> `playwright install` (no `sudo`) only downloads the browser into your user profile —
> that's fine unprivileged. `playwright install-deps` installs **system** packages via
> apt, which is the one step here that legitimately needs `sudo`.

If you have Chrome/Chromium/Edge already installed system-wide (§5), you can point login at
that instead and skip `playwright install chromium` — but you still want
`install-deps` if you ever fall back to the Playwright-managed Chromium.

---

## 5. Detect your browser and log in

`notebooklm login` seeds a **reusable session profile** on this machine so later runs can
re-authenticate — including headless — without a visible window. Do it once per machine.

There are two login styles, and the right one depends on the machine and the browser:

- **`--browser chromium|chrome|msedge`** — launches that browser for an interactive Google
  sign-in. Needs a **display** (a desktop).
- **`--browser-cookies chrome|firefox|brave|edge`** — reads cookies from a browser you're
  **already** signed into on this machine, instead of launching Playwright.

### 5.1 Detect what's installed

Run this block; it reports which browsers it finds on `PATH`:

```bash
for b in \
  "google-chrome:--browser chrome" \
  "google-chrome-stable:--browser chrome" \
  "chromium:--browser chromium" \
  "chromium-browser:--browser chromium" \
  "microsoft-edge:--browser msedge" \
  "microsoft-edge-stable:--browser msedge" \
  "brave-browser:--browser-cookies brave" \
  "firefox:--browser-cookies firefox" ; do
    cmd="${b%%:*}"; flag="${b##*:}"
    if command -v "$cmd" >/dev/null 2>&1; then
      printf 'FOUND  %-22s -> notebooklm login %s\n' "$cmd" "$flag"
    fi
done
echo "(nothing above? no system browser found — use the Playwright chromium from §4)"
```

### 5.2 Pick the login command (desktop with a display)

Choose the **first** case that matches, in this order:

| Your situation | Login command |
|---|---|
| **A.** Chrome / Chromium / Edge is installed | `notebooklm login --browser chrome`  ·  `--browser chromium`  ·  `--browser msedge` |
| **B.** Only Firefox or Brave | `notebooklm login --browser-cookies firefox`  ·  `--browser-cookies brave` |
| **C.** No browser at all | `playwright install chromium` (from §4), then `notebooklm login --browser chromium` |

**Case A (a Chromium-family browser is installed):**

```bash
notebooklm login --browser chrome
# or: notebooklm login --browser chromium
# or: notebooklm login --browser msedge
```

A browser window opens; sign in with your NotebookLM Google account (`<YOUR_EMAIL>`). When
it completes, the reusable profile is saved.

**Case B (only Firefox/Brave — read cookies from the browser you're already signed into):**

```bash
# Sign into Google/NotebookLM in that browser first, then:
notebooklm login --browser-cookies firefox
# or:
# notebooklm login --browser-cookies brave
```

**Case C (no system browser):** install the Playwright-managed Chromium (§4), then:

```bash
notebooklm login --browser chromium
```

### 5.3 Headless server (no display)

On a headless box `echo "$DISPLAY"` prints nothing and an interactive `--browser` login
has no window to draw — you can't type your Google password there. Two ways around it:

**Option A — log in on a desktop, copy the session to the server (the usual path).**

1. On any machine **with a display** (your laptop, a desktop — any OS with the CLI
   installed), run the §5.2 login and complete the interactive sign-in. That writes the
   CLI's session/profile (its stored `storage_state`) into the CLI's config directory.
2. Find where the CLI keeps that profile — check the login output or
   `notebooklm login --help`; it's under the CLI's config dir, commonly
   `~/.config/notebooklm/`.
3. Copy that directory to the **same path** on the server, over SSH:

   ```bash
   # Run FROM the desktop. Replace <server> with your host/user.
   rsync -av ~/.config/notebooklm/  <server>:~/.config/notebooklm/
   # (or: scp -r ~/.config/notebooklm <server>:~/.config/ )
   ```

4. On the server, enable headless re-auth (§5.4) so the copied session can refresh itself,
   then verify with §6. The copied session is what lets the headless server run
   non-interactively.

**Option B — `--browser-cookies` (only if the server already has a signed-in browser
profile on disk).** If for some reason the server does have a browser profile you're
already logged into, `notebooklm login --browser-cookies chrome|firefox|brave|edge` reads
those cookies without opening a window. On a true headless server that profile usually
doesn't exist, so Option A is the reliable one.

### 5.4 Enable headless re-auth (for long/deep runs and all servers)

Once a session is seeded (by §5.2 or copied in via §5.3), enable headless
re-authentication so a long-running or non-interactive job can refresh its own session
mid-run instead of failing:

```bash
export NOTEBOOKLM_HEADLESS_REAUTH=1
```

Put that line in your shell profile so every shell — and every scheduled/`ssh` run — picks
it up:

```bash
echo 'export NOTEBOOKLM_HEADLESS_REAUTH=1' >> ~/.bashrc
```

`research.sh ... deep` also exports this for you, so a deep run gets it even if you forgot.
A headless server should keep it set permanently.

> **If a later run fails with an auth error,** the stored session expired. Re-run the §5.2
> login (on a desktop) and re-copy the profile per §5.3, then carry on.

---

## 6. Verify with a real operation

Confirm auth actually works by hitting the service — listing your notebooks is
non-destructive:

```bash
notebooklm list
```

If that returns without an auth error, you're set. (If your build names the verb
differently, `notebooklm --help` shows the exact subcommands — `create` in §7 is
an equally good live check.)

---

## 7. Create a notebook and add a source

Create one notebook per **domain** (e.g. `infra`, `apps`, `ops`). Prefer a few broad
notebooks over many tiny ones.

```bash
# Create a notebook; note the id it prints back.
notebooklm create "infra"
#   -> created notebook <NOTEBOOK_ID>

# Prepare a build-doc (the local file you edit; the notebook reads the uploaded copy).
mkdir -p ~/.kb/build
printf '# infra\n\nFirst notes.\n' > ~/.kb/build/infra__architecture.md

# Upload it as a SOURCE (what queries actually read).
notebooklm source add -n <NOTEBOOK_ID> ~/.kb/build/infra__architecture.md

# Confirm it ingested — wait until the source shows "ready".
notebooklm source list -n <NOTEBOOK_ID>
```

Record the friendly-key → id mapping so you never paste a raw UUID again. Create
`~/.kb/notebooks.json`:

```json
{ "infra": "<NOTEBOOK_ID>", "apps": "<NOTEBOOK_ID>", "ops": "<NOTEBOOK_ID>" }
```

Ask it a question (the cheap, common operation — reading never changes the corpus):

```bash
notebooklm ask -n <NOTEBOOK_ID> "<an extensive, context-rich question about your infra>"
```

> **Editing a source later** means re-uploading it: edit the build-doc, `source add` the
> new version, wait until it's **ready**, then `source delete -n <NOTEBOOK_ID> <OLD_SOURCE_ID>`
> — always add-new → wait-ready → delete-old, so a notebook is never left at 0 sources.
> See `docs/OPERATIONS.md` §3.

---

## 8. Run web research

`research.sh` drives the research, **waits** for ingestion, and **verifies** the sources
actually landed (the raw CLI can exit 0 without having imported anything). Put a copy in
your KB root the first time:

```bash
cp research.sh ~/.kb/ && chmod +x ~/.kb/research.sh    # first time only
```

Then run it. Make sure the venv is active first, so `notebooklm` is on `PATH`:

```bash
source ~/.kb/venv/bin/activate      # if not already active

~/.kb/research.sh <NOTEBOOK_ID> "<research question or topic>" fast   # quick, shallow sweep
~/.kb/research.sh <NOTEBOOK_ID> "<research question or topic>" deep   # broad, multi-source
```

- **fast** — a quick pass with fewer sources; good for a first look.
- **deep** — a broad, multi-source pass. It exports `NOTEBOOKLM_HEADLESS_REAUTH=1` for you
  so a long headless job can refresh its own auth mid-run. On a **headless server** keep
  that variable set permanently anyway (§5.4), and make sure the login session was seeded
  or copied in (§5.3) — deep research needs a working session to drive.
- On success the script prints a single integer on stdout: the number of sources added.
  Diagnostics go to stderr. It exits non-zero if nothing landed.

Read the imported material back with **fulltext**, not an artifact export:

```bash
notebooklm source list -n <NOTEBOOK_ID>                    # find the new source id
notebooklm source fulltext -n <NOTEBOOK_ID> <SOURCE_ID>    # the raw, usable text
```

---

## Troubleshooting

- **`notebooklm: command not found`** — the venv isn't active in this shell. Run
  `source ~/.kb/venv/bin/activate`.
- **`python3 -m venv` fails with "ensurepip is not available"** — `python3-venv` isn't
  installed. Run the §1 `apt-get install` line.
- **`playwright: command not found`** — the venv isn't active, or the `[browser]` extra
  wasn't installed. Re-activate the venv and re-run `pip install "notebooklm-py[browser,cookies]"`.
- **Chromium launches but immediately errors about a missing `.so` library** — the system
  libraries aren't installed. Run `sudo ~/.kb/venv/bin/playwright install-deps chromium`
  (§4).
- **Login opens no window / can't launch a browser** — either you have no Chromium browser
  (run `playwright install chromium`, then `notebooklm login --browser chromium`), or
  you're on a headless server with no display (`echo "$DISPLAY"` is empty) — use the §5.3
  copy-the-session path instead.
- **`sudo playwright ...` says command not found** — `sudo` uses root's PATH, not the
  venv's. Call the full path: `sudo ~/.kb/venv/bin/playwright install-deps chromium`.
- **Auth error on a later run** — the stored session expired. Re-run the §5.2 login on a
  desktop and (for a server) re-copy the profile per §5.3.
- **`research.sh: Permission denied`** — it isn't executable. Run
  `chmod +x ~/.kb/research.sh`.
- **`jq: command not found`** — install it: `sudo apt-get install -y jq` (§1).
- **Research seems to do nothing** — confirm auth (`notebooklm list`), then
  re-list sources; the async import can take minutes. `research.sh` already waits and
  verifies, and fails loudly if nothing imported.

---

## Quick reference (bash)

```bash
# One-time setup
sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip jq
mkdir -p ~/.kb && python3 -m venv ~/.kb/venv
source ~/.kb/venv/bin/activate
python -m pip install --upgrade pip
pip install "notebooklm-py[browser,cookies]"
playwright install chromium
sudo ~/.kb/venv/bin/playwright install-deps chromium

# Login — desktop (pick the flag that matches your browser)
notebooklm login --browser chrome        # or chromium | msedge
# notebooklm login --browser-cookies firefox   # or brave
# Login — headless server: log in on a desktop, then copy the session:
#   rsync -av ~/.config/notebooklm/ <server>:~/.config/notebooklm/
echo 'export NOTEBOOKLM_HEADLESS_REAUTH=1' >> ~/.bashrc   # servers + deep runs

# Every new shell
source ~/.kb/venv/bin/activate

# Daily
notebooklm list
notebooklm ask -n <NOTEBOOK_ID> "<long, contextual question>"
notebooklm source add -n <NOTEBOOK_ID> ~/.kb/build/<key>__<topic>.md
notebooklm source list -n <NOTEBOOK_ID>
notebooklm source fulltext -n <NOTEBOOK_ID> <SOURCE_ID>

# Research
cp research.sh ~/.kb/ && chmod +x ~/.kb/research.sh        # first time only
~/.kb/research.sh <NOTEBOOK_ID> "<topic>" fast             # quick, shallow sweep
~/.kb/research.sh <NOTEBOOK_ID> "<topic>" deep             # broad; sets headless re-auth
```

---

*Part of the NotebookLM KB System. Placeholders only — no private data. See `README.md`
for the concept and `docs/OPERATIONS.md` for the full operations manual.*
