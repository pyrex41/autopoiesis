---
date: 2026-06-25
researcher: Claude
topic: "Hot-path performance architecture — a provable Shen brain compiled per-path, with an OpenResty/shen-lua read tier serving content zero-copy"
inputs:
  - thoughts/shared/plans/dvcs-vfs/25-final-verdict-go-vs-ocaml.md
  - thoughts/shared/plans/dvcs-vfs/21-synthesis-shen-backends.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
tags: [performance, shen, lua, openresty, luajit, vfs, hot-path, cas, edenfs, datalog, sendfile]
status: draft-for-review
last_updated: 2026-06-25
last_updated_by: Claude
---

# Hot-path performance architecture: provable Shen brain, fastest-host-per-path body

This explores how to make the **VCS / VFS hot path fast** while keeping the **provable Shen
core** the user wants (a Shen program + Datalog, shelling out for the rest; see `25` discussion).
The thesis: speed and provability are not in tension, because **proving happens at build time and
running happens on LuaJIT** — and Shen's defining trait (portability across backends) lets you
**compile one provable source to the best host for each path**.

> Written to be attacked by a perf-weighted panel (OpenResty author + Woo author + consistency +
> edge/security). Open questions for them in §9.

---

## 1. The category error this dissolves

"A provable Shen brain is too slow for a VFS hot path" conflates two *times*:

- **Build time:** Shen's sequent-calculus type checking and the Datalog policy analysis run in the
  compiler/toolchain. This is where "we can prove it does what we want" is cashed.
- **Run time:** the deployed artifact for the read tier is **compiled Lua executing on LuaJIT** —
  JIT-compiled, near-native. The type checker is *not* in the request path; it already ran.

So the proof and the speed happen at different moments. You ship a proven artifact that runs as fast
as LuaJIT, not as fast as a Shen interpreter.

## 2. The organizing insight: one provable source, compiled per-path

Shen compiles to many backends (Lua, SBCL, Go, Scheme, …). Treat that as a **performance strategy**,
not a portability footnote:

| Concern | Compiled to | Why |
|---|---|---|
| **Hot reads / content serve** | **shen-lua → OpenResty (LuaJIT + nginx)** | event-loop IO, JIT, zero-copy byte serving, in-process shared cache |
| **The land path** (serialized, single-leader, infrequent) | **shen-SBCL** (or shen-go), shelling out to `git` | correctness > speed; real `git merge-tree`; mature subprocess story |
| **Batch / GC / policy analysis** | whichever fits | offline, throughput-oriented |

You **write and prove the land-FSM, the ACL Datalog, and the conflict logic once**, in Shen. The
proof rides on the source, so it covers every target; the performance is tuned per target. No other
candidate (all-OCaml, pure-Rust) can split this way — it is unique to Shen and is the core reason the
perf story works *without* abandoning the provable single source.

## 3. Why OpenResty fits a content-addressed VCS read path freakishly well

Two properties of the workload make it close to ideal for OpenResty:

1. **Content addressing ⇒ zero-invalidation caching.** A hash names exactly one byte string forever.
   So every cache layer is correct-by-construction with no invalidation logic:
   - `lua_shared_dict` (cross-worker, in-process) for trees/manifests + resolved attrs + ACL
     decisions;
   - on-disk blob cache;
   - **CDN edge with `Cache-Control: immutable`** — a monorepo's hot files served from the edge,
     forever, never revalidated.
2. **The bytes never need to enter Lua.** The brain makes a *decision*; nginx moves the *payload*.

### The killer pattern: brain decides, nginx serves (zero-copy)

```
GET /blob-by-path?commit=<c>&path=<p>
  └─ access_by_lua  (shen-lua, JIT'd):
       1. resolve (commit, path) -> blob-hash      [shared_dict hit ~always]
       2. Datalog ACL check (principal, path)        [shared_dict decision cache]
       3. on allow:  ngx.exec / X-Accel-Redirect -> internal location /cas/<hash>
  └─ nginx internal location /cas/<hash>:
       sendfile() the blob from the CAS dir         [kernel zero-copy; Lua never touches bytes]
       open_file_cache keeps the fd hot
```

The provable Shen brain is in the **decision** path (resolve + authorize — both cacheable, cheap,
JIT'd). It is **never** in the **payload** path. This is the single most important structural choice
for perf, and it mirrors the "proven brain / trusted shell" split at request granularity: *Shen
decides, nginx (trusted, C-fast) serves.*

## 4. This is the EdenFS shape — and it's the honest way to get VFS perf

You were never going to run a fast kernel mount *inside* Shen. EdenFS itself is a **local mount
daemon + a remote source-of-truth service** (Mononoke, over Thrift). Adopt that split:

- **OpenResty = the fast source-of-truth content/metadata service** (the Mononoke-equivalent):
  serves trees, blobs (zero-copy), and land/ACL decisions over HTTP/2 (or gRPC).
- **The mount = a thin local client** (FUSE/9p/NFS) that is mostly a **cache**, faulting blobs in
  over HTTP from OpenResty on `read()` and pinning a sparse profile locally.

Hot-path `read()` latency budget:

```
read() on a warm file        -> local page cache               (microseconds)
read() on a faulted-in file  -> local mount cache hit           (microseconds)
read() on a cold file        -> 1 HTTP RTT to OpenResty:
                                  resolve + ACL  (shared_dict, JIT)   ~tens of µs
                                  + nginx sendfile of the blob        (bandwidth-bound)
                                = one RTT + transfer, then cached locally forever (immutable)
```

The cold case is one RTT + transfer; everything after is local. That is competitive with EdenFS's
own cold-fault path, and the warm/sparse cases never leave the box.

## 5. Read/write split as a deployment fact

- **Read tier:** a *stateless, scale-out* OpenResty fleet. Reads need no coordination (the
  Datomic/Hickey point) — a read carries an **`as-of` basis header** (the landed-seq cookie); the
  tier serves a consistent snapshot at that seq from immutable content. Add nodes for read QPS.
- **Write tier:** one *serialized* land-leader (shen-SBCL/go, shelling to `git`), with the fenced
  append-only landed-log (Aphyr's fencing token). Lands are infrequent and serialized *by design*;
  they don't need the OpenResty fleet.
- The two communicate through the **immutable CAS + the landed-log** only. The read tier pulls new
  landed-log entries (or is pushed) and updates its `shared_dict` resolve cache; because content is
  immutable, a slightly-behind read tier is simply serving an earlier `as-of` — never *wrong*.

## 6. More concrete perf moves

- **Partial-evaluate the Datalog policy into generated Lua.** At policy-land time, specialize the
  landed ACL ruleset into a concrete LuaJIT-friendly matcher (no interpreter on the hot path). You
  *prove* the Datalog (decidable), *generate* the Lua, and **differential-test the generated matcher
  against the Datalog oracle**. Provable policy, compiled-fast enforcement.
- **`shared_dict` decision cache** keyed by `(principal, path-prefix, acl-version)`; invalidated only
  when policy lands (rare) by bumping `acl-version`. Steady-state authz = one dict lookup.
- **`cosocket`** peer/origin fetch on a CAS miss — non-blocking on nginx's event loop.
- **`open_file_cache` + `sendfile` (+ `aio threads` for large blobs)** for blob fds.
- **mmap'd packs** for many small objects; serve slices via internal locations.
- **HTTP/2 or gRPC** between mount client and service to multiplex the fan-out of a cold subtree
  (avoids the one-RTT-per-blob storm Torvalds flagged in the original design — batch the `want` set).

## 7. How this keeps the provability promise (proof-obligations, restated for perf)

| Property | Where proved | Where it runs |
|---|---|---|
| Land-FSM transitions legal | Shen sequent types (build) | land tier (SBCL) |
| ACL soundness / longest-prefix-deny-wins / no-unowned-path | Datalog analysis (build, decidable) | read tier (generated Lua) + land tier |
| Generated Lua matcher ≡ Datalog | differential test (CI) | read tier |
| Land ordering / idempotency / fencing | Shen logic (protocol) | land tier |
| Blob/tree integrity | content addressing (re-hash) | both tiers |
| **NOT proved (trusted oracles):** `git` merge, nginx, the FS, LuaJIT itself | — | shell / host |

The deployed read tier is *generated, JIT'd Lua* whose behavior was *proved/oracle-checked at build
time*. The proof is preserved; only the *execution* is fast.

## 8. The "even if we reimplement later" payoff, reinforced

The Shen source remains the **executable specification + conformance oracle**. If the read tier ever
needs to be hand-written in C/Rust for the last increment of speed, you differential-test it against
the Shen-derived oracle. The provable source is never wasted — it is the spec the fast thing obeys.

## 9. Honest rough edges (open questions for the panel)

1. **shen-lua ↔ LuaJIT (Lua 5.1) compatibility.** The whole read tier assumes shen-lua emits code
   that runs (and JITs well) on LuaJIT, not just reference Lua. Does Shen's runtime (tail calls,
   bignums, the reader, the type-tagged values) compile to JIT-friendly Lua, or does it defeat the
   JIT (NYI traces, excessive boxing)? **This is the load-bearing assumption.**
2. **LuaJIT GC under large working sets.** LuaJIT's GC (and the 2GB-ish address constraints of some
   builds) vs a big `shared_dict` of trees/decisions — does it hold, or do we need an external cache
   (mmap, a sidecar)?
3. **The mount is still not HTTP.** The thin FUSE/9p/NFS client is real work and is where syscall
   latency lives; OpenResty makes the *service* fast, not the mount. Is HTTP/2-to-a-local-mount-daemon
   actually low-latency enough, or do we want a Unix-socket/shared-memory transport?
4. **Consistency under caching.** Does the `as-of` basis header + immutable content genuinely give
   read-your-writes across a scale-out, partially-behind read tier — or are there windows where a
   client reads stale resolve-cache after its own land? (Aphyr's lane.)
5. **Security of the X-Accel handoff + shared cache.** Can a client smuggle a path that resolves to a
   blob it shouldn't read (ACL checked on resolve, but the internal `/cas/<hash>` location must be
   un-reachable directly)? Cache-key poisoning? Multi-tenant `shared_dict` isolation? (Ptacek's lane.)
6. **Partial-eval correctness drift.** The generated Lua matcher must stay ≡ the Datalog as rules
   evolve; is differential testing enough, or do we need the generator itself proved?

## 10. Summary

- **Proving is build-time; running is LuaJIT.** No provable-vs-fast trade.
- **One provable Shen source → compiled to the best host per path** (lua/OpenResty for reads,
  SBCL/go for lands). Shen's portability *is* the perf strategy.
- **Brain decides, nginx serves zero-copy.** Content addressing makes every cache layer correct with
  no invalidation; immutable blobs go to the edge.
- **EdenFS shape:** OpenResty = fast source-of-truth service; mount = thin caching client.
- The provable core survives reimplementation as the **spec/oracle**.

If the panel's §9 concerns hold up, this is a system that is simultaneously the most *expressive*,
the most *provable*, and — on the hot path — genuinely *fast*.

## Appendix — relationship to prior docs
Builds on the `25` verdict's "if you want the Shen brain" branch and the user's shell-out direction.
Complements (does not replace) `13` (all-OCaml) — the perf architecture here is the *Shen* path's
answer to the hot-path concern that drove the OCaml recommendation.
