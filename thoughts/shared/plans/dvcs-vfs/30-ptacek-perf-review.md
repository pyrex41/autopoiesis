---
date: 2026-06-25
reviewer: Thomas Ptacek (persona)
status: review
topic: "Security + edge-ops review of the hot-path perf architecture: OpenResty/shen-lua read tier, X-Accel-Redirect zero-copy blob serve, multi-tier immutable caching in front of a serialized land tier"
inputs:
  - thoughts/shared/plans/dvcs-vfs/26-hotpath-perf-architecture.md
  - thoughts/shared/plans/dvcs-vfs/22-ptacek-go-vs-ocaml.md
tags: [review, ptacek, security, edge, openresty, x-accel, cdn, cache, authz, cas, sendfile]
---

# Ptacek review — is this safe to run at the edge?

I reviewed the architecture choice once already (`22`: I'd run all-OCaml, and most of this is
reinventing Sapling). This doc is a different question. It's not "which language" — it's "you want to
put a content-addressed store behind a CDN with per-principal ACLs, using nginx's internal-redirect
machinery as the authorization boundary." That's a *security* document wearing a *performance*
document's clothes, and I'm going to read it as the former, because that's where it lives or dies.

I'm wearing two hats here: the Matasano hat (I have spent pentest days turning exactly this pattern
into "read any object") and the Fly.io edge hat (I have been paged by exactly this CDN-cache-vs-authz
tension). Both hats say the same thing, so let me say it up front.

---

## Blunt verdict

**Conditional — and the condition is severe enough that I'd block the design until it's met.**

The good news first, because it's real and I want to credit it: **brain-decides / nginx-serves is a
legitimate, Fly-adjacent production pattern.** Internal redirects to a `sendfile()` location, with
the application only making the *decision*, is how a lot of serious shops serve large payloads
without dragging bytes through the app runtime. And **content-addressing genuinely is the
cache-friendliest workload on earth** — immutable, self-verifying, zero invalidation. The author is
not wrong that these two facts compose nicely. If you only had one tenant and no ACLs, I'd sign off in
a paragraph.

But you have per-principal ACLs over a content-addressed store, and you want to cache aggressively at
a shared edge. That combination is the single hardest authorization problem in web infrastructure,
and **this document treats it as a footnote** (§9.5 is one open question; §6 cheerfully says "CDN
edge with `immutable` — served forever, never revalidated" without ever asking *to whom*). The design
as written has at least one path that serves a private blob to a principal who was never authorized,
and several that serve *any* blob to *any* caller. None of these are exotic. They are the first five
things on my checklist.

**The architecture is sound in shape and dangerous in default.** It is conditionally safe *only if*
every item in S1–S7 below is closed before a single byte is cached at a shared layer. Until then it is
not safe to run at the edge — not because the pattern is wrong, but because "cache everything
immutable" and "authorize per principal" are in direct conflict and the doc resolves that conflict by
ignoring it.

---

## The core thing the document gets wrong: hash IS the capability, but it's NOT the authorization

Everything below flows from one confusion baked into §3 and §6. Let me state it precisely because the
whole review hangs on it.

In a content-addressed store, **the hash is a read capability** — `knowing-the-hash == being-able-to-
name-the-bytes`. The doc leans on this for caching (a hash names one byte string forever, so caches
are correct-by-construction). True. But it then quietly assumes the hash is *also* the unit of
authorization, because that's what makes the cache layers "correct with no invalidation logic" (§6).

It is not. **Authorization in this system is per-(principal, path), and it is enforced exactly once:
in the `access_by_lua` resolve step, on the way in.** After that step, the request is a bare
`X-Accel-Redirect -> /cas/<hash>` and *the hash carries no principal and no ACL*. Every layer
downstream of the resolve — the internal location, the disk cache, the `lua_shared_dict`, the CDN —
operates on the hash alone. So the security of the entire system reduces to a single invariant:

> **No byte of `/cas/<hash>` is ever reachable except as the output of a successful, fresh,
> per-principal ACL check for the specific principal making the request.**

The document never states this invariant, and as written it violates it in at least four places.
That's the review.

---

## Findings

### S1 — The internal `/cas/<hash>` location is directly reachable / X-Accel-Redirect is smugglable — **CRITICAL**

This is the one. This is the scariest bypass and it's the reason for the conditional verdict.

The pattern (§3) is: Lua checks ACL, then emits `X-Accel-Redirect: /cas/<hash>`, and nginx serves
that internal location with `sendfile()`. The security of this rests *entirely* on the assumption that
`/cas/<hash>` is reachable **only** via an internal redirect from the Lua tier — never from the
client. That assumption is one config line away from false, and there are multiple ways to make it
false:

**(a) Direct request to `/cas/`.** If the `location /cas/` block is missing the `internal;`
directive — or if a refactor, a templated config, a `try_files`, a `location /` regex, or an
`if`-block ever exposes that prefix — then `GET /cas/<hash>` serves the blob with **zero ACL check**.
Content-addressing means an attacker who has *ever* seen a hash (from a previous authorized read, a
log, an error message, a git protocol exchange, a teammate's screen) can now read that blob forever,
directly, bypassing the brain entirely. And because hashes leak constantly (they're in every tree
object, every manifest, every `as-of` response), "has ever seen a hash" is a low bar. **`internal;`
on the CAS location is the single most load-bearing line in the entire system and the doc never
mentions it.**

**(b) Client-supplied `X-Accel-Redirect` reflected.** nginx honors `X-Accel-Redirect` as a *response*
header from the upstream/Lua. The classic catastrophe is when the application ever copies a
client-controlled value into that response header, or when a misconfigured proxy passes a client
*request* header named `X-Accel-Redirect` through to a context where it's interpreted. If a client
can get `X-Accel-Redirect: /cas/<any-hash>` to appear on the response, they read any blob. The Lua
tier must **never** let any client-influenced data reach that header, and the front proxy must
**strip** `X-Accel-Redirect` (and `X-Accel-*`) from inbound requests. Unspecified in the doc.

**(c) Request smuggling / normalization to the internal prefix.** If there's any front-tier
(CDN, L7 LB, a second nginx) ahead of the OpenResty fleet, HTTP request smuggling (CL.TE/TE.CL, or
HTTP/2 downgrade desync) lets an attacker prepend a smuggled `GET /cas/<hash>` request that hits the
origin *behind* whatever edge auth exists. Same outcome: direct internal-location read. The
`internal;` directive defends against direct *external* requests to that nginx, but smuggling makes a
request *look* internal-origin. You need defense in depth: the CAS location should require a proof
that the resolve step ran (see mitigation), not just trust that it wasn't reached externally.

**(d) Path normalization in the resolve, not just the serve.** The ACL is checked on `(commit, path)`
in Lua. If the Lua resolve normalizes `path` differently than it canonicalizes for the
hash lookup — `..`, `.`, doubled slashes, trailing slash, percent-encoding (`%2e%2e`), Unicode, NUL —
then you authorize one path and resolve another's hash. This is S1 from my prior review (`22`),
reincarnated at the Lua layer. `src/app/../secrets/key` passes an `src/app/` allow grant and resolves
the secrets blob's hash, which then gets `X-Accel`'d with no further check. **Canonicalize the path to
its final repo-relative form, authorize *that*, and resolve the hash from *that same* canonical
string — never two different strings.**

**Mitigation (all of these together, not any one):**
1. `internal;` on `/cas/` — mandatory, asserted in a config test that fails the build if absent.
2. Front proxy and OpenResty both **strip inbound `X-Accel-*`, `X-Sendfile`, and any reflected-header
   vectors** at the very edge.
3. **Bind the redirect to a fresh per-request proof.** Don't redirect to `/cas/<hash>` as a bare
   path. Have the Lua tier mint a short-TTL, single-use, HMAC'd token over
   `(hash, principal, acl-version, expiry)` and pass it on the internal redirect; the internal
   location validates the HMAC (via a cheap `access_by_lua` or nginx `secure_link`) before
   `sendfile()`. Now reaching `/cas/` directly, smuggling it, or replaying an old hash all fail
   because there's no valid fresh token. This converts "hash = capability" into "hash + fresh
   authz-bound token = capability," which is the only safe form. The author already proposes
   partial-eval'ing the Datalog into Lua — minting an HMAC in that same step is trivial.
4. Terminate HTTP/2 carefully and run a smuggling/desync test suite against the full edge chain.
5. Canonicalize-then-authorize-then-resolve on the *same* canonical path; reject `..`, encoded
   traversal, NUL, absolute paths in the path constructor.

**Without item 3, this design is one missing `internal;` away from "read any blob by hash, no auth."**
That is the verdict in one sentence.

### S2 — CDN/edge cache keyed on hash serves private blobs cross-principal — **CRITICAL**

§6: "CDN edge with `Cache-Control: immutable` — a monorepo's hot files served from the edge, forever,
never revalidated." Stop. **The CDN cache key, by default and by the doc's own logic, is the hash (or
the URL containing the hash) — NOT the principal.** So:

- Principal A (authorized for `src/secrets/key`) fetches it. The resolve produces `/cas/<H>`, the CDN
  caches the bytes under key `<H>` with `immutable`.
- Principal B (NOT authorized) requests something whose resolve produces the same `<H>` — or, worse,
  if the cacheable URL is `/blob-by-path?commit=c&path=p` and that normalizes/collides, or if B can
  influence the cache key — gets a **cache HIT at the edge and the bytes are served without the
  origin's Lua ACL ever running.**

The whole point of an edge cache is to *not hit the origin*. But your authorization *only exists at
the origin*. So **every edge cache hit is, by construction, a request that skipped authorization.**
For public content that's fine. For per-principal-ACL'd content it is a direct confidentiality breach.
"Cache everything immutable" and "authorize per principal" cannot both be true at a shared cache
unless the cache key includes the authorization decision. The doc wants both and picks caching.

This is not a corner case. It is the *central* tension and §6 is on the wrong side of it. See the
dedicated section below for the resolution. Severity CRITICAL because the failure mode is silent
cross-tenant data disclosure with no log line at the origin (the origin never saw the request).

### S3 — `lua_shared_dict` cache key is forgeable / cross-tenant poisonable — **HIGH**

§6 proposes a `shared_dict` decision cache keyed by `(principal, path-prefix, acl-version)`, plus a
resolve cache. One `shared_dict` is shared across all workers and *all tenants*. Concerns:

- **Key construction must be injective and canonical.** If the key is built by string concatenation
  (`principal .. ":" .. path .. ":" .. ver`), then a principal or path containing the delimiter (`:`)
  collides: principal `a` + path `b:c` keys the same as principal `a:b` + path `c`. A user who can
  influence their own principal string or the path can **forge another principal's cached ACL
  decision** — poison the dict so an unauthorized principal reads a cached *allow*. Use a
  length-prefixed or hashed-tuple key, never naive concatenation, and treat every component as
  untrusted bytes.
- **Caching ALLOW decisions is itself a revocation hazard.** A cached `allow` for
  `(principal, prefix, acl-version)` is correct only until policy changes. The doc invalidates by
  bumping `acl-version` on land. But the read tier is explicitly allowed to be "slightly behind"
  (§5) — so there's a window where a fired employee's `allow` is still cached at a behind read node
  *and* `acl-version` hasn't propagated. Combine with S2 (edge cache) and revocation latency stacks:
  shared_dict TTL + read-tier lag + CDN immutable. See revocation discussion below.
- **Poisoning the resolve cache** `(commit, path) -> hash`: same key-injectivity problem, but the
  blast radius is worse — poison it and you redirect an authorized principal's read to an
  attacker-chosen hash (integrity), or cache a resolve for a path the poisoner shouldn't see and let
  it leak via timing/existence. Resolve-cache entries should be keyed on canonicalized inputs and the
  values content-verified (the hash is self-verifying — re-checking on serve is cheap insurance).
- **DoS via dict eviction.** One `shared_dict` shared across tenants is a shared resource; a noisy or
  malicious tenant can churn the dict (LRU eviction) and degrade everyone's authz cache to
  cold-path, which on a Prolog/Datalog evaluator (per `22` finding S4) is a CPU amplification vector.
  Partition dicts per trust-domain or size/rate-limit per principal.

### S4 — Content-addressing existence/dedup oracle, now at edge-cache timing resolution — **HIGH** (was MEDIUM)

In `22` I flagged confirm-by-hash as MEDIUM. The caching tiers *upgrade* it. With a multi-tier cache,
an unauthorized principal gets a **high-resolution timing oracle**: a request that hits `shared_dict`
or edge cache returns in microseconds; one that misses goes to origin/disk. So even if the ACL
correctly denies the *content*, the **cache-hit/miss timing confirms whether some other principal
recently read a given hash**, and whether a guessed-content hash *exists* in the store. For
"secrets in the monorepo," confirm-by-hash plus a presence/timing side channel is enough to validate
guessable secrets without ever being authorized. Mitigation: don't let cache state be observable
across principals — per-principal cache partitions (which you need for S2 anyway) collapse this
channel; constant-time-ish deny paths; deny *before* any cache probe that could reveal another
principal's activity.

### S5 — Revocation in an immutable + edge-cached world is effectively impossible without design for it — **HIGH**

The doc celebrates "served forever, never revalidated" (§6) and "slightly-behind read tier is never
*wrong*" (§5). Both are true for *content correctness* and false for *authorization*. Authorization is
**mutable** (you fire someone, you change a grant) layered over **immutable** content. The doc never
reconciles this. Concretely: an employee is terminated; their access is revoked at the land tier by a
policy land. But:

- their `allow` may be cached in N read nodes' `shared_dict` until `acl-version` propagates;
- any blob they were authorized for and that got cached at the **CDN edge under a hash key with
  `immutable`** is now servable to anyone who can reach that cache entry and name the hash —
  *including them*, via S1/S2 — and the CDN was explicitly told never to revalidate.

**You cannot revoke an `immutable` edge-cached object by policy change**, because the policy lives at
the origin and the edge was instructed not to ask the origin. This is the operational nightmare:
revocation requires a global edge purge keyed on... what? You don't know which hashes the fired
employee touched unless you logged every resolve. Mitigation: per-principal/per-tenant cache keys
(so an entry is never shared to a principal who didn't authorize it), short-TTL signed URLs for
private content instead of `immutable` (revocation = stop signing, ≤ TTL window), and an explicit
"what's our revocation SLA and how do we purge" runbook that the doc currently lacks. **If the answer
to "how fast can we cut off a fired admin" is "whenever the CDN TTL expires, and we can't enumerate
what to purge," that's a finding by itself.**

### S6 — Range requests, conditional requests, and partial-content quirks on the internal serve — **MEDIUM**

The internal `/cas/<hash>` `sendfile()` location will, by default, honor `Range:` requests,
`If-Range`, `If-None-Match`/`ETag`, and HTTP/2 byte-range coalescing. Two issues: (a) if the
authz-binding token (S1 item 3) is validated only on the initial request but range continuations or
cached 206 responses are served from a tier that didn't see the token, you get partial-read bypass;
(b) ETag = hash is convenient but it makes the ETag a *cross-principal cache validator* — a client
presenting `If-None-Match: "<hash>"` can probe existence (304 vs 200) as another oracle (feeds S4).
Decide the range/conditional story explicitly; validate authz on every sub-request including range
continuations; don't let ETag become an unauthenticated existence oracle.

### S7 — Operability, blast radius, and the "policy lands at the edge" pipeline — **HIGH (ops)**

Per `22`, my whole lens is the pager. This architecture is strictly *more* to operate than the
all-OCaml single binary I recommended: an OpenResty read fleet, a separate serialized land tier, the
Shen toolchain (compile-to-lua *and* compile-to-SBCL), git shell-outs on the land side, the
partial-eval'd Datalog-to-Lua generator, **and a CDN**. Each is a crash domain, a config surface, and
a place a bad change propagates.

- **Bad-policy blast radius is now global and fast.** The doc's §6 partial-evaluates the landed ACL
  into generated Lua pushed to the read fleet. A bad policy land — or a bug in the
  Datalog→Lua generator — propagates an over-permissive matcher to *every edge read node at once*,
  and the differential test (§6) is the only thing standing between "policy compiles" and "policy is
  wrong in prod." The doc itself flags "partial-eval correctness drift" (§9.6) as an open question.
  An over-permissive generated matcher + edge caching of the resulting allows = a breach you can't
  quickly recall (S5). You need: staged policy rollout (canary read node), a kill-switch that fails
  *closed* to the slow Datalog oracle, and the generated-matcher diff gated in CI as blocking, not
  advisory.
- **Where you get paged:** (1) a wedged read node serving stale-allow after a revocation; (2) a CDN
  purge that can't enumerate what to purge; (3) the Shen-lua toolchain producing a matcher that
  diverges from the oracle under a rule shape the differential test didn't cover; (4) the land tier
  and read tier disagreeing on `acl-version` during a partial propagation, which is a *security*
  incident manifesting as a cache-coherence bug — the worst kind, because it looks like a perf
  blip until someone reads something they shouldn't.
- **Fail-closed is unspecified.** What does a read node do when it can't reach the land tier, when
  `acl-version` is unknown, when the generated matcher fails to load, when the `shared_dict` is full?
  Every one of those must fail *closed* (deny). The doc's whole framing ("slightly-behind is never
  wrong") biases toward fail-*open*-ish availability thinking, which is correct for content and
  catastrophic for authz.

The single-binary all-OCaml alternative authorizes in one bounded total function in one process you
can audit and reason about. This design trades that for edge speed and pays in a much larger, harder-
to-reason-about authorization perimeter. That trade can be worth it — Fly makes versions of it — but
only with the S1–S6 controls in place and a real revocation/fail-closed story, none of which the doc
has yet.

---

## The hard part: caching vs per-principal authorization

This deserves its own section because it's *the* tension and the doc is on the wrong side of it.

**The conflict, stated cleanly:** A cache exists to answer requests *without consulting the authority*.
Your authority is the per-principal ACL at the origin Lua tier. Therefore **every cache hit is an
unauthorized-by-construction response** — the cache served bytes without the ACL running. For public
content this is the entire value of a CDN. For per-principal private content it is a vulnerability.
The doc says "content is immutable, so cache forever" — but *immutability is about correctness of the
bytes, not about who may see them.* The hash being a stable name does nothing to make the recipient
authorized.

You cannot have all three of: (1) shared cache keyed on hash, (2) per-principal read ACLs, (3) cache
hits that skip the origin. Pick the resolution per content class:

**Resolution A — split public vs private tiers (do this).** Classify content. Truly public blobs
(open-source deps, public docs) go in a public CAS tier that is cached aggressively, `immutable`, at
the shared edge, with *no* per-principal ACL — because there's nothing to protect. Private blobs go in
a tier that is **never** cached at a shared layer keyed on hash alone. This is the cleanest answer and
it's the one Fly-adjacent shops actually use: the edge cache only ever holds things that are safe for
anyone who can reach that cache.

**Resolution B — signed URLs with short TTL for private content (do this, combined with A).** For
private blobs, the Lua tier mints a short-TTL signed URL / token bound to `(hash, principal,
acl-version, expiry)` (this is the same HMAC token as S1 item 3). The CDN/edge *may* cache the bytes,
but the **cache key includes (or the access requires) the authz-bound token**, so a hit is only served
to a request carrying a valid fresh token for that principal. Revocation = stop minting tokens; the
exposure window is the TTL, which you control (minutes, not "immutable forever"). This restores
revocability and keeps most of the caching win.

**Resolution C — per-principal/per-tenant cache partitioning.** Make the cache key
`(authz-token-or-principal-class, hash)` so a cached entry is *physically* never reachable by a
principal who didn't authorize it. More memory (less dedup across principals) but it collapses S2, S4,
and most of S5 at once. Use for the `shared_dict` and disk tiers; combine with A/B for the CDN.

**What you must NOT do** is exactly what §6 says: cache private, per-principal-ACL'd blobs at a shared
edge under a hash-only key with `immutable`. That is the breach. The doc's "zero-invalidation caching"
boast is *correct for content and wrong for authorization* — and the doc never makes that distinction.
Making it is the single most important edit to §6.

---

## Is this safe to run at the edge?

**Conditional — NO as written, YES if S1–S6 are closed and §6 is rewritten per the public/private
split.** The brain-decides/nginx-serves shape is good and the immutable-content cache instinct is
good. But the document as drafted ships with hash-only cache keys, no `internal;`/token binding called
out, no public/private split, and no revocation story — i.e., it ships the breach by default.

**The single scariest bypass:** **A client reaches the internal `/cas/<hash>` location directly — via
a missing `internal;` directive, a reflected/smuggled `X-Accel-Redirect`, or HTTP request smuggling —
and reads ANY blob in the store by hash with the per-principal ACL never running, because
authorization is enforced only at the resolve step and the hash carries no principal.** In a
content-addressed store, knowing-the-hash equals reading-the-content, hashes leak everywhere (trees,
manifests, logs), and the only thing standing between an attacker and "read every secret in the
monorepo" is one nginx config line and the absence of a header-smuggling path. The fix is to never let
the hash alone be sufficient: bind every internal serve to a fresh, single-use, HMAC'd
`(hash, principal, acl-version, expiry)` token minted in the same authorized resolve step, so reaching
`/cas/` by any means without a valid fresh token fails closed.
