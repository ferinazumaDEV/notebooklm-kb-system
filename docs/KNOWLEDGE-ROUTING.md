# Knowledge Routing — the 3-destination rule

This is the core rule of the second-brain system: **every durable learning has
exactly one home.** Before you save anything, decide which of the three destinations it belongs to.
Getting this right is what keeps local memory small enough to load
every session, while still capturing everything worth keeping.

The system has two writable stores plus an explicit "discard" outcome:

- **INTERNAL** — a small set of local Markdown files (your "memory"), loaded into
  context at the start of *every* session. Because it always costs tokens, it has to stay
  short.
- **EXTERNAL** — one or more NotebookLM notebooks queried *on demand* through a
  CLI wrapper. This is the deep-reference layer; it costs nothing until you ask it
  a question.
- **NONE** — discarded on purpose. Live, changing state is verified against the
  system when needed, never written down.

```
                        A new learning
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼               ▼
         INTERNAL        EXTERNAL          NONE
      (local memory)   (NB notebook)    (discard)
     always loaded     query on demand  verify live
       keep short       deep reference    never store
```

---

## Destination 1 — INTERNAL (local memory)

**What it is:** a handful of short Markdown files under your memory directory (e.g. `~/.kb/`)
that get injected into the agent's context on every run.

**Store here only what the agent must know *before* it can act correctly:**

- **Identity** — who the operator is, what to call them, who they are *not*, the role the
  agent plays. Facts that frame every interaction.
- **Hard rules / vetoes** — non-negotiable constraints. "Never run X." "Never reintroduce Y."
  "Always do Z as this user, never as root." Things that cause real damage if forgotten.
- **Method feedback** — corrections about *how you work*, not about a domain. "Inspect before
  guessing." "Verify before asserting." "Finish the whole task, no loose ends." These
  shape behavior across all projects.
- **Open WIP** — the small live pointer to what's in flight right now: the current
  project, the running job, the next step. This is the one exception to "no live
  state": it's a *pointer* to the work, not a metric, and it's deleted the moment the work
  is done.

**Rules for INTERNAL:**

- **Keep it short.** Every line here is a token tax on every session. One line per
  memory, linking to the detail (see `MEMORY.template.md`). If an entry grows beyond one
  line or two, the body belongs in EXTERNAL and only the pointer stays here.
- **Prune WIP ruthlessly.** When a task ends, its WIP line leaves INTERNAL. Any
  durable lessons it leaves behind get routed (usually to EXTERNAL); the status line is discarded.
- **No procedures.** Step-by-step how-tos, command syntax, and long gotchas
  don't live here: they live in EXTERNAL, and INTERNAL only says "see notebook `<key>`".

---

## Destination 2 — EXTERNAL (NotebookLM notebook)

**What it is:** one or more NotebookLM notebooks, each covering a domain (infra, apps, a
product area, ops...). You query them with a long, context-rich
natural-language question through a small CLI wrapper, for example:

```
~/.kb/nb <notebook-key> "<a long, specific question with full context>"
```

Querying costs tokens only when you ask; the notebook itself is free to keep large.

**Store here everything that is durable reference but not needed *up front*:**

- **Reference & background** — architecture, how a system is wired, why a
  decision was made.
- **Procedures** — step-by-step how-tos, setup and recovery runbooks, deploy steps.
- **Commands & syntax** — exact invocations, flags, config keys, the detail of
  "how do I actually run this".
- **Gotchas** — traps, footguns, non-obvious constraints discovered the hard way.
- **Negative findings** — "we tried X and it does NOT work because Y." This is gold and almost always gets
  lost if not saved on purpose. Record the dead end so no one walks it
  again.
- **Stable design** — design tokens, style rules, canonical templates, the
  source-of-truth reference for how something should look or be built.

**Rules for EXTERNAL:**

- **Query before you execute.** If a procedure lives in a notebook, read it *before* doing
  the task: don't reconstruct it from memory.
- **Don't guess what isn't local.** If reference material isn't in INTERNAL and you're
  unsure, **query the notebook**: never make up the answer. A query that gets
  skipped and leads to a guess is itself a routing failure worth fixing.
- **Ask long questions.** NotebookLM answers better with full context. Write a paragraph,
  not a keyword.
- **Editing means re-ingesting.** These notebooks are built from source documents. If
  you change a build document, you have to **re-upload the source** so the notebook
  reflects it. Editing only the local copy is not enough.

---

## Destination 3 — NONE (discard on purpose)

**What it is:** the deliberate decision *not* to save something, because it is live state
that the system itself is the authority on.

**Never store — verify it against the system when you need it:**

- Disk usage / free space (`%`)
- IP addresses, ports currently in use
- Counters, queue depth, row counts, "how many X are there right now"
- Tokens, keys, secrets, session credentials
- Which service is currently running / the currently deployed version
- Any value that is true *now* and false *later*

Writing this down creates a dated lie: the moment it's saved it starts drifting from
reality, and a future reader trusts the stale copy. The right move is always to query
the live system (`df`, `ip a`, `systemctl status`, the API, the secret store) at the
moment you need the value.

> **The one gray zone — WIP.** A *pointer* to work in flight ("grinding the batch job,
> ~2 days") is allowed in INTERNAL because it orients the next session. A *metric* about that
> work ("847 files done, 61% disk used") is NONE: verify it live. When in
> doubt: is it a pointer to a task, or a number that changes on its own? Pointers can
> live in WIP; numbers are discarded.

---

## Two rules that make routing work

### Split mixed learnings

Most real lessons are a *bundle* of several facts of different kinds. Don't
dump the whole bundle into a single destination. **Break it apart and route each piece separately.**

> Example: *"I found out this tool throttles its default download format to a
> crawl, so I switched to a lower-quality format that comes in fast — and by the way, never
> run its build step as root on this machine."*

That single realization splits into:

- The throttling trap + the workaround (format flag) → **EXTERNAL** (a gotcha + a
  procedure).
- "Never run the build as root here" → **INTERNAL** (a hard rule / veto).
- The download speed you happened to observe → **NONE** (live state, discard).

One learning, three homes. Splitting is the norm, not the exception.

### One fact, one home

Each fact lives in **exactly one** destination. Don't copy a procedure into local memory "for
convenience", and don't rewrite a hard rule inside a notebook. Duplication is how the two
stores drift out of sync: you fix a fact in one place, forget the other, and now you have two
answers and no way to know which is current.

- If a fact is in EXTERNAL, INTERNAL may have at most a **one-line pointer** to
  it ("see notebook `<key>`"), never a copy of the content.
- If you find the same fact in two places, that's a bug: keep the authoritative copy in its
  correct destination and delete the other.
- When a fact changes, you update it in its single home — and nowhere else.

---

## Quick decision checklist

Before you save anything, ask yourself in order:

1. **Does it change on its own over time?** (disk, IPs, counters, tokens, versions)
   → **NONE.** Verify it live instead.
2. **Must the agent know it *before* acting, every session?** (identity, hard rules, method,
   current WIP pointer) → **INTERNAL.** Fit it in one line; link to the detail.
3. **Everything else** — reference, procedure, command, gotcha, dead end, stable
   design → **EXTERNAL.** Put it in the right notebook; leave at most a pointer in INTERNAL.
4. **Is it actually several facts?** → **Split it** and route each piece through steps 1–3.
5. **Is it already saved somewhere?** → **Don't duplicate.** One fact, one home.
