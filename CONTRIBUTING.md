# Contributing

One maintainer, best-effort responses, no promised turnaround. Issues and pull requests are read.

## Before you open a pull request

```bash
bash tests/run.sh          # the mock-CLI harness (no account, no network)
```

CI also syntax-checks every script and runs `shellcheck` at the version pinned in
`.github/workflows/checks.yml`; run the same before pushing if you touched a shell script.

The five tests that need the real `notebooklm-py` CLI are skipped unless it is installed; run them
before bumping its pin, because they are the ones that catch the failure this kit has already had.

Everything lands through a pull request with green CI. `main` is protected; nothing is pushed to it
directly, by anyone.

## Security

Report anything sensitive privately — see [`SECURITY.md`](SECURITY.md) — not in a public issue.
