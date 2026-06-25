---
date: 2026-06-25
reviewer: "Eitaro Fukamachi (persona)"
status: review
topic: "Common Lisp / SBCL implementation-reality review of metavfs (00-architecture.md)"
target: thoughts/shared/plans/dvcs-vfs/00-architecture.md
tags: [review, common-lisp, sbcl, ffi, concurrency, performance, packaging, nfs, raft, lmdb, ironclad, content-store]
---

# CL-implementation review of `metavfs`

## Verdict

This is **implementable in Common Lisp by a competent team**, and most of the spine (CAS,
manifest, land FSM, ACL-as-data, even Raft) is squarely within what the ecosystem and SBCL
can do today — Raft has been written in CL before (`cl-raft`, `cl-paxos`-class toys), LMDB
has a working binding that the substrate already depends on, ironclad SHA-256 is real, and
the land queue is honestly just a state machine over the EAV store. **The real CL risk is
not the consensus algorithm — Aphyr already owns that lane — it is three concrete things:**
(1) the **userspace NFSv3 server in §7.3 is a multi-person-quarter subproject that requires
hand-writing ONC-RPC + XDR + portmapper + MOUNT because none of those exist as a usable CL
library**; (2) the **substrate's single global `store-lock`** (`store.lisp:22`, held by
*every* `transact!` and *every* `take!`) is a hard serialization point that a VFS doing
thousands of concurrent metadata reads against the same store the land worker writes will
turn into a contention wall — the design's "thousands of concurrent RPCs" and the
substrate's one mutex are on a collision course; and (3) the **hot paths allocate like
crazy** — whole-file `(unsigned-byte 8)` reads, hex-string blob keys in an `equal`
hash-table, and recursive plist/sexpr manifests — which on SBCL means GC pressure and
heap blowup at monorepo scale unless they reach for `static-vectors`/`fast-io`/specialized
arrays and stop keying CAS by hex strings. None of these need *new* libraries except the
NFS stack; they need the team to use the *right existing* ones and to not fight SBCL's GC.
Below, the blockers and significant items with concrete library/technique fixes.

---

## Findings

### 1. [Blocker] The userspace NFSv3 server (§7.3, §10.4, P6) is a from-scratch ONC-RPC/XDR/MOUNT/portmapper stack — there is no CL library for any layer of it

**Concern.** §7.3 recommends "NFSv3 loopback server in SBCL" as the *realistic* mount path
and frames it as lower-risk than FUSE. As someone who wrote a production HTTP server in CL
(Woo) on libev: NFS is dramatically harder to bring up than HTTP, and the CL ecosystem
gives you **nothing** for it. To serve NFSv3 you must implement, in order:

- **ONC RPC (RFC 5531)** — the Sun RPC framing, including record-marking over TCP, auth
  flavors (at least `AUTH_UNIX`), call/reply discrimination, program/version/proc dispatch.
  There is **no maintained CL ONC-RPC library**. (`cl-rpc`-ish things are abandoned/non-existent.)
- **XDR (RFC 4506)** — the External Data Representation codec for every NFS struct. There is
  **no CL XDR library worth using.** You will hand-roll big-endian fixed-width
  encode/decode for `fhandle3`, `fattr3`, `sattr3`, `nfs_fh3`, `entryplus3`, `READDIRPLUS`
  cookies, etc. This is exactly the kind of fiddly byte work the substrate already half-does
  by hand (`decode-u64-be`/`decode-u32-be` in `lmdb-backend.lisp:225-239`) — multiply that
  by the entire NFSv3 + MOUNT (RFC 1813) struct catalog.
- **portmapper / rpcbind (program 100000)** *or* a fixed-port + `mount -o port=...` dance —
  on Linux you'll either run your own rpcbind responder or bypass it; either way it's more
  protocol surface.
- **MOUNT protocol (program 100005)** — `MNT`/`UMNT`/`EXPORT`, handing out the root file
  handle.
- The **`mount(2)` side**: `mount -t nfs -o vers=3,tcp,port=N,mountport=M,nolock localhost:/ ...`
  needs root or a configured `fstab`/autofs entry; getting attribute-cache coherence
  (`acregmin`/`acdirmin`) right so the kernel doesn't serve stale `GETATTR` is its own tuning
  exercise.

Then **under concurrency** (the design's whole point): `READDIRPLUS` on a million-entry
directory, stable `READDIR` cookies across manifest changes, `GETATTR` storms during a
`find`, file-handle stability across re-mounts (a NFS file handle must be stable and
opaque — you need a persistent fh↔manifest-path mapping, not just "hash the path"), and
NFSv3's stateless model fighting your lazy-fetch latency. EdenFS's NFS backend is a large
C++ effort by Meta; "we'll do it in Lisp in P6" undersells it by an order of magnitude.

**CL-specific reasoning.** The socket layer is the *easy* part and you have good options
(below). The problem is 100% protocol implementation with zero library leverage, plus
SBCL FFI is *not* even involved (NFS is pure userspace sockets) — so the one thing CL is
good at here (no FFI) doesn't save you, because the work is XDR/RPC plumbing, not FFI.

**Recommendation.**
- **Keep the Phase-1 no-mount checkout (P5) and treat the mount as genuinely optional / R&D.**
  The doc already does this in §7.3's "Phase-1 fallback" and §10.4 — *good* — but the
  roadmap should be even blunter: P6 is a research project, not a feature with a date.
- For the socket layer when you do attempt it, **do not use Woo/libev** — Woo is an HTTP
  server, not a generic RPC reactor, and bending it to NFS framing buys nothing. Use
  **`usocket`** for portable TCP, or **`sb-bsd-sockets`** directly if you want UDP + control;
  for a high-concurrency event loop reuse the pattern from **`cl-async`/`libuv`** or
  **`iolib`** (which gives you proper non-blocking sockets and an event loop and is the
  closest thing CL has to "do real network servers"). I'd reach for **iolib** here precisely
  because it also gives you `isys` syscall access for the `mount`/`stat` boundary.
- **Reconsider FUSE-via-FFI honestly.** The doc claims NFS is *less* risky than FUSE. That's
  half-true: **`cl-fuse`** exists (Tomas Hlavaty / others) and `cl-fuse-meta-fs` on top of it,
  but it is **lightly maintained and binds the high-level libfuse callback API**, which means
  the C library runs the event loop and calls *into* SBCL on its own threads — and that is
  the actual FFI/GC hazard (callbacks from foreign threads must be SBCL threads or you crash;
  see Finding 8). My honest take: **FUSE is less *code* (libfuse does RPC/dispatch for you)
  but more *FFI/GC risk*; NFS is more *code* but no FFI/GC risk.** The doc picks the
  no-FFI-but-huge-code path; that's defensible, but call it what it is — neither is cheap, and
  "NFS is the safe choice" is too strong. If you want a mount in months not years, a
  **9P (Plan 9 filesystem protocol) server** is far simpler than NFS (tiny message set,
  trivial to encode, Linux mounts it via `mount -t 9p`/`v9fs`), and is the path I'd actually
  recommend over both — it's the EdenFS-class lazy-FS protocol with a fraction of NFS's
  surface and no FFI.

### 2. [Blocker] The substrate's single global `store-lock` serializes all reads and writes — the VFS-vs-land-worker concurrency story does not survive contact with `store.lisp`

**Concern.** §2/§5.3 imagine a VFS server handling "thousands of concurrent RPCs" doing
manifest/attr lookups against the substrate, *concurrently with* the land worker writing
`:change`/`:trunk` entities. But `transact!` takes `(store-lock store)` for the entire
write critical section (`store.lisp:154`), and — worse for a read-heavy VFS — **`take!`
also grabs the same `store-lock`** (`linda.lisp:49`) for its whole body. Every land-job
claim, every status transition, every `:change` write contends on **one** `bt:make-lock`.

There is a subtler trap: the design routes durable land-job status through `transact!`
(per the roadmap G0-1) *instead of* `take!` — good for durability — but that means each
status transition now does the **full** `transact!` path including the LMDB write
(`lmdb-transact!`, `store.lisp:181`) **inside the lock**. So the global lock is now held
across an LMDB `with-txn (:write t)` + fsync. Under load, that's a global stop-the-world on
the substrate for the duration of a disk sync, while VFS metadata readers pile up behind it.

**CL-specific reasoning.** Reads in this store are mostly lock-free *as written* —
`entity-attr`/`find-entities` read the entity-cache/value-index hash-tables without taking
`store-lock` — which is great for VFS read throughput but is **only safe because writers
hold the lock and SBCL hash-tables aren't safe under concurrent rehash**. If a `transact!`
grows a hash-table (rehash) while a VFS reader is mid-`gethash`, you can get corrupted reads
or a crash. SBCL's `make-hash-table :synchronized t` exists but the substrate doesn't use it.
So today you have *fast but unsynchronized* reads racing a *globally-locked* writer. That's a
latent data race the moment the VFS reads the same store the land worker writes.

**Recommendation.**
- **Separate the read store from the write store.** The RSM is the authority; the substrate
  is "the queryable projection" (the doc's own words, §5.2). Lean into that: the VFS should
  read from an **immutable snapshot of the projection** (an `fset` pmap — you already depend
  on `fset`), swapped atomically by the land worker after each commit. Readers hold a
  reference to an immutable map and never touch the live store at all → genuinely lock-free,
  GC-safe reads, no rehash race. This is the standard Clojure-style "atom holding a persistent
  map" pattern and `fset` is exactly the tool.
- For the substrate writes that *must* go through `transact!`, **get the LMDB write off the
  global lock.** The lock should protect the in-memory index update; the LMDB durability
  write can be done by a single dedicated writer thread draining a queue (one fsync amortized
  over a batch — you already have `with-batch-transaction`, `store.lisp:201`, use it). Holding
  `store-lock` across an fsync is the contention bug; batching + a writer thread fixes it.
- If you keep reading the live store, **make the hot hash-tables `:synchronized t`** or accept
  and document the writer-exclusivity invariant and never read mid-write. Don't leave it
  implicit.

### 3. [Blocker] The capture-and-rebind dynamic-var pattern will not scale to a multi-threaded Raft node and will silently break in subtle ways

**Concern.** CLAUDE.md and `conductor.lisp:342-349` establish the house pattern: threads do
not inherit `with-store` bindings, so every spawned thread must capture
`autopoiesis.substrate:*substrate*` and `*store*` and rebind them. A Raft node is not one
tick thread — it's an election-timer thread, a per-peer `AppendEntries` sender, an apply
thread, the land worker, the VFS server's connection threads, plus whatever the blob
gossip plane uses. **Every one** of these must correctly capture and rebind `*substrate*`,
`*store*`, `*entity-cache*`, `*value-index*`, `*intern-table*`, `*resolve-table*`,
`*next-entity-id*`, `*next-attribute-id*` (the full set `with-store` binds,
`store.lisp:264-272`). Miss one in one thread and you get a thread reading a *different*
(or `nil`) store — and because reads are lock-free and silent, the failure mode is
**wrong data, not an error**.

**CL-specific reasoning.** Dynamic variables are per-thread in SBCL; this is correct CL but
it's a footgun multiplier in a many-threaded subsystem. The substrate already papered over
"7 individual variable captures" with a single `*substrate*` context capture
(`conductor.lisp` comment) — that consolidation is the right instinct but it's *convention*,
not *enforcement*. A Raft implementation with a dozen thread entry points will reintroduce the
bug per entry point.

**Recommendation.**
- **Make the capture a single macro and forbid raw `bt:make-thread` in the new packages.**
  Provide `(with-substrate-thread (...) body)` (or extend the existing context object) that
  captures the *one* `*substrate*` context (everything else hangs off it via
  `substrate-context-*`) and rebinds it in the new thread. The codebase already proved one
  capture suffices; enforce it.
- Better: **pass the store explicitly** instead of via specials wherever the new code can.
  `transact!`, `take!`, `find-entities` all accept `:store`/read from `*store*` — thread the
  store as an argument through the Raft/land code and you sidestep the dynamic-binding
  inheritance problem entirely. Specials are convenient for a REPL session; for a server with
  N worker threads, explicit is safer.
- Use **`bordeaux-threads`** for the threads themselves (already a dep, portable), but do not
  hand-roll a thread-per-connection model for the VFS — use **`lparallel`** (already a dep) or
  a bounded `bt-semaphore`-gated pool. Thread-per-RPC against a one-lock substrate is the
  worst case.

### 4. [Significant] Blob CAS keyed by hex strings in an `equal` hash-table is a memory and GC problem at monorepo scale

**Concern.** `content-store.lisp` stores blobs in `(make-hash-table :test 'equal)` keyed by
the **hex string** from `byte-array-to-hex-string` (`:83`), and S-exprs in another `equal`
table keyed by `sexpr-hash` strings. At millions of files:
- Each key is a **64-character string** (256-bit hash as hex) = a freshly-allocated CL string
  object (~80+ bytes with header) per blob, vs. 32 raw bytes. You're paying 2x the bytes plus
  an object header plus pointer-chasing, for *every* blob and *every* manifest node, forever
  resident.
- `equal` on strings is a full `char=` scan; `sxhash` on a 64-char string hashes all 64 chars.
  Compared to keying by the 32-byte vector, you do more work per lookup and the table is bigger.
- The store is **entirely in-memory** (`store-blobs` is a hash-table, no LMDB) — §10.5 admits
  the LMDB blob DB is unbuilt. So at monorepo scale you're holding every blob's *bytes* plus
  hex keys in the SBCL heap → multi-GB heap → long GC pauses (relevant to Aphyr's lease-read
  Finding 4, which depends on bounding `max_pause`).

**CL-specific reasoning.** SBCL's GC is generational but a giant live `equal` hash-table full
of byte-vectors and strings is exactly the kind of large old-generation set that makes full
GCs expensive. Hex-string keys are pure waste: ironclad gives you the raw digest
(`produce-digest` returns a `(simple-array (unsigned-byte 8) (32))`) and *you* convert it to
hex (`byte-array-to-hex-string`); you can just... not.

**Recommendation.**
- **Key the CAS by the raw 32-byte digest, not hex.** Use `(make-hash-table :test 'equalp)`
  (equalp compares arrays element-wise) or, better, a custom hashing keyed by the integer form
  of the digest (`ironclad:octets-to-integer`) which gives you `eql`-hashable fixnum-ish keys
  and the fastest possible table. Reserve hex strings for the *wire/UI boundary* only. This
  halves key memory and speeds every lookup. (Manifest entries can still carry hex for
  human-readability if you want, but the in-memory index should not.)
- **Get blob bytes out of the heap.** Back the blob store with LMDB (the binding is already a
  dep, and `lmdb-backend.lisp` already opens a `"blobs"` db, `:50`) so blob bytes live in
  mmap'd pages, not the SBCL heap — LMDB's `MDB_val` is a zero-copy pointer into the mmap, and
  the **`lmdb`** binding exposes the value as octets; you read on demand and let the OS page
  cache do its job. This is the single biggest GC-pressure win and it's mostly wiring, not new
  code.
- For large blobs, read with **`static-vectors`** (foreign-allocated `(unsigned-byte 8)` that
  the GC never moves/scans) and SHA them with **ironclad's `update-digest` on the
  static-vector** — keeps multi-MB file buffers off the GC's plate entirely.

### 5. [Significant] ironclad SHA-256 is fine for correctness but will be a throughput bottleneck on a monorepo; plan the libcrypto escape hatch

**Concern.** `blob-hash` (`content-store.lisp:79`) and `tree-hash` (`filesystem-tree.lisp:224`)
use pure-CL ironclad SHA-256. ironclad is correct and pure-Lisp-portable, but it is **several
times slower than OpenSSL's SHA-256** (which uses SHA-NI CPU instructions ironclad can't reach).
Hashing every byte of a multi-million-file monorepo on initial scan, and re-hashing on every
land, is CPU-bound, and ironclad will be the bottleneck of the scan/land path.

**CL-specific reasoning.** This is a known ironclad limitation — it's a from-scratch CL crypto
lib with no assembly/intrinsics. For content-addressing throughput you want hardware SHA.

**Recommendation.**
- **Make the hash function pluggable and add an FFI path to libcrypto** (`EVP_DigestInit_ex`
  / `EVP_DigestUpdate` / `EVP_DigestFinal_ex` via **`cl-plus-c`/`cffi`**, or reuse an existing
  binding like **`ironclad` only for the fallback**). The proxy environment note in this repo
  ships a CA bundle, so OpenSSL is present; binding the EVP SHA-256 is ~30 lines of CFFI and
  buys SHA-NI. Keep ironclad as the no-FFI fallback so the build still works without libcrypto.
- **Hash with `static-vectors` buffers** (Finding 4) so the FFI call to libcrypto can pass a
  stable foreign pointer with zero copy.
- **Don't re-hash whole trees.** `tree-hash` over a flat entry list rehashes everything on any
  change (the doc flags this in §3.2). The recursive manifest fixes the *structure*, but make
  sure the implementation only hashes *changed* subtree nodes and reuses child-node hashes by
  reference — that's the whole point of the Merkle manifest and it's where the real CPU savings
  are, more than the SHA implementation.

### 6. [Significant] Manifest-as-plist/sexpr is convenient but will cons heavily; consider structs for the hot manifest nodes

**Concern.** The tree-entry format is a plist (`filesystem-tree.lisp:18-26`,
`(:file "path" :hash ... :mode ... :size ... :mtime ...)`) and the proposed manifest-node is
a nested sexpr (§3.2). Every accessor (`entry-hash`, `entry-mode`, etc.) does `getf` — a linear
scan of the plist. Building/walking a recursive manifest for millions of files means allocating
millions of small lists and doing `getf` scans on the hot path (conflict detection, sparse
fetch, VFS `READDIR`).

**CL-specific reasoning.** plists are great for serialization and human-readability and terrible
for hot-path access: `getf` is O(n) over the plist, and each entry is several cons cells the GC
must trace. For a structure walked on every directory listing, `defstruct` (or even
`(simple-array t)` slots) gives you O(1) slot access, packed storage, and far fewer GC roots.
The doc's "reuse the sexpr format verbatim" is the right call for the *serialized/CAS* form but
the wrong call for the *in-memory traversal* form.

**Recommendation.**
- **Two representations: sexpr for CAS/wire (hash-stable, the doc's format), `defstruct` for
  in-memory manifest nodes** decoded on read and cached in the LRU (`lru-cache.lisp`). Decode
  the plist into a `(defstruct manifest-entry type path hash mode size)` once on fetch, walk
  the struct. This keeps the content-addressed format stable (don't change what you hash) while
  making traversal cheap.
- Reusing the **snapshot CLOS class** for `landed-change` (§3.3) is *reasonable* — CLOS slot
  access is fine, snapshots aren't the per-file hot path. But the *manifest entries* under it
  should be structs, not CLOS instances (CLOS instance allocation + slot access is heavier than
  `defstruct`; at millions of entries that matters).
- Watch the canonical-string hashing: `canonical-entry-string` (`:237`) `format`s every entry
  through `format nil "F:~A:~A:~D:~D"` — `format` is slow and conses. For the hot manifest hash,
  write the bytes directly with **`fast-io`** (`fast-write-byte`/`fast-write-sequence` into a
  reusable buffer) instead of `format` + `babel:string-to-octets`. This is the same trick Woo/
  Jonathan use to avoid `format` on hot paths.

### 7. [Significant] Serialization via `prin1-to-string`/`read-from-string` (the substrate's current approach) is unsafe and slow for the Raft log and manifests — pick a real codec

**Concern.** The substrate persists values with `serialize-value` =
`babel:string-to-octets(prin1-to-string value)` and reads them back with `read-from-string`
(`lmdb-backend.lisp:216-223`). For the Raft log + manifest round-tripping the design needs, this
is a problem on three axes:
- **Safety:** `read-from-string` with default `*read-eval*`/`*readtable*` is a code-execution
  and resource hazard on any data that crosses a trust boundary (a peer's `AppendEntries`, a
  client's submission). A malicious or buggy peer can feed `#.(...)` or intern unbounded symbols.
- **Speed/size:** `prin1`/`read` is slow and verbose vs. a binary codec; the Raft log is
  append-heavy and you'll want compact, fast frames.
- **Determinism:** the doc requires apply to be a pure function of the log and manifest hashes to
  be canonical; `prin1` output is not guaranteed canonical across implementations/settings
  (float printing, package qualification, `*print-circle*`).

**CL-specific reasoning.** This is squarely my territory. Options, ranked for *this* use:
- **`cl-conspack`** (CONS-pack) — binary, schema-less, handles CL data (symbols, structs via
  refs), fast, canonical-ish. My first pick for the **manifest CAS form and the Raft log
  entries** because it round-trips Lisp data without `read-eval` and is compact.
- **`cl-messagepack` / `messagepack`** — if you want a cross-language-friendly wire (you might,
  for ops tooling), MessagePack is fast and well-specified; good for **Raft RPC frames**.
- **`jsown` / `jonathan`** — only if you need JSON (you mostly don't here); `cl-json` (current
  dep) is the slow one — do **not** put `cl-json` on the Raft hot path.
- If you insist on sexprs for readability, **read with `*read-eval*` bound to `nil` and a
  locked-down readtable, and `with-standard-io-syntax`** for canonical printing — but I'd still
  use conspack for anything performance- or trust-sensitive.

**Recommendation.** **Manifest CAS bytes and Raft log entries → `cl-conspack`** (binary,
canonical, no read-eval); **Raft peer RPC frames → `cl-messagepack`** if you want
language-neutral ops, else conspack again. **Never** `read-from-string` a peer's or client's
bytes with `*read-eval*` on. Close the `persistence.lisp:69` tree-field gap by serializing the
manifest with conspack, not by extending the `prin1` serializer.

### 8. [Significant] FFI/foreign-thread realities if FUSE is ever chosen; and `cl-lmdb` fsync semantics need verification for Aphyr's Finding 10

**Concern (FUSE half).** If P6 ever goes FUSE instead of NFS/9P: libfuse runs its own event
loop and invokes your callbacks from **foreign threads it spawns**. SBCL callbacks invoked from
a thread SBCL didn't create will crash or corrupt unless that thread is registered with the SBCL
runtime. The high-level `cl-fuse` API hides the loop, which is convenient until a GC happens
during a callback on a foreign thread.

**Concern (LMDB half — the durability one Aphyr flagged).** The Raft log and blob durability
ride on the **`lmdb`** binding (Fernando Borretti's `cl-lmdb`, the `lmdb:` package the substrate
uses). Aphyr's Finding 10 demands fsync-before-ack. LMDB *by default* is durable (it fsyncs on
commit), **but**: (a) `MDB_NOSYNC`/`MDB_NOMETASYNC`/`MDB_WRITEMAP` flags disable that, and the
binding's `open-env` here (`lmdb-backend.lisp:28`) doesn't pass them, so default-durable — good,
but the team must **never** flip those for "speed" on the Raft log; (b) the binding wraps the C
library via CFFI, and you must confirm the binding actually surfaces a durable commit (no
`MDB_NOSYNC`) and that `with-txn (:write t)` does a real `mdb_txn_commit` per the durability you
think. (c) LMDB's single-writer model means **one writer txn at a time per env** — which
*reinforces* Finding 2: the Raft log writer and the substrate projection writer contend at the
LMDB level too, not just the CL lock.

**CL-specific reasoning.** This is the FFI boundary where "it works in the REPL" and "it survives
power loss / fuzzing" diverge. The binding is real and used, but its durability contract is the
load-bearing assumption of the entire fault model and nobody has stated they verified it.

**Recommendation.**
- **If FUSE: bind low-level libfuse (`fuse_session_loop`) yourself via CFFI and pump the loop
  from an SBCL-created thread**, or register foreign threads — don't trust the high-level
  `cl-fuse` callback model for a server. Honestly: **prefer 9P (Finding 1) and avoid FUSE FFI
  entirely.**
- **For LMDB: write a power-loss test** (kill -9 mid-commit, reopen, assert committed entries
  present) against the `lmdb` binding before trusting it for the Raft log. Pin the binding
  version in Qlot (Finding 9). Consider a **dedicated LMDB env for the Raft log** separate from
  the substrate projection env, so the single-writer-per-env constraint doesn't make the log and
  projection serialize against each other. If `cl-lmdb`'s durability proves shaky, the fallback
  is a simple **append-only WAL written with `fast-io` + explicit `sb-posix:fsync`** — that's
  ~100 lines and gives you exact control over fsync-before-ack, which is what Raft actually
  needs. (SBCL gives you `sb-posix:fsync` directly; you do not need a library for the WAL.)

### 9. [Significant] Packaging: Shen/shen-cl is a bootstrap-not-ASDF deployment liability; pin everything with Qlot

**Concern.** `bridge.lisp` loads shen-cl **lazily at runtime** by `load`ing a `boot.lsp`/
`install.lsp` it hunts for across `~/shen-cl/`, `vendor/`, `/usr/local/share/`, Quicklisp
local-projects (`find-shen-install`, `:38-68`), and the comment warns boot.lsp *calls
`save-lisp-and-die`*. This is **not** an ASDF/Quicklisp-installable dependency; it's a
side-loaded interpreter with global mutable state behind a single lock. Pulling that into a
**production** consensus system's build is a real liability: non-reproducible builds (it depends
on a file existing in one of N paths), a runtime `load` that can warn/partially-fail
(`:98-103` swallows load errors), and the `*shen-lock*` global serialization Aphyr's Finding 9
already flagged for the control plane.

The new packages (`packages/raft`, `packages/metavfs`) plus their deps (an RPC codec, possibly
iolib/usocket, possibly cffi+libcrypto, the lmdb binding) need **reproducible pinning**.

**CL-specific reasoning.** Quicklisp's monthly dist is fine for libraries but a production server
wants exact pins. This is what Qlot is for, and it's the only sane way to pin a hairy set
including a non-Quicklisp thing like shen-cl.

**Recommendation.**
- **Adopt Qlot.** Add a `qlfile`/`qlfile.lock` at the repo root pinning every dep (including
  `lmdb`, `iolib`/`usocket`, `cl-conspack`/`cl-messagepack`, `cffi`, and the existing set) to
  exact versions/SHAs. This makes the build reproducible and CI-able, which a consensus system
  must be.
- **Get Shen off the production critical path.** The roadmap (G1-9) already says apply never
  calls Shen and the hot path uses substrate **Datalog** (`datalog.lisp`/`rules.lisp:71`,
  terminating, lock-free, *already a dep, already in the substrate*). Take that further:
  **make Shen an optional, dev-only authoring tool**, not a runtime dependency of `packages/raft`
  or `packages/metavfs`. Compile ACL rules to Datalog (or plain CL closures) at rule-load time,
  off the lock, and ship the *compiled* rules. Then shen-cl never has to load in production and
  the `find-shen-install`/`save-lisp-and-die` fragility never touches a running node. If Shen
  *must* ship, **vendor a pinned shen-cl and load it at build time** (bake it into the image),
  never hunt-and-`load` at runtime.

### 10. [Minor] `take!` is unordered AND non-durable — the design already knows, but the CL fix is to stop using it for the land queue entirely

**Concern.** §4.3 notes `take!` is unordered and the leader must sort-then-select. Combined with
`take!` bypassing hooks/LMDB (`linda.lisp:39` mutates cache + value-index under `store-lock` but
never calls the hook/LMDB path that `transact!` does), `take!` is a fast intra-process claim with
no durability. The roadmap correctly demotes it to a scheduling hint.

**CL-specific reasoning.** `take!` is a nice Linda primitive for ephemeral in-process work
(it's literally the conductor's event-claim, `conductor.lisp:153`), but it is the wrong tool for
a cluster-durable land queue. Using it *at all* in the land path invites someone to depend on its
(absent) durability.

**Recommendation.** In the new land code, **don't call `take!`**. Select the head job with an
ordinary indexed read and claim it with a durable `transact!` status flip (which goes through
LMDB). Keep `take!` for what it's good at (in-process ephemeral coordination) and keep it out of
the durable land FSM entirely, so the two-authorities problem (Aphyr Finding 1) can't sneak back
in via a `take!` call.

### 11. [Polish] Reuse `lparallel` for the blob/scan fan-out; don't write a thread pool

**Concern/Recommendation.** The initial monorepo scan (hash millions of files) and blob
replication fan-out are embarrassingly parallel and CPU/IO-bound. You already depend on
**`lparallel`** — use `pmap`/`ptree` for the scan (parallel SHA across files) and a `lparallel`
kernel for blob push/pull fan-out, rather than hand-rolling `bt:make-thread` pools. Bound the
kernel size to core count to avoid oversubscribing the (Finding 5) hash CPU. One caveat: capture
the `*substrate*` context into the lparallel workers (Finding 3) — lparallel worker threads also
don't inherit your dynamic bindings.

---

## Use these libraries / patterns (cheat-sheet)

| Need | Use | Notes |
|---|---|---|
| **CAS in-memory key** | raw 32-byte digest via `equalp` table or `octets-to-integer` + `eql` | **not** 64-char hex strings — halves memory, faster lookup |
| **Blob bytes at scale** | **`lmdb`** (already a dep; `"blobs"` db already opened) | mmap'd, off the SBCL heap; biggest GC win |
| **Large file buffers / hashing** | **`static-vectors`** | foreign, GC-immovable; pass straight to FFI SHA |
| **Fast SHA-256** | **`cffi`** → libcrypto `EVP_*` (SHA-NI); **`ironclad`** fallback | pluggable; ironclad correct but slow |
| **Hot-path byte writing** | **`fast-io`** (`fast-write-sequence`) | replace `format`/`babel` in `canonical-entry-string` |
| **Manifest CAS + Raft log codec** | **`cl-conspack`** | binary, canonical, no `read-eval`; close `persistence.lisp:69` with this |
| **Cross-language RPC frames** | **`cl-messagepack`** | if ops tooling wants a neutral wire; else conspack |
| **Never** | `cl-json` on hot path; `read-from-string` on untrusted bytes | slow / RCE-shaped |
| **Sockets / event loop (RPC, 9P, NFS)** | **`iolib`** (non-blocking + `isys` syscalls), or **`usocket`** for simple TCP | **not** Woo — it's HTTP-specific |
| **Mount protocol** | **9P** (tiny, `mount -t 9p`) > NFSv3 (huge) > FUSE (FFI risk) | hand-write XDR only if you truly commit to NFS |
| **WAL / fsync** | `fast-io` + **`sb-posix:fsync`** | exact fsync-before-ack control if `cl-lmdb` durability is shaky |
| **Parallel scan / blob fan-out** | **`lparallel`** (already a dep) `pmap` + bounded kernel | capture `*substrate*` into workers |
| **Thread-local store binding** | one `with-substrate-thread` macro capturing `*substrate*` | enforce; forbid raw `bt:make-thread` in new pkgs |
| **Lock-free VFS reads** | **`fset`** pmap snapshot, atomically swapped per land | already a dep; avoids the global `store-lock` and rehash race |
| **Dependency pinning** | **Qlot** (`qlfile.lock`) | pin lmdb, iolib, conspack, cffi, shen-cl-if-any |
| **Rules engine (hot path)** | substrate **Datalog** (`rules.lisp:71`) | already a dep, lock-free, terminating; keep Shen dev-only |

---

## Realistic CL effort — gut check on the riskiest phases

- **P0 (recursive manifest + CAS round-trip): weeks, low risk.** This is the part CL is *good*
  at. The only real work is (a) the recursive Merkle manifest and (b) wiring blobs+manifests
  through LMDB with a real codec (conspack), closing `persistence.lisp:69`. Use structs for
  in-memory nodes, conspack for CAS bytes, raw-digest keys. Genuinely a solid, shippable
  foundation. Do this first, as planned.

- **P1 (linear trunk + land FSM, single-node): weeks, low–medium risk.** It's a state machine
  over the EAV store. The CL traps are all in Finding 2/3/10: keep durable status flips on
  `transact!` (not `take!`), watch the global lock, capture dynamic vars. No new libraries.

- **P3 (Raft transport + durable log): 2–4 months, medium risk — but bounded.** Raft itself is
  well-trodden and *has* been done in CL; it's a lot of careful code, not a research problem.
  The CL-specific risks are: (a) **RPC transport** — use `usocket`/`iolib` + `cl-messagepack`/
  conspack frames, don't reach for dexador (dexador is an HTTP *client*; Raft is not HTTP — if
  you want HTTP transport you'd pair Woo server + dexador client, but a raw socket + length-
  prefixed conspack frame is simpler and faster and what I'd do); (b) **log durability** — verify
  `cl-lmdb` fsync or write a `sb-posix:fsync` WAL (Finding 8), this is the load-bearing bit;
  (c) **thread hygiene** across the many Raft threads (Finding 3). All tractable. The Jepsen-
  style test suite the roadmap mandates is the right gate and is itself writable in CL with the
  existing `fiveam` + a partition/crash nemesis.

- **P6 (NFS mount): person-quarters to person-year, HIGH risk — this is the real rabbit hole.**
  Hand-writing ONC-RPC + XDR + MOUNT + portmapper + concurrent READDIRPLUS with stable file
  handles, in a language with **zero** library support for any of those layers, is a multi-quarter
  effort and arguably a multi-person-year one if you want it correct and performant under load.
  **De-risk exactly as the doc says — ship the no-mount checkout (P5) first** — and then, if a
  mount is truly required, **build a 9P server, not NFS.** 9P's message set is a fraction of
  NFSv3's, it mounts natively on Linux (`v9fs`), needs no portmapper/MOUNT/XDR catalog, and has
  no FFI. That single substitution turns the riskiest phase from "research project" into "hard
  but scoped feature." If 9P is somehow unacceptable, the FUSE-via-low-level-CFFI path is the next
  least-bad, and NFS is the *most* code for the *least* leverage despite the doc ranking it safest.

**Bottom line:** nothing here forces you to invent three libraries — *except* the NFS stack, which
forces you to invent four (RPC, XDR, MOUNT, portmapper). Drop NFS for 9P (or no-mount), back the
CAS with LMDB + conspack + raw-digest keys, kill the global-lock contention with an `fset`
read-snapshot, get an fsync contract you've tested, pin it all with Qlot, and keep Shen out of
the production image — and this ships.
