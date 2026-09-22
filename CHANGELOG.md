# Changelog

Notable changes, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This is a kit of shell scripts rather than a package, so a "version" is a state of
the scripts and their documentation. Only `main` is supported; `git pull` is the
upgrade path.

## [Unreleased]

### Changed

- **The licence is now AGPL-3.0-or-later, stated everywhere.** Until this change the
  repository said "AGPL-3.0" in every source header, both READMEs, the FAQ, the
  provenance notes and `CITATION.cff` — which is the "only" form. The cluster's
  licence policy for a service-with-a-moat has been AGPL-3.0-or-later since
  25 August 2026, and this repository had drifted from it. Nineteen occurrences
  moved in one change so that no two files disagree. `LICENSE` itself is untouched:
  it is the Free Software Foundation's text, and the "or later" choice is expressed
  in the notices, as the licence's own instructions say. This is a relaxation made
  by the sole copyright holder; it grants more, not less.

## [0.1.1] — 2026-09-22

### Added

- **`CITATION.cff`.** Until now this repository had none, so Zenodo derived the
  deposit metadata on its own, and the v0.1.0 record was archived with the license id
  `apgl-v3` while the repository declares AGPL-3.0. That id **is not in Zenodo's
  licence vocabulary**, which lists `agpl-3.0-only` and `agpl-3.0-or-later` and
  nothing resembling `apgl-v3`. The file carries the concept DOI read from the
  existing deposit, not a guessed one, and `AGPL-3.0-only` because that is what
  `LICENSE` and the README already say.

  **It did not fix the licence, and this entry said it would.** Measured after
  publishing v0.1.1: the deposit was minted with `{"id": "apgl-v3"}` again, with the
  citation file present and declaring `AGPL-3.0-only`. Whatever produces that id is
  upstream of `CITATION.cff`. Everything else in the deposit is correct — version,
  concept DOI, and an archive byte-for-byte identical to the tag across all 30 files.
  The mechanism is not established and is not guessed at here; see `RELEASING.md` for
  what to try next and how to test it without risking a deposit.
- **`RELEASING.md`.** The procedure for this repository, whose important half is that
  it is the *opposite* of a package repository: there is no `release.yml`, the tag
  triggers nothing, and publishing the GitHub Release **by hand** is what fires the
  Zenodo webhook and mints the version DOI. Doing that in a package repository breaks
  the run after PyPI has published, which is how two releases were repaired by hand on
  14 September 2026.
- **A bilingual README**, `README.es.md`, with a check that keeps the pair honest: it
  keys on a content hash of the English file rather than on a commit, so it survives
  squash merges and refuses a pull request that moves one side without the other.
- **`CONTRIBUTING.md` and `.github/CODEOWNERS`**, so the repository says how it
  actually works rather than leaving it to be inferred.

### Changed

- **The "~99%" figure now says what it is, everywhere it appears.** It is one
  documented comparison, not a benchmark, and reading it as a general claim was
  possible before this change. A number that travels without its scope is a number
  that will be quoted without it.
- Every GitHub Action is **pinned to a commit SHA**, with Dependabot keeping the pins
  current, and the workflows moved to `actions/checkout@v7` and `setup-python@v7`.

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

[0.1.1]: https://github.com/ferinazumaDEV/notebooklm-kb-system/releases
[0.1.0]: https://github.com/ferinazumaDEV/notebooklm-kb-system/releases
