---
date: 2026-06-25
researcher: Claude
topic: "Grounding research — LiteFS/LTX, Irmin, and the distributed-SQLite landscape as foundations for a trunk-only DVCS-VFS"
tags: [research, litefs, ltx, litevfs, irmin, ocaml, sqlite-vfs, mvsqlite, dqlite, fossil, cas, merge]
status: complete
last_updated: 2026-06-25
last_updated_by: Claude
sources_note: "Synthesized from three parallel web-research passes. Citations inline."
---

# Grounding Research: SQLite-VFS / LiteFS / Irmin as a DVCS-VFS Foundation

Context: the user has an OCaml repo, `litevfs` (a "VFS for distributed SQLite"), and asked
whether a **clean build borrowing ideas** — possibly OCaml-based — is cleaner than building the
trunk-only DVCS-VFS on the Autopoiesis CL substrate. Target scale is **moderate** (hundreds of
developers, not Google/Meta). This document grounds that decision in how the relevant systems
actually work. (I could not read the private `litevfs` repo from this session; the analysis is
of the LiteFS/LiteVFS lineage it is named after, swappable once the repo is readable.)

---

## 1. LiteFS / LiteVFS / LTX — distributed SQLite, not a VCS

**What it is.** LiteFS replicates SQLite by mounting a **FUSE** filesystem over the DB directory
and watching the journal/WAL to detect transaction boundaries, packaging each transaction's
changed **pages** into an **LTX** file. LiteVFS is the alternative: a Rust `sqlite3_vfs`
extension that lazily fetches individual pages on `xRead` from LiteFS Cloud instead of mounting.
([How LiteFS Works](https://fly.io/docs/litefs/how-it-works/), [superfly/litevfs](https://github.com/superfly/litevfs))

**The LTX format** (the genuinely reusable idea):
- 100-byte header + sorted page block + 16-byte trailer.
- Header carries `MinTXID`/`MaxTXID` (monotonic `uint64` transaction ids) and a
  **`PreApplyChecksum`** (rolling checksum of the whole DB *before* this file).
- Trailer carries **`PostApplyChecksum`** (after) + a file CRC.
- **Chaining invariant:** file N+1's `PreApplyChecksum` must equal file N's `PostApplyChecksum` —
  a hash-chained, append-only, totally-ordered log. Compaction merges TXID ranges (LSM-style).
  ([superfly/ltx](https://github.com/superfly/ltx/blob/main/ltx.go))
- Checksum is **CRC64-XOR** (commutative, O(changed-pages) incremental) — corruption/split-brain
  detection, **not** cryptographic content-addressing.

**Distribution model:**
- **Single primary**, leased via **Consul** (10s TTL default; up to 10s write-unavailability on
  failover) or a **static**永-primary. Replicas stream LTX over HTTP and apply by verifying the
  checksum chain. ([ARCHITECTURE.md](https://github.com/superfly/litefs/blob/main/docs/ARCHITECTURE.md), [lease.go](https://github.com/superfly/litefs/blob/main/lease.go))
- **Async replication** — subsecond data-loss window on primary crash; *not* consensus-linearizable.
- Read-your-writes via a `(TXID, checksum)` position cookie + a proxy that holds a read until the
  replica catches up. ([Tracking Consistency](https://fly.io/blog/tracking-consistency-with-litefs/))
- **~100 TPS** write ceiling (FUSE round-trip cost). **LiteFS Cloud shut down Oct 2024** —
  LiteVFS's lazy-fetch backend no longer exists as a service. ([Sunsetting LiteFS Cloud](https://community.fly.io/t/sunsetting-litefs-cloud/20829))

**Verdict (researcher, blunt):** *LiteFS/LTX is a replication log for a binary page store, not a
VCS.* It has no file paths, no tree, no human-readable diff, no merge; CRC64 ≠ content address;
replication is async not durable-by-consensus.

### What maps to a trunk VCS (steal the patterns, not the engine)

| LiteFS/LTX | DVCS analogue | Strength |
|---|---|---|
| LTX append-only log, monotonic TXID, PreApply↔PostApply chaining | **Linear trunk**, commit seq, verify-by-chain parent pointer | **Strong** |
| Consul-leased single primary | **Land-leader** (lease, *not* Raft) | **Strong** (esp. at moderate scale) |
| LiteVFS lazy per-page `xRead` fetch | **Lazy file materialization** in a sparse checkout | **Strong (architecturally)** |
| LTX compaction (merge TXID ranges) | History compaction / packing | Partial |
| **Page-level binary**, no paths/lines | source files want **file/line** granularity | **Mismatch — disqualifying as storage** |

---

## 2. The distributed-SQLite landscape — and why page-granularity is wrong for source

The `sqlite3_vfs` interface is a vtable (`xRead`/`xWrite`/`xSync`/`xLock`/`xShmMap`…); a
page-fetching VFS intercepts `xRead`, converts the byte offset to `pgno = iOfst/page_size + 1`,
and serves from a local cache or a remote store. `PRAGMA locking_mode=EXCLUSIVE` removes the
`xShmMap` shared-memory complexity for a single-writer model. ([sqlite.org/vfs](https://sqlite.org/vfs.html), [wal.html](https://sqlite.org/wal.html))

| System | Replication | Idea worth stealing |
|---|---|---|
| **dqlite** (Canonical) | Physical WAL-frames via C-Raft, in-memory VFS | Raft *is* the only journal; intercept at WAL-frame level |
| **rqlite** | Logical (SQL text via Raft) | Clean HTTP query API; but non-determinism is fragile |
| **mvSQLite** | Physical MVCC on FoundationDB: `(page,version)→hash` + `hash→bytes` | **Two-level: versioned index + immutable content store; OCC conflict detection; O(log n) time-travel** |
| **cr-sqlite** | Logical CRDT merge | CRDT sync for *metadata* (review state, CI, attrs) — not source |
| **Litestream/LiteFS** | Physical WAL/LTX → object store | Rolling checksum = cheap commit integrity; generation = snapshot + log |
| **Fossil** | Artifact bag + SQLite cache | **Blob store is truth; SQLite is a recomputable derived index** |

**The logical-vs-physical axis:** physical/page replication is content-addressed-blob-shaped
(immutable fixed blobs, a commit = new index generation); logical/SQL is patch-series-shaped.
([pvk.ca — replication without logs-on-logs](https://pvk.ca/Blog/2021/04/30/sqlite-replication-without-logs-on-logs/))

**Where the 4KB page helps:** B-tree metadata queries (file history, blame, lineage) in plain
SQL; atomic commits with referential integrity; automatic dedup; O(log n) point-in-time reads;
the battle-tested `xRead` lazy-fetch pattern.

**Where it fails for source (the honest part):** diffs are line-level, pages are 4KB-B-tree-node
level — the page layer is *invisible* to a `git diff`; **3-way merge is a file-content/text
operation no page construct helps with**; small files share pages, big files span hundreds; the
`xShmMap` multi-reader WAL interface is a real distributed obstacle. **Conclusion: use SQLite as
the metadata/commit-graph index (Fossil model), and a content-addressed blob/tree store for file
content — do NOT route VCS storage through the SQLite page log.** mvSQLite's `(page,version)→hash`
+ `hash→bytes` is the right *shape*, but with **"path" replacing "page number"** — which is
exactly Git's / Irmin's tree-of-blobs model. ([mvSQLite](https://su3.io/posts/mvsqlite), [Fossil tech overview](https://fossil-scm.org/home/doc/tip/www/tech_overview.wiki), [Why SQLite doesn't use Git](https://sqlite.org/whynotgit.html))

---

## 3. Irmin (OCaml) — the storage/merge/history substrate that's already built

**What it is.** "A distributed database built on the same principles as Git," in OCaml, by
Tarides/MirageOS. Git-shaped object model: **Contents (blobs) → Nodes (trees) → Commits →
Branches**, all content-addressed (SHA-256 in irmin-pack; SHA-1 + git-compat in irmin-git).
([mirage/irmin](https://github.com/mirage/irmin), [irmin.org](https://irmin.org/))

**The headline: Irmin has real, typed 3-way merge** — directly answering Torvalds' #1 Showstopper.
- `Irmin.Merge` API: `old:'a promise -> 'a -> 'a -> ('a, conflict) result`, with the LCA passed
  lazily; composable combinators (`default`, `idempotent`, `seq`, `option`, `pair`, `alist`,
  `Map`, `Set`, `counter`). Store-level `merge_into` computes the LCA and merges path-by-path.
  ([Merge API](https://mirage.github.io/irmin/irmin/Irmin/Merge/index.html), [custom_merge.ml](https://github.com/mirage/irmin/blob/main/examples/custom_merge.ml))
- **Caveat:** for *raw blobs* the default merge is "conflict if both touched." Real **line-level
  text 3-way merge** still needs a custom content type calling diff3 / libgit2 xdiff — hundreds
  to low-thousands of LOC. So merge is *enabled and structured*, not *free*.

**Backends & scale:** **irmin-pack** (append-only pack + index, used by **Tezos mainnet**) is the
production backend. Tezos numbers (Octez): 250GB→25GB storage, block validation 274ms→23ms,
index 21GB→59MB, >1000 TPS. ([irmin-pack intro](https://tarides.com/blog/2020-09-01-introducing-irmin-pack/), [6x faster](https://tarides.com/blog/2022-04-26-lightning-fast-with-irmin-tezos-storage-is-6x-faster-with-1000-tps-surpassed/)) Built-in **GC** (rolling window + archive lower volumes), **watch** (`irmin-watcher` inotify/FSevents), **push/pull sync**, **GraphQL**. Maintained quarterly (3.11, 2025-06); minor-version API churn is real — budget for it.
- **Caveat:** *not* proven at 10M-file/500k-commit monorepo scale; Tezos is a deep ledger tree
  with sequential single-writer writes. At **moderate** scale this is not a concern. No built-in
  sparse/partial-clone-by-path network primitive (build it at the VFS layer on lazy trees).

**OCaml systems ecosystem (vs. the CL situation Fukamachi flagged):**
- **FUSE:** `ocamlfuse` (maintained, libfuse 2/3; google-drive-ocamlfuse is the proof). Lwt/Eio
  integration is fiddly (libfuse owns the loop) but solved — ~a week of plumbing, not 4 libraries.
- **9P:** `mirage/ocaml-9p` (maintained, Lwt-native) — Linux mounts `-t 9p` natively; arguably
  cleaner than FUSE for a server controlling the client OS.
- **Concurrency:** **Eio** (effects-based, multicore, io_uring) on OCaml 5.3+ is the right choice;
  Irmin is Lwt-internally so a `lwt_eio` bridge is needed. ([Eio 1.0](https://tarides.com/blog/2024-03-20-eio-1-0-release-introducing-a-new-effects-based-i-o-library-for-ocaml/))
- **SQLite + custom VFS:** `sqlite3-ocaml`/`caqti`; a custom VFS is feasible via `ctypes` inverted
  stubs (with the usual C-callback/GC care). ([ocamlfuse](https://github.com/astrada/ocamlfuse), [ocaml-9p](https://github.com/mirage/ocaml-9p))
- **Consensus:** **no production Raft in OCaml** (oraft is incomplete). But for a single-primary
  trunk + read-replicas, **Irmin push/pull is sufficient — no Raft needed at moderate scale.**

**Verdict (researcher):** OCaml + Irmin is a **credible, substantially lower-risk** foundation than
CL/SBCL. Irmin eliminates ~12–18 months of core infra (CAS, Merkle, commits, branches, **merge**,
GC, sync); OCaml's maintained FUSE/9P bindings eliminate the CL "invent 4 libraries" problem. What
remains (same in any language, but from a higher floor): trunk land-queue, path ACLs, text-file
merge, sparse semantics, replication/HA.

---

## 4. The composite picture (input to the direction brief)

The three streams agree on a clean decomposition:

- **Storage / history / merge** → **Irmin** (file/blob/tree CAS, typed merge, GC, sync). *Not*
  SQLite pages.
- **Trunk land-queue + distribution** → **LiteFS/LTX-style**: leased single land-leader + an
  append-only, checksum-chained log of landed commits + replica streaming for read-your-writes.
  At moderate scale this *replaces* the entire Raft layer of the original design.
- **Metadata / queries** → optionally **SQLite as a Fossil-style derived index** (commit graph,
  blame, path history, ACL queries) — replicatable via LiteFS/dqlite if you want HA reads. This is
  where the `litevfs` knowledge is *directly* reusable.
- **VFS mount** → OCaml **ocamlfuse / ocaml-9p**, lazy blob fetch on read; no-mount sparse checkout
  first.
- **Language** → **OCaml** is the credible foundation; the CL substrate's value here is the *ideas*
  and the review corpus, not the code.

This is a smaller, lower-risk system than `00-architecture.md`, and it answers Torvalds' three
Showstoppers head-on (merge: Irmin+diff3; virtualization: maintained OCaml FUSE; dirstate: still to
build, but the FUSE layer can feed write-tracking). The direction brief (`07`) makes the call.

---

## Appendix — primary sources

LiteFS/LTX: fly.io/docs/litefs, github.com/superfly/{litefs,ltx,ltx-rs,litevfs}, ARCHITECTURE.md,
lease.go. Distributed SQLite: sqlite.org/{vfs,wal,walformat,fileformat}, github.com/{canonical/dqlite,
rqlite/rqlite,losfair/mvsqlite,vlcn-io/cr-sqlite}, litestream.io, fossil-scm.org, pvk.ca,
sqlite.org/whynotgit. Irmin/OCaml: github.com/mirage/{irmin,ocaml-9p}, irmin.org,
mirage.github.io/irmin (Merge/Tree APIs), tarides.com (irmin-pack, Tezos, Eio blogs),
github.com/astrada/ocamlfuse, ocaml-multicore/eio, janestreet.com (multicore saga),
github.com/komamitsu/oraft.
