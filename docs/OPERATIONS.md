# OPERATIONS — Knowledge Base System

A "second brain" for AI agents, built from two writable stores plus a deliberate third non-store:

1. **Local memory** — small Markdown files loaded into the agent every session
   (identity, hard rules, method feedback, work in progress).
2. **NotebookLM notebooks** — a larger reference corpus that is *consulted on demand*
   rather than loaded, to spend tokens slowly.
3. **NONE / discard bucket** — live, perishable data that is **never written down**
   and re-checked against the system whenever it is needed.

This document is the operating manual for maintaining that system: how the pieces fit together,
how to read from a notebook, how to write to one correctly, how to run research on the
web, and the traps that will bite you if you skip a step.

All commands below assume a CLI wrapper on your `PATH`: `kb`/`nb` stand for a tiny wrapper
you write that maps a key to a notebook id via `notebooks.json` and calls
`notebooklm ... -n <NOTEBOOK_ID>`; it is not included in this repo. Adjust names/paths to
your installation. Placeholders like `<NOTEBOOK_ID>`, `<YOUR_EMAIL>`, `<KEY>` and `~/.kb/`
stand for your own values.

---

## 1. Architecture

### The three destinations

Every durable thing you learn is routed to exactly one place. This is the most
important rule in the system; get it wrong and the KB rots.

| Destination | Store | What lives here | Examples |
|---|---|---|---|
| **INTERNAL** | Local memory files | Identity, hard rules, method feedback, active WIP | "The operator is X, not Y", "never run the build as root", "prefers overlays to cards" |
| **EXTERNAL** | A NotebookLM notebook | Reference, procedure, gotchas — anything you look up but don't need every turn | "How the deploy script works", "the API returns 403 without a custom User-Agent", tool flags |
| **NONE** | *Nowhere* — re-check live | State that changes on its own | disk %, current IP, the status of a running service, counters, a token's value, a version number |

Practical rules:

- **One fact, one home.** Don't copy a procedure into local memory *and* a notebook.
  Local memory should *point at* the notebook ("details in `<KEY>`"), not duplicate it.
- **If it's reference and it isn't local, don't guess — go ask the notebook.**
  A missing answer is a signal to consult, never to make something up.
- **If it changes on its own, don't store it.** Verify it against the system at the moment of use.
- **Partition, don't pile up.** When a notebook or a local file grows beyond its topic,
  split it before it saturates.

### Local memory layout

```
~/.kb/memory/
  MEMORY.md                 # index — the only file guaranteed loaded each session
  user_<who>.md             # identity of the operator
  project_<name>.md         # one file per active project (WIP + pointers)
  feedback_<topic>.md       # method corrections you must not repeat
  reference_<topic>.md      # small, always-needed reference (rare — most goes EXTERNAL)
```

`MEMORY.md` is an index with one-line links to the rest. Keep it light: you pay for it
in tokens every session.

### NotebookLM notebooks

Notebooks are grouped by domain (e.g. one for infrastructure, one for a build
pipeline, one for publishing, etc.). Each notebook has:

- a stable **id** (a UUID) — keep these in a small config file, not in prose;
- a set of **sources** (the uploaded documents it reasons over);
- a human-readable **title** for each source.

A tiny local config maps friendly keys to ids so you never paste a UUID by hand:

```
~/.kb/notebooks.json        # { "<KEY>": "<NOTEBOOK_ID>", ... }
~/.kb/source_titles.json    # { "<NOTEBOOK_ID>": ["Title A", "Title B", ...] }
```

Aim for a small number of broad notebooks rather than many tiny ones. When a
notebook nears its source cap or its topic clearly forks, split it.

*Dated note, 2026-09-23.* The cap has a number, per plan: 50 sources per notebook on the
standard plan, 100 on AI Plus, 300 on AI Pro, 500 and 600 on the two AI Ultra plans, in a
table Google labels "Usage Limits (Subject to Change)" (Source: [Upgrade Gemini
Notebook](https://support.google.com/gemininotebook/answer/16213268?hl=en), read 2026-09-23). Each source is capped at 500,000 words or
200 MB for local uploads, with no page limit (Source: [Gemini Notebook
FAQ](https://support.google.com/gemininotebook/answer/16269187?hl=en), read 2026-09-23). A single build-doc can therefore grow far past the
point where it should be split; the reason to split earlier is retrieval quality, not the cap.

---

## 2. Consulting a notebook (read path)

Consulting is the cheap, routine operation. Do it whenever you need reference that
isn't in local memory.

```bash
kb ask <KEY> "<an extensive, context-rich question>"
```

- **Ask with long, specific questions.** NotebookLM answers a well-framed question
  far better than a keyword. Include what you're doing, what you already know, and what
  you need to get out of it. "How do I do X?" is weak; "I'm doing X on system Y, I've
  already done Z, what are the exact steps and known failure modes of the final part?"
  is strong.
- **Consult *before* acting**, not once you're already stuck. If a canonical procedure
  exists in a notebook, read it first.
- The wrapper resolves `<KEY>` to the notebook id via `notebooks.json`, runs the
  query, and prints the grounded answer.

Reading is non-destructive. Nothing you ask changes the corpus.

*Dated note, 2026-09-23.* Reading is not free of quota. Since 2026-09-02 Gemini Notebook meters
usage by compute — prompt complexity, models, features, chat length — and the quota "refreshes
every 5 hours until you reach your weekly limit"; AI Plus is two times and AI Pro four times
the standard allowance (Source: [Usage limits for Gemini Notebook](https://support.google.com/gemininotebook/answer/17670842?hl=en&co=GENIE.Platform%3DDesktop), read
2026-09-23). A long chain of `ask` calls or studio generations can exhaust a window, so a
scheduled agent must budget for a refused ask rather than assume a fixed daily count. The
numbers themselves belong in the NONE bucket. The page meters prompts and generations, not
listing sources, which is why the healthcheck's probe stays `source list` and never `ask`
(observed, needs-verification). Whether `add-research` draws on the same quota is not stated
on that page (needs-verification, 2026-09-23).

---

## 3. Editing a notebook (write path) — the re-upload rule

> **A NotebookLM notebook reasons over its uploaded *sources*, not over a file on
> your disk.** Editing your local copy of a document changes nothing in the notebook
> until you replace the source. This is the step people forget.

Every reference document has two forms:

- the **build-doc** — the Markdown/text file you edit locally (the source of truth
  you keep on hand);
- the **source** — the copy uploaded to the notebook, which is what queries read.

They diverge the moment you edit one and not the other. So the write path is:
**edit the build-doc, then re-upload as a source, then delete the old source.**

### Correct sequence (add-new → wait-ready → delete-old)

```bash
# 1. Edit the build-doc locally.
$EDITOR ~/.kb/build/<KEY>__<topic>.md

# 2. Upload the NEW version as a source.
kb source add <KEY> ~/.kb/build/<KEY>__<topic>.md

# 3. WAIT until the new source is fully processed / "ready".
#    A source that is still ingesting will not answer queries.
kb source list <KEY>          # repeat until the new one shows ready

# 4. ONLY THEN delete the OLD source.
kb source delete <KEY> <OLD_SOURCE_ID>
```

### Why the order matters — never leave 0 sources

- **Add before you delete.** If you delete first and the upload fails, the notebook is
  left empty and *every* query against it returns nothing until you fix it. Adding
  first makes the worst case a harmless duplicate, not an outage.
- **Wait for "ready" before deleting the old one.** Deleting the old source while
  the new one is still ingesting leaves a window where the notebook has no usable
  answer for that topic.
- **A notebook must never sit at 0 sources.** Some backends won't accept queries,
  or will behave oddly, with an empty notebook. Treat "0 sources" as a broken state
  to get out of immediately.

### Deduplicate after

Once you've confirmed the new source is ready and deleted the old one, run a list to
confirm there's exactly one copy of that topic:

```bash
kb source list <KEY>
```

If a batch job or a retry left two copies, delete the stale one now. Duplicate
sources make answers inconsistent (the model may cite the old text) and eat into
the source cap.

*Dated note, 2026-09-23.* Add-before-delete needs one spare slot under the plan's source cap
— 50 per notebook on the standard plan as of 2026-09-23 (Source: [Upgrade Gemini
Notebook](https://support.google.com/gemininotebook/answer/16213268?hl=en)). At the cap, the upload of the new version fails before the old
source can be removed; keep a slot free, or split the notebook before it fills.

---

## 4. Web research (deep vs. fast)

Beyond the private corpus, the system can pull fresh material from the web and
integrate it into a notebook — useful for topics that move faster than your build-docs. Govern
this through the research helper rather than by hand:

```bash
~/.kb/research.sh <NOTEBOOK_ID> "<research question or topic>" fast
~/.kb/research.sh <NOTEBOOK_ID> "<research question or topic>" deep
```

There are two modes:

- **fast** — a quick, shallow gather. No extra login.
  **Capped at roughly ~10 sources** (observed, needs-verification) — good for a first sweep,
  not for exhaustive coverage.
- **deep** — broader, multi-source research. Requires the headless-reauth setup
  below (see §5) because it drives a real browser session.

`research.sh` wraps the underlying tool and applies your defaults. It takes the notebook id
directly — map a key to its id yourself via `notebooks.json`. Keep your settings in the
script so the caller doesn't have to remember flags.

### Reading research results — `source fulltext`, not `artifact export`

When research produces material, **read it back with the source fulltext**, not
by exporting an "artifact":

```bash
kb source fulltext <KEY> <SOURCE_ID>      # correct: the actual text you can act on
# NOT: artifact export  (returns a rendered/summary object, not the raw usable text)
```

`artifact export` gives you a packaged/rendered view; `source fulltext` gives you
the raw ingested text you can quote, chunk, and route. Use fulltext.

*Dated notes, 2026-09-23:*

- **Absence from a list is not evidence of removal — on the studio path too.** Upstream
  issue #2432 (opened 2026-09-21) reports that on 0.8.2 the artifact wait step inferred
  `REMOVED` when a generation id was missing from the studio list, while the very next
  `download` pulled a finished file; 2 false failures in 7 runs with a concurrent generation
  on the same account. The fix, PR #2433, was merged on 2026-09-23 and is in no release
  (Source: [notebooklm-py issue #2432](https://github.com/teng-lin/notebooklm-py/issues/2432)). Anyone adding audio or video
  overview generation to this kit must verify by listing or downloading, the way
  `research.sh` re-lists sources, and never by the wait verdict.
- **The Studio surface keeps growing; the rule above does not move.** Google's back-to-school
  update (rollout from 2026-09-15) adds real-time voice conversations in the mobile app, an
  in-app audio recorder, learning overviews, new quiz formats and short video overviews
  (Source: [Google Workspace Updates, 2026-09-18](https://workspaceupdates.googleblog.com/2026/09/new-back-to-school-features-and-learning-tools-available-in-Gemini-Notebook.html)). Raw text still comes from
  `source fulltext`; each new artifact type is one more target for the polling problem in the
  previous bullet.

---

## 5. Headless re-auth setup for deep research (one-time)

Deep research drives a real browser and therefore needs a valid, refreshable login
that works without a visible window. Set this up once per machine.

```bash
# 1. Install the CLI with its browser extras. [browser] already pins Playwright
#    (no separate `pip install playwright`); [cookies] is needed for
#    `login --browser-cookies` (Firefox/Brave).
pip install "notebooklm-py[browser,cookies]>=0.8.2,<0.9"

# 2. ONLY if you have no system Chrome / Chromium / Edge for Playwright to drive:
#    download Playwright's own Chromium (a bare `playwright install` would pull
#    several browsers). install/install.sh does the same check.
playwright install chromium

# 3. Log in ONCE, interactively, to seed the stored session/cookies.
notebooklm login

# 4. From then on, enable headless re-auth so deep runs can refresh the
#    session without a visible browser window.
export NOTEBOOKLM_HEADLESS_REAUTH=1
```

Put the `export` in your shell profile (or in `research.sh`) so scheduled and
non-interactive runs pick it up. With `NOTEBOOKLM_HEADLESS_REAUTH=1` set and a
session already seeded by the one-time `notebooklm login`, deep research can
re-authenticate on its own.

If deep research suddenly fails with an auth error, the stored session has expired:
re-run `notebooklm login` once (interactively) to reseed it, and carry on.

*Dated notes, 2026-09-23:*

- **The default host is `notebook.google.com` since notebooklm-py 0.8.1** (2026-08-14);
  `notebooklm.google.com` remains supported for existing setups (Source: [notebooklm-py v0.8.1
  release](https://github.com/teng-lin/notebooklm-py/releases/tag/v0.8.1)). Upstream's configuration reference constrains
  `NOTEBOOKLM_BASE_URL` to `https://notebook.google.com` (default), `https://notebooklm.google.com`
  (pre-rebrand personal host) or `https://notebooklm.cloud.google.com` (enterprise); any other
  host raises `ValueError`. The same reference lists `NOTEBOOKLM_HEADLESS_REAUTH` (enabled by the
  literal `1`) and `NOTEBOOKLM_HEADLESS_REAUTH_CDP_URL` (loopback only) (Source: [notebooklm-py
  docs/configuration.md](https://github.com/teng-lin/notebooklm-py/blob/main/docs/configuration.md), read 2026-09-23).
- **When 0.9 lands, re-test before the pin moves.** Upstream `main` already labels its
  unreleased work as v0.9 (Source: [notebooklm-py CHANGELOG, Unreleased](https://github.com/teng-lin/notebooklm-py/blob/main/CHANGELOG.md), read
  2026-09-23). What to re-run against it: the CLI shape of `source add` / `list` / `delete` /
  `fulltext`, `source add-research` with `--from web --import-all --mode`, `ask`, `auth refresh`,
  and the five real-CLI parse tests in `tests/run.sh`; then move the pin in every file that
  carries it and update the mock in `tests/bin/notebooklm`.

---

## 6. Known gotchas

- **Fast research is capped at ~10 sources** (observed, needs-verification). It's a first
  sweep, not full coverage. If you need breadth, use deep — and expect to run several passes
  and deduplicate.
- **Deep research needs the headless-reauth setup (§5).** Without the browser extra,
  a seeded `notebooklm login`, and `NOTEBOOKLM_HEADLESS_REAUTH=1`, deep runs fail to
  authenticate. This is the most common "it worked yesterday" failure.
- **Read results with `source fulltext`, not `artifact export`.** Fulltext is the raw,
  usable text; export is a rendered/summary object. Pulling export and getting a
  packaged blob is a frequent time-sink.
- **Never leave a notebook at 0 sources.** Always add-new → wait-ready → delete-old
  (§3). Deleting first turns a failed upload into an outage.
- **Wait for "ready" before deleting the old source.** A source that's ingesting can't
  answer; deleting the old one too soon opens a window with no answer.
- **Editing the build-doc does nothing until you re-upload the source.** The notebook
  reads its uploaded copy, not your disk. The divergence between build-doc and source is silent.
- **Answers are faithful to the corpus, not to the truth.** NotebookLM grounds its
  answers in the sources you gave it. If a source is wrong, stale, or biased, the
  answer will be confidently wrong the same way. Output quality = corpus quality. Curate the
  sources; don't treat a grounded answer as verified fact.
- **Ask with extensive, context-rich questions.** Short keyword queries give shallow
  answers. Lay out the full situation (§2).
- **Don't store live state.** Disk, IP, service status, tokens, versions — verify them
  from the system, never from memory (§1, NONE bucket).

---

## 7. Quick reference

```bash
# READ
kb ask <KEY> "<long, contextual question>"     # query a notebook
kb source list <KEY>                            # list sources + ready state
kb source fulltext <KEY> <SOURCE_ID>            # read raw ingested text

# WRITE (always add → wait → delete)
$EDITOR ~/.kb/build/<KEY>__<topic>.md           # edit build-doc
kb source add <KEY> <path>                       # upload new source
kb source list <KEY>                             # wait until new one is ready
kb source delete <KEY> <OLD_SOURCE_ID>           # remove stale source

# RESEARCH
~/.kb/research.sh <NOTEBOOK_ID> "<topic>" fast   # ~10-source cap (observed, needs-verification)
~/.kb/research.sh <NOTEBOOK_ID> "<topic>" deep   # deep (needs §5)

# ONE-TIME DEEP SETUP
pip install "notebooklm-py[browser,cookies]>=0.8.2,<0.9"
playwright install chromium                      # only if no system Chrome/Chromium/Edge
notebooklm login
export NOTEBOOKLM_HEADLESS_REAUTH=1

# AUTH RECOVERY
notebooklm login                                 # reseed an expired session
```

---

## 8. Maintenance checklist

- [ ] `MEMORY.md` is kept as a light index; heavy content lives in linked files or notebooks.
- [ ] Every durable learning is routed to exactly one of INTERNAL / EXTERNAL / NONE.
- [ ] No fact is duplicated across stores.
- [ ] Every edit to a build-doc is followed by a re-upload (add → wait → delete).
- [ ] No notebook is ever left at 0 sources or with stale duplicates.
- [ ] `notebooks.json` / `source_titles.json` are kept in sync with the real notebooks.
- [ ] Deep-research auth is seeded and `NOTEBOOKLM_HEADLESS_REAUTH=1` is exported.
- [ ] Sources are curated for accuracy — the corpus is the ceiling on answer quality.
