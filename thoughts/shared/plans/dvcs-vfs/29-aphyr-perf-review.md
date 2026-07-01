---
date: 2026-06-25
reviewer: "Kyle Kingsbury (persona)"
status: review
topic: "Jepsen-style consistency review of the hot-path performance architecture: a stateless, scale-out OpenResty read tier in front of the fenced single land-leader, serving cached/immutable content with an `as-of` (landed-seq) basis header"
target: thoughts/shared/plans/dvcs-vfs/26-hotpath-perf-architecture.md
inputs:
  - thoughts/shared/plans/dvcs-vfs/26-hotpath-perf-architecture.md
  - thoughts/shared/plans/dvcs-vfs/08-aphyr-review-v2.md
  - thoughts/shared/plans/dvcs-vfs/17-aphyr-shen-backends.md
  - thoughts/shared/plans/dvcs-vfs/24-hickey-go-vs-ocaml.md
tags: [review, jepsen, openresty, cache, read-tier, as-of, basis, read-your-writes, monotonic-reads, acl-toctou, shared_dict, fencing, immutable, cdn]
---

# Jepsen-style review of the hot-path perf architecture (26): the scale-out read tier

## Verdict

The *foundation* is right, and I want to say that before I take it apart. Content-addressed,
immutable bytes are the one thing in this whole document set that is correct-by-construction:
a hash names one byte string forever, so the blob cache — `shared_dict`, on-disk, and `Cache-Control:
immutable` at the CDN edge — needs no invalidation and cannot serve you a wrong *blob*. And an
`as-of` basis header is exactly the right *shape*: it is Datomic's `(d/as-of db t)` / `(d/sync conn
t)`, a request that says "serve me a value at a basis at least as new as N." I have praised this
mechanism (`24`), and I praise it again. If the only thing the read tier ever did was serve immutable
blobs by hash, this review would be one paragraph long: ship it.

**But the document conflates "immutable blob" with "the read tier," and that conflation is
load-bearing and false.** The read tier does not just serve blobs by hash. It serves two things that
are *not* immutable and *not* content-addressed: (1) the **resolve mapping `(commit,path) → blob-hash`**,
which is versioned and changes on every land; and (2) the **ACL decision `(principal, path) →
allow/deny`**, which is versioned and changes on every policy land. The doc caches *both* of these in
`shared_dict` (§3.1, §6) and then makes the sweeping claim (§5) that "because content is immutable, a
slightly-behind read tier is simply serving an earlier `as-of` — never *wrong*." That sentence is the
2026 reincarnation of the "linearizable because one leader" sentence I struck in `08 Finding 1`. It is
**true for blobs, false for the resolve and ACL caches, and false for read-your-writes in general.**

The doc itself knows it has not done the work. §9 open-question 4 reads: *"Does the `as-of` basis
header + immutable content genuinely give read-your-writes across a scale-out, partially-behind read
tier — or are there windows where a client reads stale resolve-cache after its own land? (Aphyr's
lane.)"* That is the author admitting, in writing, that the central consistency claim of §5 is
**unverified and the enforcement unspecified.** §5 *asserts* the guarantee; §9.4 *defers* it to me.
You cannot do both. A guarantee you defer is not a guarantee; it is a hope. **The `as-of` mechanism is
necessary and good; the document specifies the *cookie* but not the *enforcement*, and an unenforced
basis header is a comment, not a consistency mechanism.**

So: the perf architecture does **not**, as written, preserve read-your-writes or monotonic reads
across the scale-out read tier. It can be *made* to — the `as-of` basis is the right tool — but every
enforcement obligation is missing. This carries **2 Criticals** (RYW silently violated by a behind
node serving a stale basis as if current; the resolve/ACL caches keyed and invalidated incorrectly so
a pre-land mapping or pre-revoke allow can be served) and **3 Majors** (non-monotonic reads under
scale-out with no stickiness; the read tier serving from an uncommitted/losing-fork log tail; the
`as-of` basis underspecified as to what the read carries and what the node enforces).

**Counts: 2 Critical, 3 Major, 2 Minor.**

---

## Findings

### F1. [CRITICAL] Read-your-writes is silently violated: a client that lands at seq N and reads with `as-of: N` against a replicated-behind node (applied-seq < N) gets an *older* snapshot served as if it satisfied the request. §5's "a behind read tier is just serving an earlier `as-of`, never wrong" is true for *some-consistent-snapshot*, false for *read-your-writes*.

**Claim attacked.** §5: *"a read carries an **`as-of` basis header** (the landed-seq cookie); the tier
serves a consistent snapshot at that seq from immutable content"* and *"because content is immutable, a
slightly-behind read tier is simply serving an earlier `as-of` — never *wrong*."*

Here is the distributed-systems distinction the sentence erases. There are two different read
contracts, and the doc claims one while specifying the other:

- **Some-consistent-snapshot** (a.k.a. consistent-prefix / "give me *a* coherent view"): a behind node
  serving its own applied-seq M < N is fine — it is *a* real, internally-consistent snapshot of trunk.
  For this contract, "a behind tier serves an earlier `as-of`, never wrong" is **true**.
- **Read-your-writes** (the client lands N, then must observe ≥ N): a behind node serving M < N is
  **wrong by definition** — the client cannot see its own write. The basis header `as-of: N` is a
  *lower bound the node must satisfy or refuse*, not a label the node is free to ignore.

§5 delivers the first and *calls* it the second. The whole point of the cookie (it is the LiteFS
`(TXID, checksum)` position cookie, it is `(d/sync conn t)`) is that the node must **block until
applied-seq ≥ N, or redirect, or fail** — never silently serve M < N. The doc never says the node does
any of these. It says the tier "serves a consistent snapshot at that seq," which a behind node
*cannot do for seq N* — it can only serve seq M and hope the client doesn't notice it's not N.

**Concrete history (RYW violated, silently):**

1. Land tier: client C lands commit H. Leader assigns **seq 101**, fsyncs, re-validates fence/lease,
   acks C `{landed: 101}` (per `08`'s fixed land path). C's basis cookie is now 101.
2. The read fleet has nodes A (applied-seq 101, caught up) and B (applied-seq 100, replicated-behind —
   it has not yet pulled landed-log entry 101; its `shared_dict` resolve cache still maps
   `(trunk, /src/foo)` to H's *predecessor* blob-hash).
3. C's next request — `GET /blob-by-path?commit=trunk&path=/src/foo` with `as-of: 101` — is
   load-balanced to **B** (stateless fleet, no stickiness; §5 "stateless, scale-out").
4. B's `access_by_lua` resolves `(trunk, /src/foo)` from its `shared_dict` → it returns the
   **pre-land** blob-hash (applied-seq 100's mapping). B has no idea this is stale: the entry is a
   valid seq-100 mapping, the blob it points to is immutable and verifies its hash perfectly. B
   `X-Accel-Redirect`s to `/cas/<old-hash>`, nginx `sendfile`s the **old bytes**, 200 OK.
5. C reads `/src/foo` and sees the **content from before its own land**. Read-your-writes violated. No
   error, no redirect, no signal. C's `as-of: 101` was carried on the wire and **ignored by B**, which
   is operating at 100.

This is precisely the open question the doc poses to itself in §9.4 — *"windows where a client reads
stale resolve-cache after its own land"* — and the answer is **yes, the window is wide open**, because
nothing in §5 makes B compare its applied-seq to the header and refuse. The immutability of the blob is
a red herring: the blob is consistent, but it is the *wrong blob for basis 101*, because the
**resolve mapping is the thing that is behind**, and the resolve mapping is not immutable (F2).

**Why "never wrong" is the trap.** "Never wrong" is true for the *bytes-vs-hash* relation and false for
the *basis-vs-request* relation. The doc proves the first and asserts the second. A behind read tier is
"never wrong" *only* for clients who asked for some-snapshot; for any client carrying a basis ≥ its own
land, a behind node that ignores the basis is *exactly* wrong.

**Required spec:**
- State the read contract per request. A request carrying `as-of: N` is a **read-your-writes /
  bounded read**: the serving node **MUST** satisfy applied-seq ≥ N or it **MUST NOT** answer from
  local state. Spell out the three legal behaviors and pick the order: (a) **block** until
  applied-seq ≥ N up to `T_ryw`; (b) on timeout, **redirect** to a node (or the leader) known to be
  ≥ N; (c) if neither is reachable, **fail explicitly** with "cannot satisfy `as-of: N` (node at M <
  N)" — the same availability-sacrificed-for-RYW trade I demanded in `08 Finding 4`. A read with **no**
  `as-of` header is a some-snapshot read and may be served from any applied-seq (and *that* is where
  "behind is never wrong" legitimately applies — say so explicitly so the two contracts are not
  conflated again).
- The node must **know its own applied-seq** and **compare it to the header on every request**. This
  is the single missing mechanism. Without it the basis header is decorative.
- State how a behind node learns it is behind enough to redirect (it needs the leader's current tip,
  or at least to trust the client's `as-of` as the bound — the latter is sufficient and cheaper:
  the node only needs `local applied-seq ≥ header`, no global knowledge required).

---

### F2. [CRITICAL] The resolve cache and the ACL-decision cache are NOT immutable across lands/policy changes, but the doc treats them like blobs. A stale `shared_dict` entry serves a pre-land `(commit,path)→hash` mapping or a pre-revoke ACL *allow*. This is the ACL-TOCTOU/stale-allow concern from `08`, relocated to the cache layer — and the keying the doc gives is insufficient to prevent it.

**Claim attacked.** §3.1: *"`lua_shared_dict` (cross-worker, in-process) for trees/manifests + resolved
attrs + ACL decisions"* under the heading *"Content addressing ⇒ zero-invalidation caching ... every
cache layer is correct-by-construction with no invalidation logic."* And §6: *"`shared_dict` decision
cache keyed by `(principal, path-prefix, acl-version)`; invalidated only when policy lands (rare) by
bumping `acl-version`."*

The §3.1 framing is **category-confused and dangerous**: it lists "trees/manifests + resolved attrs +
ACL decisions" under the *zero-invalidation* property that belongs **only to content-addressed blobs**.
Trees and manifests addressed *by hash* are immutable (fine). But "**resolved attrs**" — the output of
`resolve(commit, path) → hash` — and "**ACL decisions**" are **functions of a versioned input**
(trunk state at a seq; policy at an acl-version). They are *not* named by their content; they are named
by `(commit, path)` and `(principal, path)`, whose *values change*. Caching a function-of-versioned-state
under a key that omits the version is the classic stale-read bug.

§6 *partially* fixes the ACL side — it keys on `acl-version` and bumps it on policy land. Good instinct.
But there are three holes, two of them sharp:

**(a) The resolve cache has no version in its key at all.** §3.1 says resolve results are cached; §6
only versions the *ACL* cache. If the resolve `shared_dict` is keyed `(commit, path)` with `commit =
"trunk"` (the common VFS access pattern — clients read "trunk:/path", not "by explicit commit hash"),
then **the key is mutable**: "trunk" means seq 100 on Monday and seq 101 after a land, but the key is
the literal string "trunk" both times. A node that cached `(trunk, /src/foo) → old-hash` at applied-seq
100 will serve `old-hash` *forever* (or until LRU eviction) even after it applies seq 101 — because the
key did not change, so nothing invalidates it. **This is F1's stale read made permanent by a missing
cache-key dimension.** The resolve cache MUST be keyed by the *resolved basis*, i.e.
`(landed-seq, path) → hash` (or `(immutable-commit-hash, path) → hash`, never `(mutable-ref-name,
path)`). Keyed that way, the cache *is* immutable-by-construction (seq N's mapping for a path never
changes), and a behind node simply has *no entry* for `(101, /src/foo)` and must fault it in or refuse
— which is the correct behavior, and which composes with F1's basis check.

**(b) ACL revoke is a *deny* that must beat a cached *allow*, and an `acl-version` bump on a behind
node is not enough.** Consider the concrete stale-allow:

1. acl-version = 7. Principal P has read on `/secret`. Node B caches decision
   `(P, /secret, v7) → ALLOW`.
2. A policy land revokes P's access to `/secret`. Leader lands it at **acl-version 8** (and
   landed-seq, say, 200).
3. Node B is **replicated-behind**: it has not yet pulled the policy land. B's view of acl-version is
   still **7**. A request from P for `/secret` arrives carrying — what? If the client's `as-of` does
   not *include the acl-version*, B computes its cache key as `(P, /secret, v7)` and hits the cached
   **ALLOW**. P reads `/secret` **after being revoked**. This is `08 Finding 3`/the ACL-TOCTOU
   stale-allow, now at the cache layer, and §6's keying does **not** stop it: the key is correct, but
   B is *at the wrong acl-version* and doesn't know it, so it never invalidates v7 and never consults
   v8.

   The bug is identical in shape to F1: a versioned decision served by a node behind the version, with
   no basis check forcing the node to refuse. §6's "invalidated when policy lands by bumping
   acl-version" assumes the bump *reaches the node* before the request — which is exactly what async
   replication does **not** guarantee. **A revoke is a safety-critical event; serving a pre-revoke
   allow from a behind cache is a security incident, not a staleness inconvenience.**

**(c) The basis must bind the acl-version, and the deny path must fail-closed.** The client's `as-of`
must carry (or the node must derive) the **acl-version corresponding to the landed-seq basis**, so that
a node behind on policy *cannot* answer an authorization at a stale version. And the read contract for
authz must be **fail-closed under uncertainty**: a node that cannot confirm it is at acl-version ≥ the
required version must **deny or redirect**, never serve a cached allow from an older version.

**Required spec:**
- **Key the resolve cache by an immutable basis**, never by a mutable ref. Either `(landed-seq, path)`
  or `(commit-hash, path)`. A node behind seq N then has *no entry* for basis N and is forced down the
  fault-in/refuse path (composes with F1). Strike "resolved attrs" from the §3.1 "zero-invalidation"
  list — only hash-addressed objects belong there.
- **Bind the ACL decision to a monotone policy basis and check it against the request basis.** Key
  remains `(principal, path-prefix, acl-version)` *but* the node MUST verify **its own applied
  acl-version ≥ the request's required acl-version** before serving any decision (and certainly before
  serving an ALLOW). A behind node MUST fail-closed (deny/redirect), never serve a stale allow.
- **State the basis is a pair (or composite):** `(landed-seq, acl-version)` — or fold acl-version into
  the landed-log so a single monotone seq covers both. The read MUST carry, and the node MUST enforce,
  *both* dimensions, or a policy-behind node serves pre-revoke allows even when its data is current.
- **Make the internal `/cas/<hash>` location unreachable except via an authorized `X-Accel-Redirect`**
  (this is also Ptacek's lane, but it is the consistency backstop too: if the only way to bytes is
  through the resolve+authz decision, then fixing the decision cache fixes the byte serve). State that
  direct `/cas/<hash>` access is denied at the nginx config level.

---

### F3. [MAJOR] Monotonic reads are not preserved: a client can read seq N from one fleet node, then read seq < N from a different node, because the fleet is stateless/scale-out with no session-stickiness or monotonic-read mechanism. Scale-out reintroduces non-monotonic reads.

**Claim attacked.** §5: *"a *stateless, scale-out* OpenResty fleet ... Add nodes for read QPS."* §3.1's
caching, §0/§5 statelessness.

Monotonic reads (a session never goes backward in time) is a *separate* guarantee from RYW, and the
scale-out, stateless design breaks it independently. Even a client that never lands anything can observe
trunk *un-advance*:

**Concrete history (time goes backward):**

1. Client C (read-only, no land) issues read 1, load-balanced to node A (applied-seq 101). C observes
   `/src/foo` at seq 101 — including, say, a file that was *added* at 101.
2. C issues read 2 moments later, load-balanced to node B (applied-seq 100, behind). B serves
   `/src/foo` at seq 100 — the file C just saw is **gone**.
3. C has watched trunk move **backward**, 101 → 100. For a VFS this is brutal: a build that listed a
   file, then `read()`s it and gets ENOENT; a tool that saw a manifest entry, then can't resolve it.

Without `as-of`, the fleet provides at best *some-snapshot* per request and **no** cross-request
ordering. The doc offers no session affinity, no client-carried high-water-mark, no monotonic-read
cookie. "Stateless, scale-out" is precisely the property that, unaddressed, *guarantees* non-monotonic
reads under replica lag.

The fix is cheap and the doc already half-has it: the `as-of` cookie **is** the monotonic-read
mechanism if the *client* treats it as a high-water-mark and **every** read carries `as-of:
max(seqs-seen-so-far)`. Then F1's basis enforcement (node must satisfy applied-seq ≥ `as-of`)
*automatically* delivers monotonic reads: a node behind the client's high-water-mark refuses/redirects
rather than serving an earlier seq. But this requires (a) the client to maintain and send the
high-water-mark on *all* reads (not just post-land), and (b) F1's enforcement to exist. Neither is
specified.

**Required spec:**
- State the monotonic-read mechanism explicitly: **the client maintains a high-water-mark = max
  landed-seq observed across all responses, and sends it as `as-of` on every subsequent read**;
  responses **must** return the serving node's applied-seq so the client can advance the mark. (This
  is the LiteFS position cookie used as a *session* invariant, not just a post-land one.)
- With F1's enforcement, monotonic reads fall out for free. *Without* a client high-water-mark,
  alternatively specify **session-sticky routing** (consistent-hash the client to a node), but note
  that stickiness alone does **not** survive a node falling behind or being replaced, and the cookie
  approach is strictly stronger. Pick one and write it.
- Default with no header: declare reads non-monotonic and some-snapshot only. Do not let the absence
  of a header silently masquerade as a consistent session.

---

### F4. [MAJOR] The read tier can serve content from an *uncommitted* or *losing-fork* land. The doc never says the read tier reads only *committed* landed-log, nor how it learns a tail was rolled back after a leader change (the detect-then-discard from `08`/`17`). A pulled-then-truncated entry leaves the fleet serving a fork that trunk no longer contains.

**Claim attacked.** §5: *"The read tier pulls new landed-log entries (or is pushed) and updates its
`shared_dict` resolve cache."* §3 / §4: the read tier as the source-of-truth content service.

The land tier's safety story (`08`, `17`) is: a single leased leader, a fencing token CAS'd on the
durable append, and — when the fence fails (GC pause + clock skew + lease handoff) — a checksum-chain
**detect-then-discard**: the diverged fork is truncated and the stale node resyncs from the current
primary, **losing its un-replicated tail**. That recovery model has a consequence the perf doc never
confronts: **the read tier pulls landed-log entries, and a pulled entry can later be truncated.**

**Concrete history (read tier serves a discarded fork):**

1. Old leader L1 (GC-paused past its lease) resumes and appends landed-log entry seq 101 = H, acks (or
   nearly acks). Per `08 Finding 1`, in the un-fenced window this entry exists in L1's log.
2. The read fleet — "pulls new landed-log entries ... or is pushed" — **pulls L1's entry 101 (H)** and
   updates its `shared_dict` resolve cache: `(101, /path) → H's hash`.
3. The cluster resolves the split: N2 is the real primary, its seq 101 = H' (a *different* commit).
   L1's fork is **detected and discarded** — L1 truncates 101=H and resyncs 101=H'.
4. **The read fleet still has `(101, /path) → H` cached.** It is now serving a commit that **trunk no
   longer contains** — a losing-fork phantom — to any client that reads at `as-of: 101`. Worse, two
   clients reading `as-of: 101` against different fleet nodes can see H vs H' (split content for the
   same basis), which is *worse* than stale: it is **two different values for the same linearization
   point**.

The doc has no notion of "the read tier reads only **committed** log," no quorum/durability threshold
the read tier waits for before caching, and no **truncation/rollback signal** that tells the fleet to
*invalidate* a cached entry that got discarded. Because the resolve cache is currently keyed by mutable
state (F2) and is treated as append-only/never-invalidated (§3 "no invalidation logic"), there is in
fact **no mechanism in the design to un-cache a rolled-back entry at all.** That is the immutability
assumption applied to a thing (the seq→commit binding under a fork) that is *not* immutable until the
land tier says it is committed.

**Required spec:**
- **Define a commit watermark.** The read tier MUST only pull/cache landed-log entries that are
  **committed** = durable to the configured durability width AND past the fence's point-of-no-return
  (i.e., entries that cannot be truncated by a leader change). State that the read tier's cacheable
  basis is `min(committed-seq)`, never the leader's bleeding-edge tip. This makes the seq→commit
  binding genuinely immutable *for cached seqs* — which is the property §3 *assumed* but never
  *secured*.
- **Specify the rollback/truncation path** for the (rare, but possible per the `08`/`17` model) case
  where the read tier cached an entry that later gets discarded: an explicit invalidation (the fleet
  subscribes to truncation events and purges `shared_dict` entries ≥ truncation point) — *or*, far
  cleaner, **guarantee by the commit watermark that uncommitted entries are never cached in the first
  place**, so truncation can never reach a cached seq. Strongly prefer the latter; state it.
- State that the read tier learns the watermark from the **landed-log itself** (the committed prefix),
  not from any single leader's claim, so a stale leader's appends are never above the watermark the
  fleet trusts.

---

### F5. [MAJOR] The `as-of` cookie/basis is the right Datomic-style mechanism, but the doc specifies the *cookie* and not the *enforcement contract*: it never states what the read must carry, what the node must check, or what the node does when it can't satisfy the basis. An unenforced basis header is decorative.

**Claim attacked.** §5: *"a read carries an **`as-of` basis header** (the landed-seq cookie); the tier
serves a consistent snapshot at that seq."* §9.4 defers the verification of this to "Aphyr's lane."

This is the meta-finding that F1–F4 are instances of. The `as-of` basis — `(d/sync conn t)` / the
LiteFS position cookie — is genuinely the correct primitive for cheap consistent reads, and I have
said so (`24`, and the panel agreed it is "the right shape"). But a basis is a **contract between
client and node**, and a contract has *two* sides:

- **What the client must carry.** The doc says "the landed-seq cookie." Insufficient on three counts:
  (1) it must be the client's **high-water-mark** seq, not just its last land (F3); (2) it must bind
  the **acl-version** (or a composite seq covering policy), or policy-behind nodes serve stale allows
  (F2); (3) it must be carried on **every** read that needs recency, including pure reads (F3), not
  only post-land reads.
- **What the node must enforce.** The doc says nothing. It must: read its **own applied-seq**, compare
  it to the header, and **block / redirect / fail-closed** if behind (F1); key its resolve cache by an
  **immutable basis** so "behind" means "no entry" rather than "stale entry" (F2); refuse to serve
  authz at a stale acl-version (F2); and only ever cache **committed** seqs (F4).

The document does **none** of the node-side enforcement and only half of the client-side carriage. It
specifies a header and an intention ("serve a consistent snapshot at that seq") and leaves the
machinery that would make the intention true entirely to the reader — then, in §9.4, asks *me* whether
the intention holds. **The honest reading of the document as written is: the basis header is carried
and ignored.** That is not a linearizable or RYW read tier; it is a some-snapshot read tier with a
suggestive HTTP header.

**Is the `as-of` basis *sufficient* for linearizable/RYW reads?** Yes — *if and only if* enforced. The
basis-point model is sound: "serve me a value at basis ≥ N" + "node refuses if applied < N" gives you
RYW (N = your land) and monotonic reads (N = your high-water-mark) and even linearizable reads (N =
the leader's committed tip, fetched fresh) — all without the read tier coordinating, exactly the
Datomic/Hickey property the doc invokes. The mechanism is not the problem. **The absence of its
enforcement is the entire problem.**

**Required spec:** Promote the `as-of` contract from a sentence to a section. Specify, precisely:
1. The basis the client carries: a monotone composite `(landed-seq, acl-version)` (or single
   landed-seq if policy is folded into the log), maintained as a session high-water-mark.
2. The node's obligation on receiving basis B: serve from local state **only if** `applied-basis ≥ B`;
   else block ≤ `T_ryw`, then redirect, then fail-closed with an explicit error.
3. The response always returns the serving node's `applied-basis`, so the client advances its
   high-water-mark (closing F3).
4. The cacheable basis ceiling = the **committed** watermark (closing F4).
5. The resolve and ACL caches keyed by immutable basis (closing F2).

Until §5 reads like that, §9.4's question answers itself: **no, it does not give RYW.**

---

### F6. [MINOR] §3 "every cache layer is correct-by-construction with no invalidation logic" is true for the blob/CDN layer and false as a blanket statement; the CDN `immutable` directive must never be applied to resolve/ACL responses.

**Claim attacked.** §3.1: *"every cache layer is correct-by-construction with no invalidation logic,"*
including *"CDN edge with `Cache-Control: immutable` — a monorepo's hot files served from the edge,
forever, never revalidated."*

For **blobs addressed by hash**, `Cache-Control: immutable` forever at the edge is correct and
excellent — a hash-named byte string is safe to cache to the heat death of the universe. But the
sentence sits under a heading that *also* covers resolve and ACL results (F2), and the danger is that
an implementer applies `immutable` to a **`/blob-by-path?commit=trunk&path=...`** response. That URL is
**not** content-addressed — `commit=trunk` is mutable — and marking its response `immutable` at a CDN
caches a **pre-land mapping at the edge, forever, across every tenant**, which is F1/F2 escalated to a
shared edge cache you cannot easily purge. A pre-revoke ALLOW cached `immutable` at the edge is a
revoke that *never takes effect for cache lifetime*.

**Required spec:** State the rule sharply: **`Cache-Control: immutable` is permitted ONLY on responses
keyed by content hash** (`/cas/<hash>`, or `?commit=<explicit-hash>&path=`). Any response whose key
contains a **mutable ref** (`trunk`, a branch name) or an **authorization decision** MUST be
`no-store` / `private` / `must-revalidate` and MUST carry the basis so a client/edge cannot reuse it
across a land or a policy change. Two cache classes, two policies; never one blanket "immutable."

---

### F7. [MINOR] Multi-tenant `shared_dict` and the decision cache need tenant isolation in the key, or one tenant's cached allow leaks to another. (Flagged in §9.5 as Ptacek's lane; noting the consistency face.)

**Claim attacked.** §6: decision cache keyed `(principal, path-prefix, acl-version)`; §3.1 a shared
`lua_shared_dict` across workers.

The key includes `principal`, which is correct, so a naive cross-principal leak is avoided. But if the
deploy is multi-tenant and `path-prefix` is not namespaced by tenant, two tenants with overlapping path
namespaces (`/src/...`) can collide on `(principal, /src, v7)` if `principal` is not globally unique
across tenants, or if a future "anonymous"/role principal is shared. This is primarily Ptacek's lane
(`09`/security), but it has a consistency face: a cache key that is not a *total* function of all
inputs that determine the decision will serve one input's result for another's request. Noting it so
the key-completeness obligation from F2 is stated once for *all* decision inputs, not just version.

**Required spec:** The decision cache key must be a total function of **every** input the authorization
depends on: `(tenant, principal, path, acl-version)` — and the resolve key likewise `(tenant?,
landed-seq, path)`. If any decision input is omitted from the key, the cache can serve a wrong
decision. State the completeness requirement explicitly.

---

## What the read tier MUST enforce to keep RYW / monotonic reads under caching

This is the load-bearing section. The `as-of` basis is a good foundation; here is the minimum
enforcement that turns it from a decorative header into an actual guarantee. The read tier must
implement **all** of these — any one missing reopens a Critical above.

1. **Every serving node knows its own applied-basis** — its `(applied-landed-seq, applied-acl-version)`
   — and treats the request's `as-of` as a **lower bound it must satisfy or refuse**. On a request
   carrying basis B:
   - if `applied-basis ≥ B`: serve from local immutable content/cache;
   - else: **block** up to `T_ryw`, then **redirect** to a node/leader known ≥ B, then **fail-closed**
     with an explicit "cannot satisfy `as-of` B" error.
   A node MUST NEVER silently serve `applied-basis < B`. (Closes F1, F3.)

2. **The resolve cache is keyed by an immutable basis** — `(landed-seq, path) → hash` or
   `(commit-hash, path) → hash`, **never** `(mutable-ref, path)`. Then "behind" means "cache miss for
   basis N," which routes into rule 1's fault-in/refuse path, instead of "stale hit." (Closes F2's
   resolve half, and is what makes §3's "no invalidation" *actually* true for the resolve layer.)

3. **Authorization is bound to a monotone policy basis and fails closed.** The decision cache key is a
   **total** function of all decision inputs `(tenant, principal, path, acl-version)`. A node MUST
   verify its **applied acl-version ≥ the request's required acl-version** before serving any decision,
   and MUST **deny or redirect** (never serve a cached ALLOW) when it cannot confirm it is current. A
   revoke is safety-critical: pre-revoke allows from a behind cache are forbidden. (Closes F2's ACL
   half, F7.)

4. **Only committed log is cacheable.** The read tier pulls/caches landed-log entries only up to the
   **committed watermark** (durable to width + past the fence's point-of-no-return), never the leader's
   bleeding tip. This makes the seq→commit binding immutable for every cached seq, so a discarded
   losing-fork tail is never cached and never served. If, despite this, an uncommitted entry is ever
   cached, an explicit truncation-invalidation must purge `shared_dict` entries ≥ the truncation point.
   (Closes F4.)

5. **The client carries a session high-water-mark on every recency-sensitive read** — `as-of =
   max(basis observed so far)` — and every response returns the serving node's applied-basis so the
   client can advance it. With rule 1, this yields monotonic reads for free and RYW for post-land
   reads. (Closes F3, completes F5's client side.)

6. **Two cache classes, two cache policies.** `Cache-Control: immutable` (and forever-CDN) is permitted
   **only** on hash-addressed responses. Any response keyed by a mutable ref or carrying an authz
   decision is `no-store`/`private`/`must-revalidate` and carries the basis. (Closes F6.)

If the document specifies rules 1–6, then — and only then — the §5 claim becomes true, in this exact
restated form:

> *"A read carrying basis B is served only by a node whose applied-basis ≥ B, from a resolve cache
> keyed by immutable basis, with authorization gated on a current policy version, over committed log
> only — so a behind node refuses or redirects rather than silently serving an earlier snapshot.
> Read-your-writes and monotonic reads hold because the basis is a lower bound the node *enforces*, not
> a label it *carries*. A behind read tier is never wrong **for some-snapshot reads (no basis header)**;
> for basis-carrying reads it is either correct or it refuses — never silently stale."*

That sentence is the honest version of §5. The current §5 is the "linearizable because one leader"
sentence wearing a performance hat: a correct-shaped mechanism whose enforcement is asserted, deferred,
and unbuilt. Build the enforcement (rules 1–6) and you have what the doc promises: cheap, immutable-
content reads that are *also* read-your-writes and monotonic. The foundation is genuinely good. Finish
it.

---

## Summary

- **The immutable-blob + `as-of`-basis foundation is correct and I endorse it** — content addressing
  gives zero-invalidation blob caching for free, and a basis-point is exactly Datomic's
  `(d/as-of/sync)`, the right primitive for coordination-free consistent reads.
- **But §5 conflates "immutable blob" with "the read tier."** The resolve mapping and the ACL decision
  are **versioned, not immutable**, and the doc caches them as if they were — so a behind node serves a
  pre-land mapping (F1) or a pre-revoke allow (F2), the scale-out fleet serves non-monotonic reads
  (F3), and a discarded losing-fork tail can be served as live trunk (F4).
- **The `as-of` cookie is specified; its enforcement is not.** The doc carries a basis header and,
  as written, ignores it — then asks me in §9.4 whether RYW holds. It does not, until the node-side
  enforcement (the "what the read tier must enforce" section) is written.
- **All fixes are spec-and-enforce, not redesign** — the basis mechanism is right; it needs teeth.
  Close F1 and F2 (the two Criticals) by giving the basis header enforcement and keying the
  resolve/ACL caches by immutable basis, and the read tier earns the consistency story the land tier
  already (per `08`/`17`) fought to provide.

**Counts: 2 Critical, 3 Major, 2 Minor.**

The single gate before this read tier ships: **F1 + F2** — a node must enforce its applied-basis
against the request basis (refuse/redirect when behind), and the resolve/ACL caches must be keyed by
an immutable basis with authz fail-closed at stale policy versions. Without those two, the scale-out
read tier silently breaks the read-your-writes guarantee the rest of the system was built to keep.
