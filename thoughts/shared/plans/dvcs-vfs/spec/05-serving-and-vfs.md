---
date: 2026-06-26
researcher: Claude
topic: "mvfs — serving (read/serve tier) & VFS (thin mount) design"
status: design
layer: spec
builds_on: thoughts/shared/plans/dvcs-vfs/spec/00-overview.md
informed_by:
  - thoughts/shared/plans/dvcs-vfs/26-hotpath-perf-architecture.md
  - thoughts/shared/plans/dvcs-vfs/27-agentzh-perf-review.md
  - thoughts/shared/plans/dvcs-vfs/31-synthesis-perf.md
  - thoughts/shared/plans/dvcs-vfs/32-shen-lua-perf-correction.md
tags: [openresty, luajit, shen-lua, sendfile, mlcache, edenfs, fuse, sparse, dirstate, vfs]
last_updated: 2026-06-26
---

# 05 — Serving & VFS

> Builds on the keystone `00-overview.md`. Honors invariants **I1–I9**; this doc is the home of the
> byte-path enforcement that backs **I8** (read-your-writes + monotonic reads at the read tier) and
> **I9** (authorization on every byte path). It refines, and must not contradict, §5.2 (`as-of`
> basis), §5.3 (serve token), and §5.4 (the Shen↔shell boundary). Consistency mechanics defer to
> **`04-read-boundary-consistency-security.md`**; the ACL/Datalog model defers to
> **`03-policy-and-acl.md`**. This doc owns the *mechanism*: how nginx serves bytes and how the mount
> faults them in.

This doc has two halves:

- **Part A — the read/serve tier** (the Mononoke-equivalent: a stateless, scale-out OpenResty fleet
  running shen-lua). "Brain decides, nginx serves zero-copy."
- **Part B — the VFS / mount** (the EdenFS-equivalent: a thin local client that is mostly a cache +
  dirstate, faulting blobs in over HTTP/2).

A note on provenance: the perf reviews `26`/`27`/`31` were written when an OCaml decision tier was
favored and when agentzh's prior ("a Lisp-to-Lua transpiler won't JIT") was assumed. `32` corrects
that: **`pyrex41/shen-lua` is a performance-engineered LuaJIT 2.1 target** — source→Lua→machine code,
native tail-call-to-loop lowering, primitive-mapped (un-boxed) values, and a native **`soa32`**
inference substrate (int32 FFI arrays, ~8.9× / −93% alloc vs the legacy engine, ~1.5× SBCL overall).
So the read tier **is shen-lua**, not OCaml, and the decision path genuinely JIT-compiles. Every
agentzh *mandate* below (cache hierarchy, GC64, shmem/mmap working set, kTLS, aio/directio,
request-coalescing, table-driven matcher) still stands — those were never contingent on the language;
they are OpenResty/LuaJIT facts. We bake them in.

---

## Part A — The read / serve tier

### A1. Principle: "brain decides, nginx serves zero-copy"

The request path is split so that the Shen brain (compiled to JIT'd shen-lua) makes a *decision* and
nginx moves the *payload*. The bytes never enter the Lua VM, so blob size is irrelevant to Lua/GC.

```
GET /read?commit=<c>&path=<p>     (as-of basis carried per §5.2 / doc 04)
  └─ access_by_lua  (shen-lua, JIT'd machine code):
       1. enforce as-of basis: applied-seq ≥ as-of.seq  else refuse/redirect   [I8; doc 04]
       2. resolve (commit, path) -> blob-hash                                    [mlcache L1 hit ~always]
       3. Datalog ACL check (principal, path) at as-of.acl-version (soa32 trie)  [I6; doc 03]
       4. on allow: mint serve-token = HMAC_k(hash, principal, acl-version, expiry)  [§5.3]
       5. ngx.exec("/cas/<hash>")  with serve-token as internal-only header      [in-request jump]
  └─ location /cas/<hash>  { internal; }   (verifies serve-token; fail closed — I9)
       sendfile() the blob from the CAS dir       [kernel zero-copy; Lua never touches bytes]
       open_file_cache keeps the fd hot
```

The Shen brain is in steps 1–4 (resolve + authorize + mint — all cacheable, all JIT'd, allocation-
light). It is **never** in step 5's payload path. This mirrors "proven brain / trusted shell" (§2) at
request granularity: *Shen decides, nginx (trusted, C-fast) serves.*

`ngx.exec` vs `X-Accel-Redirect`: use **`ngx.exec`** when the brain is in `access_by_lua` of the same
server — it is an internal jump within the same nginx request, no extra socket, no HTTP round-trip
(microseconds). `X-Accel-Redirect` is reserved for the case where a *separate upstream* backend names
the file (e.g., a future split where the decision tier is a distinct process). They are **not** the
same cost; prefer `ngx.exec` here.

### A2. The build step: shen-lua compiles the brain into OpenResty

The decision path is **JIT'd shen-lua** (per `32`: source → Lua → LuaJIT machine code; `soa32`
inference). The deployed artifact is produced at build/land time, not assembled per request:

1. **Compile the brain.** `shen-lua` compiles the proven Shen decision logic (resolve helpers, the
   authorization entry points, the `soa32` Datalog driver) **KLambda → Lua source**. The kernel
   bytecode cache (`string.dump`, ~30 ms warm boot) and the user fasl cache (skips
   reader/macroexpand/typecheck) make reloads cheap.
2. **Load into OpenResty.** The emitted Lua modules are placed on `lua_package_path` and pulled in
   from `init_by_lua` (once per worker master, pre-fork) so LuaJIT can warm traces before serving.
3. **Partial-eval the policy to a trie.** The *policy* is the landed Datalog ruleset (the most recent
   committed policy entry, identified by `acl-version`; see §5.1 / `03`). At policy-land time it is
   partial-eval'd into a **trie / table lookup over `soa32`** — *data, not branchy generated code*
   (agentzh F6: a long `if/elseif` cascade is JIT-hostile and reshuffles on every rule edit). The
   matcher walks longest-prefix-match-with-deny-wins as a fixed-shape loop (index, compare, descend),
   so the inner loop is the same shape regardless of rule count. The **trie builder is
   differential-tested against the Datalog oracle** in CI (the brain is the conformance spec, §8 of
   `00`).

This relocation is the load-bearing correction from agentzh's review *as applied to shen-lua*:
shen-lua's *runtime* logic does JIT (refuting F1's generic prior — see `32`), but we **still** emit
the policy as a lookup table rather than generated control flow, because the table is what JITs best
and is trivially fuzzable.

### A3. Cache hierarchy: lua-resty-mlcache (NOT raw shared_dict)

**Mandate (agentzh F2):** do not cache tree/manifest objects in raw `lua_shared_dict`. A shared_dict
stores *strings only* (serialize on every `:set`, `cjson`/MessagePack decode on every `:get`), is
guarded by *one mutex per dict* across all workers (a contention point at scale), evicts FIFO-ish
(not true LRU), and fragments its slab. Putting the hot lookup on shared_dict instead of an in-worker
LRU is a 100–1000× per-lookup haircut.

Use **`lua-resty-mlcache`**, which packages the correct two-tier shape:

- **L1 = `lua-resty-lrucache` per worker** — holds **live, decoded Lua tables** (resolved
  `(commit,path)→hash` entries, decoded tree/manifest objects, ACL decisions). No serialization, true
  LRU, **no lock** (per-worker, single-threaded within the worker). The hot path hits here ~always:
  ~tens of nanoseconds (table index + LRU bump), no GC, no lock.
- **L2 = `lua_shared_dict`** — cross-worker shared layer holding the *serialized* form; populates L1
  on a worker miss and survives reloads. Lives in **shmem slabs, not the Lua GC heap** — so a large
  L2 adds no GC marking cost (see A5).
- **L3 = disk / origin callback** — mlcache's callback runs on a miss, fronted by its built-in
  **`lua-resty-lock`** (single-flight; see A4).

Content addressing makes this honest: an entry keyed by a **hash** is valid forever, so L1 entries
*never go stale* — mlcache's hardest job (invalidation) is skipped for the blob/tree layer.
**Versioned** keys (resolve map, ACL decisions) are the exception and are keyed by version (A6).

Cache keys:

| Cached thing | Key | Immutable? |
|---|---|---|
| blob bytes | (not in Lua; `sendfile` + page cache + `open_file_cache`) | yes — eternal |
| tree/manifest object | `tree:<tree-hash>` | yes — eternal |
| resolve result | `resolve:<commit-hash>:<path>` (commit pins the tree) | per-commit |
| ACL decision | `acl:<principal>:<path-prefix>:<acl-version>` | per-version |

### A4. Cold-blob single-flight (request coalescing)

**Mandate (agentzh F4):** when a hot-but-cold blob is requested by N concurrent clients, naive code
fires N identical origin fetches — a thundering herd that can melt the origin (a monorepo top-level
`BUILD`/lockfile/header read by every CI job at once). Use **`lua-resty-lock`** (mlcache's L3 lock is
exactly this) so the first request for hash H acquires the lock, fetches via cosocket, populates the
cache + writes the CAS file, and the other N−1 **wait, then read the now-warm cache** — one origin
fetch, not N.

- Budget a small **dedicated `lua_shared_dict` for locks**.
- The lock has a timeout: design the wait path to **fall through to a direct fetch** (not error) if
  the holder is slow, avoiding correlated stalls.
- Origin/peer fetch on miss uses **`lua-resty-http` (cosocket)**; keep connections in the per-worker
  pool via `sock:setkeepalive()` (set `pool_size`, `keepalive_timeout`) to avoid a connect +
  handshake per miss. For an **HTTP/2 batched want-set** to the origin (B-side fan-in, §B5), lean on
  nginx's own upstream via an internal proxied location reached by `ngx.exec` rather than hand-rolling
  h2 in cosockets (cosockets speak HTTP/1-style).

### A5. LuaJIT runtime: GC64 + working set out of the Lua heap

**Mandates (agentzh F5):**

1. **Build GC64.** Classic LuaJIT caps the Lua heap at ~1–2GB (low-address tagged pointers). Build
   LuaJIT with `-DLUAJIT_ENABLE_GC64`. OpenResty's bundled `openresty/luajit2` enables GC64 by
   default on 64-bit — **verify** (`luajit -v`). GC64 removes the address-space cap.
2. **Keep the big working set OUT of the Lua GC heap.** LuaJIT's GC is non-generational,
   non-compacting incremental mark-sweep; mark cost scales with *live object count*, so a metadata
   cache held as millions of small live Lua tables causes p99/p999 pauses — *that*, not the address
   cap, is the real ceiling. Discipline:
   - **Blob bytes** → `sendfile` / page cache (already out of the heap).
   - **L2 tree metadata** → `shared_dict` shmem slabs (out of the GC heap).
   - **L1 lrucache** is the *only* GC-visible layer → **cap its element count aggressively**; let L2
     (shmem) be the big layer, trading a little decode CPU for a flat GC.
   - For a truly large hot resolve index, hold it as an **mmap'd structure** (e.g. an mmap'd
     sorted/FST index of `(commit,path)→hash`, or the `soa32` policy trie itself) read via FFI —
     **mmap pages are kernel page cache, invisible to the Lua GC**, and shared across workers for
     free. This is also where the `soa32` int32 arrays live: GC-invisible by construction.

Net: GC64 + "big set in shmem/mmap, small set in lrucache" holds the memory story at monorepo scale.

### A6. Consistency hooks (detail in `04`)

The read tier *enforces* the `as-of` basis (§5.2): a read carries `as-of := (seq, acl-version)`; the
serving worker MUST have `applied-seq ≥ seq` and evaluate ACLs at `acl-version`, else refuse/redirect
(**I8**). Mechanics — applied-basis enforcement, the wait-or-503 hold, client high-water-mark,
per-worker lag skew across the fleet — are specified in `04`. The serving-side obligations this doc
pins:

- **Versioned cache keys.** Resolve and ACL cache entries include the version (`commit-hash` /
  `acl-version`) in the key (A3). You cannot serve a resolve or decision computed under a *different*
  basis. The blob layer is the only **immutable, edge-cacheable** class; the resolve/ACL layers are
  *versioned, not immutable*.
- **Committed-watermark only.** Never cache or serve a resolve at a `seq` the worker has not applied
  from the landed-log.
- **Fail closed at stale `acl-version`.** If the worker cannot evaluate at the requested
  `acl-version`, refuse — never silently use an older ruleset (**I6**).

### A7. Security hooks (detail in `04`)

The byte path is gated by the **serve token** (§5.3): `serve-token := HMAC_k(hash, principal,
acl-version, expiry)`, single-use, minted **only** in the authorized resolve step (A1 step 4). The
`/cas/<hash>` location:

- is **`internal;`** — *mandatory*. The only way to reach it is the `ngx.exec` after resolve+authorize
  in the **same request**; the hash is **derived server-side** from the authorized `(commit,path)`,
  never accepted from a client (agentzh F7 / Ptacek). A hash alone never authorizes a read (**I9**).
- **verifies the serve token** before `sendfile` and **fails closed** on absent/expired/invalid.
- splits **public vs private tiers**: only the public/immutable class is eligible for a CDN edge with
  `Cache-Control: immutable`; private content is per-principal partitioned and not edge-cached (the
  revocation / fired-employee story lives in `04`).

Cache-key hygiene: `principal` in any decision key is the *authenticated, post-auth* identity (never
a spoofable header); `acl-version` is part of every ACL key so an old-ruleset decision can never be
reused; in a multi-tenant dict, the tenant id is part of *every* key. These are correctness
constraints that also keep the cache *effective* — an under-keyed cache forces caching off and
collapses the perf story.

### A8. OpenResty config sketch

```nginx
# --- shared memory (shmem slabs, GC-invisible) ---
lua_shared_dict mvfs_l2        512m;   # mlcache L2: serialized trees/resolve/acl
lua_shared_dict mvfs_l2_miss    32m;   # mlcache negative cache
lua_shared_dict mvfs_locks      16m;   # lua-resty-lock single-flight (A4)
lua_shared_dict mvfs_basis       4m;   # applied-seq watermark (cross-worker; doc 04)

# --- blob fd cache: immutable CAS => long-lived, safe (A1) ---
open_file_cache          max=200000 inactive=24h;
open_file_cache_valid    24h;          # /cas files are append-only, never mutated in place
open_file_cache_min_uses 1;
open_file_cache_errors   on;

init_by_lua_block {
  local mlcache = require "resty.mlcache"
  -- shen-lua-emitted modules (A2): brain decision + soa32 policy trie loader
  local brain = require "mvfs.brain"          -- compiled by shen-lua at build time
  brain.load_policy_trie("/var/mvfs/policy/")  -- mmap'd soa32 trie (A5)
  package.loaded.mvfs_cache = assert(mlcache.new("mvfs", "mvfs_l2", {
    lru_size   = 100000,                       -- L1 element cap (A5: keep small)
    ttl        = 0,                            -- immutable keys never expire (A3)
    neg_ttl    = 5,
    shm_miss   = "mvfs_l2_miss",
    ipc_shm    = "mvfs_l2",
    resty_lock_opts = { timeout = 0.5 },       -- single-flight (A4)
  }))
}

server {
  listen 443 ssl http2;
  # kTLS for TLS zero-copy (A9): sendfile stays kernel-side under TLS
  ssl_conf_command Options KTLS;               # OpenSSL 3 + nginx built for kTLS
  sendfile on;
  tcp_nopush on;

  location = /read {
    access_by_lua_block {
      local brain = require "mvfs.brain"
      local cache = package.loaded.mvfs_cache
      -- 1) enforce as-of basis (I8; doc 04)
      if not brain.basis_ok(ngx.var.arg_asof) then return brain.refuse_or_redirect() end
      -- 2) resolve via mlcache (L1 lrucache -> L2 shmem -> origin single-flight)
      local hash = cache:get("resolve:"..ngx.var.arg_commit..":"..ngx.var.arg_path,
                             nil, brain.resolve, ngx.var.arg_commit, ngx.var.arg_path)
      -- 3) Datalog ACL on soa32 trie (I6; doc 03), keyed by acl-version
      if not brain.authorize(ngx.var.principal, ngx.var.arg_path) then return ngx.exit(403) end
      -- 4) mint single-use serve-token (§5.3)
      ngx.req.set_header("X-Mvfs-Serve", brain.mint_serve_token(hash, ngx.var.principal))
      -- 5) internal jump; bytes never enter Lua
      return ngx.exec("/cas/"..hash)
    }
  }

  location ~ ^/cas/(?<blobhash>[0-9a-f]+)$ {
    internal;                                  # MANDATORY (I9; A7)
    access_by_lua_block {
      local brain = require "mvfs.brain"
      if not brain.verify_serve_token(ngx.var.blobhash,
                                      ngx.req.get_headers()["X-Mvfs-Serve"]) then
        return ngx.exit(403)                   # fail closed
      end
    }
    # size-gated aio threads + directio for large blobs (A9)
    aio threads;
    directio 4m;
    output_buffers 2 1m;
    alias /var/mvfs/cas/$blobhash;             # sendfile from CAS dir (zero-copy)
  }
}
```

### A9. Zero-copy footguns (config-level)

- **kTLS for the TLS edge.** Plain `sendfile()` is kernel zero-copy *only for cleartext*. Terminate
  TLS in nginx without kTLS and every byte traverses userspace to be encrypted — sendfile's benefit
  is largely gone. Configure **kTLS** (OpenSSL 3 + nginx built for it) for true zero-copy under TLS.
  For an on-host mount client, run that hop **cleartext over a Unix domain socket** and keep zero-copy
  where it matters.
- **Large blobs block the worker.** A `sendfile` of a large file is a syscall on the event-loop
  thread and can head-of-line-block thousands of requests. Use **size-gated `aio threads` +
  `directio`** (e.g. `directio 4m;`) so a 500MB blob is offloaded to a thread pool (sendfile is
  bypassed when aio/directio kicks in — intended). Test the interaction.
- **CAS is append-only, never mutated in place.** `open_file_cache` holding an fd to a repacked-in-
  place blob would serve garbage. GC of the CAS **only unlinks, never overwrites** — then long
  `open_file_cache_valid` is purely a win (immutability gift).

### A10. Read-tier latency / throughput budget

| Path | Cost | Notes |
|---|---|---|
| resolve + ACL, all-cache-hit | **L1 lrucache get (~tens of ns) + a few table ops** | dominated by table ops, not Lua logic |
| metadata decisions / box | **~100k–300k+ /s**, p99 well under 1 ms | bottleneck is shared_dict lock if L1 hit rate is poor, then nginx overhead |
| blob serve (warm, cleartext) | line-rate, NIC/disk-bound | saturates 10–25GbE on payload before CPU |
| blob serve (TLS edge) | CPU-bound on encryption **unless kTLS** | TLS, not Lua, is the edge bottleneck (A9) |
| blob serve (large) | +latency for that request, worker stays responsive | via `aio threads` (A9) |
| cold miss | **1 RTT to origin + transfer**, *provided coalesced* | without single-flight (A4) a popular cold blob's tail explodes |

The order you meet bottlenecks: (1) L1 hit rate (keep it high; A3), (2) shared_dict lock if L1 misses
(A3), (3) TLS-edge CPU for payload (A9), (4) GC p99 if the live Lua heap is big (A5). None is "Lua
being slow" — with the `soa32` decision path JIT-compiled (per `32`), the decision logic is not the
bottleneck.

---

## Part B — The VFS / mount (thin client, EdenFS shape)

### B1. Topology: source-of-truth service + thin caching mount

You were never going to run a fast kernel mount *inside* Shen. EdenFS itself is a **local mount
daemon + a remote source-of-truth service** (Mononoke over Thrift). mvfs adopts the same split:

- **OpenResty (Part A) = the fast source-of-truth content/metadata service** (the Mononoke-equivalent):
  serves trees, blobs (zero-copy), and resolve/ACL decisions over HTTP/2.
- **The mount = a thin local client** that is mostly a **cache + dirstate**, faulting blobs in over
  HTTP/2 on `read()`, pinning a sparse profile locally, and maintaining a Git-index-style dirstate.

The mount holds *no authority*. It is a cache of immutable content plus local working-tree state; the
service is the single source of truth (gated by serve tokens, A7). A slightly-behind mount is simply
viewing an earlier `as-of` — never *wrong* (immutability).

### B2. Mount mechanism: FUSE recommended (with rationale)

**Recommendation: FUSE for the on-host mount, with a checkout-first fallback (§B6) shipped before
it.** Rationale and trade-offs:

| Option | For | Against |
|---|---|---|
| **FUSE** *(recommended)* | EdenFS-proven for exactly this lazy-fault VFS; rich (`read`/`getattr`/`readdir` interception for fault-in + dirstate); userspace daemon, no kernel module to ship; works cross-distro | per-syscall userspace round-trip latency; macOS needs macFUSE |
| 9p | simple protocol, VM/container-friendly | weaker caching semantics, higher per-op overhead for a dev workstation, less battle-tested for monorepo VFS |
| NFS (loopback) | kernel-side attr/data caching for free; EdenFS uses NFS on macOS where FUSE is painful; no FUSE dependency | a full NFS server to implement; cache-coherence/invalidation harder to drive precisely for lazy fault-in |

FUSE is the closest match to the proven EdenFS shape and gives the finest control over lazy fault-in
and dirstate; NFS-loopback is the right *secondary* backend for macOS where FUSE is operationally
painful (mirroring EdenFS's own platform split).

**Implementation note.** The mount daemon is a **separate small native helper**, *not* shen-lua in
the request path. shen-lua's host FFI could in principle drive libfuse, but the mount's job is
syscall plumbing + a local cache, not decision-making — keep the brain at the service tier (A1) and
let the mount be a thin, boring, fast C/Rust/Go helper that speaks HTTP/2 to the service and libfuse
to the kernel. (This keeps the Shen↔shell boundary, §5.4, clean: the mount is *trusted shell*.)

### B3. Fault-in on `read()`

```
open()/read() on a path:
  - path materialized locally?  -> serve from local cache  (page cache / mount cache; microseconds)
  - not materialized?           -> 1 HTTP/2 GET /read?commit=<c>&path=<p>  (carries as-of basis)
                                     service resolves+authorizes+sendfiles the blob (Part A)
                                     mount writes blob into local cache, then satisfies read()
                                   = one RTT + transfer; cached locally forever (immutable)
getattr()/readdir() on a cold dir:
  - fault in the tree object (not the blob bytes): GET the tree, populate dirstate stat info
  - lazy: do NOT fetch child blobs until they are read (sparse, §B4)
```

The mount caches by **content hash**, so a faulted-in blob is valid forever and never revalidated.
Tree fault-in populates `getattr`/`readdir` from tree metadata *without* pulling blob bytes — this is
what makes `ls` / `status` cheap on a cold subtree.

### B4. Sparse / lazy checkout for the monorepo

- **Sparse profiles.** The mount pins a **sparse profile** (a set of path globs the developer
  works in); only those subtrees are materialized/kept. The rest exists virtually and faults in on
  demand. This is what makes a hundreds-of-developers monorepo usable on one workstation.
- **Lazy subtree fault-in via git tree walk.** A cold subtree is materialized by walking the **git
  tree** from the root tree of the `as-of` commit, faulting in child trees as directories are entered
  and blobs as files are read — never the whole monorepo.
- **Batched cold-subtree fetch (B5)** prevents the tree walk from becoming one-RTT-per-object.

### B5. Cold-fan-in: batched want-set over HTTP/2

Torvalds' original objection to a lazy VFS is *one-RTT-per-blob* on a cold checkout. Fix: when the
mount needs many objects (a cold subtree, a sparse-profile expansion), it computes a **batched
want-set** (the set of tree+blob hashes from the git tree walk) and fetches them **multiplexed over a
single HTTP/2 connection** to the service, rather than a serial request per object. The service
serves each via the Part A path (resolve is trivial — the mount already has the hashes from the tree
walk; ACL still applies). HTTP/2 multiplexing collapses N round-trips into ~1 RTT of pipelined
streams.

### B6. Dirstate: Git-index-style, O(changes) status

The mount maintains a **Git-index-style dirstate** so `status`/`diff` are O(changes), not O(repo):

- Per tracked path, store `(size, mtime, ctime, inode)` alongside the expected content hash (the
  classic git index `stat` cache).
- On `status`: for each tracked path, compare the current `stat` to the cached `(size,mtime,ctime,
  inode)`. **If they match, short-circuit** — the file is assumed unchanged, no hash recompute. Only
  files whose `stat` differs are re-hashed and compared. Net work is **O(changed files)**, not O(repo
  size) — essential at monorepo scale (EdenFS/Sapling do exactly this).
- The dirstate also records the sparse profile and the current `as-of` basis (the commit the working
  tree is checked out against), so `status` knows what to diff against.

### B7. Materialize-on-demand checkout (ship first; mount later)

Per the keystone non-goals (§6: "an in-kernel FUSE *requirement*" is out — "mount is a thin client;
checkout-first is fine"), the **first shipped artifact is a no-mount, materialize-on-demand
checkout**:

- `mvfs clone` writes the dirstate + sparse profile but materializes **nothing** (or only the sparse
  root).
- `mvfs checkout <path>` materializes a path/subtree on demand via the batched want-set (B5), writing
  real files to disk and updating the dirstate (B6).
- `status`/`diff` use the dirstate short-circuit (B6); `submit` goes to the land tier (`02`).

This delivers the EdenFS *experience* (sparse, lazy, O(changes) status, content-addressed cache) with
**no FUSE dependency** — the boring, robust path. The **FUSE mount (B2) is a later increment** that
turns `checkout`-on-demand into transparent `read()`-on-demand, reusing the same fault-in (B3),
sparse (B4), batched fetch (B5), and dirstate (B6) machinery.

### B8. Mount client responsibilities (summary)

The mount/checkout client is responsible for, and *only* for:

1. **Local content cache**, keyed by content hash (immutable, never revalidated).
2. **Fault-in** of blobs (on `read()`/`checkout`) and trees (on `getattr`/`readdir`) over HTTP/2.
3. **Sparse profile** pinning + lazy subtree materialization via git tree walk (B4).
4. **Batched want-set** fetching to avoid one-RTT-per-blob (B5).
5. **Git-index-style dirstate** for O(changes) `status`/`diff` (B6).
6. **Carrying the `as-of` basis** on every service request and tracking the client high-water-mark
   for monotonic reads (I8; mechanics in `04`).
7. **Holding the serve flow's client side** (it presents principal credentials; the service mints and
   verifies serve tokens — the mount never sees a hash it wasn't authorized to resolve; I9 / A7).

It is **not** responsible for any authorization or ordering decision — those live in the service
(Part A) and the land tier (`02`). The mount is trusted shell (§5.4): a cache, not a brain.

### B9. Cold-read latency budget

```
read() on a warm file        -> local page cache                 (microseconds)
read() on a faulted-in file  -> local mount cache hit            (microseconds)
read() on a cold file        -> 1 HTTP/2 RTT to the service:
                                  resolve + ACL  (Part A, JIT'd)       ~tens of µs
                                  + nginx sendfile of the blob         (bandwidth-bound)
                                = 1 RTT + transfer, then local forever (immutable)
cold subtree (N objects)     -> batched want-set, HTTP/2 multiplex     ~1 RTT + transfer
                                 (NOT N RTTs — B5)
```

Warm and faulted-in cases never leave the box. The cold case is one RTT + transfer and then local
forever (content immutability). The cold *subtree* case is one batched RTT, not N — this is the
specific fix for the fan-out storm.

---

## Cross-references

- **`00-overview.md`** — honored names, invariants I1–I9, §5 contracts (esp. §5.2 `as-of`, §5.3 serve
  token, §5.4 Shen↔shell boundary).
- **`03-policy-and-acl.md`** — the Datalog ACL model on `soa32`, longest-prefix-deny-wins, the path
  model. Part A's matcher (A2) is the *partial-eval'd, runtime* form of `03`'s policy.
- **`04-read-boundary-consistency-security.md`** — full mechanics of `as-of` enforcement (I8),
  monotonic reads, per-worker lag, serve-token lifecycle & revocation, public/private tier split, the
  fired-employee/edge-cache problem (I9). Part A (A6, A7) carries the *serving-side hooks*; `04` owns
  the contract.
- **Invariants this doc backs:** **I8** (read-your-writes + monotonic at the scale-out read tier;
  A6) and **I9** (authorization on every byte path; A1 step 5 / A7 / `/cas` `internal;`).
```
