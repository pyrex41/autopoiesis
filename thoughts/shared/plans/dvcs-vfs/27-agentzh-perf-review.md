---
date: 2026-06-25
reviewer: "Yichun Zhang / agentzh (persona)"
status: review
topic: "OpenResty/LuaJIT review of the shen-lua read tier in 26-hotpath-perf-architecture.md"
inputs:
  - thoughts/shared/plans/dvcs-vfs/26-hotpath-perf-architecture.md
  - thoughts/shared/plans/dvcs-vfs/25-final-verdict-go-vs-ocaml.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
tags: [openresty, luajit, lua-resty-core, lua-resty-lrucache, lua-resty-lock, shared_dict, sendfile, x-accel-redirect, cosocket, gc64, jit, perf-review]
---

# agentzh review: the OpenResty / shen-lua read tier

I built ngx_lua, lua-resty-core, lua-nginx-module's cosocket layer, the `lua-resty-*`
ecosystem, and a couple of CDN/gateway-scale platforms on exactly this stack. I have spent
more time than anyone should reading `jit.dump` output and chasing trace aborts in
production. So I'll be concrete about what this design gets right and where it is leaning on
assumptions that LuaJIT will not honor.

Short version up front: **the *shape* of this architecture is exactly what I would build —
"brain decides, nginx serves" is the correct pattern, and content addressing genuinely
removes the hardest part of caching (invalidation). But the doc's load-bearing assumption —
§9.1, "shen-lua emits JIT-friendly LuaJIT, so the read tier runs near-native" — is the one
part I would bet against, and it happens to be the one the whole "provable *and* fast" thesis
rests on.** The good news is that the architecture is robust to that assumption being false,
*if* you accept that the Lua tier is a control-plane glue layer and not a compute kernel.

---

## Verdict

**Conditional yes.**

The read tier is sound **as a decision-and-dispatch plane**: resolve `(commit, path) →
hash`, authorize, then `X-Accel-Redirect`/`ngx.exec` into an internal location and let nginx
`sendfile()` the bytes. That is bread-and-butter OpenResty and it will do very well — tens to
low-hundreds of thousands of QPS per box for the metadata decision, payload throughput
bounded by NIC/disk, not Lua.

It is **not** sound if you are counting on shen-lua's *generated* code to JIT-compile to
near-native and do real per-request computation in the hot path. It almost certainly won't
JIT well. The fix is architectural, not a tuning knob: keep generated-Shen-Lua off the
per-request hot path entirely. Treat the hot path as table lookups + string ops in
hand-written idiomatic Lua (which *does* JIT), and let the Shen-derived code run at
*land/compile time* to *produce* those lookup tables and the specialized matcher.

The single biggest perf risk is below.

### The single biggest perf risk

**The read tier never actually runs JIT-compiled — shen-lua's generated code falls off the
trace compiler (NYI / aborts) and executes in the LuaJIT interpreter, so the "compiled Lua =
near-native" premise (§1, §9.1) is false in practice.** Everything downstream of that — the
latency budget in §4, the "tens of µs resolve+ACL," the claim that proving and speed live at
different times "for free" — is sized against a number you will not hit if real Shen-generated
code is in `access_by_lua`. De-risk this *first*, with `jit.dump`/`-jp`, before anything else
in the plan. It is cheap to measure and it decides the whole story.

---

## Findings

### F1 — [Critical] shen-lua → LuaJIT: assume interpreted, not JIT'd, until proven otherwise

This is §9.1, and the doc correctly flags it as load-bearing. My experience says the honest
default is "it runs in the interpreter."

Why I expect this, concretely. LuaJIT's trace compiler is a *tracing* JIT: it records a hot
loop or hot call path into a linear IR trace, and the trace must consist entirely of
operations it can compile. The moment it hits a **NYI** ("not yet implemented") bytecode or
an unsupported C call, the trace **aborts** and that path stays in the interpreter. A
Lisp-with-types compiled down to Lua hits the classic NYI/abort triggers head-on:

- **Deep / non-tail recursion.** Shen leans on recursion. LuaJIT does not trace across most
  recursive calls well; recursion to non-trivial depth is a reliable trace killer. (Tail
  calls in Lua are proper, but tracing *through* them into a stable hot trace is another
  matter.)
- **Big runtime dispatch.** A Shen runtime carries type-tagged values, a `cons`/symbol
  representation, equality/`unify` dispatch, and a trampoline. Generated code tends to be one
  enormous function table or a giant `if/elseif` dispatch. Megamorphic dispatch blows the
  trace's type specialization — every new value shape is a guard exit / side trace, and you
  thrash.
- **Boxing.** Tagged values mean tables-or-closures per value. That is allocation on the hot
  path → GC pressure (see F5) → and the allocations themselves are often the thing that keeps
  a trace from being profitable even when it compiles.
- **`string.*` / pattern / `pairs` NYIs.** `string.format`, many `string.*` calls,
  `pairs()` (vs `ipairs`), `next` over hashes, varargs in inner loops — all are NYI or
  trace-hostile in LuaJIT 2.1. Generated reader/printer code is full of these.
- **The reader / bignums.** If any of Shen's reader or numeric tower rides into the request
  path, that is interpreter territory, full stop.

Net: I would bet the generated Shen-Lua hot path runs **interpreted**. LuaJIT's interpreter
is unusually fast (hand-written assembly) — maybe 2–5× a typical bytecode VM — but it is
**not near-native**, and it is nowhere near the 50–100× you implicitly assume when you say
"JIT'd, ~tens of µs." Interpreted, a non-trivial resolve+authorize in generated Lisp-style
code is more plausibly **hundreds of µs to low-ms**, and worse it allocates.

**What to measure (do this in week one, it's a half-day spike):**
- `jit.v` to stderr (`-jv` / `jit.v.start("/path/log")`): watch for a flood of `abort`
  lines naming your generated functions. That is the diagnosis.
- `jit.dump` (`-jdump`): confirm whether the resolve/ACL functions even produce traces, and
  if so where they exit / what's NYI. Look for `NYI` annotations.
- **`-jp` (the LuaJIT profiler, `jit.p`)**, or better, the **`SystemTap`/`stap++` flame
  graphs** I shipped with the OpenResty toolkit, and **on-CPU flame graphs via `perf` +
  `lj-lua-stacks`**. Run a realistic mix and look at where wall time actually goes. If you see
  `lj_BC_*` interpreter symbols dominating, you are interpreted.
- Count **GC allocation rate** with `collectgarbage("count")` deltas per request, and watch
  `ngx.shared`-independent heap growth. High alloc/req confirms boxing.

**The fix (architectural, and it's the good news):**
Do not put generated Shen-Lua in `access_by_lua`. Instead:
1. At **land time** (off the hot path), run the Shen-derived logic to *emit data*: the
   resolved `(commit→tree)` maps, and a **specialized, table-driven matcher** for the ACL
   (see F6).
2. The hot path becomes **hand-written idiomatic Lua** doing: a `shared_dict` get, a
   `lua-resty-lrucache` get, a couple of table indexes, an integer compare for longest-prefix.
   *That* JITs, or doesn't need to because it's already three FFI-free table ops.

This preserves the doc's actual thesis ("proving is build-time; running is fast") — but it
relocates the boundary correctly: the *fast* runtime is plain Lua over precomputed data, not
shen-lua executing. The doc's framing in §1 ("the deployed artifact is compiled Lua executing
on LuaJIT — JIT-compiled, near-native") should be rewritten to "the deployed artifact is
*precomputed lookup data* plus a thin hand-written Lua dispatcher; the Shen runtime is not in
the request path." That's a stronger claim and a true one.

---

### F2 — [Critical] `lua_shared_dict` is the wrong primary cache for tree/manifest objects

The doc (§3.1, §6) caches "trees/manifests + resolved attrs + ACL decisions" in
`lua_shared_dict`. I wrote a lot of that subsystem; here is the reality you are signing up for:

1. **It stores strings only.** Every `:set` serializes, every `:get` returns a string you
   must deserialize. Caching a *tree object* means `cjson`/MessagePack encode on write and
   decode on read **on every request**. For a fan-out subtree listing, that decode cost can
   dwarf the lookup you came for. You do not get "an in-process object cache"; you get an
   in-process *serialized byte* cache.
2. **One lock per dict.** `ngx.shared.DICT` is guarded by a single shared mutex (a spinlock +
   futex in shmem) across **all worker processes**. Under high concurrency, hot dicts become a
   contention point — every `get`/`set`/`incr` serializes against every other worker's access
   to the same dict. At CDN scale I have absolutely seen this dict lock show up in flame graphs
   as the bottleneck. The decode-on-get makes the critical section longer than people expect
   (the copy-out happens under the lock).
3. **FIFO-ish eviction, not LRU.** When the slab is full, `:set` evicts via a forced-eviction
   of old entries (it walks the queue); it is not a real LRU and under memory pressure you get
   surprising evictions and occasional `:set` failures ("no memory") that you must handle.
4. **Slab allocator fragmentation.** Variable-size values (trees of wildly different sizes)
   fragment the slab; effective capacity is well below `size`.

**The correct shape (and it's a well-trodden one in OpenResty):** a **two-tier cache**.
- **L1: `lua-resty-lrucache` per worker** — stores **live Lua tables/objects, no
  serialization**, true LRU, **no lock** (it's per-worker, single-threaded within the worker).
  This is where your decoded tree/manifest objects live and where the hot path hits ~always.
- **L2: `lua_shared_dict`** — the cross-worker shared layer, holding the *serialized* form,
  used to populate L1 on a worker miss and to share across workers/reloads.
- This is exactly the pattern `lua-resty-mlcache` packages (L1 lrucache + L2 shared_dict + L3
  callback with **built-in `lua-resty-lock` to prevent stampede**). **Use `lua-resty-mlcache`
  rather than rolling your own** — it already solves the L1/L2 coherence, the negative caching,
  the IPC invalidation channel, and the stampede lock. For an immutable, content-addressed
  workload it is almost a perfect fit because you can skip the hard part (invalidation): a hash
  key is valid forever, so L1 entries never go stale.

**Quantify it:** rough order-of-magnitude on commodity hardware —
- `lrucache` get of a live table: ~tens of **nanoseconds** (a table index + LRU bump), no GC,
  no lock.
- `shared_dict` get + `cjson.decode` of a modest tree: ~**single-digit to tens of µs**, plus
  lock contention that grows with worker count and QPS, plus GC from the decoded table.
That's a 100–1000× difference per hot lookup. For a read tier whose whole job is fast
metadata resolution, putting the hot lookup on `shared_dict` instead of `lrucache` is leaving
the dominant win on the table.

One more: for the *blob bytes*, the doc is right not to cache them in `shared_dict` — bytes
go through `sendfile` + `open_file_cache` (F3), never into Lua. Keep it that way. `shared_dict`
is for small decision metadata only, and even then behind an lrucache.

---

### F3 — [Sound, with footguns] "brain decides, nginx serves" via X-Accel-Redirect / `ngx.exec` + sendfile + open_file_cache

This is the right pattern. It is what I would build, and the zero-copy framing is correct: the
bytes never enter the Lua VM, so blob size is irrelevant to Lua/GC. Specifics and the footguns:

- **`ngx.exec("/cas/<hash>")` vs `X-Accel-Redirect`.** `ngx.exec` is an internal jump within
  the same nginx request — *no* extra socket, *no* HTTP round-trip; it's the cheap one and the
  one to use when the brain is in `access_by_lua`/`content_by_lua` of the same server.
  `X-Accel-Redirect` is for when an *upstream* (a separate backend) names the file. They are
  not the same cost; the doc lists both as if interchangeable. Prefer `ngx.exec` /
  `ngx.location.capture`-free internal location here. The internal redirect itself is cheap
  (microseconds) — fine.
- **Footgun 1 — `open_file_cache` and immutability.** `open_file_cache` caches open fds + stat
  results with a TTL and `open_file_cache_valid`. For a normal site that means staleness risk;
  for **content-addressed blobs it is a gift** — files at `/cas/<hash>` never change, so you can
  set very long `open_file_cache_valid` and high `max=` with confidence. The footgun is the
  *inverse*: if you ever **garbage-collect / repack the CAS** and unlink a blob whose fd is
  still cached, you serve from a now-unlinked inode (fine on Linux until the fd closes) or, if
  repacked in place, serve stale/garbage. Rule: **CAS files are append-only and never mutated
  in place; GC only unlinks, never overwrites.** Then open_file_cache is purely a win.
- **Footgun 2 — sendfile + TLS.** Plain `sendfile()` is kernel zero-copy *only for cleartext*.
  The moment you terminate **TLS in nginx**, userspace must encrypt every byte, so the bytes
  *do* traverse userspace (not Lua, but not zero-copy either) — sendfile's benefit is largely
  gone unless you have **kernel TLS (kTLS)** configured (`ssl_conf_command` / OpenSSL 3 + kTLS,
  and nginx built for it). On most deployments you will *not* have kTLS. So "zero-copy byte
  serving" is true for the internal/cleartext hop (e.g., OpenResty → local mount daemon over a
  Unix socket or plaintext HTTP/2 on the box), and *not* true edge-facing over TLS. Size the
  CPU budget accordingly. If the mount client is on the same host, run that hop in cleartext
  over a Unix domain socket and you keep zero-copy where it matters.
- **Footgun 3 — large blobs and worker blocking.** `sendfile` of a large file can block the
  nginx worker (it's a syscall on the event-loop thread). For large blobs use **`aio threads`**
  (thread-pool offload) **with `directio`** for files above a threshold, so a 500MB blob doesn't
  stall the whole worker's event loop and head-of-line-block thousands of other requests. The
  doc mentions `aio threads` in §6 — good — but make it conditional on size (`directio 4m;`
  `aio threads;`) and *test it*, because `aio threads` + `sendfile` interact (sendfile is
  bypassed when aio/directio kicks in; that's fine and intended).
- **Footgun 4 — the internal location must be unspoofable.** `location /cas/ { internal; }` —
  the `internal` directive is mandatory and the doc's §9.5 worry is real and correctly placed.
  The only way to reach `/cas/<hash>` must be via the `ngx.exec` after the ACL check. Never let
  the hash appear in a client-controllable way that bypasses resolve+authorize. (More in F7.)

Net on F3: correct pattern, no architectural change needed, but the §3 framing overstates
"zero-copy" for the TLS edge and underplays the large-blob worker-blocking issue. Both are
config-level fixes.

---

### F4 — [Major] cosocket origin/peer fetch on miss: pooling is fine, but you MUST coalesce the thundering herd

§6's "`cosocket` peer/origin fetch on a CAS miss — non-blocking on nginx's event loop" is
correct as far as it goes, and the cosocket model is genuinely good here:

- cosockets are **per-request** but the underlying **connection pool is per-worker**
  (`sock:setkeepalive()` returns the TCP conn to a per-worker pool keyed by host:port). Use it;
  otherwise you pay a connect + (for TLS) handshake per miss. Set `pool_size` and
  `keepalive_timeout` deliberately.
- Use **`lua-resty-http`** (cosocket-based) or raw `ngx.socket.tcp`. If the origin is HTTP/2 or
  gRPC for the batched `want` set (§6, good idea — avoids Torvalds' one-RTT-per-blob storm),
  note cosockets speak HTTP/1-style by default; for HTTP/2 upstream you'll lean on nginx's own
  upstream/`proxy_pass` (which `ngx.exec` to an internal proxied location handles cleanly)
  rather than hand-rolling h2 in Lua.

**The missing piece, and it's a Major one: request coalescing on a cold popular blob.** When a
hot-but-cold blob is requested by N concurrent clients, naive code fires **N identical origin
fetches** — a thundering herd / cache stampede that can melt the origin and waste bandwidth N×.
This is *the* classic OpenResty miss-path bug. You need **`lua-resty-lock`** (or
`lua-resty-mlcache`'s built-in lock, which *is* `lua-resty-lock`) so that the first request for
hash H acquires a lock, fetches, populates the cache + writes the file, and the other N−1
**wait on the lock and then read the now-warm cache** — one origin fetch, not N. For a monorepo
where a single popular file (a top-level `BUILD`/lockfile/header) is read by every CI job at
once, this is not optional; it's the difference between a calm origin and a self-inflicted DDoS.

Detail: `lua-resty-lock` is itself built on a `shared_dict`, so budget a small dedicated dict
for locks and remember the lock has a timeout — design the wait path to fall through to a direct
fetch (not error) if the lock holder is slow, to avoid correlated stalls.

---

### F5 — [Major] LuaJIT memory ceiling + GC: build GC64, keep the big working set out of the Lua heap

The doc flags this (§9.2). The facts:

- **The 2GB/1–4GB ceiling is real on non-GC64 LuaJIT.** Classic LuaJIT allocates the Lua heap
  in the low 2GB of the address space (a consequence of 32-bit-tagged pointers in the original
  design). On such a build, total Lua-managed memory (all your `lrucache` tables, decoded
  trees, closures, strings) is capped around ~1–2GB and you get `not enough memory` / allocator
  failures past it. **Mitigation #1, mandatory: build LuaJIT with `-DLUAJIT_ENABLE_GC64`
  (GC64 mode).** OpenResty's bundled LuaJIT (the `openresty/luajit2` fork) enables GC64 by
  default on 64-bit now — *verify your build* (`luajit -v`, check for GC64). GC64 removes the
  2GB cap (heap can use the full address space).
- **But GC64 does not remove GC pause pain.** LuaJIT's GC is a **non-generational, non-compacting
  incremental mark-and-sweep** (the long-promised new GC, "GC2/generational," never landed in
  mainline). With a **large live working set** — millions of small table nodes for cached trees
  — mark cost scales with live-object count, and you get **stop-the-world-ish incremental steps**
  that show up as p99/p999 latency spikes. This is the real ceiling, not the address space. A
  monorepo metadata cache held as **live Lua tables** is exactly the pathological case: lots of
  small, long-lived objects = expensive marking forever.

**Mitigations, in order of leverage:**
1. **Keep the bulk working set OUT of the Lua heap.** This is the big one and it's free given
   F2/F3: blobs go through `sendfile` (kernel/page cache, not Lua heap — already correct). Tree
   metadata in `shared_dict` lives in **shmem slabs, not the Lua GC heap** — so a large L2 cache
   does *not* add GC marking cost. The GC danger is only the **L1 lrucache** of decoded objects.
   Cap the lrucache element count aggressively; let L2 (shmem) be the big layer. Trade a bit of
   decode CPU for a small Lua heap and flat GC.
2. **For a truly large hot metadata set, consider an mmap'd external structure** (e.g., an
   mmap'd sorted/FST index of `(commit,path)→hash`, or `lua-resty-mlcache` over a big
   shared_dict) read via FFI — mmap pages are kernel-managed page cache, **invisible to the Lua
   GC**, and shared across workers for free. This is how I'd hold a monorepo-scale resolve index
   without ever pressuring the Lua heap.
3. **Tune the GC**: `collectgarbage("setpause", ...)` / step multiplier, or in newer
   OpenResty/luajit2 the `gc.opt`/`jit.opt` knobs; but tuning is a band-aid — the structural fix
   is #1.
4. **Shard by worker / by repo** if one process's live set is still too big.

Net: with GC64 + "big set in shmem/mmap, small set in lrucache," the memory story holds at
monorepo scale. Without that discipline — i.e., if you naively cache decoded trees as live Lua
tables to "make it fast" — you will hit GC-pause p99 cliffs well before you hit any QPS limit.
The doc's instinct to worry here is right; the mitigation is concrete and doesn't need a sidecar
for moderate scale.

---

### F6 — [Major] Partial-evaluating Datalog into LuaJIT: yes, but emit a *table*, not branchy code

§6 wants to specialize the landed ACL Datalog into "a concrete LuaJIT-friendly matcher (no
interpreter on the hot path)." Feasible — and the right idea — **but the naive realization
defeats the JIT the same way F1 does.** If "generate Lua" means emitting a big
`if prefix=="/a/b" then ... elseif ...` cascade or a generated recursive matcher, you get
exactly the megamorphic/branchy code LuaJIT traces poorly: long if/elseif chains don't trace
into a tight loop, and each rule edit reshuffles the branch predictor.

The ACL here is, per the §25/Norvig framing, **longest-prefix-match with deny-wins** — that is
*not* a search problem, it's a lookup. So generate **data, not control flow**:

- Build, at land time, a **prefix structure**: either (a) a hash map from each path-prefix to
  its decision keyed for direct lookup with a small fixed number of probes (walk the path
  components up the tree, ≤ depth lookups, each an O(1) `shared_dict`/`lrucache`/table get), or
  (b) a compact **trie / FST** serialized into an mmap'd blob and walked via FFI. Both are
  table-driven, allocation-free on the hot path, and **JIT-friendly because the inner loop is a
  fixed shape** (index, compare, descend) regardless of how many rules exist.
- The decision is then **cached** keyed by `(principal, path-prefix, acl-version)` (the doc's
  §6 plan — good), so steady state is one `lrucache`/`shared_dict` get and you rarely even run
  the matcher.

So: prove the Datalog at build time (decidable — agreed), **compile it to a lookup table, not
to generated branches**, differential-test the *table builder* against the Datalog oracle (the
doc's §7/§9.6 plan is right). The generator's output being *data* also sidesteps §9.6's
"generated code drift" worry partially: it's easier to fuzz a pure table than generated
control flow.

This is the same lesson as F1 in miniature: **the JIT-friendly thing is precomputed data +
fixed-shape hand-written walker; generated Lisp/branchy code is the JIT-hostile thing.**

---

### F7 — [Major, security/perf interaction] the X-Accel handoff and shared-cache key hygiene

Tied to the doc's §9.5 (Ptacek's lane) but there's a perf-relevant OpenResty angle:

- **`internal` is necessary but watch the resolve→exec gap.** The ACL is checked on
  `(principal, path)`, then you `ngx.exec` to `/cas/<hash>`. The invariant "you cannot reach a
  blob you weren't authorized for" depends on **resolve+authorize and the exec being one atomic
  decision in the same request** with no client influence on the hash between them. Since
  content addressing means a hash *is* the bytes, an attacker who can supply a hash directly
  (or poison the resolve cache) reads arbitrary blobs. So: never key any cache or any internal
  location on a client-supplied hash without having *first* proven the principal may read the
  `(commit,path)` that maps to it. The hash must be *derived* server-side from the authorized
  path, never accepted from the client.
- **`shared_dict` cache-key poisoning / multi-tenancy.** If decision cache keys are
  `(principal, path-prefix, acl-version)`, make sure `principal` is the *authenticated* identity
  (post-auth), not a header a client can spoof, and that `acl-version` is bumped atomically on
  policy land so you can never serve a decision computed under an old ruleset. A single global
  `shared_dict` shared across tenants is fine *if* the tenant id is part of every key; the
  failure mode is a missing tenant component in a key → cross-tenant decision reuse. Cheap to
  get right, catastrophic to get wrong.

Perf relevance: these are correctness constraints that *also* keep the cache effective — a
poisoned or under-keyed cache forces you to disable caching, which collapses the perf story.

---

### F8 — [Minor] consistency / `as-of` and the resolve cache (perf side of §9.4)

Not my primary lane (Aphyr's), but the OpenResty mechanics: the read tier holds a per-worker
`lrucache` + `shared_dict` resolve cache and lags the landed-log. Read-your-writes after a
client's own land requires the client's `as-of`/landed-seq cookie to be **≥** the seq the
serving worker has applied. Two OpenResty footguns:
- **Per-worker lag skew.** Different workers update their L1 lrucache at different times → the
  same client hitting worker A then worker B can go *backwards* in seq. If you promise
  monotonic reads, you must gate on the `shared_dict` (cross-worker) seq, or pin/await. A
  `lua-resty-lock`-guarded "wait until applied_seq ≥ requested_seq" (like LiteFS's proxy hold)
  is the pattern; budget a bounded wait + a 503/retry past timeout.
- This interacts with caching: you cannot cache a resolve result *across* an `acl-version` or
  `landed-seq` boundary without including it in the key — which you're already doing for ACL;
  do the same for resolve. Immutability makes the *blob* cache eternal, but the
  `(commit,path)→hash` *resolve* map is only immutable per commit; key it by commit/seq.

---

### F9 — [Minor] realistic numbers

Putting it together, on a single commodity box (say 16–32 cores, 10–25GbE), with the
*corrected* architecture (hand-written Lua dispatch over precomputed tables; lrucache L1 +
shared_dict/mlcache L2; sendfile + open_file_cache; coalesced misses):

- **Metadata decision path (resolve + ACL, all-cache-hit):** dominated by an `lrucache` get
  (tens of ns) + a couple of table ops. Realistically **100k–300k+ decisions/sec per box**,
  p99 well under a millisecond. The bottleneck at this point is **the `shared_dict` lock** (if
  you lean on L2 too often) and nginx request overhead, *not* the Lua logic. Keep hit rate in
  L1 high and the dict lock stays off the flame graph.
- **If instead you run real shen-lua generated code interpreted in `access_by_lua` (the
  un-fixed design):** I'd expect **single-digit to low-tens of thousands QPS** with much fatter
  p99 from GC, i.e., a **10×+ haircut** and a latency tail. That gap *is* F1.
- **Blob serve path:** bounded by NIC and disk/page-cache, not Lua. Warm blobs from
  `open_file_cache` + page cache → line-rate; you'll saturate 10–25GbE on payload long before
  CPU, *for cleartext*. **TLS-terminated edge without kTLS:** CPU-bound on encryption, plan for
  it (this, not Lua, becomes the edge bottleneck — F3). Large blobs via `aio threads` keep the
  worker responsive but add latency for that request.
- **Cold-miss path:** one RTT to origin + transfer (the §4 budget is right) **provided you
  coalesce** (F4); without coalescing, a popular cold blob's tail explodes under concurrency.

So the read tier can absolutely be fast — *as a dispatcher*. The real bottlenecks, in the order
you'll meet them: (1) whether real Shen-Lua is on the hot path (F1), (2) `shared_dict` lock if
L1 hit rate is poor (F2), (3) TLS-edge CPU for payload (F3), (4) GC p99 if the live Lua heap is
big (F5). None of those is the network or "Lua being slow" in the abstract.

---

## What the doc gets right (so it's on the record)

- **The "brain decides / nginx serves" split is the correct structural choice.** Keeping bytes
  out of the Lua VM is exactly right and is what makes blob size irrelevant to the VM. (§3)
- **Content addressing ⇒ no cache invalidation** is genuinely the killer property — it removes
  the single hardest thing about caching and makes `open_file_cache`, edge `immutable`, and a
  multi-tier cache safe by construction. (§3.1)
- **The EdenFS / Mononoke shape** (fast source-of-truth service + thin caching mount) is the
  honest, proven topology; OpenResty is a very good fit for the *service* half. (§4)
- **Read tier stateless & scale-out, write tier serialized** is right and plays to OpenResty's
  strengths (shared-nothing workers, add boxes for read QPS). (§5)
- **Batching the `want` set over HTTP/2** to avoid one-RTT-per-blob is the correct fix for the
  fan-out storm. (§6)
- **Caching the ACL decision keyed by `(principal, prefix, acl-version)`** is the right
  steady-state design. (§6)

## What to change in the doc

1. Rewrite §1/§9.1: drop "compiled Lua executing on LuaJIT — near-native" as the claim. Replace
   with: *the Shen-derived logic runs at land/compile time to emit lookup tables + a specialized
   matcher; the request hot path is hand-written idiomatic Lua over precomputed data.* Add the
   `jit.dump`/`-jp` measurement spike as a **gating** task, like S1 in doc 25.
2. §3.1/§6: specify the cache as **`lua-resty-mlcache` (L1 `lua-resty-lrucache` + L2
   `lua_shared_dict`)**, not raw `shared_dict`. State the serialize-on-every-access and
   single-lock facts.
3. §6: change "partial-evaluate Datalog into generated Lua" to "into a **table/trie**, walked by
   a fixed-shape hand-written matcher" — emit data, not branches.
4. §6: add **`lua-resty-lock`-based request coalescing** to the cosocket miss path explicitly.
5. §9.2: mandate a **GC64 LuaJIT build** and the "big set in shmem/mmap, small set in lrucache"
   discipline; note the GC is non-generational mark-sweep and the real risk is p99 pauses, not
   the address-space cap.
6. §3: qualify "zero-copy" — true for cleartext/internal hop; **needs kTLS** to hold at the TLS
   edge; add size-gated `aio threads`+`directio` for large blobs and the `internal` directive
   requirement.

---

## Bottom line

The architecture is sound *if you accept that the OpenResty tier is a precompiled-data dispatch
plane, not a place where Shen-generated code executes per request.* Made that way, it's fast,
it scales out, and content addressing makes the caching honest. Left as written — with
generated Shen-Lua assumed to JIT near-native in `access_by_lua` — the perf story does not hold,
because that code will run in the LuaJIT interpreter with GC pressure, not as a trace-compiled
near-native kernel.

**Conditional yes.** Single biggest risk: **shen-lua's generated code does not JIT — measure it
with `jit.dump`/`-jp` before you build anything else, and move the Shen runtime to build/land
time so the hot path is plain Lua over lookup tables.**
