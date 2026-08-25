# Research Prompt Template (NotebookLM)

A prompt-engineering cheatsheet for driving **NotebookLM** as the
research/reference half of a "second brain." In this system, an AI agent keeps a
small **local memory** (identity, hard rules, work-in-progress) and offloads the
durable reference material to **NotebookLM notebooks**; it then queries those
notebooks on demand instead of re-deriving the knowledge every session. That
query step is what this document is about.

There are two distinct operations, and each takes different prompts:

1. **Add research** — you ask NotebookLM to go find sources on a topic and pull
   them into a notebook (the "web research" / "discover sources" flow). This
   *grows* the corpus.
2. **Ask** — you query a notebook that already has sources and get a grounded
   answer with citations. This *reads* the corpus.

Both are prone to the same failure: a vague prompt produces a vague, lossy
result, and you won't notice what got dropped because the output still *looks*
complete.

The rules below are ordered by how often they save your skin.

---

## 1. Specific beats broad (add-research queries)

When you ask NotebookLM to discover and ingest sources, a broad query returns a
broad, shallow set: a few generic summary pages you already knew. A narrow query
returns the primary sources, the edge cases, and the version-specific details you
actually needed.

**The mechanism:** the research step is essentially a search-and-summarize.
Search rewards specificity. "Tell me about X" competes with all the beginner
content on the internet about X. "The exact failure mode of X under condition Y
on version Z" competes with almost nothing, so it surfaces the deep material.

### Bad → Good

| Too broad (returns summaries) | Specific (returns primary + edge-case sources) |
| --- | --- |
| `authentication best practices` | `refresh-token rotation with reuse detection for a public SPA client, including the revoke-on-reuse tradeoff` |
| `how to make CLI tools` | `handling SIGINT/SIGTERM cleanly in a long-running <LANGUAGE> CLI so child processes and temp files are cleaned up` |
| `video encoding tips` | `two-pass vs CRF in <ENCODER> for vertical 9:16 short-form, target file size under N MB at 1080x1920` |
| `<TOOL> rate limits` | `<TOOL> API rate-limit headers, retry-after semantics, and the difference between per-key and per-endpoint buckets` |

### A reusable shape for add-research queries

```
<specific artifact/behavior> for <exact context: platform, version, constraint>,
including <the tradeoff / edge case / gotcha you most want covered>.
```

Fill the query with the constraints you already know. Every constraint you name
is a filter that steers ingestion toward the sources that matter and away from
the 101-level noise. You're not being polite by keeping it short — you're
throwing signal in the trash.

**Rules of thumb**

- **Name the version / platform / language.** "In <FRAMEWORK> v16" beats "in <FRAMEWORK>".
- **Name the constraint.** "under memory pressure", "on a metered connection",
  "without root", "for a free-tier account" — constraints select real sources.
- **One topic per research call.** A query that spans three topics ingests
  shallowly on all three. Make three focused calls instead; the corpus is additive.
- **Ask for the gotcha explicitly.** Add "including known pitfalls and failure modes"
  so ingestion pulls in the troubleshooting/incident pages, not just the
  happy-path docs.
- **Prefer nouns that appear in real sources.** Use the field's actual
  terminology (error codes, header names, flag names). Jargon is a search key.

---

## 2. Harden the `ask()` prompt against blind spots (querying an existing notebook)

When you query a notebook with a multi-part question, NotebookLM will happily
answer the parts it found good grounding for and **silently skip the rest**. The
answer reads as finished. The omission is invisible unless you force it to be
visible.

Two techniques make omissions impossible to hide.

### 2a. Number the sections and forbid silent drops

Give the model an explicit, ordered checklist, and require it to address **every**
item — including the ones it can't answer, which it must flag as such rather than
skip.

```
Answer ALL of the following. Number your answer 1–5 to match. Omit none.
If a numbered item is not covered by the sources, write "NOT IN SOURCES"
under that number instead of skipping it. Do not merge items.

1. <question one>
2. <question two>
3. <question three>
4. <question four>
5. <question five>
```

Why each clause earns its place:

- **"Number your answer 1–5 to match"** — makes a missing item structurally
  obvious. A jump from 3 to 5 is something you (or a downstream script) can catch.
- **"Omit none"** — strips the model of its default license to consolidate.
- **"NOT IN SOURCES"** — turns a silent gap into an explicit, greppable token.
  This is the most valuable clause of all: it tells you where the notebook is
  *thin*, which is itself a research finding (it tells you what add-research to do next).
- **"Do not merge items"** — stops the model from fusing two questions into one
  blurry paragraph that half-answers both.

### 2b. Demand the shape of the output

If you need the answer in a specific shape (a table, a command, a numbered
procedure), say so, and say what to do when the sources don't support that shape:

```
Return the answer as a table with columns: <A> | <B> | <C>.
One row per <item>. If a cell is unknown from the sources, put "—".
Do not drop rows.
```

Same principle: name the structure, and give an explicit placeholder for the
unknown so a gap can't pass itself off as completeness.

### A reusable ask() skeleton

```
You are answering ONLY from the notebook's sources. Cite where possible.

Cover every numbered point below, in order, numbered to match. Omit none.
For any point the sources don't cover, write "NOT IN SOURCES" — do not skip it.

1. <point>
2. <point>
3. <point>
...

Then, in a final section titled "GAPS", list every point you marked
NOT IN SOURCES so I can see the coverage holes at a glance.
```

That final **GAPS** section turns the query into a coverage report. When it's
empty, the notebook had you covered. When it isn't, you get your next
add-research list for free.

---

## 3. What NotebookLM WON'T do — add this yourself on top

NotebookLM is a **grounded summarizer over the sources you gave it**. That framing
predicts its blind spots exactly. It's excellent at "what do my sources say about
X" and structurally incapable of several things people mistakenly expect from it.
A human or a second LLM pass has to supply these things; don't assume the notebook
did.

| NotebookLM WON'T… | Why (its nature) | Who/what must supply it |
| --- | --- | --- |
| **Rate source quality** | It treats an ingested source as fact-to-ground-on; it doesn't score some random blog against the official docs or a peer-reviewed paper. | You, at ingestion time: feed it good sources; and a reviewer who knows the field. |
| **Reason probabilistically about scenarios** | It reports what the sources *claim*, not "what's likely to happen if…". It doesn't run a hypothetical or estimate probabilities. | A reasoning LLM (or you) that takes the grounded facts and does the scenario/risk modeling. |
| **Verify truth / catch source errors** | If a source is wrong, the grounded answer faithfully repeats the mistake. Grounding is not fact-checking. | External verification: cross-check the load-bearing claims against a second, independent source before acting. |
| **Know anything outside its sources** | "NOT IN SOURCES" is a real boundary, not laziness. It has no opinion on what it wasn't given. | Add-research to ingest the missing sources, then ask again. |
| **Stay current on its own** | The sources are a snapshot from when they were ingested. It doesn't find out the world changed. | A refresh cadence: re-ingest volatile topics; treat versions/prices/limits as perishable. |
| **Track live/mutable state** | It's reference memory, not a status dashboard. Disk %, the current IP, "is the service up right now?" are never notebook facts. | Check the live system directly; never store or ask the notebook for live state. |

### The division of labor

Think of it as a pipeline, and keep each stage honest about what it can promise:

```
add-research  →  NotebookLM (grounded recall + citations)  →  reasoning/verification layer  →  action
   (you pick             (what the sources say —                  (is it true? is it good?          (do the thing,
    specific,             faithfully, with gaps                     what's likely? apply             on verified,
    good sources)         flagged)                                  judgment)                        reasoned facts)
```

- **Before NotebookLM:** pick specific, credible sources (§1). Garbage in is still garbage out.
- **Inside NotebookLM:** get faithful, gap-flagged recall (§2). Trust it *only* as "what
  my sources say".
- **After NotebookLM:** rate, verify, and reason (§3). This is where a second LLM or a
  human earns their keep. Never let a grounded summary walk straight into an
  irreversible action without this pass.

---

## Quick reference (copy/paste)

**Add research (grow the corpus):**

```
<specific artifact/behavior> for <exact context: platform/version/constraint>,
including known pitfalls and failure modes.
```

**Ask (read the corpus, hardened against blind spots):**

```
Answer ALL points below, numbered to match, in order. Omit none.
Write "NOT IN SOURCES" for anything the sources don't cover — never skip.
Do not merge items. End with a "GAPS" section listing every NOT IN SOURCES item.

1. ...
2. ...
3. ...
```

**Always remember what NotebookLM won't do:** rate sources · model
scenarios/probabilities · verify truth · exceed its sources · self-update · store
live state. Add that yourself on top.
