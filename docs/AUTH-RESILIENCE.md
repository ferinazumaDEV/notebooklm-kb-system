# AUTH RESILIENCE — keep NotebookLM auth from failing silently

NotebookLM has no service-account or API-key auth: the CLI drives a **browser session**
(Google cookies stored in a profile). That session is the single point of failure for the
whole knowledge base. This document explains how it rots, and a small, safe setup that turns
a silent multi-day outage into a self-healing system with an early email alert.

> TL;DR: run a **frequent keepalive**, a **real-operation healthcheck that emails you on
> failure**, and a **hardened wrapper**. Do **not** install a Google "master token".

## Why the session dies (and why you don't notice)

- **Cookie rotation.** The session cookie `__Secure-1PSIDTS` rotates on a window that can be
  as short as minutes. A once-a-day keepalive can simply *cross* that window — the cookie is
  never refreshed in time and the session dies server-side.
- **Silent failure.** A naive refresh cron that only writes a warning to a logfile fails
  invisibly. You find out days later, the first time an agent actually needs a notebook.
- **The status commands lie.** `notebooklm doctor` and `auth check` report *valid* because
  the cookies are *present* — while every real RPC bounces to `accounts.google.com`. **Only a
  real operation** (e.g. `source list`) detects the outage. Never gate health on `doctor`.

## The fix — three cheap pieces

### 1. A frequent keepalive (proactive)

`notebooklm auth refresh` is a one-shot keepalive: it pokes the auth path so Google rotates
`__Secure-1PSIDTS`, then persists the fresh cookie jar. Run it **every ~15 minutes** so you
never cross the rotation window — not once a day.

```cron
*/15 * * * * NOTEBOOKLM_HEADLESS_REAUTH=1 notebooklm auth refresh >> ~/.kb/refresh.log 2>&1
```

### 2. A real-operation healthcheck that alerts (reactive)

[`healthcheck.sh`](../healthcheck.sh) probes with a **real, cheap op** (`source list` on a
small notebook). If auth is down it first tries an unattended re-auth (keepalive + headless
re-mint); if that can't fix it (the Google session is truly dead), it **emails you** the exact
recovery steps — once per cooldown window, and it goes quiet automatically on recovery.

```cron
9,39 * * * * KB_HEALTHCHECK_NOTEBOOK=<NOTEBOOK_ID> KB_ALERT_EMAIL=<YOUR_EMAIL> \
             KB_MAIL_CMD="$HOME/.mail/send" ~/path/to/healthcheck.sh >/dev/null 2>&1
```

Test it without sending mail: `HC_DRY_RUN=1 KB_HEALTHCHECK_NOTEBOOK=<id> ./healthcheck.sh`.

### 3. A hardened CLI wrapper

Wrap the `ask` path so it (a) exports `NOTEBOOKLM_HEADLESS_REAUTH=1` (lets the CLI re-mint a
session mid-call), (b) retries once on an auth error, and (c) on a persistent auth failure
prints **one clean human line** with the re-login steps instead of a stack trace + "report a
bug". Your agents get a readable signal, not noise.

## Recovering a dead session

When the Google session dies server-side, neither the keepalive nor headless re-auth can
revive it — and **importing cookies does not fix it** either. You need one interactive login
on a machine with a browser, signed into the notebook's Google account:

1. `notebooklm login --browser chrome --storage ./nblm_state.json` — complete the Google
   login **without closing the window** (a half-closed window leaves an empty state file).
2. Copy `nblm_state.json` to the host, back up the old profile state, and replace it:
   ```bash
   cp <profile>/storage_state.json <profile>/storage_state.json.bak-$(date +%F)
   cp nblm_state.json <profile>/storage_state.json && chmod 600 <profile>/storage_state.json
   ```
3. Verify with a **real op** (not `doctor`): `notebooklm source list -n <NOTEBOOK_ID>`.

With the frequent keepalive in place, this manual step should be rare — and the healthcheck
guarantees you hear about it in minutes, not days.

## Why NOT a "master token"

The `gpsoauth` path can mint a Google **master token** so the box re-authenticates forever
with no human login. It is tempting for "never falls again" — and it is a **bad idea**:

- A master token is **full-account access** and **cannot be revoked** short of a password
  change. It is exactly the credential info-stealer malware targets.
- Storing it on an always-on server means a host compromise = permanent, silent, total
  account takeover.

The trade this system makes instead: short-lived browser cookies + a rare, early-flagged
human re-login. Slightly less "hands-off", dramatically smaller blast radius. Keep it.
