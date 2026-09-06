# Security policy

## Supported versions

This is a kit of shell scripts, not a versioned package. **Only `main` is supported** — that is where
fixes land, and there are no maintained branches behind it. If you installed by cloning, `git pull`
is the upgrade path.

## Reporting a problem

Please report privately first.

1. Preferred: GitHub's private vulnerability reporting on this repository — **Security → Report a
   vulnerability**
   ([direct link](https://github.com/ferinazumaDEV/notebooklm-kb-system/security/advisories/new)).
2. If that form is not available to you,
   [open an issue](https://github.com/ferinazumaDEV/notebooklm-kb-system/issues) saying only that you
   have a security report and how to reach you. **Never paste cookies, a `storage_state.json`, a
   notebook id or raw logs into a public issue** — a private channel will be arranged from there.

Expect a first reply within a week. Small project, spare time; no formal SLA and no bug bounty.

## The two things that actually matter here

**1. The auth profile is a live Google session.** Authentication to NotebookLM is a browser session:
`notebooklm login` seeds a `storage_state.json` holding Google cookies. That file is not a token
scoped to this tool — anyone who copies it gets your NotebookLM session. Treat it exactly like a
password:

- keep it `chmod 600`, in a directory only your user can read;
- never commit it, never put it in a backup that syncs somewhere shared, never paste it into an issue;
- if you think it leaked, sign out of the session from your Google account's device/activity page —
  deleting the local file alone does not invalidate it.

`healthcheck.sh` exists because this session rots on two clocks and Google's own `doctor` / `auth
check` report "valid" while every real call fails. The alert email it sends contains the failure
symptom and no cookie values.

**2. Everything you put in a notebook goes to Google.** That is the design, not a leak: the whole
point is that NotebookLM does the reading on Google's infrastructure. So the notebook is reference
material, never a vault. **Never put a token, key, password or session credential in a source
document** — write "pull it from `<secret store>`" instead. The routing rules in this kit already send
live state and secrets to the NONE bucket, which is what keeps them out of both stores by design.

The full checklist, including the sweep to run before publishing anything, is in
[README → Security](README.md#security) and [docs/FAQ.md](docs/FAQ.md).

## Installation

There is no `curl | bash` here, deliberately. You clone the repository and run
`bash install/install.sh` (or `install/install.ps1` on Windows) from the checkout, so the script is on
your disk and readable before it runs. Read it first — it creates `~/.kb/`, builds a virtualenv there
and installs the `notebooklm-py` CLI into it.

The kit pins its dependency — `notebooklm-py[browser,cookies]>=0.8.2,<0.9` — rather than tracking
whatever is newest. That is a compatibility decision, not a security guarantee: `pip` still fetches
the package from PyPI, and its supply chain is its own.

Note what those extras are for. The installer looks for a browser you already have, and one of the
login paths (`--browser-cookies`) works by **reading the cookies of a browser profile you are already
signed into**, rather than opening a fresh login window. That is a convenience with a real cost: the
tool is reaching into your everyday browser profile. If you would rather keep the two apart, log in
with `notebooklm login --browser <name>` into a profile used for nothing else.

## Scope

This repository is **not** a Google or NotebookLM product, and it is not `notebooklm-py`. It is a set
of wrapper scripts around that CLI. A vulnerability in NotebookLM itself belongs to Google, and one in
the underlying CLI belongs to that project; report those upstream. What belongs here is anything these
scripts do wrong — leaking a credential into a log or an argument list, writing state with permissions
that are too open, or failing to notice that authentication has silently died.

Reports that an operator can hurt themselves — putting a secret in a notebook on purpose, committing
`notebooks.json`, or leaving the auth profile world-readable — are documentation issues rather than
vulnerabilities. Still welcome as issues.
