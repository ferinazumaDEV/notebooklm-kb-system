# FAQ — NotebookLM KB System

Common questions about the **NotebookLM KB System**: a token-efficient "second brain" and
memory layer for AI/LLM agents, built on a `notebooklm` CLI. Answers are kept honest and
accurate to what the tool actually does.

Placeholders like `<NOTEBOOK_ID>`, `<KEY>`, `<YOUR_EMAIL>` and `~/.kb/` stand for your own
values — see the [README](../README.md) and [Operations runbook](OPERATIONS.md) for the full
picture.

---

## What is the NotebookLM KB System?

It's a self-hostable knowledge-base workflow that gives an AI agent a persistent, cheap
memory. It has three destinations for everything the agent learns:

- **Local memory** — a handful of short Markdown files loaded into the agent's context on
  *every* session (identity, hard rules, method corrections, work in progress). It's small on
  purpose because you pay for it in tokens each run.
- **NotebookLM notebooks** — a large reference corpus (procedures, command syntax, gotchas,
  dead ends, stable design) that is **queried on demand** instead of loaded. It's free to keep
  big; it only costs tokens when you ask.
- **A discard bucket (NONE)** — live, perishable state (disk %, IPs, tokens, "is the service
  up?") that is **never written down** and re-verified from the system when needed.

The net effect: the agent remembers a lot while loading almost nothing, and broad research is
offloaded to NotebookLM instead of being re-derived every session.

## Is this "AI agent memory" or a "second brain for LLM agents"?

Both — that's exactly the use case. The local memory is the always-loaded working set; the
notebooks are the deep, queryable long-term store. Together they act as a second brain for an
LLM agent: identity and rules stay resident, everything else is one grounded query away.

## How do I do web research with NotebookLM from the CLI?

Use the research wrapper:

```bash
~/.kb/research.sh <NOTEBOOK_ID> "<an extensive, context-rich question>" fast
# or, for a broader pass:
~/.kb/research.sh <NOTEBOOK_ID> "<query>" deep
```

What happens:

1. NotebookLM runs the search-and-ingest on Google's infrastructure and imports the results as
   **sources** into the target notebook.
2. The wrapper does **not** trust the CLI exit code — it re-lists the notebook's sources before
   and after and reports the number actually added (the last line of stdout is that integer).
   The underlying CLI can exit `0` even when nothing was imported (network blip, empty results,
   degraded auth, an async job that never finished), so verification is built in.
3. You then read the material back with `kb ask <KEY> "<question>"` or, for the raw text,
   `kb source fulltext <KEY> <SOURCE_ID>` — **not** `artifact export`, which returns a
   rendered/summary object rather than usable text.

Ask with long, specific questions. NotebookLM answers a well-framed question far better than a
keyword — include what you're doing, what you already know, and what you need out of it.

## What's the difference between `fast` and `deep` research?

- **fast** — a quick, shallow sweep. No extra login needed. Capped at roughly **~10 sources** —
  good for a first pass, not exhaustive coverage.
- **deep** — a broader, multi-source pass. It drives a real browser session, so it needs the
  one-time headless re-auth setup below. `research.sh deep` also exports
  `NOTEBOOKLM_HEADLESS_REAUTH=1` for you so a long-running job can refresh its own auth
  mid-run.

## Does it work headless / on a server?

Yes. Deep research is designed to run without a visible browser window:

```bash
# one time, interactively, to seed a reusable session:
notebooklm login
# then, for non-interactive / scheduled runs:
export NOTEBOOKLM_HEADLESS_REAUTH=1
```

With a session seeded once and `NOTEBOOKLM_HEADLESS_REAUTH=1` set, deep research can
re-authenticate on its own — so it fits cron jobs and server-side agents. `fast` mode needs no
browser login at all. If deep research suddenly fails with an auth error, the stored session
expired: re-run `notebooklm login` once to reseed it and carry on.

## How much can this save vs a multi-agent research workflow? (reduce agent token cost)

The expensive part of broad research is **generation** — every sub-agent that reads pages and
writes notes bills output tokens. NotebookLM moves that whole crawl-and-summarize step onto
Google's infrastructure, so the agent only pays to read the compact, cited result.

| | Broad recon via NotebookLM | Broad recon via a multi-agent LLM swarm |
|---|---|---|
| Where the crawl+summarize runs | Google infra (outside your token budget) | Your model — each sub-agent bills output tokens |
| Agent tokens per research | ~a few thousand (read the result) | ~1.9M output tokens (measured, a real 52-agent fan-out) |
| What you get | faithful, cited synthesis of the corpus | a synthesized report |

That's roughly **1.9M → ~5K agent tokens, about a 99% reduction** for a broad recon — and the
savings compound: re-querying an existing notebook with `kb ask` is a few-K-token read forever,
versus re-running the whole recon. (These are order-of-magnitude figures; plug in your own token
rates for cost.)

## When should I NOT use NotebookLM research?

It's a narrow advantage — a hybrid, not a silver bullet:

- **Single facts you already know where to find.** A direct lookup is cheaper and faster than
  kicking off a research job. NotebookLM pays off only when you'd otherwise fan out across many
  sources.
- **When you need verified truth.** Answers are *faithful to the corpus*, not fact-checked. If a
  source is wrong, stale, or biased, the answer is confidently wrong the same way. Grounding is
  not fact-checking — curate your sources.
- **When you need it instantly.** Research is async, with minute-scale latency; it's not an
  interactive search.

Use it as a pipeline: NotebookLM does the broad, cheap gathering; the agent spends its (now
small) token budget verifying the load-bearing claims and deciding what to do.

## How do I update a notebook without breaking it?

A notebook reasons over its **uploaded sources**, not the file on your disk — editing your local
build-doc changes nothing until you re-upload. Always **add new → wait for "ready" → delete
old**:

```bash
$EDITOR ~/.kb/build/<KEY>__<topic>.md     # 1. edit the build-doc
kb source add <KEY> ~/.kb/build/<KEY>__<topic>.md   # 2. upload the new version
kb source list <KEY>                       # 3. wait until it shows "ready"
kb source delete <KEY> <OLD_SOURCE_ID>     # 4. only then remove the stale one
```

Never delete first: if the upload fails you're left with an empty notebook, and a notebook at
**0 sources** may refuse queries. See [Operations §3](OPERATIONS.md) for the full write path.

## Where does a new piece of knowledge go?

Route every durable learning to exactly one destination:

- **INTERNAL** (local memory) — identity, hard rules, method fixes, active WIP.
- **EXTERNAL** (a notebook) — reference, procedures, commands, gotchas, stable design.
- **NONE** (nowhere) — anything that changes on its own; verify it live from the system.

One fact, one home — don't duplicate a procedure into both memory and a notebook. The full rule
with worked examples is in [Knowledge routing](KNOWLEDGE-ROUTING.md).

## Is this an official Google or NotebookLM product?

No. It's an independent, open-source project (AGPL-3.0) that builds a memory-and-research
workflow on top of a `notebooklm` CLI. It is not affiliated with, endorsed by, or supported by
Google or NotebookLM. NotebookLM is a product of Google; this repo is a separate community tool.

## What do I need to install it?

`bash`, `jq`, and the `notebooklm` CLI on your `PATH`; the automated installer builds an
isolated `~/.kb/` virtualenv, installs `notebooklm-py[browser,cookies]`, and auto-detects a browser you
already have (Chrome / Edge / Brave / Firefox) — you don't need to install a specific browser
just for this. See [Installation](../README.md#installation) for the automated scripts and the
step-by-step guides per terminal.

## Is it safe to publish my knowledge base?

Only if you keep secrets out of it. Never put tokens, keys, passwords, or session credentials in
a notebook source — write "pull it from `<secret store>`" instead. Keep `notebooks.json` and the
auth profile local (don't commit them), and sweep the tree for emails, IPs, and token-shaped
strings before pushing anything public. The NONE bucket already keeps live secrets out of both
stores by design. See [Security](../README.md#security) for the full checklist.
