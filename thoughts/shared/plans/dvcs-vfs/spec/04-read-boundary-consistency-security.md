---
date: 2026-06-26
researcher: Claude
topic: "mvfs — read boundary: consistency (as-of/RYW/monotonic) AND security (serve tokens/tiers/revocation)"
status: design
layer: spec
builds_on: thoughts/shared/plans/dvcs-vfs/spec/00-overview.md
satisfies:
  - thoughts/shared/plans/dvcs-vfs/29-aphyr-perf-review.md  # consistency (F1–F7, rules 1–6)
  - thoughts/shared/plans/dvcs-vfs/08-aphyr-review-v2.md     # ACL-TOCTOU / stale-allow
  - thoughts/shared/plans/dvcs-vfs/17-aphyr-shen-backends.md # detect-then-discard / losing fork
  - thoughts/shared/plans/dvcs-vfs/30-ptacek-perf-review.md  # security (S1–S7)
  - thoughts/shared/plans/dvcs-vfs/22-ptacek-go-vs-ocaml.md  # path canonicalization / threat model
invariants: [I2, I6, I8, I9]
tags: [spec, read-tier, as-of, basis, read-your-writes, monotonic-reads, committed-watermark, serve-token, hmac, x-accel, internal, cache-partitioning, revocation, multi-tenant]
last_updated: 2026-06-26
---

# 04 — Read boundary: consistency AND security

> Builds on the keystone `spec/00-overview.md`. Honors invariants **I2** (total land
> order), **I6** (ACL soundness / no stale-allow), **I8** (read-your-writes + monotonic
> reads), **I9** (authorization on every byte path). It refines but MUST NOT redefine the
> frozen contracts §5.1 (landed-entry), §5.2 (`as-of` basis), §5.3 (serve token).

## 0. Why these two concerns are one document

Consistency and security meet at exactly one boundary: the **basis**. A read carries
`as-of := (seq, acl-version)`. That same `acl-version` is (a) the *consistency basis* at
which ACLs are evaluated (I6, I8) and (b) the value HMAC-bound into the **serve token**
that authorizes the byte path (I9). The pair cannot be split: a node that is behind on
`acl-version` is simultaneously a *stale read* (Aphyr) and a *stale allow / pre-revoke
authorization* (Ptacek). One enforcement point — "node's applied-basis ≥ request basis,
else refuse" — closes both. So we specify them together.

The two failures we are paid to prevent:

- **Aphyr's trap:** an unenforced basis header is a comment, not a consistency mechanism.
  The behind node serves an *earlier* snapshot as if it were the requested one.
- **Ptacek's trap:** "hash = capability." Authorization runs once at resolve; downstream
  (internal location, `shared_dict`, disk, CDN) sees only the hash. One missing `internal;`
  line, one reflected `X-Accel-Redirect`, one hash-keyed edge cache, and any blob is readable
  by anyone who ever saw the hash.

Both reduce to the same rule, stated once and obeyed everywhere:

> **THE READ-BOUNDARY RULE.** A serving node answers from local state *only if* its
> `applied-basis ≥ request basis`, over **committed** log only; and a byte of
> `/cas/<hash>` is reachable *only* as the output of a fresh, authorized resolve that
> minted a valid serve token for *this* principal at *this* `acl-version`. Otherwise the
> node **blocks → redirects → fails closed**. It NEVER silently serves stale, and NEVER
> serves bytes on the hash alone.

---

# PART A — CONSISTENCY (I8, and I6 at the cache layer)

## A.1 The `as-of` basis enforcement contract (keystone §5.2) — closes F1, F5

The basis is a **monotone composite**: `basis := (seq, acl-version)`, both `u64`, both
drawn from the landed-log (`acl-version` is the `seq` of the most recent committed policy
entry; §5.1). "≥" on a basis is componentwise: `b1 ≥ b2  ⟺  b1.seq ≥ b2.seq ∧
b1.acl-version ≥ b2.acl-version`.

### A.1.1 What the client carries

On **every recency-sensitive read**, the client sends the basis it requires as a lower
bound, in two headers:

```
X-Mvfs-As-Of-Seq:  <u64>     ; required landed-seq (the resolve basis)
X-Mvfs-As-Of-Acl:  <u64>     ; required acl-version (the authorization basis)
```

The basis is the client's **session high-water-mark** (A.3), not merely its last land.
A read with **no** `as-of` headers is declared a *some-snapshot* read: it MAY be served
from any committed applied-basis and is NOT read-your-writes nor monotonic. Absence of a
header MUST NOT be silently treated as a consistent session (closes F5 client side, F3).

### A.1.2 What the node checks (and what it does when behind)

Every serving node knows its own `applied-basis := (applied-seq, applied-acl-version)`,
advanced only by applying **committed** landed-log entries (A.5). On a basis-carrying read:

```
;; as-of enforcement — runs in access_by_lua before any resolve/serve.
;; req.basis = (req.seq, req.acl)   node.applied = (applied-seq, applied-acl)
function enforce-as-of(req, node):
    deadline = now() + T_ryw                       ; bounded wait (config; A.6)
    loop:
        if node.applied.seq  >= req.seq
       and node.applied.acl  >= req.acl:
            return SERVE                            ; basis satisfiable locally
        if now() >= deadline:
            break
        wait-for-apply(min(req.seq, req.acl), until=deadline)  ; CV on apply, no spin
    ;; still behind after T_ryw — never serve stale:
    target = pick-node-known-ge(req.basis)          ; a peer whose applied >= basis,
                                                    ; else the leader read-index endpoint
    if target != nil:
        return REDIRECT(target)                     ; 307, X-Mvfs-Redirect-Basis: req
    return FAIL_CLOSED(409, "cannot satisfy as-of "
                            .. req.seq .. "/" .. req.acl
                            .. " (node at " .. node.applied.seq
                            .. "/" .. node.applied.acl .. ")")
```

Order is fixed: **block (≤ `T_ryw`) → redirect → fail closed**. A node MUST NEVER serve
with `applied-basis < req.basis`. The node needs **no global knowledge**: the client's
basis *is* the lower bound; the node only compares it to its own local applied-basis.

The leader exposes a **read-index** endpoint: given a basis, it either confirms it is the
authority at ≥ basis and serves, or returns its current committed tip so the client/peer
can find a node that is caught up. This is the redirect-of-last-resort target.

Every response (serve, redirect, or some-snapshot) returns the serving node's actual basis:

```
X-Mvfs-Applied-Seq: <u64>
X-Mvfs-Applied-Acl: <u64>
```

so the client can advance its high-water-mark (A.3). This composes I6 into A.1: ACLs are
evaluated *at* `applied-acl-version`, and `applied-acl-version ≥ req.acl` is a precondition
to serve, so a node behind on policy refuses rather than evaluating against stale rules.

## A.2 Read-your-writes (I8) — closes F1

When a land returns its `(seq, acl-version)` ack (per `02`, after fenced fsync-before-ack,
I4), the client **pins that pair as its basis floor**: it raises its session high-water-mark
to `max(current, (seq, acl-version))` and sends it on all subsequent reads. By A.1.2 the
node must satisfy `applied-basis ≥ (seq, acl-version)` or block/redirect/fail — so the
client can never read a snapshot older than its own land. The wait is bounded by `T_ryw`;
on timeout the read is redirected to a caught-up peer or the leader read-index, never served
stale. RYW is thus a *consequence* of A.1 with `basis = the land's ack`, requiring no extra
machinery.

## A.3 Monotonic reads — closes F3

The client maintains a **session high-water-mark**:

```
hwm := (max seq observed across all responses, max acl-version observed)
```

advanced from the `X-Mvfs-Applied-*` headers of every response. Every recency-sensitive
read carries `as-of = hwm`. With A.1.2 enforcement, a node behind the client's hwm
*refuses/redirects* rather than serving an earlier seq — so the session can never go from
observing N to observing < N. Monotonic reads fall out of A.1 for free; no extra protocol.

**Stateless scale-out** is preserved precisely because monotonicity rides on the
*client-carried* hwm, not on server affinity. Session-sticky routing (consistent-hash the
client to a node) is an **optional optimization** to reduce block/redirect churn, but it is
NOT the mechanism and MUST NOT be relied on for correctness: stickiness does not survive a
node falling behind, restarting, or being replaced. The hwm check is the authority; stickiness
is a hint.

## A.4 Two cache classes, two cache keys — closes F2, F6

There are exactly two cache classes. Conflating them is the original sin (Aphyr F2/F6,
Ptacek S2). **Class boundaries are by key shape, not by storage tier.**

### Class 1 — IMMUTABLE blobs (content-addressed)

Hash-named byte strings and git tree/commit objects. A hash names one byte string forever
(I5), so these are correct-by-construction with **zero invalidation**.

```
cache-key (blob)  := ("blob", hash)            ; hash = git object id
cache policy      := Cache-Control: public, immutable, max-age=31536000
serveable from    := lrucache (L1) + shared_dict/disk (L2) + CDN edge (L3)
```

`immutable` / forever-CDN is permitted **ONLY** on this class — i.e. only on responses whose
key is a content hash (`/cas/<hash>`, or `?commit=<explicit-hash>&path=`). (Security note:
even Class 1 *private* blobs are not CDN-cacheable under a bare hash key — see B.7. The
`immutable` directive concerns *correctness of bytes*; *who may see them* is B.7's problem.)

### Class 2 — VERSIONED resolve-map and ACL decisions

These are functions of a *versioned input* whose value changes on every land. They are NOT
content-addressed and MUST NEVER be marked `immutable`.

**Resolve map** `(commit, path) → hash`. The cache key MUST be keyed by an **immutable
basis** — never a mutable ref like `trunk`:

```
cache-key (resolve) := ("resolve", tenant, landed-seq, canonical-path)
                       ;; landed-seq is an immutable basis: seq N's mapping for a
                       ;; path NEVER changes. Equivalently ("resolve", tenant,
                       ;; commit-hash, canonical-path). NEVER ("resolve","trunk",path).
cache policy        := private, no-store at the edge; in-process/shared_dict only
```

Keyed this way the resolve cache *is* immutable-by-construction: a node behind seq N simply
has **no entry** for `(…, N, path)`, which routes into A.1.2's block/redirect/fail path
("behind" = cache miss, not stale hit). This is what makes §3's "no invalidation" claim
actually true for the resolve layer.

**ACL decision** `(principal, path) → allow/deny`. The key is a **total function of every
input the decision depends on** (A.9 / S3):

```
cache-key (acl)  := ("acl", tenant, principal, canonical-path-or-prefix, acl-version)
cache policy     := private, no-store at the edge; per-principal partition (B.7)
```

A node MUST verify `applied-acl-version ≥ req.acl-version` **before serving any decision,
and certainly before serving an ALLOW** (A.1.2 already enforces this as part of basis ≥).
A node that cannot confirm it is current **fails closed** (deny/redirect), never serves a
cached allow from an older version. This is I6 at the cache layer: no stale-allow.

| Property | Class 1 (blob) | Class 2 (resolve / acl) |
|---|---|---|
| Key contains | content hash | basis (`landed-seq` / `acl-version`) + tenant |
| `Cache-Control` | `immutable`, forever | `private`/`no-store` at edge; in-proc only |
| CDN edge | yes (public blobs only, B.7) | **never** |
| Invalidation | none needed | by basis bump (key changes) + watermark truncation (A.5) |
| Behind node | has older blobs (fine) | **cache miss** → block/redirect/fail (A.1.2) |

## A.5 Committed-watermark-only — closes F4

The read tier serves and caches **only committed** landed-log entries. Define:

```
committed-watermark := max seq that is BOTH
                         (a) durable to the configured durability width (I4), AND
                         (b) past the fence's point-of-no-return (cannot be truncated
                             by a leader change; I7)
```

The read tier's cacheable/serveable basis ceiling is `committed-watermark`, derived from
the **landed-log's committed prefix itself** — never from any single (possibly stale) leader's
bleeding-edge tip. Rules:

1. The read tier pulls/applies entries only up to `committed-watermark`. `applied-seq` (A.1)
   never exceeds it. Uncommitted/bleeding-tip entries are **never cached in the first place**.
2. Because only committed seqs are cached, the `seq → commit-hash` binding is genuinely
   immutable for every cached seq — a discarded **losing-fork tail** (the detect-then-discard
   recovery of `08`/`17`: GC-paused old leader appends 101=H, read tier could pull it, then
   the real primary's 101=H′ wins and H is truncated) is *never* cached and *never* served.
   This is the primary defense; prefer it absolutely.
3. **Backstop** (defense in depth): the read fleet subscribes to a **truncation/rollback
   signal** carrying a `truncation-point`. On receipt it purges all resolve/acl cache entries
   with `landed-seq ≥ truncation-point` and lowers `applied-seq` to `truncation-point − 1`.
   With rule 1 this should be unreachable for cached seqs; it exists only to bound the blast
   radius of an implementation bug that cached above the watermark.

Consequence: two clients reading `as-of: 101` against different nodes can never see H vs H′
for the same basis — the only seq-101 either node can serve is the committed one.

## A.6 Bounds and tunables

| Symbol | Meaning | Default | Trade |
|---|---|---|---|
| `T_ryw` | max block before redirect/fail | 200 ms | larger = more availability, more latency tail |
| replica-lag budget | target `tip − applied-seq` | ≤ 2 entries | enforced by pull frequency; over-budget → redirect rate ↑ |
| serve-token TTL | B.6 | 30 s | smaller = tighter revocation, more re-mints |
| private-cache TTL | B.8 | 60 s | the bounded revocation window for private content |

---

# PART B — SECURITY (I9)

## B.6 Serve tokens (keystone §5.3) — closes S1

### B.6.1 The invariant Ptacek demanded, stated normatively

> **No byte of `/cas/<hash>` is ever reachable except as the output of a successful, fresh,
> per-principal ACL check for the specific principal making the request, at the current
> acl-version.** (I9.) The hash alone NEVER authorizes.

### B.6.2 Token shape and the mint/verify flow

```
serve-token := base64url( msg || tag )
  msg := (hash, principal, acl-version, expiry, nonce)
  tag := HMAC-SHA256_k( canonical-encode(msg) )     ; k = serve-signing key, rotated
```

- **Minted ONLY in an authorized resolve step.** The same `access_by_lua` that (a)
  canonicalizes the path (B.6.4), (b) resolves `(commit, canonical-path) → hash` at the
  enforced basis (A.1), and (c) evaluates the Datalog ACL ALLOW for *this* principal at
  `applied-acl-version`, then (d) mints the token. No other code path may mint. A deny path
  mints nothing and fails closed.
- **Single-use.** `nonce` is recorded in a short-TTL `shared_dict` (`seen-nonces`) at first
  use; replay (same nonce again) is rejected. TTL = token TTL + skew; eviction is safe because
  expired tokens already fail the expiry check.
- **Fresh.** `expiry := now() + serve-token-TTL` (B.5 default 30 s). The internal location
  rejects expired tokens.

```
;; MINT (resolve tier, after ACL ALLOW at current acl-version):
function mint-serve-token(hash, principal, acl-version):
    msg = encode(hash, principal, acl-version, now()+TTL, random-nonce-128())
    return b64url(msg .. hmac_sha256(SERVE_KEY, msg))

;; emit the internal redirect carrying the token (NOT a bare path):
ngx.header["X-Accel-Redirect"] = "/cas/" .. hash
ngx.req.set_header("X-Mvfs-Serve-Token", token)   ; consumed internally, never to client

;; VERIFY (internal /cas location, access_by_lua, fail-closed):
function verify-serve-token(token, hash):
    msg, tag = split(b64url-decode(token))
    if not constant-time-eq(tag, hmac_sha256(SERVE_KEY, msg)): deny(403)  ; forged/tampered
    (t_hash, t_princ, t_aclv, t_exp, t_nonce) = decode(msg)
    if t_hash   != hash:                      deny(403)  ; token not for THIS hash
    if now()    >  t_exp:                      deny(403)  ; stale
    if t_aclv   <  current-required-acl(hash): deny(403)  ; minted under old policy
    if seen-nonce?(t_nonce):                   deny(403)  ; replay
    record-nonce(t_nonce, ttl=TTL+skew)
    allow → sendfile
```

### B.6.3 The nginx internal-location config sketch (mandatory `internal;`)

```nginx
# Front edge: strip every inbound smuggling vector at the door.
# (applies on the public server{} AND any front proxy/CDN ahead of it)
proxy_set_header  X-Accel-Redirect      "";
proxy_set_header  X-Accel-Limit-Rate    "";
proxy_set_header  X-Accel-Buffering      "";
proxy_set_header  X-Accel-Charset        "";
proxy_set_header  X-Sendfile             "";
proxy_set_header  X-Mvfs-Serve-Token     "";   # clients may NEVER supply this
# Reject any client request whose URI normalizes into the internal prefix:
location ^~ /cas/ {
    # Public clients hitting /cas/ directly get 404 — see internal block below.
    return 404;
}

# The byte path. internal; is the single most load-bearing line in the system.
location = /cas/serve {                 # reached ONLY via X-Accel-Redirect
    internal;                           # MANDATORY. No external request can reach this.
    access_by_lua_block { verify_serve_token() }   # fail-closed token check (B.6.2)
    alias /var/mvfs/cas/;               # resolved object path
    sendfile on;                        # zero-copy
    add_header Cache-Control "public, immutable, max-age=31536000";  # blobs only
}
```

The redirect target is `/cas/serve` (an internal-only location), not a client-reachable
URL. A **build-time config test MUST fail the build** if the `internal;` directive is absent
from the serve location (S1 mitigation 1: asserted in CI, not assumed).

### B.6.4 The bypasses this kills (S1 a–d)

| Bypass | How it works | Why it now fails |
|---|---|---|
| **(a) Direct `/cas/` access** | `GET /cas/<hash>` if `internal;` missing → blob with no ACL | `internal;` (CI-enforced) makes the serve location unreachable externally; the public `/cas/` location returns 404; even if reached, `verify-serve-token` denies with no token. |
| **(b) Reflected/smuggled `X-Accel-Redirect`** | client gets `X-Accel-Redirect` onto a response, or a request header is passed through | Front + origin **strip** all `X-Accel-*` and `X-Mvfs-Serve-Token` inbound; Lua never copies client data into that header; token still required. |
| **(c) HTTP request smuggling** (CL.TE/TE.CL, H2 downgrade) | smuggled `GET /cas/...` looks internal-origin | Serve requires a **fresh valid token**, not mere internal-origin; a smuggled request carries none → 403. (Plus: terminate H2 carefully, run a desync test suite.) |
| **(d) Path normalization split** | authorize `src/app/` but resolve `src/app/../secrets/key` | **Canonicalize once**, authorize the canonical path, resolve the hash from the *same* canonical string; reject `..`, `.`, `//`, trailing `/`, `%2e%2e`, Unicode equivalents, NUL, absolute paths. Token binds `hash`, so resolve/serve cannot diverge. |

The token converts "hash = capability" into "hash + fresh authz-bound token = capability,"
which is the only safe form. Reaching `/cas/` by *any* means without a valid fresh token
fails closed.

## B.7 Caching-vs-per-principal-authz tension — closes S2, the central problem

The conflict, stated cleanly: a cache exists to answer **without consulting the authority**;
the authority is the per-principal ACL at resolve; therefore **every shared-cache hit on a
hash-only key is, by construction, a response that skipped authorization**. For public
content that is the whole value of a CDN; for per-principal-private content it is a breach.
You cannot have all three of {shared cache keyed on hash, per-principal ACL, cache hits that
skip origin}. Resolution = classify content and apply different policies:

**Public/private tier split (do this).**

- **Public tier:** truly public blobs (open-source deps, public docs) — *no per-principal
  ACL*, nothing to protect. Edge-cacheable aggressively, `immutable`, hash-keyed, CDN-OK.
- **Private tier:** everything ACL'd. **NEVER** cached at a shared edge under a hash-only
  key.

**Per-principal cache partitioning (do this for shared_dict + disk).** The cache entry is
*physically* unreachable by a principal who didn't authorize it:

```
private cache-key := (tenant, principal-or-authz-class, hash)   ; not (hash) alone
```

This collapses S2 (cross-principal hit), S4 (timing/existence oracle across principals — a
principal can only probe its own partition), and most of S5 (revocation) at once. Cost: less
cross-principal dedup, more memory; accepted for private content.

**Short-TTL signed URLs for private content (do this for any edge caching of private).** If
private bytes are cached at an edge at all, access REQUIRES the serve token (B.6) whose
expiry bounds exposure; the cache key includes the authz-bound token, so a hit serves only a
request carrying a valid fresh token for that principal. Revocation = stop minting; window =
TTL.

| Content | Edge-cacheable? | Key | TTL |
|---|---|---|---|
| Public blob | yes, CDN, forever | `("blob", hash)` | `immutable` |
| Private blob | not on hash-only key; only via signed-URL/token | `(tenant, principal, hash)` + token | ≤ serve-token-TTL |
| Resolve map | no (in-proc/shared_dict only) | `("resolve", tenant, seq, path)` | versioned by seq |
| ACL decision | no (per-principal partition) | `("acl", tenant, principal, path, acl-version)` | versioned by acl-version |

What you MUST NOT do (the §6 breach): cache private, per-principal-ACL'd blobs at a shared
edge under a hash-only key with `immutable`.

## B.8 Revocation under content-addressing + caches — closes S5

The fired-employee problem: authorization is **mutable** (you revoke a grant) layered over
**immutable** content. You cannot revoke an `immutable` hash-keyed edge object by a policy
change, because the policy lives at the origin and the edge was told never to ask. Mechanisms,
each bounding a window:

1. **acl-version bump propagation.** A revoke is a policy land → new `acl-version`. The read
   tier applies it up to `committed-watermark` (A.5); A.1.2 forbids serving an ALLOW at an
   older `applied-acl-version`. Propagation lag is bounded by the replica-lag budget (A.6).
2. **Short private-cache TTL** (`private-cache-TTL`, default 60 s). Private ACL-decision and
   private-blob cache entries expire within this window regardless of propagation.
3. **Token expiry** (`serve-token-TTL`, default 30 s). No new bytes flow after revocation +
   token TTL, because new resolves deny (no mint) and outstanding tokens expire.
4. **Never `immutable` on private content** (B.7): private bytes are reachable only via fresh
   tokens, so there is no un-purgeable forever-edge copy to chase.

**Bounded staleness window for a revocation to take effect:**

```
revocation-window ≤ max( replica-lag(acl-version propagation),
                         private-cache-TTL,
                         serve-token-TTL )
              ≈    max( ~lag, 60 s, 30 s )  ≈ 60 s with defaults.
```

After this window, no node serves a pre-revoke allow and no token mints for the revoked
principal. Public content is, by definition, not subject to revocation (it was never
ACL-gated). Operators get an explicit **revocation SLA** = `revocation-window`, and a
runbook: revocation is *time-bounded by config*, not "whenever the CDN feels like it,"
because private content is never `immutable`-edge-cached.

## B.9 Multi-tenant isolation & cache-key hygiene — closes S3, S7, F7

A cache key that is not a **total, injective function of every decision input** can serve one
input's result for another's request (poisoning / cross-tenant leak). Requirements:

1. **Tenant in every Class-2 key** (resolve, acl) and in the private-blob key. Two tenants
   with overlapping path namespaces (`/src/...`) MUST NOT collide.
2. **Injective encoding — no naive concatenation.** Building a key by
   `principal .. ":" .. path .. ":" .. ver` collides when a component contains the delimiter
   (principal `a` + path `b:c` ≡ principal `a:b` + path `c`), letting a principal forge
   another's cached ALLOW. Use **length-prefixed** fields or a **hashed tuple**; treat every
   component as untrusted bytes:

   ```
   key := sha256( len(tenant)||tenant || len(principal)||principal
                 || len(canon-path)||canon-path || u64(acl-version) )
   ```

3. **Resolve values are content-verified on serve.** The hash is self-verifying; re-checking
   it on serve is cheap insurance against a poisoned resolve entry redirecting to an
   attacker-chosen hash.
4. **Partition dicts per trust domain**; size/rate-limit per principal so a noisy/malicious
   tenant cannot LRU-churn another tenant's authz cache into the slow Datalog cold path
   (CPU-amplification DoS).
5. **Fail closed everywhere** (S7): unknown `acl-version`, unreachable land tier, generated
   matcher fails to load, `shared_dict` full → **deny**. The "behind is never wrong" framing
   is correct for *content* and catastrophic for *authz*; authz defaults to deny.
6. **Range/conditional requests** (S6): validate the serve token on **every** sub-request
   including range continuations; do not let `ETag = hash` become an unauthenticated existence
   oracle (per-principal partitioning + token-on-every-subrequest collapses this).

## B.10 Threat model table

| # | Asset | Threat | Mitigation (spec ref) |
|---|---|---|---|
| T1 | Any blob | Direct `/cas/<hash>` read, no ACL (missing `internal;`) | `internal;` on serve location, CI-asserted; public `/cas/` → 404; token required (B.6.3) |
| T2 | Any blob | Reflected/smuggled `X-Accel-Redirect` | Strip inbound `X-Accel-*` + `X-Mvfs-Serve-Token`; never copy client data into the header; token still required (B.6.4b) |
| T3 | Any blob | HTTP request smuggling → looks internal | Fresh valid token required, not internal-origin trust; H2 terminated carefully + desync test suite (B.6.4c) |
| T4 | Secret blob | Path-normalization split: authorize one path, resolve another's hash | Canonicalize once → authorize → resolve same canonical string; token binds `hash` (B.6.4d) |
| T5 | Private blob | Cross-principal CDN/edge hit on hash-only key | Public/private tier split; private never edge-cached on hash key; signed-URL/token required (B.7) |
| T6 | Private blob / decision | Timing/existence oracle across principals | Per-principal cache partitioning; deny before cache probe; constant-time-ish deny (B.7, S4) |
| T7 | ACL decision | Stale-allow / pre-revoke ALLOW from behind node | `applied-acl-version ≥ req.acl` precondition (A.1.2); fail-closed; revocation window (B.8) |
| T8 | ACL decision cache | Key forgery via delimiter collision (poisoning) | Length-prefixed / hashed-tuple injective key; untrusted-bytes treatment (B.9.2) |
| T9 | Resolve cache | Poison → redirect to attacker hash | Canonical-input key + content-verify hash on serve (B.9.3) |
| T10 | Cross-tenant data | Overlapping path namespace collision | Tenant in every Class-2 / private key (B.9.1) |
| T11 | Authz cache (all) | LRU-churn DoS → forces slow Datalog cold path | Per-trust-domain dict partition; per-principal rate/size limit (B.9.4) |
| T12 | Fired principal's bytes | Un-purgeable `immutable` edge copy | Private content never `immutable`-edge-cached; token TTL bounds exposure (B.7, B.8) |
| T13 | Serve token | Replay of a captured token | Single-use nonce in `seen-nonces` dict; expiry (B.6.2) |
| T14 | Whole authz perimeter | Over-permissive generated matcher pushed fleet-wide | Staged/canary policy rollout; kill-switch fails closed to slow Datalog oracle; generated-matcher diff gated blocking in CI (S7) |
| T15 | Byte path | Range/conditional sub-request bypass; ETag existence oracle | Token validated on every sub-request incl. range; ETag not an unauthenticated oracle (B.9.6, S6) |

---

## Cross-reference summary

- **I2** (total land order): A.5 — read tier applies committed prefix in landed-log order.
- **I6** (ACL soundness / no stale-allow): A.1.2 + A.4 (ACL key + `applied-acl ≥ req.acl`
  precondition) + B.8 (revocation window).
- **I8** (RYW + monotonic reads): A.1 (enforced basis) + A.2 (RYW = basis pinned to ack) +
  A.3 (monotonic = client hwm); both are consequences of A.1.2 enforcement.
- **I9** (auth on every byte path): B.6 (serve tokens, `internal;`, fail-closed) + B.7
  (tier split / partitioning) + B.9 (key hygiene, fail-closed).

## Conformance gate (do not ship without)

1. A node compares `applied-basis` to request basis on every basis-carrying read and
   block→redirect→fails-closed; never serves `applied-basis < req.basis` (A.1, F1/F5).
2. Resolve cache keyed by immutable basis; ACL cache keyed by total injective function incl.
   `acl-version` + tenant; "behind" = cache miss → A.1 path (A.4/B.9, F2).
3. Only `committed-watermark` seqs are cached/served; truncation backstop wired (A.5, F4).
4. `internal;` on the serve location, CI-asserted; serve token verified fail-closed; inbound
   `X-Accel-*` stripped; path canonicalized-then-authorized-then-resolved (B.6, S1).
5. Public/private split + per-principal partitioning; no private hash-only edge cache; private
   content never `immutable` (B.7, S2).
6. Revocation window bounded and documented as the SLA; authz fails closed everywhere
   (B.8/B.9, S5/S7).
