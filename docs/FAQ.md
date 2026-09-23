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
3. You then read the material back with `notebooklm ask -n <NOTEBOOK_ID> "<question>"` or, for
   the raw text, `notebooklm source fulltext -n <NOTEBOOK_ID> <SOURCE_ID>` — **not**
   `artifact export`, which returns a rendered/summary object rather than usable text.

Ask with long, specific questions. NotebookLM answers a well-framed question far better than a
keyword — include what you're doing, what you already know, and what you need out of it.

*Dated notes, 2026-09-23:*

- **Long has an upper bound on the `ask` path.** Upstream issue #2425 (opened 2026-09-15,
  closed 2026-09-20) shows that when a chat request's prompt plus pinned-source payload is too
  large, the server rejects it with status 3 (`INVALID_ARGUMENT`) and the CLI reports it as "No
  parseable chunks in streaming chat response … the API wire format may have changed"; the
  reporter measured failure above roughly 5,100 characters and success below roughly 4,500 with
  the same pins (Source: [notebooklm-py issue #2425](https://github.com/teng-lin/notebooklm-py/issues/2425)). The threshold is the
  reporter's measurement on CLI 0.7.3, not a maintainer statement (needs-verification,
  2026-09-23). The misleading message is a 0.7.3 parser bug fixed in 0.8.0 (#1636); on the 0.8.2
  this kit pins the rejection is reported as `ChatError` with server status 3, and the maintainer
  states the character range "should be treated as an observation for that request, not a
  guaranteed API limit" (Source: [notebooklm-py issue #2425, maintainer comment 2026-09-20](https://github.com/teng-lin/notebooklm-py/issues/2425)).
  Treat that error as a possible oversize prompt before assuming Google changed the UI.
- **Step 2 above is justified again from upstream.** Issue #2432 (opened 2026-09-21) reports
  that on 0.8.2 the studio wait step reported `REMOVED` for generations that had in fact
  finished (Source: [notebooklm-py issue #2432](https://github.com/teng-lin/notebooklm-py/issues/2432)). Verification by re-listing
  is the pattern, not a quirk of the research wrapper.

## What's the difference between `fast` and `deep` research?

- **fast** — a quick, shallow sweep. No extra login needed.
  Capped at roughly **~10 sources** (observed, needs-verification) — good for a first pass, not
  exhaustive coverage.
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
headless re-auth setup, but it still requires the one-time `notebooklm login` like every other
command. If deep research suddenly fails with an auth error, the stored session
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
savings compound: re-querying an existing notebook with `notebooklm ask` is a few-K-token read forever,
versus re-running the whole recon. (These are order-of-magnitude figures; plug in your own token
rates for cost.)

*Scope, restated 2026-09-23.* The ~99% is one task, run one time, counting only the output tokens
billed to the agent; NotebookLM's own compute is not counted, the two outputs were not scored
for equal quality, and run-to-run variability was not measured. It is a documented observation,
not a rate — the same scope the README gives it.

## How much can I ask per day?

*Dated answer, 2026-09-23.* There is no fixed daily count any more. Since 2026-09-02 Gemini
Notebook meters usage by compute — prompt complexity, models, features, chat length — and the
quota "refreshes every 5 hours until you reach your weekly limit"; AI Plus is two times and AI
Pro four times the standard allowance, AI Ultra "5x or 20x higher than AI Pro depending on your
subscription" (Source: [Usage limits for Gemini Notebook](https://support.google.com/gemininotebook/answer/17670842?hl=en&co=GENIE.Platform%3DDesktop)). A scheduled agent
should budget for a refused ask rather than count on a number.

The limits Google publishes on the same date, all tagged "Subject to Change" (Source: [Upgrade
Gemini Notebook](https://support.google.com/gemininotebook/answer/16213268?hl=en), read 2026-09-23):

| Plan (2026-09-23) | Sources per notebook | Chats per day | Audio Overviews per day |
|---|---|---|---|
| Gemini Notebook (standard) | 50 | 50 | 3 |
| AI Plus | 100 | 200 | 6 |
| AI Pro | 300 | 500 | 20 |
| AI Ultra (20 TB) | 500 | 2.5K | 100 |
| AI Ultra (30 TB) | 600 | 5K | 200 |

Each source is capped at 500,000 words or 200 MB for local uploads, with no page limit (Source:
[Gemini Notebook FAQ](https://support.google.com/gemininotebook/answer/16269187?hl=en), read 2026-09-23).

Two things to keep in view: the per-day chat counts on the upgrade page and the compute-based
model on the usage-limits page are both live on 2026-09-23 and Google has not reconciled them;
and every number here is perishable — it belongs in the NONE bucket, checked at the source when
it matters, never quoted from memory.

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
$EDITOR ~/.kb/build/<KEY>__<topic>.md                                # 1. edit the build-doc
notebooklm source add -n <NOTEBOOK_ID> ~/.kb/build/<KEY>__<topic>.md  # 2. upload the new version
notebooklm source list -n <NOTEBOOK_ID>                               # 3. wait until it shows "ready"
notebooklm source delete -n <NOTEBOOK_ID> <OLD_SOURCE_ID>             # 4. only then remove the stale one
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

No. It's an independent, open-source project (AGPL-3.0-or-later) that builds a memory-and-research
workflow on top of the unofficial `notebooklm-py` CLI by Teng Lin
(<https://github.com/teng-lin/notebooklm-py>, MIT); tested with notebooklm-py 0.8.2. It is not
affiliated with, endorsed by, or supported by
Google or NotebookLM. NotebookLM is a product of Google; this repo is a separate community tool.

*Dated notes, 2026-09-23:*

- **Google renamed NotebookLM to Gemini Notebook on 2026-07-16**, "the same standalone product";
  automatic redirects keep existing shared notebooks and links working (Source:
  [blog.google](https://blog.google/innovation-and-ai/products/gemini-notebook/notebooklm-gemini-notebook/), [Google Workspace Updates](https://workspaceupdates.googleblog.com/2026/07/notebooklm-now-gemini-notebook.html)). This
  repository, the `notebooklm-py` package and the `notebooklm` command keep the old name.
- **Upstream says so itself.** The notebooklm-py 0.8.2 release notes state that "both backends
  rely on undocumented Google APIs and may change without notice" (Source: [notebooklm-py v0.8.2
  release](https://github.com/teng-lin/notebooklm-py/releases/tag/v0.8.2)).
- **"Notebooks in Gemini" are a different thing.** The Gemini app's own notebooks, rolled out to
  schools and organisations from 2026-09-14, take up to 10 sources each and are a Gemini-app
  feature (Source: [Google Workspace Updates, 2026-09-17](https://workspaceupdates.googleblog.com/2026/09/notebooks-in-gemini-dedicated-workspace-for-focused-organized-work-now-for-schools-and-organizations.html)). This kit, the ids
  in `notebooks.json` and the CLI address Gemini Notebook notebooks only.

## Is there an official API?

*Dated answer, 2026-09-23.* For the consumer product this kit drives, no. For the enterprise
edition, a Preview API exists under Pre-GA terms: it creates, gets, lists, deletes and shares
notebooks, adds sources (Google Docs, Google Slides, raw text, web content, YouTube videos,
file upload) and creates an audio overview (Source: Gemini Notebook Enterprise API,
[notebooks](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-notebooks) and [sources](https://docs.cloud.google.com/gemini/enterprise/notebooklm-enterprise/docs/api-notebooks-sources), both "Last updated
2026-09-22 UTC"). The documented pages contain no ask/chat operation; that is an observation
of those pages on 2026-09-23, not a Google statement, and it is why the enterprise API does
not replace the browser-session CLI for this kit's read path.

- The 2026-07-16 rename did not move the endpoints: "the product functionality remains the
  same, and the APIs still use the same endpoints" (Source: [Gemini Enterprise release notes,
  entry of July 16, 2026](https://docs.cloud.google.com/gemini/enterprise/docs/release-notes)).
- Inside a VPC Service Controls perimeter, website URLs cannot be added as notebook sources
  because "direct website ingestion performs a live web crawl, generating outbound traffic
  beyond Google networks"; Google Docs and YouTube URLs remain supported (Source: [Gemini
  Enterprise release notes, entry of September 09, 2026, labelled Breaking](https://docs.cloud.google.com/gemini/enterprise/docs/release-notes)).
  The web search-and-ingest that `research.sh` drives has no enterprise equivalent inside such
  a perimeter as of that date.

## What do I need to install it?

`bash`, `jq`, and the `notebooklm` CLI on your `PATH`; the automated installer builds an
isolated `~/.kb/` virtualenv, installs `notebooklm-py[browser,cookies]>=0.8.2,<0.9`, and auto-detects a browser you
already have (Chrome / Edge / Brave / Firefox) — you don't need to install a specific browser
just for this. See [Installation](../README.md#installation) for the automated scripts and the
step-by-step guides per terminal.

## Is it safe to publish my knowledge base?

Only if you keep secrets out of it. Never put tokens, keys, passwords, or session credentials in
a notebook source — write "pull it from `<secret store>`" instead. Keep `notebooks.json` and the
auth profile local (don't commit them), and sweep the tree for emails, IPs, and token-shaped
strings before pushing anything public. The NONE bucket already keeps live secrets out of both
stores by design. See [Security](../README.md#security) for the full checklist.
