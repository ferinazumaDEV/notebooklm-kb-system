# Memory — <YOUR_PROJECT> (operator: <YOUR_NAME>)

<!--
  This is the INDEX file of the local memory. It is loaded into the agent's context on
  EVERY session, so keep it small: one line per memory, each one linking to a
  detail file or to a NotebookLM notebook. See KNOWLEDGE-ROUTING.md to know
  what goes here (INTERNAL) versus in a notebook (EXTERNAL) versus discarded (NONE).

  Golden rules:
    - One line per memory in the index below.
    - The body of a memory lives in its own small file; the index only points to it.
    - Anything long, procedural, or reference-shaped goes to a NotebookLM notebook,
      and the index only names the notebook key.
    - Live state (disk %, IPs, counters, tokens, versions) is NEVER stored —
      verify it on the system when you need it.
-->

**System-wide rule — 3 destinations for every learning:** INTERNAL (this local memory:
identity, hard rules, method feedback, open WIP) · EXTERNAL (a NotebookLM notebook:
reference, procedures, commands, gotchas, negative findings, stable design) · NONE (live
state → verify on the system, never store). If the reference material is not in local memory,
**don't guess it** — query the notebook: `~/.kb/nb <notebook-key> "<extensive question with full context>"`.
(`nb` stands for a tiny wrapper you write that maps a key to a notebook id via `notebooks.json`
and calls `notebooklm ask -n <NOTEBOOK_ID>`; it is not included in this repo.)
Canonical rule: see [[feedback-knowledge-routing]].

---

## Memory file format (frontmatter)

Each individual memory file starts with a small frontmatter block so that the
loader (and you) know at a glance what it is:

```yaml
---
name: feedback-verify-before-asserting   # unique slug; also the [[link]] target
description: Don't assert facts or root causes without first verifying them.
type: feedback                           # one of: user | feedback | project | reference
---
```

**The `type` field — four kinds of memory:**

| type        | what it holds                                             | INTERNAL because...                         |
|-------------|----------------------------------------------------------|---------------------------------------------|
| `user`      | who the operator is, how to address them, their role     | identity frames every interaction           |
| `feedback`  | a correction about *how you work*, or a hard rule/veto   | it must shape behavior in every session     |
| `project`   | a live project: its goal, constraints, and current WIP   | it drives what you do right now             |
| `reference` | a stable pointer to where the deeper detail lives        | it's the short handle of an EXTERNAL store  |

Keep the body of each file short: a few lines of the durable essence, and then a
link to the notebook that holds the full detail. If a file grows beyond one screen, its
content probably belongs in a notebook (EXTERNAL), leaving only a pointer here.

---

## The index (one line per memory)

Each line: `[[link]]` — essence in one sentence, ending with where the detail lives.

### Identity (type: user)
- [[user-operator]] — the operator is <YOUR_NAME>, the technical operator; address them as such
  and never confuse them with <OTHER_ROLE>.

### Projects (type: project) — includes live WIP pointers
- [[project-main-app]] — main product = <describe it in a phrase>; runs as `<user>` on
  `<host-role>`; architecture detail in the `infra` notebook.
- [[project-data-pipeline]] — <one-line goal>; **WIP: batch job running (~2 days), see the
  file for the resume command**; tooling in the `<key>` notebook.
- [[project-side-tool]] — <one-line goal>; commands and gotchas in the `<key>` notebook.

### Feedback and hard rules (type: feedback)
- [[feedback-knowledge-routing]] — **canonical 3-destination routing rule** (INTERNAL /
  EXTERNAL / NONE) + split-mixed-learnings + one-fact-one-home.
- [[feedback-no-sudo-build]] — **VETO**: never run the build step as root; only service
  restarts run as root; the why in the `infra` notebook.
- [[feedback-inspect-before-guessing]] — when a framework's behavior is unclear,
  log/inspect it first instead of iterating over guessed names.
- [[feedback-verify-before-asserting]] — don't assert facts or root causes without verifying them
  first.
- [[feedback-finish-everything]] — if we start something, it gets finished 100%; no loose
  "optional" ends unless a step is truly impossible (and say so explicitly).

### Reference pointers (type: reference)
- [[reference-mail]] — send mail from `<YOUR_EMAIL>` via the local helper `~/.mail/send`;
  setup in the `infra` notebook.
- [[reference-notebooks]] — the NotebookLM notebook keys and how to query them (below).

---

## NotebookLM notebooks (EXTERNAL — query, don't load)

Query on demand: `~/.kb/nb <key> "<extensive question with full context>"`. The IDs live in
`notebooks.json`; the operational mechanics (re-ingest, auth, backups) in `~/.kb/OPERATIONS.md`.
Account: `<YOUR_EMAIL>`. Notebook ids look like `<NOTEBOOK_ID>` and are never inlined here.

- **`infra`** — servers, network, backups, security, deployment runbooks, architecture of the
  main app. Hard rule: never stop the production service.
- **`apps`** — non-infra products: app/backend detail, web deployment steps, design/UI tokens.
- **`ops`** — day-to-day operations: procedures, gotchas, recovery steps, negative findings.

Flow reminder: a single end-to-end task usually touches two notebooks (e.g. one
to *build* something, another to *publish* it). If a notebook grows beyond its domain,
split it out instead of oversaturating it.

---

## Cross-linking with `[[name]]`

Memories reference each other by their `name` slug wrapped in double brackets: `[[user-operator]]`,
`[[feedback-knowledge-routing]]`. The link target is exactly the `name:` from that file's
frontmatter — so the names must be **unique** and **stable** (renaming a file
means updating every `[[link]]` that points to it).

Use the links to:
- point the index at each memory's detail file (the whole index above is links);
- connect a project with the feedback that constrains it
  (e.g. [[project-main-app]] → [[feedback-no-sudo-build]]);
- chain a specific rule to the canonical one
  (e.g. any routing decision → [[feedback-knowledge-routing]]).

A memory should link *outward* to the notebook (EXTERNAL) that holds its full detail, and
*sideways* to related memories — but it should never *copy* their content. One fact, one home.

---

## Maintenance

The operational mechanics — querying notebooks, editing a build document and **re-ingesting the
source**, integrity checks, auth refresh, backups — live in `~/.kb/OPERATIONS.md`,
not here. When a project's WIP line goes stale, prune it: route any durable lesson
to its home (usually a notebook) and delete the status line from this index.
