---
date: 2026-06-26
researcher: Claude
topic: "mvfs — data model & storage (CAS via git, trunk, landed-log, change-id, stacks, idempotency)"
status: design
layer: spec
builds_on: thoughts/shared/plans/dvcs-vfs/spec/00-overview.md
tags: [design, spec, shen, cas, git, landed-log, change-id, idempotency, value-semantics]
last_updated: 2026-06-26
---

# mvfs — Data Model & Storage

> This document refines the keystone (`00-overview.md`); it does not redefine its names,
> invariants (I1–I9), or §5 frozen contracts. Where this doc needs a contract changed, it
> **flags** it in the closing "Contracts to refine" section rather than silently diverging.

This is the storage substrate beneath the land-queue kernel (`02`), the policy plane (`03`), and
the read/serve tier (`04`/`05`). It specifies exactly two kinds of state:

- **Immutable values** — git objects (blobs/trees/commits) named by hash, plus the append-only
  **landed-log**. These are *information*; they accrete, never mutate (I5).
- **One mutable identity** — the trunk tip (`refs/heads/trunk` + `applied-seq`). A single pointer,
  advanced only by the leased leader (`02`, I1/I7).

Everything reads a value; only the leader advances the one pointer. This is the Datomic spine
(`../24` Finding "database-as-a-value, passed by basis-point") expressed in git + a checksum-chained
log.

---

## 1. Content storage = git objects via shell-out

### 1.1 Why git, not a library

Content storage is delegated to the **trusted shell** (keystone §2, §5.4): we shell out to the
`git` CLI for all CAS operations. We do not reimplement object storage, dedup, packing, or GC. The
proven brain (Shen) decides *what* to store and *in what order*; `git` is the oracle that stores it.

What we get **for free** by delegating to git:

- **Content dedup** — identical blobs/trees collapse to one object by hash (I5).
- **Packfiles + delta compression** — `git gc` / `git repack` produce packed, delta-encoded storage.
- **GC by reachability** — `git gc` / `git prune` collect objects unreachable from refs. The trunk
  ref + the landed-log's referenced commit hashes are the reachability roots (§7.3).
- **Tamper-evidence** — a hash names exactly one byte string / tree; corruption is detectable via
  `git fsck` (supports I5).

> **libgit2 / git-as-library is an explicit non-goal for v1.** The git **CLI is the v1 oracle** and
> the conformance baseline (the executable spec differentially tests against it). `libgit2` (or a
> long-lived `git cat-file --batch` coprocess) is a permitted *later* optimization to cut
> fork/exec cost on the read hot path — but it must be byte-identical to the CLI, and the CLI
> remains the source of truth.

### 1.2 Object identity & hash algorithm

git objects are addressed by the hash of `"<type> <len>\0<payload>"`. Per the keystone (§5.1
`hash`), mvfs uses **git's object hash** — **SHA-256** for new repositories
(`git init --object-format=sha256`), falling back to SHA-1 only for interop with legacy git tooling.
SHA-256 is the v1 default; the `hash` type in §5.1 is the git object id under whichever format the
repo was initialized with. A repo's object-format is fixed at init and recorded once in repo
metadata; all log entries and trees use that format.

### 1.3 The audited primitive surface (keystone §5.4)

The complete set of `git` invocations the brain may call. **No other git subcommands are in the
trusted surface.** Each is a pure function of its inputs except where it writes a CAS object
(idempotent: writing the same bytes yields the same hash, a no-op if present).

| Operation | Exact command | Purpose |
|---|---|---|
| Write a blob | `git hash-object -w --stdin` (or `-w -t blob <file>`) | bytes → blob hash; `-w` persists to CAS |
| Read an object | `git cat-file -p <hash>` / `git cat-file blob <hash>` | hash → bytes |
| Object type/size | `git cat-file -t <hash>` / `-s <hash>` | metadata probe |
| Batch read (hot path) | `git cat-file --batch` / `--batch-check` (coprocess) | many hash→bytes without per-call fork/exec |
| Build a tree (flat) | `git mktree` (stdin: `mode SP type SP hash TAB name\n`) | explicit tree from entries |
| Build a tree (from index) | `git read-tree <tree>` then `git write-tree` | construct/derive trees via the index |
| Write a commit | `git commit-tree <tree> -p <parent> -m <msg>` (env: author/committer) | (tree, parent, msg) → commit hash |
| Existence check | `git cat-file -e <hash>` | does object exist locally |
| 3-way merge (content) | `git merge-file` / `git merge-tree` | real text merge (detailed in `02`) |
| GC / pack | `git gc` / `git repack` / `git prune` | reclaim + compress (§7.3) |
| Integrity audit | `git fsck` | verify CAS integrity (I5) |

Notes:
- **All of these run with an explicit `GIT_DIR`** (the bare object store) and **no working tree**;
  trees are built via `mktree`/`commit-tree`, never via `git add`/checkout on the server. This keeps
  the CAS a pure object database.
- `commit-tree` produces a commit with **exactly one parent** (I1). A merge commit (two parents) is
  never produced — trunk is linear.
- Writing is **content-idempotent**: `hash-object -w` of identical bytes returns the same hash and
  does not duplicate storage (I5, supports I3 dedup at the byte level).

### 1.4 Shen-ish type sketch

```shen
(datatype git-object
  Hash : hash;
  ____________________
  (git-blob Hash) : git-object;     \\ leaf: file content

  Hash : hash;
  Entries : (list tree-entry);
  ____________________
  (git-tree Hash Entries) : git-object;

  Hash : hash; Tree : hash; Parent : hash; Msg : string;
  ____________________
  (git-commit Hash Tree Parent Msg) : git-object;)

\\ a tree entry, the unit git mktree consumes
(datatype tree-entry
  Mode : file-mode; Name : path-component; Target : hash;
  Kind : (mode-or [blob tree]);
  ____________________
  (entry Mode Kind Name Target) : tree-entry;)
```

---

## 2. Trees / manifests for monorepo scale

The monorepo manifest at any `seq` is a **git tree object**, recursively nested — git's native
directory representation. There is no separate manifest format; the tree *is* the manifest.

### 2.1 Recursive trees and the cost model

A tree object lists its immediate children: for each child, `(mode, kind∈{blob,tree}, name, hash)`.
Subdirectories are themselves tree objects referenced by hash. This gives the monorepo properties we
need at hundreds-of-developers / large-tree scale:

- **O(depth) subtree fetch.** To materialize `a/b/c/`, fetch the root tree, then `a`, then `a/b`,
  then `a/b/c` — `depth` object reads, independent of total repo size. This is the structural basis
  for lazy/sparse reads in `05`.
- **O(1) unchanged-subtree compare.** Two trees with the same hash are byte-identical and therefore
  structurally identical (I5). A change that touches only `x/y/` leaves every sibling subtree's hash
  unchanged, so a diff prunes entire untouched subtrees by hash equality without descending. This is
  what makes `paths-touched` (§5) cheap to compute and what makes blame/path-history (§8) tractable.

### 2.2 Path resolution: `(root-tree, path) → blob hash`

Resolution walks the tree chain from the entry's `root-tree` (the content identity of trunk at that
`seq`, keystone §5.1):

```
resolve(root-tree, "a/b/file.txt"):
  t ← root-tree
  for each component c in ["a", "b"]:
     e ← lookup c in (entries of tree t)        \\ entries sorted; binary search
     require e.kind = tree                        \\ else: not a directory
     t ← e.target
  e ← lookup "file.txt" in (entries of tree t)
  require e.kind = blob
  return e.target                                 \\ the blob hash
```

```shen
(define resolve-path
  Tree []            -> (ok Tree)
  Tree [C | Rest]    -> (let E (lookup-entry Tree C)
                          (if (= (kind E) tree)
                              (resolve-path (target E) Rest)
                              (if (empty? Rest)
                                  (ok (target E))      \\ final blob
                                  (error not-a-dir)))))
```

This pure function is the heart of the read-tier `resolve` step (`04`). It needs **no coordination**
(§7): given a `root-tree` hash (carried in an `as-of` basis, keystone §5.2), any replica resolves
any path against immutable values alone. The resolved blob hash is what the serve token authorizes
(keystone §5.3, I9).

---

## 3. The linear trunk & the `change` / landed-change

### 3.1 Trunk = a linear chain of single-parent commits (I1)

The trunk is a chain of git commits, each with **exactly one parent** (I1). The **trunk tip** is the
head of this chain — `refs/heads/trunk`, the single mutable pointer (§7). A landed-change is one such
commit. Because every commit has exactly one parent and the leader assigns `seq = tip+1`
(keystone I1, enforced in `02`), the history is a gapless line: no branches, no merge commits in
published history.

```
seq:    0          1          2          3
commit: C0  ◄────── C1 ◄────── C2 ◄────── C3   = refs/heads/trunk (tip)
        (root)    parent=C0  parent=C1  parent=C2
root-tree:T0        T1         T2         T3
```

### 3.2 `change` vs `commit`: the stable `change-id`

A **commit hash** is per-revision: each time a change is amended, rebased onto a new trunk tip, or
revised during review, git produces a **new commit object with a new hash** (different tree and/or
parent → different content → different hash, I5). That is correct and desirable for content
integrity, but it means the commit hash **cannot** be the stable identity of "the change" across its
review lifecycle.

So mvfs carries a **`change-id`** (keystone §5.1 `change-id`): a **Gerrit-style stable identifier**
that is **minted once** when a change is first created locally and **preserved across every
revision and rebase**. Two commit objects with the same `change-id` are two *revisions of the same
change*; the latest one to land is the landed revision.

- **Generation:** a random 160/256-bit id, rendered as `I` + hex (Gerrit convention,
  e.g. `Ia1b2c3...`). Minted client-side at first `mvfs commit`. Unique with overwhelming
  probability; collisions are additionally guarded by the landed-log dedup set (§6, I3).
- **Storage (frozen as a commit trailer):** the `change-id` is stored as a **git commit-message
  trailer** in the commit object itself:
  ```
  <subject line>

  <body...>

  Change-Id: Ia1b2c3d4e5f6...
  ```
  Because it lives in the commit *message*, it survives `commit-tree` regeneration as long as the
  message is carried forward (which restack/amend always do). It is content-addressed *with* the
  commit (part of the bytes git hashes) yet **stable across revisions** because the author copies the
  same trailer into each new revision's message. This is exactly Gerrit's mechanism and needs no
  git extension.
- **Why a trailer, not a git note:** notes (`refs/notes/*`) are a *mutable side ref* keyed by commit
  hash — they would have to be re-attached on every rebase (new commit hash) and are not part of the
  content-addressed commit. A trailer is immutable, travels with the message for free, and is
  greppable by stock git (`git log --grep`, `git interpret-trailers`). The landed-log additionally
  records `change-id` as a first-class field (§5) so the canonical mapping
  `change-id → landed commit-hash` lives in the spine, not only in the message.

```shen
(datatype change
  Cid : change-id;                 \\ stable across revisions (Gerrit-style)
  Rev : commit-hash;              \\ current revision's commit object (per-revision)
  Parent : commit-hash;
  Tree : root-tree;
  ____________________
  (revision-of Cid Rev Parent Tree) : change;)
```

---

## 4. Local commits & stacks (client-side)

Everything in this section is **client-side and pre-land**: it never touches the spine until a land
is acked. It exists so authors can build, restack, and submit.

### 4.1 Three client states for work-in-progress

1. **Uncommitted work** — dirty blobs in the local dirstate/working area, not yet a commit object.
   Tracked by the thin mount/checkout's write-tracking (`05`), analogous to git's index.
2. **A local commit** — uncommitted work crystallized into a real git commit object (via
   `hash-object` for changed blobs → `write-tree`/`mktree` → `commit-tree`), carrying a freshly
   minted (or preserved, on amend) `Change-Id` trailer. Not yet landed.
3. **A stack** — an ordered list of local commits, each the parent of the next, each with its **own
   distinct `change-id`**, all rooted at the author's current view of the trunk tip.

### 4.2 Stack representation before landing

A stack is just a short linear chain of local commits — git's native shape — distinguished from
trunk only by *not being referenced by `refs/heads/trunk`*:

```
trunk tip = C2 (T2)
                 ▲
local stack:     │
   L0  parent=C2   change-id=Iaaa   \\ bottom of stack (lands first)
   L1  parent=L0   change-id=Ibbb
   L2  parent=L1   change-id=Iccc   \\ top of stack (lands last)
```

- The stack is held under a local ref (e.g. `refs/mvfs/stack`) — purely client-side, never
  published; trunk has no branches (keystone §6 non-goals).
- **Each commit owns one `change-id`** — the stack is "a stack of changes sharing a lineage," and
  the change-ids are what survive restack. They are submitted **bottom-up**.
- **Restack-on-land:** when the trunk tip advances (someone else landed), the author rebases the
  stack onto the new tip. Each rebased commit gets a **new commit hash** (new parent) but **keeps its
  `change-id`** (copied trailer, §3.2). The land kernel (`02`) matches the submitted revision to its
  change-id, so review continuity and idempotency (§6, I3) hold across the restack.

```shen
(datatype stack
  ____________________
  empty-stack : stack;

  Base : commit-hash;             \\ the trunk tip the stack is rooted on
  Commits : (list change);        \\ ordered bottom→top, each a distinct change-id
  ____________________
  (rooted-stack Base Commits) : stack;)
```

Submission packages one or more stack entries to the leader; admission/merge/land is the kernel's
job (`02`). This doc only fixes the *representation*: a linear chain of single-parent local commits,
each carrying a stable `change-id`.

---

## 5. The landed-log entry — the spine

The landed-log is the **sole replication authority** (keystone §3 diagram). It is an append-only,
checksum-chained, fenced sequence of entries. git stores *content*; the log stores the *total order*
and the *authorization/integrity metadata* that git objects alone cannot express (I2, I4, I6, I7).

### 5.1 Entry shape (EXACT, from keystone §5.1)

The on-disk record carries exactly these fields, in this order (do not redefine — keystone §5.1):

```
landed-entry := {
  seq            : u64        ; monotonic, gapless (I1/I2)
  change-id      : id         ; stable across revisions/rebase (Gerrit-style)
  commit-hash    : hash       ; git commit object for this landed change
  parent-hash    : hash       ; predecessor commit (single parent; trunk is linear)
  root-tree      : hash       ; git tree = content identity of trunk at this seq
  paths-touched  : sorted[path]
  author         : principal
  acl-version    : u64        ; log seq of the policy entry this land was authorized against (I6)
  fence          : u64        ; fencing token = leader lease epoch; CAS'd on durable append (I7)
  prev-checksum  : u64        ; == prior entry post-checksum (chain integrity)
  post-checksum  : u64        ; rolling checksum after this entry
  ts             : i64        ; taken at submit time (apply must be clock-free)
}
```

A **policy entry** is a distinguished landed-entry whose payload is a Datalog ruleset delta; for it,
`acl-version` is itself the new authority (`03`). The shape is otherwise identical, so the chain,
checksum, and replication logic are uniform.

```shen
(datatype landed-entry
  Seq : u64; Cid : change-id; Commit : hash; Parent : hash; Root : hash;
  Paths : (sorted path); Author : principal; Acl : u64; Fence : u64;
  Prev : u64; Post : u64; Ts : i64;
  ____________________
  (landed Seq Cid Commit Parent Root Paths Author Acl Fence Prev Post Ts)
    : landed-entry;)
```

### 5.2 The rolling checksum (XOR-CRC64, LTX-style)

We adopt the LTX rolling-checksum design (`../06` §1: CRC64-XOR — commutative, O(changed)
incremental) but **as an integrity/anti-split-brain chain, not a content address** — content
addressing is git's job (I5). The checksum proves the *log replayed in order is intact*; the git
hashes prove the *content is intact*.

**Per-entry contribution** (the value an entry folds into the running checksum):

```
contrib(entry) := CRC64( seq ‖ change-id ‖ commit-hash ‖ parent-hash ‖ root-tree
                         ‖ paths-touched ‖ author ‖ acl-version ‖ fence ‖ ts )
```
where `‖` is the canonical serialization of §8 (deterministic, length-prefixed) and `CRC64` is
ISO-3309 / ECMA-182 CRC-64. `prev-checksum` and `post-checksum` are **excluded** from `contrib`
(they are the chain, not content).

**The fold (commutative XOR):**

```
post-checksum(N) := prev-checksum(N)  XOR  contrib(entry N)
prev-checksum(N) := post-checksum(N-1)            ; the chain link
post-checksum(0) := contrib(entry 0)              ; prev-checksum(0) := 0
```

Properties (why XOR-CRC64):
- **O(changed) incremental:** appending entry N is a single CRC64 over that entry plus one XOR —
  independent of log length. No rehash of history.
- **Commutative & self-inverse:** XOR lets a *compaction* recompute the checksum of a merged range
  by XOR-ing the contributions of the entries it replaces, without replaying byte-by-byte
  (mirrors LTX TXID-range compaction, `../06` §1) — and lets a verifier detect a missing/duplicated
  entry as a non-zero residual.
- **Cheap, not cryptographic:** this catches corruption, truncation, reordering, and split-brain
  divergence. It is **not** a defense against a malicious forger — that role is git's content hashes
  (I5) plus the fence (I7). The two layers are complementary.

**Chain invariant (normative, supports I2/I4):**

```
∀ N ≥ 1 :  entry(N).prev-checksum == entry(N-1).post-checksum
∀ N     :  entry(N).post-checksum == entry(N).prev-checksum XOR contrib(entry(N))
```
A replica applying the log verifies both equations on every entry; a mismatch halts apply (refuse to
diverge) — this is how a replica trusts the stream without trusting the transport (`04`).

### 5.3 On-disk format & durable append semantics

**Layout.** The log is a sequence of length-framed records in segment files, append-only:

```
record := [ u32 len_be ][ payload : len bytes ][ u32 crc32c_be(payload) ]
```
- `payload` is the canonical serialization of the §5.1 entry (format per §8 — git-native lines for
  the canonical form; msgpack for the compact form).
- `len_be` frames the record so a reader can scan without parsing; the trailing `crc32c` is a
  *framing* checksum (torn-write / truncation detection at the I/O layer), **distinct** from the
  semantic XOR-CRC64 chain in §5.2.
- Records accumulate into **segment files** (`landed-NNNNNNNN.log`, rolled at a size bound); a tiny
  `HEAD` file records `(applied-seq, post-checksum, active-segment, offset, fence)` for O(1)
  tip lookup and crash recovery. On open, recovery scans the active segment forward from the last
  consistent offset, validating framing CRC and the §5.2 chain, and truncates any trailing torn
  record.

**Durable append (fsync-before-ack — I4).** The leader's append is the linearization point:

1. Hold the lease witness; obtain the current `fence` (lease epoch) and CAS it on the append
   (keystone §5.4 "fencing-token CAS"; I7 — a stale leader's CAS fails and it cannot append).
2. Compute `prev-checksum = HEAD.post-checksum`, `post-checksum` per §5.2.
3. `write()` the framed record to the active segment.
4. **`fsync()` the segment file**, then `fsync()` the directory entry if the segment is new.
5. Atomically update `HEAD` (write-tmp + `rename` + `fsync(dir)`).
6. **Only then ack** the submitter, at the stated durability width (`02`/`04` define width;
   v1 single-leader width = "durable on the leader").

An **ack therefore implies the entry is durable on the leader at the stated width (I4)** — no lost
acked land. Replicas pull/stream segments and apply in order (I2), verifying §5.2 on each entry.

> The git commit object referenced by `commit-hash` is written to the CAS (§1.3, `commit-tree`)
> **before** the log append, so that the moment an entry is durable, its content is already
> reachable. The log append is what makes the change *real* and *ordered*; the commit object is
> merely its content.

---

## 6. Idempotency keys & dedup

Per **I3** (at-most-once landing per `idempotency-key` and stable `change-id`), dedup lives **in the
log/RSM, not a side table** (keystone I3; `../24` Finding 4 / "steal #4": derived state must never
become a second authority). There is no separate idempotency database; the authority is the log
plus an in-memory dedup set that is a *pure function of the log* (rebuildable on restart by replay).

### 6.1 What is keyed

A submission carries an **`idempotency-key`** (client-minted per submit attempt) and the change's
**`change-id`** (stable, §3.2). The leader, before landing, checks:

- **`change-id` already landed?** → return the existing landed `seq`/`commit-hash` (the change is
  already on trunk; a retried or duplicate submit is a no-op success). This makes restack-and-resubmit
  safe (§4.2).
- **`idempotency-key` already seen for this change?** → return the prior outcome (ack or reject)
  without re-running admission/merge. This makes network-retry safe (the classic
  "did my submit go through?" case).

```shen
(datatype dedup-key
  Cid : change-id; Idem : idempotency-key;
  ____________________
  (dedup-key Cid Idem) : dedup-key;)

\\ the dedup set is derived from the log, never an independent store
(define dedup-seen?
  Log Key -> (member? Key (fold-dedup-keys Log)))
```

> **Storage of `idempotency-key`.** The §5.1 entry shape does **not** currently carry an
> `idempotency-key` field, yet I3 requires the log to be the dedup authority. See "Contracts to
> refine" — the key must be persisted *in the entry* (recommended) so the dedup set is reconstructible
> by pure replay after a leader crash; otherwise idempotency would depend on volatile leader memory,
> weakening I3/I4 across failover.

### 6.2 Surviving compaction: bounded window vs permanent set

When the log is compacted (§5.2 commutative checksum permits merging old ranges; mirrors LTX), the
question is whether dedup keys survive.

- **`change-id` dedup → permanent.** The mapping `change-id → landed seq` is small (one entry per
  *landed* change) and semantically required forever: a `change-id` must never land twice for the
  life of the repo (I3). It is preserved across compaction as a **permanent set**, materializable as
  a compact derived index (a rebuildable cache off the log, §8) and re-derivable by full replay. Cost
  is O(landed changes), which is bounded by repo history and cheap.
- **`idempotency-key` dedup → bounded window (recommended).** Idempotency-keys are per-*attempt* and
  far more numerous (retries, aborted submits) but only matter for a short retry horizon. Keeping
  them forever is wasteful. **Recommendation:** retain idempotency-keys for a **bounded window**
  (by time, e.g. 7 days, and/or by seq-distance from tip, e.g. last 10k entries). Beyond the window,
  drop them at compaction; a retry arriving after the window simply re-runs admission — and the
  *`change-id`* permanent set still prevents a double-land, so correctness (I3, no double-land) is
  preserved even though the *fast idempotent-replay* of an ancient key is lost. This is the right
  trade: permanent protection where it's required (change-id, double-land), bounded protection where
  it's only an optimization (idempotency-key, retry-replay).

---

## 7. Identity / value semantics (Hickey)

This is the Datomic-shaped spine made literal (`../24` "What you got RIGHT" #1–#3, "steal #2–#4").

### 7.1 One mutable identity; everything else is a value

- **The one place that changes: the trunk tip.** `refs/heads/trunk` (and the log `HEAD`'s
  `applied-seq`) is the single mutable pointer in the whole system. It is a *succession of values*,
  not a mutated cell: advancing it means appending a new immutable log entry that names a new
  immutable `root-tree`. Only the leased leader advances it (I1/I7).
- **Everything else is an immutable value addressed by hash.** Blobs, trees, commits, and (once
  appended) every landed-log entry are immutable (I5). A `root-tree` hash *is* "the content of trunk
  at that seq" — a database value you can hand to any process. A `(seq, acl-version)` `as-of` basis
  (keystone §5.2) is a *basis-point*: hand it around and every node computes identical answers — the
  exact analogue of Datomic's `(d/as-of db t)` (`../24` "steal #2/#3").

### 7.2 Reads need no coordination

Because content is immutable and content-addressed, **any** replica/cache answers a read from a value
without asking the leader (`../24` #2). Path resolution (§2.2) is a pure function of `(root-tree,
path)`; serving bytes is a pure function of `(blob-hash)` (gated only by the serve-token capability,
I9, `04`/`05` — an authorization concern, not a coordination one). The leader is never on the read
path. Read-your-writes / monotonicity are achieved by the client carrying its `as-of` basis (I8,
`04`), not by locking.

```shen
\\ reads are pure over immutable values: (root-tree, path) -> bytes, no leader, no lock
(define read-at
  Root Path -> (let Hash (resolve-path Root Path)
                 (cat-file-blob Hash)))   \\ cat-file is the only effect; pure in Root/Path
```

### 7.3 GC and the value model

`git gc` (§1.3) collects objects unreachable from the reachability roots. The roots are: the trunk
tip ref, plus **every `commit-hash`/`root-tree` referenced by a retained landed-log entry**. Because
trees structurally share unchanged subtrees (§2.1), retaining all of history is cheap; compaction
(§6.2) of the *log* and `git gc` of *objects* are independent levers. GC never mutates a value — it
only removes values no basis-point can reach.

---

## 8. Serialization formats & the derived index

### 8.1 Three serializations, one canonical

- **git-native (canonical content):** blobs/trees/commits are serialized by git itself; we never
  hand-encode them. The commit message (with `Change-Id` trailer, §3.2) is the only content we
  author, as UTF-8 text.
- **sexpr (canonical log/policy form):** the landed-log entry and the Datalog policy ruleset (`03`)
  have a **canonical S-expression form** — homoiconic, human-auditable, diffable, and the form the
  Shen brain manipulates natively. The §5.2 checksum and §5.3 framing are computed over a
  **deterministic, length-prefixed** rendering (fields in §5.1 order, sorted `paths-touched`, fixed
  integer widths) so the bytes are reproducible across implementations (the differential-test
  oracle, keystone §2).
- **msgpack (compact wire/disk form):** an equivalent compact encoding for the on-disk segment
  payload and replica streaming, used where the sexpr form's size matters. The canonical sexpr form
  is normative; msgpack is a faithful re-encoding (round-trips to identical fields). Both must
  produce the **same §5.2 checksum** (the checksum is over the canonical field serialization, not
  over the chosen envelope), so encoding choice never changes the chain.

```shen
\\ the checksum/contrib is over canonical fields, independent of envelope:
(define contrib
  E -> (crc64 (canon-bytes
                [(seq E) (cid E) (commit E) (parent E) (root E)
                 (paths E) (author E) (acl E) (fence E) (ts E)])))
```

### 8.2 The derived metadata index is a rebuildable cache — never a second authority

A local index (commit graph, blame, path-history, change-id→commit map, dedup permanent set) is
maintained for query speed. Per `../24` "steal #4" / Fossil model (`../06` §2):

- The index is **a pure function of the landed-log + git CAS**. It is **never replicated**, **never
  authoritative**, and **always rebuildable** by replaying the log.
- Nothing is ever written to the index except by reading the log; **the day something writes the
  index out-of-band, value-orientation collapses** — so this is enforced as a hard rule, not a
  convention (`../24` #4).
- Implementation: it may be a SQLite file or soa32 arrays (`03`); the choice is local and
  disposable. Corruption is recovered by `rm` + replay, never by repair-in-place.

```shen
(datatype derived-index    \\ rebuildable cache; NOT a source of truth
  ____________________
  (index-of-log Log) : derived-index;)   \\ a function of the log, by construction
```

---

## 9. Invariant cross-reference

| Invariant | Where this doc enforces / supports it |
|---|---|
| **I1** (single linear trunk, one parent, gapless seq) | §1.3 `commit-tree -p` single parent; §3.1 chain; §5.1 `seq`/`parent-hash` |
| **I2** (total order = log append order) | §5.2 chain invariant; §5.3 ordered apply |
| **I3** (at-most-once per idempotency-key & change-id) | §6 dedup in the log/RSM; §6.2 permanent change-id set + bounded idem window |
| **I4** (no lost acked land) | §5.3 fsync-before-ack durable append |
| **I5** (content integrity; hash names one value) | §1.1–§1.2 git CAS; §2.1 hash-equality; tamper-evidence via `git fsck` |
| **I6** (ACL soundness at acl-version) | §5.1 `acl-version` field; policy entry (§5.1 note, `03`) |
| **I7** (fenced authority) | §5.3 fence CAS on append; §7.1 single leader advances tip |
| **I8** (RYW + monotonic reads) | §7.2 client carries `as-of` basis (detail in `04`) |
| **I9** (auth on every byte path) | §2.2 resolved blob hash gated by serve token (detail in `04`/`05`) |

---

## Contracts to refine (flag, do not silently change)

Per the keystone directive, I flag — but do not change — these §5 contract gaps surfaced while
specifying storage:

1. **§5.1 entry is missing an `idempotency-key` field, but I3 requires the log to be the dedup
   authority (§6.1).** As written, the `change-id` field supports double-land prevention, but
   per-attempt idempotency-key dedup has nowhere durable to live in the entry — forcing it into
   volatile leader memory, which would not survive failover and would weaken I3/I4 together.
   **Recommendation:** add `idempotency-key : id` (nullable for internally-generated entries like
   policy deltas) to the §5.1 shape, *excluded from* `contrib` if you want submit-retries to be
   checksum-neutral, or *included* if you want it chained. I lean: **include it in `contrib`** so a
   replayed dedup set is provably the one the leader committed. Needs a keystone decision.

2. **§5.2 checksum algorithm was named only as "rolling checksum (XOR-CRC64-style)" in the keystone
   prose; this doc fixes it to ISO/ECMA CRC-64 with XOR fold and a documented `contrib` field set
   excluding the two checksum fields.** This is a *specification*, not a contradiction, but the
   keystone should bless the exact `contrib` field list (§5.2) and CRC-64 variant so the differential
   oracle is unambiguous.

3. **Hash algorithm.** Keystone §5.1 says `hash` without fixing SHA-1 vs SHA-256. This doc commits to
   **git SHA-256 as v1 default** (§1.2). Recommend the keystone state this explicitly so all docs
   agree on object-id width (affects `as-of` token size and serve-token HMAC inputs, §5.3).

4. **§5.1 `ts` is "taken at submit time (apply must be clock-free)" — good.** This doc relies on that:
   `ts` is excluded from any ordering/correctness logic and included in `contrib` only as an opaque
   recorded value. No change needed; noting the dependency so it stays clock-free.
