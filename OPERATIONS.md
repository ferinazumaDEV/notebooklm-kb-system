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

All commands below assume a CLI wrapper on your `PATH`. Adjust names/paths to your
installation. Placeholders like `<NOTEBOOK_ID>`, `<YOUR_EMAIL>`, `<KEY>` and `~/.kb/`
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

---

## 4. Web research (deep vs. fast)

Beyond the private corpus, the system can pull fresh material from the web and
integrate it into a notebook — useful for topics that move faster than your build-docs. Govern
this through the research helper rather than by hand:

```bash
~/.kb/research.sh "<research question or topic>"
# optional flags the script forwards, e.g.:
~/.kb/research.sh --mode fast "<topic>"
~/.kb/research.sh --mode deep --into <KEY> "<topic>"
```

There are two modes:

- **fast** — a quick, shallow gather. No extra login. **Capped at roughly ~10
  sources** — good for a first sweep, not for exhaustive coverage.
- **deep** — broader, multi-source research. Requires the headless-reauth setup
  below (see §5) because it drives a real browser session.

`research.sh` wraps the underlying tool, applies your defaults, and (when `--into` is given)
hands the results to a notebook. Keep your settings in the script so the caller
doesn't have to remember flags.

### Reading research results — `source fulltext`, not `artifact export`

When research produces material, **read it back with the source fulltext**, not
by exporting an "artifact":

```bash
kb source fulltext <KEY> <SOURCE_ID>      # correct: the actual text you can act on
# NOT: artifact export  (returns a rendered/summary object, not the raw usable text)
```

`artifact export` gives you a packaged/rendered view; `source fulltext` gives you
the raw ingested text you can quote, chunk, and route. Use fulltext.

---

## 5. Headless re-auth setup for deep research (one-time)

Deep research drives a real browser and therefore needs a valid, refreshable login
that works without a visible window. Set this up once per machine.

```bash
# 1. Install the browser automation library and its browser binaries.
pip install playwright
playwright install            # or: playwright install chromium

# 2. Install the tool's browser extra (the optional dependency group that
#    enables browser-backed / deep flows).
pip install "notebooklm[browser]"

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

---

## 6. Known gotchas

- **Fast research is capped at ~10 sources.** It's a first sweep, not full coverage. If
  you need breadth, use deep — and expect to run several passes and deduplicate.
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
~/.kb/research.sh "<topic>"                       # fast (~10 source cap)
~/.kb/research.sh --mode deep --into <KEY> "<topic>"   # deep (needs §5)

# ONE-TIME DEEP SETUP
pip install playwright && playwright install
pip install "notebooklm[browser]"
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
