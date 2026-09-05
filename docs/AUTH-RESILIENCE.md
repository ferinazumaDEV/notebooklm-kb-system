# AUTH RESILIENCE — keep NotebookLM auth from failing silently

NotebookLM has no service-account or API-key auth: the CLI drives a **browser session**
(Google cookies stored in a profile). That session is the single point of failure for the
whole knowledge base. This document explains how it rots — including the part a frequent
keepalive alone does **not** fix — and a small, layered setup that turns a silent multi-day
outage into a self-healing system with an honest early alert and a graceful degraded mode.

> TL;DR: a frequent cookie keepalive is necessary but **not sufficient**. The multi-day death
> is a **device-bound token** problem that only a **real browser exercising the profile** (or a
> host-local device key) can prevent. Layer it: warm-profile keepalive → real-operation
> healthcheck that emails you → hardened wrapper → local degraded mode. Do **not** install a
> Google "master token".

## Why the session dies — and why a keepalive alone doesn't save it

Two different things rot on two different clocks. Confusing them is why *"I run a keepalive
every 15 minutes and it **still** dies every few days"* is such a common, maddening report —
and it's exactly the trap the first version of this doc fell into.

1. **The short cookie (minutes-to-hours).** The session cookie `__Secure-1PSIDTS` rotates on a
   short window. If your keepalive is too infrequent it can simply *cross* that window and the
   session dies. A frequent `auth refresh` (every ~15 min) fixes **this** failure — and only
   this one.

2. **The device-bound tokens (days) — the one a keepalive can't touch.** Modern Google
   sessions are also held up by **device-bound credentials** (Google's **DBSC** — Device Bound
   Session Credentials; primary source: the W3C/Chrome explainer
   <https://github.com/w3c/webappsec-dbsc>, Chrome docs
   <https://developer.chrome.com/docs/web-platform/device-bound-session-credentials> — and the
   refresh-token family). These are cryptographically tied to a
   **device key** that lives inside the browser profile, and they can only be renewed by **a
   real browser proving possession of that key**. A POST-based keepalive (`auth refresh` just
   rotates the cookie jar over HTTP) *cannot* produce that proof — so the refresh tokens
   quietly age out over days and the session dies **server-side, no matter how often you
   rotated the short cookie.** This is the death that survives a "perfect" keepalive.
   - *Confidence:* the multi-day death under a correct 15-min keepalive is **observed**; the
     device-bound-token mechanism is the **well-supported explanation** (it's what Google's
     browser-session design and the CLI's own browser-backed re-auth imply). Treat the fix
     below as "what empirically keeps a session alive for weeks," not folklore.
   - *Corollary:* a headless re-auth profile that is **never exercised by a real browser** is
     **born dead** — it holds cookies but has no live device key to renew them.

3. **Silent failure.** A naive refresh cron that only writes a warning to a logfile fails
   invisibly. You find out days later, the first time an agent actually needs a notebook.

4. **The status commands lie.** `notebooklm doctor` and `auth check` report *valid* because the
   cookies are *present* — while every real RPC bounces to `accounts.google.com`. **Only a real
   operation** (e.g. `source list`) detects the outage. Never gate health on `doctor`.

## The fix — prevent the death you can, recover the rest honestly

### 1. A frequent keepalive (necessary, not sufficient)

`notebooklm auth refresh` rotates `__Secure-1PSIDTS` and persists the fresh cookie jar. Run it
**every ~15 minutes** so you never cross the *short-cookie* window. Know its limit: it does
**not** renew the device-bound tokens (see above), so on its own it will not stop the multi-day
death.

```cron
*/15 * * * * NOTEBOOKLM_HEADLESS_REAUTH=1 notebooklm auth refresh >> ~/.kb/refresh.log 2>&1
```

### 2. Exercise the profile with a REAL browser (this is what actually prevents the multi-day death)

Periodically drive the persistent profile with a **real (headless) browser** — a "warm-profile"
pass — so the device-bound tokens get renewed the only way they can. In practice this is the
difference between a session that lasts *weeks* and one that dies in *days*. You need a **device
key that renews**, and there are two ways to get one:

- **Seed the device key on the host (most autonomous).** Do the interactive `notebooklm login`
  **on the machine that will run the KB**. A headless server can still show the browser through
  a throwaway virtual display (`Xvfb` + a VNC/noVNC bridge over an SSH tunnel, torn down right
  after). That login mints a **device key local to that host**, so the warm-profile pass renews
  the session **without depending on any other machine** — even if every other box is off.
- **Or borrow a live browser via CDP (loopback only).** Point the headless re-auth at a browser
  you keep signed-in and fresh (e.g. your daily desktop) over the Chrome DevTools Protocol. As a
  safety guard the CLI accepts a CDP endpoint **only on a loopback host** (`127.0.0.1`), so
  **tunnel it** (`ssh -L 9222:127.0.0.1:9222 …`) — never point it at a LAN / VPN / remote IP
  (a non-loopback endpoint is account-equivalent access and is refused). This is the freshest
  source, but it depends on that machine staying on.

### 3. A real-operation healthcheck that alerts (reactive)

[`healthcheck.sh`](../healthcheck.sh) probes with a **real, cheap op** (`source list` on a small
notebook). If auth is down it walks an **honest recovery cascade**, verifying with a real op
after **each** rung and never declaring success on dead tokens:

1. cookie keepalive (`auth refresh`) — catches the short-cookie case;
2. warm-profile headless re-mint — renews the device-bound tokens (§2);
3. *(optional)* CDP to a live loopback browser, or copy a fresh state file from an
   already-logged-in machine — a fast bridge;
4. only if all fail, **email you** the exact recovery steps — once per cooldown window, going
   quiet automatically on recovery.

```cron
9,39 * * * * KB_HEALTHCHECK_NOTEBOOK=<NOTEBOOK_ID> KB_ALERT_EMAIL=<YOUR_EMAIL> \
             KB_MAIL_CMD="$HOME/.mail/send" ~/path/to/healthcheck.sh >/dev/null 2>&1
```

Test it without sending mail: `HC_DRY_RUN=1 KB_HEALTHCHECK_NOTEBOOK=<id> ./healthcheck.sh`.

### 4. A hardened CLI wrapper

Wrap the `ask` path so it (a) exports `NOTEBOOKLM_HEADLESS_REAUTH=1` (lets the CLI re-mint a
session mid-call), (b) retries once on an auth error, and (c) on a persistent auth failure
prints **one clean human line** with the re-login steps instead of a stack trace + "report a
bug". Your agents get a readable signal, not noise.

### 5. A local degraded mode (don't go blind during an outage)

When the session is genuinely dead — the rare case only a human re-login cures — don't leave
your agents blind for the minutes-to-hours until you re-seed. Keep a **degraded fallback**: on a
persistent auth failure the wrapper serves the **local build-docs** (the same Markdown that
seeds your notebooks) via a keyword match, prints an **honest banner** ("NotebookLM is down —
this is a local, un-synthesised fallback"), and returns a **distinct exit code** so callers can
tell a degraded answer from a live one. A keyword hit over your own docs is not a NotebookLM
synthesis — but it beats a stack trace and a blind agent.

## Recovering a dead session (and getting a renewing device key)

When the session dies server-side, neither the cookie keepalive nor a POST re-auth can revive
it, and **copying stale cookies does not fix it**. You need one interactive Google login. Pick
by how autonomous you want the result:

- **(A) Log in ON THE HOST — recommended for autonomy.** Run `notebooklm login` on the KB
  machine itself (on a headless box, through a virtual display). This mints a **local device
  key**, so the warm-profile keepalive then renews the session on its own — the setup that
  survives every other machine being off.
- **(B) Log in on another machine + copy the state — a fast bridge, not a cure.**
  `notebooklm login --browser chrome --storage ./nblm_state.json` on a desktop (complete the
  Google login **without closing the window** — a half-closed window leaves an empty state
  file), then copy it over:
  ```bash
  cp <profile>/storage_state.json <profile>/storage_state.json.bak-$(date +%F)
  cp nblm_state.json <profile>/storage_state.json && chmod 600 <profile>/storage_state.json
  ```
  Quick, but it carries **no local device key**, so it degrades back to rotate-only and will die
  again unless you later do (A) or wire CDP.
- **(C) CDP to your daily browser** — see §2; the freshest source when that machine stays on.

Verify with a **real op** (not `doctor`): `notebooklm source list -n <NOTEBOOK_ID>`.

With a renewing device key (A/C) in place, this manual step should become rare — and the
healthcheck guarantees you hear about it in minutes, not days.

## Hardening a live KB without downtime

Rebuilding the auth stack under a KB people rely on? Do it **side-by-side**: build the new stack
in a **parallel, isolated directory** with its own profile, logs and config; seed it and run a
full verify (a **real end-to-end query must pass**) while the old one keeps serving; then cut
over by repointing your cron + wrapper + any hook. Keep the old directory **untouched** so
rollback is a one-line revert. Never verify a rebuild by trusting `doctor` — gate the cutover on
a live query.

## Why NOT a "master token"

The `gpsoauth` path can mint a Google **master token** so the box re-authenticates forever with
no human login. It is tempting for "never falls again" — and it is a **bad idea**:

- A master token is **full-account access** and **cannot be revoked** short of a password
  change. It is exactly the credential info-stealer malware targets.
- Storing it on an always-on server means a host compromise = permanent, silent, total account
  takeover.

The trade this system makes instead: short-lived browser cookies + a **host-local device key**
that renews them + a rare, early-flagged human re-login. Slightly less "hands-off", dramatically
smaller blast radius. Keep it.
