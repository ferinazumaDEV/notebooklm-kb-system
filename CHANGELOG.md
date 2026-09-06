# Changelog

Notable changes, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This is a kit of shell scripts rather than a package, so a "version" is a state of
the scripts and their documentation. Only `main` is supported; `git pull` is the
upgrade path.

## [0.1.0] — 2026-09-06

First tagged release. The kit had been usable for a while, but nothing marked a
state you could point at, compare against, or roll back to.

### Fixed

- **The public installation path was broken.** Three separate blockers, found by
  the 2026-09-04 audit and all of the same shape: the scripts called a
  `notebooklm-py` CLI form the dependency had stopped accepting. Fixed, and the
  dependency is now pinned to `>=0.8.2,<0.9` so it cannot drift again silently.
- Minimum Python corrected to **3.10+**, which is what `notebooklm-py` actually
  requires.
- Virtualenv path handling made robust, and macOS compatibility improved by using
  alternatives to GNU-only tool flags.
- Query strings that look like options (`--help`) are passed as queries instead of
  being parsed by the CLI.

### Added

- **`healthcheck.sh`** — NotebookLM authentication is a browser session that rots on
  two clocks, and `doctor` / `auth check` report "valid" while every real call
  fails. This makes that failure loud instead of silent, with an email alert and a
  cooldown.
- **`tests/run.sh`** — 21 checks driven by a mock `notebooklm` binary, so the suite
  needs no Google account, no credentials and no network. Plus five more that run
  against the real CLI when it is present, which are the ones that catch the
  failure mode above.
- **CI on every push and pull request**: `bash -n` on all four scripts, `shellcheck`
  at warning severity, the mock-CLI harness, and a Windows job that parses
  `install.ps1` — the only Windows install path, which no Linux runner can execute.
- **`SECURITY.md`**, with the two things that matter said plainly: the auth profile
  is a *live Google session*, not a scoped token, and deleting it locally does not
  invalidate it; and everything placed in a notebook goes to Google by design.
- **Compatibility table and honest test coverage** in the README, including what is
  *not* covered and why.
- The unofficial-dependency warning moved **above** the installation instructions.
  It used to sit in the FAQ, 200 lines below the point where somebody installs.

[0.1.0]: https://github.com/ferinazumaDEV/notebooklm-kb-system/releases
