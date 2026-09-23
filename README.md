# NotebookLM KB System — a token-efficient "second brain" for AI agents

[English](README.md) · **Español**: [README.es.md](README.es.md)

> **TL;DR — what is this?** The **NotebookLM KB System** is a self-hostable **NotebookLM CLI**
> workflow that gives an AI agent a persistent, **token-efficient second brain**: a tiny local
> memory loaded every session plus a large NotebookLM corpus queried on demand. In short, it's
> practical **AI agent memory** that can **reduce agent token cost** for broad, multi-source
> **research** by **~99% of the output tokens billed to the agent — in one documented comparison** (n = 1; see *Token savings*) versus a multi-agent web crawl.

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
2. **Run the installer** (needs Python 3.10+): `bash install/install.sh` (Linux/macOS) or `install/install.ps1` (Windows/PowerShell). It builds the `~/.kb/venv` virtualenv (Windows: `$HOME\.kb\venv`), installs the CLI, and detects your browser automatically.
3. **Log in once:** `notebooklm login` — seeds a reusable, headless-capable session on this machine.
4. **First research:** `~/.kb/research.sh <NOTEBOOK_ID> "<an extensive, context-rich question>" fast`.

---

## Installation

> ### Read this before you install
>
> **This kit drives an unofficial CLI.** It is built on
> [`notebooklm-py`](https://pypi.org/project/notebooklm-py/) by Teng Lin, a community
> project that automates a browser session against NotebookLM. It is **not** a Google
> product, there is no supported API behind it, and neither this repository nor
> `notebooklm-py` is affiliated with or endorsed by Google.
>
> *Dated note, 2026-09-23.* Two things have moved around the paragraph above without changing it:
>
> - **The product is now called Gemini Notebook.** Google renamed NotebookLM to Gemini Notebook on
>   2026-07-16, "the same standalone product"; existing shared notebooks and links keep working
>   through automatic redirects (Source: [blog.google](https://blog.google/innovation-and-ai/products/gemini-notebook/notebooklm-gemini-notebook/),
>   [Google Workspace Updates](https://workspaceupdates.googleblog.com/2026/07/notebooklm-now-gemini-notebook.html)). This repository, the `notebooklm-py`
>   package and the `notebooklm` command keep the old name.
> - **"No supported API" is true of the consumer product this kit drives.** Google Cloud publishes a
>   Preview API (Pre-GA terms) for *Gemini Notebook Enterprise* that covers notebooks, sources and
>   audio overviews; its documented pages contain no ask/chat operation as of 2026-09-23, so it
>   does not replace the browser-session CLI for this kit's read path (Source: Gemini Notebook
>   Enterprise API, [notebooks](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-notebooks) and [sources](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-notebooks-sources), both
>   "Last updated 2026-09-22 UTC"). The absence of a query endpoint is an observation of those
>   pages, not a Google statement.
>
> What follows from that, in practice:
>
> - **Google can break it without notice.** A change to NotebookLM's web app is enough.
>   When that happens the fix lives upstream, not here.
> - **Authentication is a browser session, not a token.** It expires on its own schedule
>   and can fail *silently* — `doctor` and `auth check` report "valid" while every real
>   call fails. That is why `healthcheck.sh` exists. See
>   [docs/AUTH-RESILIENCE.md](docs/AUTH-RESILIENCE.md).
> - **Everything you put in a notebook goes to Google.** That is the design, not a leak.
>   A notebook is reference material, never a vault — see [Security](#security).
> - **Treat this as a laboratory, not infrastructure.** It is useful and it is tested,
>   but do not put anything on its critical path that you cannot do by hand.
>
> The full risk notes are in [docs/FAQ.md](docs/FAQ.md) and
> [SECURITY.md](SECURITY.md).

Two ways to install: an **automated script**, or a **step-by-step guide** for your terminal.

### Automated scripts

- **Linux / macOS** → [`install/install.sh`](install/install.sh): `bash install/install.sh`
- **Windows (PowerShell)** → [`install/install.ps1`](install/install.ps1)

Both scripts create the virtualenv (`~/.kb/venv`, Windows `$HOME\.kb\venv`), install the CLI
with its browser extras (`notebooklm-py[browser,cookies]>=0.8.2,<0.9`), and **detect a browser you already
have** (Chrome / Chromium / Edge / Brave / Firefox); only if none is found do they download
Playwright's Chromium. They do not create the `~/.kb/` config files — the printed next steps
show how. On a fresh Linux server also run `sudo ~/.kb/venv/bin/playwright install-deps chromium`
([install/linux.md §4](install/linux.md)).

### Step-by-step guides

Prefer to run each step yourself, or need to troubleshoot? Follow the guide for your terminal:

- [Windows (PowerShell)](install/windows-powershell.md)
- [Windows (CMD)](install/windows-cmd.md)
- [Linux](install/linux.md)
- [macOS](install/macos.md)

---

## Compatibility and what is actually tested

### Versions

| Component | Supported | Notes |
|---|---|---|
| `notebooklm-py` | **`>=0.8.2,<0.9`** | Pinned. 0.8.2 changed the CLI shape this kit drives; the upper bound is deliberate, not laziness. |
| Python | **3.10+** | `notebooklm-py` declares `Requires-Python >=3.10`; the installer refuses anything older. |
| Linux | supported | Installer + [guide](install/linux.md). On a fresh server also run `playwright install-deps chromium`. |
| macOS | supported | Installer + [guide](install/macos.md). Uses BSD-tool alternatives where GNU ones differ. |
| Windows | supported | [PowerShell](install/windows-powershell.md) and [CMD](install/windows-cmd.md) guides, plus `install/install.ps1`. |
| Browsers | Chrome · Chromium · Edge · Brave · Firefox | Any one you already have. Playwright's Chromium is downloaded only if none is found. |

**When `notebooklm-py` releases 0.9**, this kit does not follow automatically. The pin has
to be raised deliberately, after checking that the CLI shape the scripts depend on has not
changed again — which is the whole reason the pin exists.

*Dated notes, 2026-09-23:*

- 0.8.2, released 2026-09-02, is the latest `notebooklm-py` on PyPI, so the `>=0.8.2,<0.9` pin
  currently resolves to exactly one release; `Requires-Python` is still `>=3.10`
  (Source: [PyPI JSON for notebooklm-py](https://pypi.org/pypi/notebooklm-py/json)).
- Upstream `main` already labels its unreleased work as v0.9: the Unreleased section of its
  changelog deprecates `client.rpc_call(...)` "in v0.9.0 for removal in v1.0" and makes the MCP
  stdio `source_add` host-path file-add default-deny (Source: [notebooklm-py CHANGELOG,
  Unreleased](https://github.com/teng-lin/notebooklm-py/blob/main/CHANGELOG.md), read 2026-09-23). The pin will therefore exclude the very next
  upstream release by design; the real-CLI test block has to pass against 0.9 before it moves.
- Python 3.10 reaches end of life in October 2026 (Source: [Python Developer's Guide,
  versions](https://devguide.python.org/versions/)). The 3.10 floor is upstream's declaration, not this kit's choice;
  when upstream raises it, the installer's check follows.

### What the tests cover, and what they do not

`bash tests/run.sh` → **21 passed, 1 skipped** on a clean machine.

| Covered without a network or an account | How |
|---|---|
| All four scripts parse | `bash -n` |
| `research.sh` argument handling, modes, and the exact CLI invocation it builds | a **mock `notebooklm`** binary in `tests/bin` records what it was called with |
| A query that looks like a flag (`--help`) is passed as a query, not parsed as one | same mock |
| `healthcheck.sh` failure classification, including the `AUTH_REQUIRED` envelope | same mock |

That is the part CI runs on every push, and it needs **no Google account and no credentials** —
which is the point: a suite that required a live session could not run in CI at all.

| **Not** covered automatically | Why |
|---|---|
| That the real CLI still accepts the commands these scripts build | Needs `notebooklm-py` installed. The harness *does* test this — `NOTEBOOKLM_REAL_CLI=/path/to/venv/bin/notebooklm bash tests/run.sh` runs five extra checks that reach the auth gate and assert there are no parse errors — but it is skipped when the binary is absent, which is the `1 skipped` above. |
| That NotebookLM itself still behaves | No API, no contract. Only observation. |
| Login, session renewal, and actual research runs | Require a real Google session. `healthcheck.sh` exists precisely because these fail *silently*. |

**Run the skipped block before trusting an upgrade.** It is the one check that catches the
failure mode this kit has actually suffered: the scripts calling a CLI shape that no longer
exists.

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
- [Auth resilience](docs/AUTH-RESILIENCE.md) — keep the browser-session auth from failing
  silently. Why a frequent keepalive alone **doesn't** stop the multi-day death (device-bound
  tokens), the real prevention (exercise the profile with a real browser / a host-local device
  key), a real-operation healthcheck that emails you, a hardened wrapper, a local degraded mode,
  and why *not* to use a Google master token.

---

## Project structure

```
notebooklm-kb-system/
├── README.md                        # this hub — concept, install/doc links, token math, security
├── research.sh                      # web-research wrapper: research.sh <NOTEBOOK_ID> "<query>" fast|deep
├── healthcheck.sh                   # auth healthcheck + email alert (see docs/AUTH-RESILIENCE.md)
├── LICENSE                          # AGPL-3.0-or-later
├── tests/
│   ├── run.sh                       # bash tests/run.sh — behaviour tests for both scripts (see below)
│   └── bin/notebooklm               # strict mock of the notebooklm-py 0.8.2 CLI surface the scripts use
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
    ├── MEMORY.template.md           # local-memory index template
    ├── FAQ.md                       # expanded FAQ
    └── AUTH-RESILIENCE.md           # keep browser-session auth from failing silently
```

**Tests:** `bash tests/run.sh` (needs `bash` + `jq`, no network) drives `research.sh` and
`healthcheck.sh` against a strict mock of the CLI — count-before/after, polling, timeouts,
the alert/cooldown/re-auth cascade — and checks the scripts call the CLI in the shape
notebooklm-py 0.8.2 accepts. Point `NOTEBOOKLM_REAL_CLI` at a notebooklm-py install (or have
`notebooklm` on `PATH`) and it also runs the same commands against the real CLI with an empty
`HOME`: they must fail on auth (rc 1), never on argument parsing (rc 2).

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

For that one broad recon: **1.9M → ~5K agent tokens, about a 99% reduction — measured once.**

**What that number is, and is not.** It is one task, run one time, counting only the output tokens billed to the agent; NotebookLM's own compute is not counted, the two outputs were not scored for equal quality, and run-to-run variability was not measured. It is a documented observation, not a rate. A small benchmark — corpus, question, redacted outputs, token counter, denominator, repetitions, quality criteria — is the honest next step, and until it exists the figure should be read as *what happened once*.

### Rough per-research and monthly math

Illustrative, to show the order of magnitude (plug in your own rates):

- **Per broad research:** ~5K tokens (NotebookLM path) vs ~1.9M tokens (swarm path).
- **~20 broad recons/month:** ~0.1M tokens vs ~38M tokens — a gap of roughly
  **~37.9M tokens/month** — *if* that single comparison were typical, which has not been tested. This is arithmetic on n = 1, shown for scale, not a monthly saving anyone has measured.

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
happened (it never trusts the exit code). You then read the result with
`notebooklm ask -n <NOTEBOOK_ID> "<question>"` or `notebooklm source fulltext -n <NOTEBOOK_ID> <SOURCE_ID>`.

**How much can this save vs a multi-agent research workflow?**
In the one comparison measured, **~99% of the output tokens billed to the agent**. A 52-agent fan-out cost about
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
No. It's an independent, open-source (AGPL-3.0-or-later) workflow built on top of the unofficial
`notebooklm-py` CLI by Teng Lin (<https://github.com/teng-lin/notebooklm-py>, MIT); tested with
notebooklm-py 0.8.2. It isn't affiliated with, endorsed by, or supported by Google or NotebookLM.
*Dated note, 2026-09-23.* Google renamed the product Gemini Notebook on 2026-07-16 (Source:
[blog.google](https://blog.google/innovation-and-ai/products/gemini-notebook/notebooklm-gemini-notebook/)); the names in this repository and in the CLI are unchanged.
The upstream 0.8.2 release notes say of its own transports that "both backends rely on
undocumented Google APIs and may change without notice" (Source: [notebooklm-py v0.8.2
release](https://github.com/teng-lin/notebooklm-py/releases/tag/v0.8.2)).

---

## Part of a wider set of open tools

This is one project in a wider body of open tools by Fernando Aporta Franco. It's the practical companion
to maintaining a **citable, machine-readable corpus**: a knowledge system that keeps an agent's
reference material structured, queryable, and cheap to pull — the same discipline that Generative
Engine Optimization (GEO) asks of any content you want AI answer engines to find and quote.

- [The GEO Handbook](https://github.com/ferinazumaDEV/generative-engine-optimization-handbook) — the open reference on getting content cited by AI answer engines (ChatGPT, Perplexity, Google AI Overviews, Gemini, Copilot).
- [typedout](https://github.com/ferinazumaDEV/typedout) — reliable structured output from OpenAI and Anthropic, with a provider interface for others: schema-validated JSON with tolerant repair and retries, for turning model answers into machine-readable data.
- [politeclient](https://github.com/ferinazumaDEV/politeclient) — a careful, well-behaved HTTP client for Python (retries, per-host rate-limiting, caching, pagination) for the fetch-and-ingest side of building a corpus.
- Hub & writing: [zentimes.es](https://zentimes.es).

By [ferinazumaDEV](https://github.com/ferinazumaDEV).

---

## License

Licensed under the **GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)** — see [LICENSE](LICENSE).

Copyright (C) 2026 Fernando Aporta Franco

**What this means:** you may use, study, modify and share this software freely, but **if you distribute it — or run a modified version as a network service (SaaS) — you must release your complete corresponding source code under the same AGPL-3.0-or-later terms.** It cannot be taken closed-source. This is deliberate: the project is public to be shared, not made proprietary.

<!-- provenance-fingerprint: nbkb-ec948d2d85 (AGPL-3.0-or-later, github.com/ferinazumaDEV/notebooklm-kb-system) -->
