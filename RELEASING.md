# Releasing

A release of this repository is a **citable version**: the tag becomes an archived deposit on Zenodo with its own
DOI, and that deposit is what someone cites, downloads and checks against. Everything below exists so that the
deposit and the tag cannot drift apart.

## The rule that is different here

**You create the GitHub Release by hand. That is the step that mints the DOI.**

There is no `release.yml`. The Zenodo integration is a repository webhook subscribed to the `release` event: it
fires when the Release is published, snapshots the tag, and mints a version DOI.

This is the **opposite** of the rule in the five package repositories (`typedout`, `politeclient`, `scaffld`,
`webhook-replay`, `framesig`), where `release.yml` creates the Release itself and creating it by hand breaks the
run *after* it has already published to PyPI. Getting the two backwards is how two package releases had to be
repaired by hand on 14 September 2026. Before releasing anything, check which kind of repository you are in:

| | this repository | a package repository |
|---|---|---|
| has `.github/workflows/release.yml` | no | yes |
| who creates the GitHub Release | **you** | the workflow |
| what the tag triggers | nothing | the whole release run |
| what the Release triggers | the Zenodo deposit | nothing |

## When a release is warranted

This is a kit of shell scripts, not a package, so a version is a state of the scripts and their documentation.
Publish a version when the change **reaches someone who uses or reads it**: a behaviour change in the scripts, a
corrected claim, documentation someone acts on. Continuous integration, action pinning and formatting do not
reach a user and do not justify a version.

`main` sitting ahead of the latest tag is therefore a normal, deliberate state, not a backlog.

## Steps

### 1. The preparation pull request

| file | what to change |
|---|---|
| `CITATION.cff` | `version:` and `date-released:` (ISO `YYYY-MM-DD`) |
| `CHANGELOG.md` | a new `## [X.Y.Z] — YYYY-MM-DD` heading, and its link at the bottom |

**`README.es.md` moves with `README.md`.** The translation check keys on a content hash, not a commit, so if you
touch the English README you also update the Spanish one and recompute the marker — `<!-- synced-from: <40 hex> -->`,
which is `git hash-object README.md` **taken after the last edit to the English file**. A marker computed before
the final edit points at a file that no longer exists.

**Keep every scalar in `CITATION.cff` a scalar.** A YAML list where a string is expected — `license:` written as a
list, most often — makes the deposit fail its own metadata validation and the release is archived as Failed with
no DOI minted. That happened to the cookbook's v0.1.0 on 4 September 2026.

### 2. Merge, and let CI finish on `main`

`checks` and `translations` both have to be green. Do not tag a commit whose checks have not completed.

### 3. Create the tag on the merge commit

```
gh api -X POST repos/ferinazumaDEV/notebooklm-kb-system/git/refs \
  -f ref=refs/tags/vX.Y.Z -f sha=<merge sha>
```

Nothing happens yet. Here the tag is a label, not a trigger.

### 4. Publish the GitHub Release — this mints the DOI

```
gh release create vX.Y.Z -R ferinazumaDEV/notebooklm-kb-system \
  --title "vX.Y.Z" --notes-file <notes>
```

### 5. Verify at the destination, not at the sender

A published Release is not evidence that the deposit exists. Ask Zenodo:

```
python3 - <<'PY'
import json, urllib.request
rid = "22554843"   # concept record id for this repository
req = urllib.request.Request(f"https://zenodo.org/api/records/{rid}",
                             headers={"User-Agent": "Mozilla/5.0 (compatible; release-check/1.0)"})
d = json.load(urllib.request.urlopen(req, timeout=40))
print(d["metadata"]["version"], d["doi"], d.get("conceptdoi"), d["metadata"].get("license"))
PY
```

`metadata.version` must equal the tag.

**Do not expect `license` to be right, and know why.** Both deposits of this repository — v0.1.0, before the
citation file existed, and v0.1.1, with it present and declaring `AGPL-3.0-only` — were minted with
`{"id": "apgl-v3"}`. That id **is not in Zenodo's licence vocabulary**, which lists `agpl-3.0-only` and
`agpl-3.0-or-later`. So whatever produces it sits upstream of `CITATION.cff`, and adding that file did not move
it. The mechanism is not established; this document does not guess at one.

Query the vocabulary at `https://zenodo.org/api/vocabularies/licenses/<id>`, with lowercase ids **and a browser
User-Agent**: the API answers `403` to a default client, and the older `/api/licenses/<id>` path is gone.

**What to try next, and how to test it without risking a deposit.** The GitHub integration reads a
`.zenodo.json` at the repository root, which overrides derived metadata. It has not been added here, on purpose:
a wrong shape can make a deposit fail outright and mint no DOI at all, which is worse than a wrong licence id,
and there is no dry run. Test it on a **throwaway public repository** with its own Zenodo hook first — tag it,
release it, read the record back — and only then bring the proven file here. That is the same negative-control
discipline used everywhere else in this cluster: see the file fail, and see it pass, before trusting it.

Two other ways this check has misled:

Two ways this check has misled before:

- Querying `zenodo.org/api/records?q=doi:"<concept DOI>"` returns **zero hits**, because the concept DOI is not
  any single record's `doi` field. Zero hits there proves nothing. Fetch the record by id.
- The repository's webhook delivery log can be empty for a delivery that succeeded. Ask Zenodo, not the sender.

Then check the deposit against the tag **by content**: every file in the archive must have the same SHA-256 as the
file at that tag. A DOI that resolves says a deposit exists, not that it holds what you tagged.

### 6. Software Heritage

Trigger it, wait for the visit to report `full`, and record the revision SWHID in the release notes:

```
curl -s -X POST "https://archive.softwareheritage.org/api/1/origin/save/git/url/https://github.com/ferinazumaDEV/notebooklm-kb-system/"
```

The origin API returns `NotFoundExc` while indexing, which is a false negative rather than a missing archive.

## Never

- **Never delete a release.** Deleting one is what left Zenodo returning `409` with no DOI.
- **Never edit a published deposit** to fix something. Publish the next version; the point of an archive is that
  the cited object does not move.
- **Never change the licence in `CITATION.cff` alone.** That file follows `LICENSE` and the README, it does not
  lead them.

> **Licence check — result (2026-09-23).** Verified on v0.1.2: Zenodo record 10.5281/zenodo.22923166 carries `metadata.license.id = agpl-3.0-or-later`, the value `.zenodo.json` declares. Records v0.1.0 and v0.1.1 keep `apgl-v3` (old records are not edited). `.zenodo.json` fixes the archived licence; `CITATION.cff` alone did not. The deposit stayed in state "Received" for about 55 minutes before the record existed, while zenodo.org showed a slowness notice; poll for up to an hour before suspecting the deposit. The GitHub webhook sends three events per Release (published, released, created): Zenodo answers 202 to one and 409 to the other two, which is normal.
>
> **Licence check (added 2026-09-23).** After the Zenodo record exists, read its metadata and compare `metadata.license.id` with the `license` value in `.zenodo.json` (`agpl-3.0-or-later`). Records v0.1.0 and v0.1.1 carry `apgl-v3`; if the new record still does, `.zenodo.json` did not fix it and the next thing to try is a manual edit of the record on zenodo.org.
