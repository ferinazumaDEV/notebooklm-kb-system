# NotebookLM KB System — a token-efficient "second brain" for AI agents

> **TL;DR — what is this?** The **NotebookLM KB System** is a self-hostable **NotebookLM CLI**
> workflow that gives an AI agent a persistent, **token-efficient second brain**: a tiny local
> memory loaded every session plus a large NotebookLM corpus queried on demand. In short, it's
> practical **AI agent memory** that can **reduce agent token cost** for broad, multi-source
> **research** by roughly **99%** versus a multi-agent web crawl.

A tiny, self-hostable knowledge base that lets an AI agent **remember a lot while loading
almost nothing** each session. It's a **second brain for LLM agents** with two write stores and
one deliberate non-store:

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
  swarm of sub-agents that each burn tokens crawling the web. (See the token-savings
  section for the numbers.)

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

- **INTERNAL** lives in `~/.kb/memory/` (see [Memory template](docs/MEMORY.template.md)).
- **EXTERNAL** lives in NotebookLM; a small `notebooks.json` maps friendly keys → ids.
- **NONE** lives nowhere — it's verified against the system (`df`, `ip a`,
  `systemctl status`, the API) the moment you need it.

The full rule, with worked examples, is in
[Knowledge routing](docs/KNOWLEDGE-ROUTING.md).

---

## Quick start

1. **Pick your terminal guide** in [Installation](#installation) below — or just run the automated installer.
2. **Run the installer:** `bash install/install.sh` (Linux/macOS) or `install/install.ps1` (Windows/PowerShell). It builds the `~/.kb/` venv, installs the CLI, and detects your browser automatically.
3. **Log in once:** `notebooklm login` — seeds a reusable, headless-capable session on this machine.
4. **First research:** `~/.kb/research.sh <NOTEBOOK_ID> "<an extensive, context-rich question>" fast`.

---

## Installation

Two ways to install: an **automated script**, or a **step-by-step guide** for your terminal.

### Automated scripts

- **Linux / macOS** → [`install/install.sh`](install/install.sh): `bash install/install.sh`
- **Windows (PowerShell)** → [`install/install.ps1`](install/install.ps1)

Both scripts create the isolated `~/.kb/` virtualenv, install `notebooklm[browser]`, install
the browser binary Playwright drives, and lay down the config skeleton. They **auto-detect a
browser you already have** (Chrome / Edge / Brave / Firefox) and drive that — **you don't need
to install a specific browser** just for this.

### Step-by-step guides

Prefer to run each step yourself, or need to troubleshoot? Follow the guide for your terminal:

- [Windows (PowerShell)](install/windows-powershell.md)
- [Windows (CMD)](install/windows-cmd.md)
- [Linux](install/linux.md)
- [macOS](install/macos.md)

---

## Documentation

The detailed manuals live in [`docs/`](docs/):

- [Operations](docs/OPERATIONS.md) — the full runbook: architecture, read/write paths, the
  add→wait→delete re-upload rule, deep-research headless auth, known gotchas, and a
  maintenance checklist.
- [Knowledge routing](docs/KNOWLEDGE-ROUTING.md) — the core 3-destination rule
  (INTERNAL / EXTERNAL / NONE): what goes where, how to split mixed learnings, and the
  one-fact-one-home rule, with a decision checklist.
- [Research prompt template](docs/RESEARCH_PROMPT_TEMPLATE.md) — prompt patterns for both
  operations: how to write specific add-research queries and how to harden `ask` prompts so
  nothing gets silently dropped (numbered answers, a forced `NOT IN SOURCES` token, a
  trailing `GAPS` section).
- [Memory template](docs/MEMORY.template.md) — a ready-to-fill template for the local memory
  index loaded every session: frontmatter format, memory types, one-line-per-entry index and
  `[[cross-linking]]`.
- [FAQ](docs/FAQ.md) — the expanded FAQ: what this is, how to run web research from the CLI,
  how much it saves, headless/server use, and when *not* to reach for NotebookLM.

---

## Project structure

```
notebooklm-kb-system/
├── README.md                        # this hub — concept, install/doc links, token math, security
├── research.sh                      # web-research wrapper: research.sh <NOTEBOOK_ID> "<query>" fast|deep
├── LICENSE                          # AGPL-3.0
├── install/
│   ├── install.sh                   # automated installer (Linux / macOS)
│   ├── install.ps1                  # automated installer (Windows / PowerShell)
│   ├── windows-powershell.md        # manual guide — Windows PowerShell
│   ├── windows-cmd.md               # manual guide — Windows Command Prompt
│   ├── linux.md                     # manual guide — Linux (Ubuntu/Debian, bash)
│   └── macos.md                     # manual guide — macOS (zsh)
└── docs/
    ├── OPERATIONS.md                # full operations runbook
    ├── KNOWLEDGE-ROUTING.md         # the 3-destination routing rule
    ├── RESEARCH_PROMPT_TEMPLATE.md  # add-research + ask() prompt patterns
    └── MEMORY.template.md           # local-memory index template
```

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
against a second source and deciding what to do. See
[Research prompt template §3](docs/RESEARCH_PROMPT_TEMPLATE.md) for exactly which jobs you
should keep on the agent's side (rating sources, verifying truth, modeling scenarios,
holding live state).

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

## FAQ

Short answers below; the [expanded FAQ](docs/FAQ.md) has the detail.

**What is the NotebookLM KB System?**
It's a self-hostable NotebookLM CLI workflow that gives an AI (or LLM) agent a persistent
"second brain." The agent loads a tiny local memory every session and queries a large
NotebookLM corpus only when a task needs it — so it remembers a lot while paying almost no
per-session token tax.

**How do I do web research with NotebookLM from the CLI?**
Run `~/.kb/research.sh <NOTEBOOK_ID> "<an extensive, context-rich question>" fast` (or `deep`).
NotebookLM performs the search-and-ingest on Google's infrastructure and saves the results as
sources in the notebook; the wrapper re-lists the sources to *verify* the import actually
happened (it never trusts the exit code). You then read the result with `kb ask` or
`kb source fulltext`.

**How much can this save vs a multi-agent research workflow?**
For broad, multi-source recon, roughly **99%**. A measured 52-agent fan-out cost about
**1.9M output tokens**; the same discovery routed through NotebookLM costs the agent only a
few thousand tokens to read the compact, cited result — because the crawl-and-summarize runs
on Google's side, outside the agent's token budget.

**Does it work headless / on a server?**
Yes. After a one-time interactive `notebooklm login`, set `NOTEBOOKLM_HEADLESS_REAUTH=1` and
deep research can refresh its own session without a visible browser window — suitable for
scheduled or non-interactive runs on a server. `fast` mode needs no extra login.

**What's the difference between local memory and a NotebookLM notebook here?**
Local memory is a handful of short Markdown files loaded on *every* run (identity, hard rules,
method corrections, work in progress) — keep it small, you pay for it each session. A notebook
is the large reference corpus (procedures, command syntax, gotchas, stable design) that costs
tokens only when you query it. One fact lives in exactly one place.

**When should I NOT use NotebookLM research?**
When you already know where a single fact lives — a direct lookup is cheaper and faster. Also
remember answers are *faithful to the corpus, not verified truth* (grounding isn't
fact-checking), and research is async with minute-scale latency. Use it as a pipeline for broad
gathering, then have the agent verify the load-bearing claims.

**Is this an official Google or NotebookLM product?**
No. It's an independent, open-source (AGPL-3.0) workflow built on top of a `notebooklm` CLI.
It isn't affiliated with, endorsed by, or supported by Google or NotebookLM.

---

## License

Licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)** — see [LICENSE](LICENSE).

Copyright (C) 2026 Fernando

**What this means:** you may use, study, modify and share this software freely, but **if you distribute it — or run a modified version as a network service (SaaS) — you must release your complete corresponding source code under the same AGPL-3.0 terms.** It cannot be taken closed-source. This is deliberate: the project is public to be shared, not made proprietary.

<!-- provenance-fingerprint: nbkb-ec948d2d85 (AGPL-3.0, github.com/ferinazuma/notebooklm-kb-system) -->
