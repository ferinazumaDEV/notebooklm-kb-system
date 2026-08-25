# NotebookLM KB System — a token-efficient "second brain" for AI agents

A tiny, self-hostable knowledge base that lets an AI agent **remember a lot while loading
almost nothing** each session. It has two write stores and one deliberate non-store:

- **Local memory** — a handful of short Markdown files, loaded into the agent's context on
  *every* run. Small on purpose (you pay for it in tokens each session).
- **NotebookLM notebooks** — a large reference corpus you **query on demand** instead of
  loading. It's free to keep big; it only costs tokens when you ask.
- **A discard bucket** — live, perishable data (disk %, IPs, tokens, "is the service up?")
  that is **never written down** and is re-verified from the system when needed.

What ties it all together is a **3-destination routing rule** (INTERNAL / EXTERNAL / NONE)
that decides where each new learning goes, and a **web research** step that offloads broad
discovery onto NotebookLM's own infrastructure — so the agent pays for a compact result,
not for reading the whole internet.

> Everything in this repo is generic. Every email, ID, path and name is a placeholder
> (`<YOUR_EMAIL>`, `<NOTEBOOK_ID>`, `<YOUR_PROJECT>`, `~/.kb/`). Don't put real secrets here.

---

## 1. What this is

An AI agent has a fixed, expensive context window. Two bad habits waste it:

1. **Loading everything up front** — dumping a wiki into the prompt "just in case."
2. **Re-deriving knowledge every session** — re-reading the same big documents, or doing a
   broad web recon from scratch, over and over.

This system fixes both:

- **Load only what you must know *before* you can act** — identity, hard rules, method
  corrections, and a pointer to what's in progress. That's the **local memory**. It's kept
  short so the per-session token tax is minimal.
- **Everything else is reference** — architecture, procedures, command syntax, gotchas,
  dead ends, stable design. That goes to the **NotebookLM notebooks** and is pulled in only
  when a task actually needs it, one grounded answer at a time.
- **Discovery is offloaded.** When you need broad, multi-source research, NotebookLM's
  **add-research** flow runs the search-and-ingest on Google's infrastructure. The agent
  then reads a compact, cited synthesis — a few thousand tokens — instead of unleashing a
  swarm of sub-agents that each burn tokens crawling the web. (See §6 for the numbers.)

The result is a "second brain" that's cheap to carry, deep to query, and honest about what
it doesn't know.

---

## 2. Architecture

Three destinations, one routing decision, two query paths.

```
                            A NEW LEARNING
                                  │
                    ┌─────────────┼──────────────┐
                    ▼             ▼               ▼
                INTERNAL       EXTERNAL          NONE
             (local memory)  (NB notebook)    (discard)
             ─────────────   ─────────────   ─────────────
             identity        reference       live state:
             hard rules      procedures      disk %, IPs,
             method fixes    commands        counters,
             open WIP        gotchas         tokens,
                            dead ends        versions,
                            stable design    "is it up?"
             ─────────────   ─────────────   ─────────────
             LOADED every    QUERIED on      NEVER stored —
             session         demand          verify live
             (keep short)    (keep big)      from the system


        READ PATH (cheap, common)          WRITE PATH (grow the corpus)
        ─────────────────────────          ────────────────────────────
        agent ── ask ──▶ NotebookLM        edit build-doc ──▶ source add
                 ◀── grounded answer                     ──▶ wait "ready"
                     (few-K tokens)                      ──▶ delete old source

                              research.sh <ID> "<query>" fast|deep
                                          │
                                          ▼
                         NotebookLM runs search+ingest on Google infra
                                          │
                                          ▼
                         agent reads the compact result (~few-K tokens)
```

- **INTERNAL** lives in `~/.kb/memory/` (see `MEMORY.template.md`).
- **EXTERNAL** lives in NotebookLM; a small `notebooks.json` maps friendly keys → ids.
- **NONE** lives nowhere — it's verified against the system (`df`, `ip a`,
  `systemctl status`, the API) the moment you need it.

The full rule, with worked examples, is in **`KNOWLEDGE-ROUTING.md`**.

---

## 3. Prerequisites and installation

You need **Python 3.9+**, `jq` (used by `research.sh`) and a Google account that can use
NotebookLM.

### 3.1 Create a virtualenv and install the CLI

Keep the CLI and its browser automation isolated in a venv so they can't clash with the
system Python.

```bash
mkdir -p ~/.kb
python3 -m venv ~/.kb/venv
source ~/.kb/venv/bin/activate      # do this in every shell that runs the CLI

# The CLI, WITH the browser extra (the optional dependency group that enables the
# browser-backed flows: interactive login, headless re-auth, and deep research).
pip install "notebooklm[browser]"

# Install the browser binary Playwright drives.
playwright install chromium
```

> `pip install notebooklm` on its own gives you the bare CLI, but the `[browser]` extra is
> mandatory for login and deep research. Install the extra now to avoid a confusing "works
> for ask, fails for research" state later.

### 3.2 Log in once (seed the reusable profile)

```bash
notebooklm login
```

This opens a browser once, you sign in interactively, and it **saves a reusable browser /
session profile** on this machine. That stored profile is what lets later runs
re-authenticate **headless** — with no visible window — which is what deep research needs.
Do it once per machine.

For non-interactive / scheduled runs, enable headless re-authentication so a long job can
refresh its own session mid-run instead of dying:

```bash
export NOTEBOOKLM_HEADLESS_REAUTH=1   # put this in your shell profile or in research.sh
```

If a run later fails with an auth error, the stored session expired — just re-run
`notebooklm login` once to re-seed it.

### 3.3 Create notebooks and add file sources

Create one notebook per **domain** (e.g. `infra`, `apps`, `ops`). Prefer a few broad
notebooks over many tiny ones.

```bash
# Create a notebook; note the id it prints back.
notebooklm notebook create "infra"
#   -> created notebook <NOTEBOOK_ID>

# Upload a local Markdown/text file as a SOURCE (what queries actually read).
notebooklm source add <NOTEBOOK_ID> ~/.kb/build/infra__architecture.md

# Confirm it ingested.
notebooklm source list <NOTEBOOK_ID>     # wait until the source shows "ready"
```

Record the mapping so you never paste a raw UUID again:

```bash
# ~/.kb/notebooks.json   — friendly key -> notebook id
{ "infra": "<NOTEBOOK_ID>", "apps": "<NOTEBOOK_ID>", "ops": "<NOTEBOOK_ID>" }
```

Copy `MEMORY.template.md` into place and fill in your own identity, projects, rules and
notebook keys:

```bash
mkdir -p ~/.kb/memory
cp MEMORY.template.md ~/.kb/memory/MEMORY.md
cp KNOWLEDGE-ROUTING.md OPERATIONS.md RESEARCH_PROMPT_TEMPLATE.md ~/.kb/
cp research.sh ~/.kb/ && chmod +x ~/.kb/research.sh
```

---

## 4. Daily use

### 4.1 Query a notebook (the cheap, common operation)

```bash
notebooklm ask <NOTEBOOK_ID> "<an extensive, context-rich question>"
```

- **Ask long and specific.** NotebookLM answers a well-framed question far better than a
  keyword. Say what you're doing, what you already know, and what you need out of it.
- **Query *before* you act**, not once you're stuck — if a canonical procedure lives in a
  notebook, read it first instead of reconstructing it from memory.
- Reading is non-destructive; nothing you ask changes the corpus.

See **`RESEARCH_PROMPT_TEMPLATE.md`** for prompt patterns that stop NotebookLM from
silently dropping parts of a multi-part question (numbered answers, a forced
`NOT IN SOURCES` token, a trailing `GAPS` section).

### 4.2 Run web research (grow the corpus)

Use the wrapper — it drives the research, **waits** for ingestion and **verifies** the
sources actually landed (the raw CLI can exit 0 without having imported anything):

```bash
./research.sh <NOTEBOOK_ID> "<research question or topic>" fast   # quick, shallow sweep
./research.sh <NOTEBOOK_ID> "<research question or topic>" deep   # broad, multi-source
```

- **fast** — a quick pass with fewer sources; good for a first look.
- **deep** — a broad, multi-source pass; it exports `NOTEBOOKLM_HEADLESS_REAUTH=1` for you
  so a long headless job can refresh its own auth. Needs the §3.2 login already seeded.
- On success, the script prints a single integer on stdout: the number of sources added.
  Diagnostics go to stderr. It exits non-zero if nothing landed.

Then re-read the imported material with **fulltext**, not an artifact export:

```bash
notebooklm source list <NOTEBOOK_ID>                 # find the new source id
notebooklm source fulltext <NOTEBOOK_ID> <SOURCE_ID> # the raw, usable text
```

### 4.3 The local memory + routing flow

Whenever you learn something durable, **route it before you save it**:

1. **Does it change on its own?** (disk, IPs, counters, tokens, versions) → **NONE.**
   Verify it live; don't write it down.
2. **Must the agent know it *before* acting, every session?** (identity, a hard rule, a
   method correction, a pointer to current WIP) → **INTERNAL.** One line in `MEMORY.md`,
   linked to the detail.
3. **Everything else** — reference, procedure, command, gotcha, dead end, stable design →
   **EXTERNAL.** Put it in the right notebook; leave at most a pointer in `MEMORY.md`.
4. **Is it actually several facts?** → **split it** and route each piece.
5. **Already stored?** → **don't duplicate.** One fact, one home.

The canonical rule (with examples of how to split mixed learnings) is in
**`KNOWLEDGE-ROUTING.md`**; the memory-file format is in **`MEMORY.template.md`**.

---

## 5. Maintenance

### 5.1 Editing a notebook means re-uploading the source

A NotebookLM notebook reasons over its **uploaded sources**, not a file on your disk.
Editing your local **build-doc** changes nothing in the notebook until you replace the
source. The safe sequence is **add-new → wait-ready → delete-old** (never delete first):

```bash
# 1. Edit the build-doc locally.
$EDITOR ~/.kb/build/<key>__<topic>.md

# 2. Upload the NEW version as a source.
notebooklm source add <NOTEBOOK_ID> ~/.kb/build/<key>__<topic>.md

# 3. WAIT until the new source shows "ready" (an ingesting source can't answer).
notebooklm source list <NOTEBOOK_ID>

# 4. ONLY THEN delete the OLD source.
notebooklm source delete <NOTEBOOK_ID> <OLD_SOURCE_ID>
```

Why the order: **add before delete** means a failed upload leaves a harmless duplicate,
not an empty notebook. **A notebook should never be left with 0 sources** — some backends
reject queries or misbehave when empty. Treat "0 sources" as a broken state to escape
immediately.

### 5.2 Verify with a check

After any write, list again and confirm exactly **one ready copy** of the topic:

```bash
notebooklm source list <NOTEBOOK_ID>   # exactly one ready copy per topic? good.
```

`research.sh` already has this verification built in for the research path: it snapshots
the source count *before*, polls until nothing is still "preparing", then compares the
*after* count — and fails loudly if nothing really imported. For your own manual edits, a
small wrapper that lists the sources and greps for duplicates / non-ready states is a handy
`check` script. The full runbook (with the dedup step and every gotcha) is in
**`OPERATIONS.md`**.

---

## Token savings (the whole point)

The reason to route discovery through NotebookLM instead of a multi-agent crawl inside the
agent is cost. The expensive part of broad research is **generation** — every sub-agent
that reads pages and writes notes bills output tokens. NotebookLM moves that whole
search-and-summarize step onto **Google's own infrastructure**: the `add-research` and
`ask` calls cost the agent ~**0 tokens** to run, and the agent only pays to read the
compact result that comes back.

### The comparison

| | Broad recon via NotebookLM | Broad recon via a multi-agent LLM swarm |
|---|---|---|
| Where the crawl+summarize runs | Google infra (outside your token budget) | Your model — each sub-agent bills output tokens |
| Agent tokens per research | **~a few thousand** (read the result) | **~1.9M output tokens** (measured, a real 52-agent fan-out) |
| Latency | minutes (async) | minutes (in parallel) |
| What you get | faithful, cited synthesis of the corpus | a synthesized report |

For a broad recon that's roughly **1.9M → ~5K agent tokens — about a 99% reduction.**

### Rough per-research and monthly math

Illustrative, to show the order of magnitude (plug in your own rates):

- **Per broad research:** ~5K tokens (NotebookLM path) vs ~1.9M tokens (swarm path).
- **~20 broad recons/month:** ~0.1M tokens vs ~38M tokens — a gap of roughly
  **~37.9M tokens/month**, the same ~99% savings carried across the month.

The savings compound every time you *re-query* the corpus too: an `ask` against an existing
notebook is a few-K-token read forever, versus re-running the whole recon.

### Honest caveats — it's a hybrid, not a silver bullet

This advantage is real but **narrow**. Don't oversell it.

- **Only for broad, multi-source recon.** For a single fact you already know where to find,
  a direct lookup is cheaper and faster than kicking off a research. NotebookLM pays off
  when you'd otherwise have to fan out across many sources.
- **Quality is faithful-to-corpus, not verified truth.** NotebookLM grounds answers in the
  sources it was given. If a source is wrong, stale or biased, the answer is wrong with the
  same confidence. Grounding is not fact-checking.
- **Latency is minutes.** Research is async; it's not an interactive search.

So use it as a **pipeline, not a substitute for judgment**:

```
NotebookLM  →  discovery + first-synthesis (cheap, faithful, gap-flagged)
   the agent  →  verify load-bearing claims + reason + decide (the expensive part, kept small)
```

NotebookLM does the broad, cheap gathering; the agent spends its (now small) token budget
on the part that really needs a mind — cross-checking the claims that hold up the decision
against a second source and deciding what to do. See **`RESEARCH_PROMPT_TEMPLATE.md` §3**
for exactly which jobs you should keep on the agent's side (rating sources, verifying
truth, modeling scenarios, holding live state).

---

## Security

This is a knowledge base, and knowledge bases leak if you let them.

- **Never put secrets in a notebook.** Tokens, keys, passwords, session credentials — none
  of that belongs in a source document. Notebook content is reference, not a vault. If a
  procedure needs a secret, write "pull it from `<secret store>`", not the secret itself.
- **Never commit secrets to this repo.** Every email, IP, notebook id, path and name in
  these files is a deliberate **placeholder** (`<YOUR_EMAIL>`, `<NOTEBOOK_ID>`, `~/.kb/`,
  `<YOUR_PROJECT>`). Keep your real values in your local `~/.kb/` install and in a
  gitignored config — not in anything you publish.
- **Live state isn't stored anyway.** The NONE bucket already keeps tokens, IPs and service
  state out of both stores by design — verify them from the system at the moment of use.
- **Keep `notebooks.json` / the auth profile local.** The key→id map and the browser
  profile that `notebooklm login` seeds are machine-local; don't commit or share them.
- **Sweep before you publish.** grep the tree for emails, IPv4 addresses, token-shaped
  strings (`ghp_`, `sk-`, `AIza`, `xox`, `key`) and UUIDs before pushing anything public.

---

## Files in this kit

| File | What it's for |
|---|---|
| **`README.md`** | This guide — what the system is, how to install it, use it daily, and why it saves tokens. |
| **`KNOWLEDGE-ROUTING.md`** | The core 3-destination rule (INTERNAL / EXTERNAL / NONE): what goes where, how to split mixed learnings, and the one-fact-one-home rule, with a decision checklist. |
| **`MEMORY.template.md`** | A ready-to-fill template for the local memory index — the file loaded every session. Frontmatter format, memory types, one-line-per-entry index and `[[cross-linking]]`. |
| **`OPERATIONS.md`** | The full operations manual: architecture, read/write paths, the add→wait→delete re-upload rule, deep-research headless auth, known gotchas and a maintenance checklist. |
| **`RESEARCH_PROMPT_TEMPLATE.md`** | Prompt-engineering cheat sheet for both operations: how to write specific add-research queries and how to harden `ask` prompts so nothing gets silently dropped. |
| **`research.sh`** | The web research wrapper: `./research.sh <NOTEBOOK_ID> "<query>" fast\|deep`. Runs the research, waits for ingestion and verifies the sources really landed (prints the added count). |

---

*Generic starter kit. Placeholders only — no private data. Adapt paths, keys and CLI names
to your own install.*

## License

Licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)** — see [LICENSE](LICENSE).

Copyright (C) 2026 Fernando

**What this means:** you may use, study, modify and share this software freely, but **if you distribute it — or run a modified version as a network service (SaaS) — you must release your complete corresponding source code under the same AGPL-3.0 terms.** It cannot be taken closed-source. This is deliberate: the project is public to be shared, not made proprietary.
