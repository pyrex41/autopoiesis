---
date: 2026-06-25
researcher: Claude
topic: "All-Shen-on-Go implementation plan for shengo-vfs — a trunk-only, content-addressable DVCS-VFS at moderate scale, with Shen as the brain and a production-ready Go backend as the body"
plan: all-shen-on-go
status: draft
inputs:
  - thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
  - thoughts/shared/plans/dvcs-vfs/12-synthesis-v2.md
  - thoughts/shared/plans/dvcs-vfs/11-minsky-review.md
  - thoughts/shared/plans/dvcs-vfs/14-plan-shen.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
tags: [shen, shen-go, go, golang, go-git, litefs, ltx, fuse, bazil, prolog, sequent-calculus, datatype, dvcs, vfs, trunk, fencing, moderate-scale]
last_updated: 2026-06-25
last_updated_by: Claude
---

# `shengo-vfs` — an all-Shen DVCS-VFS on a Go backend (moderate scale)

This is the **same product** as the OCaml `mvfs` direction brief (`07`), its reviewed synthesis
(`12`), and the all-Shen-on-SBCL plan (`14`): a content-addressable, **trunk-only / no-branches**,
monorepo distributed VCS with a lazy virtual filesystem, sized for **moderate scale** (hundreds of
developers) — single leased land-leader, append-only checksum-chained landed-log, **no Raft**, lazy
VFS mount, real merge, real dirstate, path-scoped ACLs.

The build language is **Shen**, compiling to a **Go** backend. It discharges the **same panel
obligations** (C1–C5, P1–P7 from `12`) and re-expresses Minsky's "make illegal states
unrepresentable" `.mli` skeleton (`11`) in Shen's **sequent-calculus `datatype` rules**.

**What changed from `14` (the SBCL sibling), and why it is a large win:** plan `14` had to *assume*
native Shen ports of Irmin/FUSE/diff that, honestly, do not exist — meaning the team would have to
**build and own a CAS store and a FUSE binding** (`14 §7.3`), the "12–18 months you meant to skip."
This plan deletes that hidden cost. Because the user has stipulated a **production-ready `shen-go`
backend** (Shen → KL → IR → **Go**, per tiancaiamao/shen-go), the body is provided by **real,
mature, in-tree Go libraries**, not fictional Shen ports:

- **`go-git`** (`github.com/go-git/go-git/v6`): a mature Git object model = content-addressed
  blob/tree/commit store + history + GC + a purpose-built **ORT/recursive 3-way textual merge with
  rename detection** — directly answers Torvalds' "no merge" Showstopper *with real code*.
- **`superfly/litefs` + `superfly/ltx`** (both Go): the leased-primary + append-only,
  checksum-chained LTX transaction log = the distribution/replication layer as **real code**, not a
  reimplemented pattern.
- **`bazil.org/fuse`** (pure-Go FUSE, no cgo): the mount — no libfuse FFI, no GC-callback hazard.
- **goroutines + channels**: the land-worker, replica-streamer, and mount-server concurrency — no
  Lwt/Eio bridge, no global-lock dance; deploy is a single static binary.

> Read alongside `07` (product), `12` (settled obligations), `11` (the type sketch), and `14` (the
> SBCL sibling). Where this plan says "same as the prior plan," the architecture is identical and
> only the host/body differs.

---

## 0. The one-paragraph thesis

Keep the **Shen brain** from `14` verbatim — the land FSM, lease capability, total merge result, and
unforgeable ACL proof as Shen `datatype` sequent rules; the path-scoped ACL / admission / conflict
control plane as Shen-Prolog `defprolog`; the policy stored homoiconically as Shen S-exprs versioned
in the repo. **Swap the body from SBCL to Go.** Because Shen compiles *to* Go, calling a Go library
is an **in-runtime call**, not an FFI marshaling boundary: there is one process, one GC, one address
space, one static binary. The brain decides; the Go body — `go-git` for the object store and merge,
`litefs`/`ltx` for the landed-log and replication, `bazil/fuse` for the mount, goroutines for
concurrency — does every byte of IO. Abstract `go-git` behind a narrow Shen `object-store` interface
you own (C1's seam, minus Irmin's churn worry since `go-git` is stable and the team can pin a
commit). Make the **landed-log the one replication authority** (reuse `litefs`/`ltx`); any query
index is a local rebuildable cache (C2). Put a **fencing token** monotonic in the landed-log, CAS'd
on the durable append (C4/P1). Land is one atomic step: `go-git` commit → derived LTX log entry
(P3). The result is the *most intellectually coherent* variant of `14` with the *shipping-risk*
profile of a mature-Go build — the genuine sweet spot this plan exists to occupy.

---

## 1. Host/runtime model and the Shen↔Go boundary

### 1.1 What "Shen compiles to Go" means for the boundary (the crucial clarification)

`shen-go` translates **Shen → KL (KLambda) → IR → Go source**, then the Go toolchain compiles that to
a native static binary. The consequence that defines this entire plan:

> **There is no FFI.** Calling `go-git` / `litefs` / `bazil-fuse` from Shen is an **in-runtime Go
> call within the same process and the same Go runtime**. No C-ABI, no `cgo` (except whatever a Go
> dep itself uses — `go-git` and `bazil/fuse` are pure Go, so *none*), no serialization across a
> language boundary, no marshaling of bytes in and out of a foreign heap, no GC-across-FFI callback
> hazard. Shen values and Go values live in one heap managed by one garbage collector.

This is categorically better than `14`'s SBCL boundary, where "assume a Shen port exists" still
bottomed out in an *immature CL libfuse `sb-alien` binding* (`14 §7.1`), and far better than an
OCaml↔C `ctypes` boundary. The "interop tax" here is **not marshaling** (there is none); it is the
narrower question of **interop *ergonomics*** — how a Shen function names and invokes a Go function,
and how a Go struct (e.g. `*object.Commit`) is represented as a value the Shen side can hold and pass
back. That is a real but bounded concern, and it is a **P0 gating spike** (§1.3, §10 spike B).

### 1.2 What is Shen, what is Go

```
┌──────────────────────────────────────────────────────────────────────┐
│  PURE SHEN  (typed, total, host-agnostic — the BRAIN)                  │
│  • land FSM (datatype sequent rules)            §3.1                   │
│  • merge-result type + structural-conflict detection driver §3.3      │
│  • ACL proof type; Shen-Prolog policy rules     §2, §3.4              │
│  • landed-log entry construction + checksum-chain logic (pure) §4     │
│  • CLI command parsing; dirstate diff logic; restack-on-land §6       │
├──────────────────────────────────────────────────────────────────────┤
│  SHEN ADAPTERS  (narrow, you own — the C1 seam; thin over Go)         │
│  • object-store  : put/get-blob, read/write-tree, commit, tree-merge  │
│  • durable-log   : fsync'd, CAS-fenced LTX landed-log append          │
│  • mount-bridge  : Readdir/Read/Getattr callbacks (bazil/fuse)        │
│  • lease         : with-leadership capability over litefs lease       │
│  • replica       : LTX stream pull/apply                              │
├──────────────────────────────────────────────────────────────────────┤
│  GO BODY  (in-runtime calls — every byte of IO; the BODY)            │
│  • go-git/v6      : CAS blob/tree/commit, history, GC, ORT 3-way merge │
│  • superfly/ltx   : LTX file format (header+pages+trailer, checksum)   │
│  • superfly/litefs: leased primary, replica streaming, position cookie │
│  • bazil.org/fuse : pure-Go FUSE mount (no cgo)                        │
│  • goroutines+chan: land-worker, replica-streamer, mount-server        │
│  • os/syscall     : fsync, pwrite, rename (durability)                 │
└──────────────────────────────────────────────────────────────────────┘
```

The Shen brain is **identical to `14`**; only the bottom two layers change from SBCL primitives to
in-runtime Go calls. That identity is the point: the expensive, reviewed, type-driven design is
preserved; the risky body is replaced with mature code.

### 1.3 The Shen↔Go call boundary — concretely

`shen-go` exposes Go functions to Shen by registering them as KL primitives (native functions the KL
evaluator can invoke). The pattern we adopt: write a **thin Go shim package** (`gobody/`) that
exports exactly the operations our Shen adapters need, with **flat, value-oriented signatures** (no
Go interfaces or generics across the boundary — pass hashes as strings, bytes as byte vectors,
structs as opaque handles keyed by an integer or a content hash). Shen calls those shims by their
registered KL symbol.

```shen
\* Shen adapter (the C1 seam). The ONLY Shen module that names the Go shim.
   `go-git.commit` is a KL primitive registered by gobody/ in §2 of the layout.
   No marshaling: the byte vector and strings are passed in-runtime. *\
(define commit-tree
  Store Parent Tree Meta ->
  (gobody.commit Store Parent Tree                 \* Tree is a go-git tree hash (string) *\
                 (meta-author Meta) (meta-message Meta)
                 (meta-change-id Meta) (meta-idem-key Meta)))

\* Shim contract (Go side, gobody/store.go), registered as KL primitive "gobody.commit":
   func Commit(store *Store, parent, tree, author, msg, changeID, idem string) (string, error)
   -> returns the new commit hash. go-git writes the object; Shen never sees *object.Commit. *\
```

**Handle discipline.** Where a Go value cannot be flattened to a string/bytes (e.g. an open
`*git.Repository`, a `fuse.Conn`, a held lease), the shim keeps it in a Go-side registry and hands
Shen back a small opaque token (an interned integer or the store path). Shen treats the token as
abstract. This keeps the boundary value-oriented and keeps Go's rich types out of the Shen domain —
which is *also* exactly what C1 demands (no `go-git.*` types in `domain.shen`).

**Concurrency boundary.** Shen has no concurrency; Go does. We do **not** try to make Shen
thread-aware. Instead: each long-lived concurrent activity (land-worker, replica-streamer, each FUSE
request) is a **goroutine that calls *into* the Shen runtime to run a pure-Shen decision function,
then performs the IO in Go.** Crucially, the **Shen KL evaluator instance for the land path is owned
by exactly one goroutine** (the land-worker), so the brain's land logic runs single-threaded by
construction — the Shen analogue of C3's "one domain owns the store." Read-path FUSE goroutines call
only **pure, side-effect-free** Shen functions (e.g. `vfs-read-plan`, `can-read?`) and serve bytes
from a Go-side content-hash cache, so they need no shared Shen mutable state. (Spike B validates that
the `shen-go` KL runtime is safe to call from multiple goroutines for the *pure* read functions, or
that we pool per-goroutine evaluators.)

---

## 2. Project layout

```
shengo-vfs/
├── go.mod                       # pins go-git/v6, superfly/ltx, superfly/litefs, bazil.org/fuse
├── go.sum                       # committed; reproducible build
├── vendor/                      # vendored deps (C1 dependency posture) — pinned commits
│   ├── github.com/go-git/go-git/v6
│   ├── github.com/superfly/ltx
│   ├── github.com/superfly/litefs
│   └── bazil.org/fuse
├── gobody/                      # the Go shim: registers KL primitives the Shen adapters call
│   ├── runtime.go               # shen-go KL runtime init + primitive registration
│   ├── store.go                 # go-git: put/get-blob, read/write-tree, commit, ORT merge
│   ├── ltxlog.go                # ltx: build/append/verify LTX entries; fenced CAS append
│   ├── litefs_lease.go          # litefs: lease acquire/renew/observe; position cookie
│   ├── fuse.go                  # bazil/fuse: mount, dispatch Readdir/Read/Getattr to Shen
│   ├── replica.go               # LTX stream pull/apply; replica applied-seq tracking
│   └── handles.go               # opaque-handle registry (repo, conn, lease tokens)
├── brain/                       # PURE SHEN — copied/forked from plan 14, host-agnostic
│   ├── types.shen               # datatype: change-states, lease, merge-result, acl  (§3)
│   ├── land.shen                # land-one FSM driver                                 (§5)
│   ├── merge.shen              # merge-tree total fn: structural detect + ort driver  (§3.3)
│   ├── acl.shen                 # defprolog ACL/admission/conflict-class             (§2-prolog)
│   ├── policy.shen              # load/reload homoiconic policy from trunk            (§7-policy)
│   ├── log.shen                 # pure landed-log entry construction + checksum chain
│   ├── dirstate.shen            # status/diff O(changes) logic                        (§3-C5)
│   ├── stack.shen               # local commit stacks + restack-on-land              (§6)
│   └── cli.shen                 # command parsing/dispatch
├── adapters/                    # SHEN adapters — the C1 seam; only these name gobody.*
│   ├── object-store.shen
│   ├── durable-log.shen
│   ├── lease.shen
│   ├── mount-bridge.shen
│   └── replica.shen
├── cmd/shengo/main.go           # entrypoint: init shen-go runtime, load brain+adapters, dispatch
└── test/
    ├── fault/                   # Go-driven fault injection (kill leader mid-append, etc.)
    └── prop/                    # property tests for merge totality, checksum chaining
```

**Go dependencies (pinned, vendored):**

| Dep | Module | Role |
|---|---|---|
| go-git | `github.com/go-git/go-git/v6` | CAS object model (blob/tree/commit), history, GC, **ORT 3-way merge + rename detection** |
| ltx | `github.com/superfly/ltx` | LTX file format: 100-byte header (MinTXID/MaxTXID/PreApplyChecksum) + sorted pages + trailer (PostApplyChecksum); the chaining invariant |
| litefs | `github.com/superfly/litefs` | leased single-primary, replica LTX streaming, `(TXID,checksum)` position cookie |
| bazil/fuse | `bazil.org/fuse` | pure-Go FUSE (no cgo) mount |
| shen-go | `github.com/tiancaiamao/shen-go` | the KL runtime the brain compiles onto |

The brain modules under `brain/` are **the Shen sources from `14` essentially unchanged**. The whole
delta of this plan lives in `gobody/` and `adapters/`.

---

## 3. The Shen datatype / defprolog skeleton (the brain, written out)

These are reproduced from `14 §2.2`/`§2.1` because the brain is deliberately unchanged; the point of
this plan is that the *body* changed, not the brain. They are restated in full so this document is
self-contained and so the reviewer can confirm the type guarantees survive the Go swap intact.

### 3.1 Land FSM — illegal transitions don't typecheck (`brain/types.shen`)

```shen
(datatype change-states

  \* A submitted change carries base, paths, idempotency key — nothing more. *\
  ____________________________________________________________________
  (submitted ChangeId Base Paths IdemKey) : (change submitted);

  \* Build `admitted` only by SUPPLYING an acl-proof (rule set §3.4, unforgeable). *\
  C : (change submitted);
  Proof : acl-proof;
  =============================  (admit)
  (advance-admitted C Proof) : (change admitted);

  \* Build `merged` only from `admitted` + a merge-result that is specifically Merged
     (§3.3); a Conflict has a different type and cannot be passed here. *\
  C : (change admitted);
  T : merged-tree;
  =============================  (merge)
  (advance-merged C T) : (change merged);

  \* `land` only a `merged` change while HOLDING a lease-witness (§3.2). *\
  C : (change merged);
  W : lease-witness;
  Seq : landed-seq;
  =============================  (land)
  (advance-landed C W Seq) : (change landed);)
```

### 3.2 Lease capability — a stale-leader land is a compile error (`brain/types.shen`)

```shen
(datatype lease
  \* No introduction rule for lease-witness — it is opaque. The ONLY producer is
     with-leadership, which hands a witness to a continuation valid only there. *\
  Body : (lease-witness --> (A));
  ===========================================  (with-leadership)
  (with-leadership Store Body) : (result A lease-lost);)
```

```shen
\* adapters/lease.shen: the TYPE above is the guarantee; this is the mechanism.
   Acquires the litefs lease + CAS-fences the landed-log head (§4), runs Body,
   RE-VALIDATES the lease after fsync, before ack (C4). *\
(define with-leadership
  Store Body ->
  (let Tok (gobody.lease-acquire Store)            \* litefs lease (Go) *\
    (if (gobody.lease-held? Tok)
        (let W (mk-witness Tok)                      \* witness exists only in this let *\
             R (Body W)
          (if (gobody.lease-still-fenced? Tok) (ok R) (error lease-lost)))
        (error lease-lost))))
```

Because `lease-witness` has no public constructor and `advance-landed` (rule `land`) requires one,
**the application cannot originate a split-brain land** — Aphyr's C4 split-brain is unrepresentable in
Shen code. Storage-layer fencing (§4) still handles the truly-concurrent race.

### 3.3 Merge as a total function returning a sum (`brain/types.shen` + `brain/merge.shen`)

```shen
(datatype merge-result
  T : tree;
  ________________________________  (merged)
  (merged-ok T) : merged-tree;

  P : path; Hs : (list hunk);
  ____________________________________________  (text-conflict)
  (text-conflict P Hs) : merge-conflict;

  P : path; K : struct-kind;        \* rename-rename | delete-modify | rename-edit | ... *\
  ____________________________________________  (struct-conflict)
  (struct-conflict P K) : merge-conflict;)
```

```shen
\* Total: every (base, ours, theirs) maps to exactly one constructor.
   The TEXTUAL 3-way merge and rename detection are go-git's ORT strategy (real code).
   The structural cases go-git's per-file merge can still surface ambiguously are
   re-classified into OUR explicit constructors (C5) so the caller must handle them. *\
(define merge-tree
  Store Base Ours Theirs ->
  (let R (gobody.merge-ort Store Base Ours Theirs)   \* go-git ORT 3-way + rename detect *\
    (cond
      ((ort-clean? R)      (merged-ok (ort-tree R)))
      ((ort-text? R)       (conflicts (map mk-text-conflict (ort-text-hunks R))))
      (true                (conflicts (map mk-struct-conflict (ort-structural R)))))))
```

**This is the upgrade `14` could only promise and `07`/`12` flagged as overclaimed (C5):** here the
textual diff3 *and* rename detection are **go-git's purpose-built, battle-tested ORT/recursive merge**
(synonym of recursive since Git 2.50), not a few-hundred-LOC hand-rolled diff3. The Shen side's job is
to **make the result total and force the caller to handle every conflict class** via the sum type —
which go-git's API does not do for you. That division (Go does the hard textual work; Shen makes the
result an unignorable type) is the whole thesis in miniature.

### 3.4 ACL proof — unforgeable, consumed by admission (`brain/types.shen` + `brain/acl.shen`)

```shen
(datatype acl
  \* No public constructor for acl-proof. acl-check is the sole producer.
     The proof is TAGGED with the trunk tip it was evaluated against (stale-proof detect). *\
  S : subject; Ps : (list path); A : action; Tip : commit-id;
  ===================================================================  (acl-check)
  (acl-check S Ps A Tip) : (result acl-proof denied);)
```

```shen
(define acl-check
  S Ps A Tip ->
  (if (all? (lambda P (can? S A P)) Ps)        \* can? drives the defprolog rules below *\
      (ok (mk-proof S Ps A Tip))                \* mk-proof is private to brain/acl.shen *\
      (error denied)))
```

### 3.5 Path-scoped ACL / admission / conflict-class — Shen-Prolog (`brain/acl.shen`)

Native `defprolog` (no separate engine); rules are **policy-as-data** loaded from the repo (§7).

```shen
\* member(Subject, Group) *\
(defprolog member
  Alice eng <-- ;
  Bob   eng <-- ;
  Carol sec <-- ;)

\* grant(Subject-or-Group, Action, PathPrefix, Effect) *\
(defprolog grant
  eng   read  "src/"           allow <-- ;
  eng   write "src/app/"       allow <-- ;
  sec   read  "src/secrets/"   allow <-- ;
  eng   read  "src/secrets/"   deny  <-- ;     \* deny beats inherited eng/src allow *\
  Carol land  "src/secrets/"   allow <-- ;)

\* applies: direct grant OR via group membership *\
(defprolog applies
  Subj Action Prefix Effect <-- (grant Subj Action Prefix Effect) ;
  Subj Action Prefix Effect <-- (member Subj Group) (grant Group Action Prefix Effect) ;)

\* prefixp: host string op (a gobody string primitive) behind a pure predicate *\
(defprolog prefixp
  Prefix Path <-- (when (gobody.string-prefix? Prefix Path)) ;)

\* effective decision: longest matching prefix wins; among ties, deny wins *\
(define can?
  Subj Action Path ->
  (resolve-acl (collect-applies Subj Action Path)))   \* findall over applies+prefixp *\

(define resolve-acl
  []    -> false
  Cands -> (let Best (max-prefix-length Cands)
                Tied (filter (lambda C (= (snd C) Best)) Cands)
             (if (some? (lambda C (= (fst C) deny)) Tied) false true)))
```

```shen
\* Conflict-class admission — a CHEAP pre-filter off the serialized path.
   Authority on conflict is the real merge (§3.3); this is only a fast hint. *\
(defprolog conflict-class
  Paths1 Paths2 <-- (member-path P1 Paths1) (member-path P2 Paths2)
                    (path-related P1 P2) ;)

(define admit-disjoint?
  Paths1 Paths2 -> (not (prolog? (conflict-class Paths1 Paths2))))
```

`can-read?`/`can-submit?`/`can-land?` are `can?` partially applied. **One rule base, two enforcement
points** (VFS read; land admission) — exactly the OCaml/`14` design.

---

## 4. Land FSM + replication protocol (go-git + litefs/ltx), fencing, RYW, durability-width

### 4.1 Data model (same as `07`/`14`)

- **Blob** = file content, content-addressed (SHA-256) by **go-git**. Stored once.
- **Tree** = go-git tree object; lazy subtree access is O(depth) → the sparse-fetch property.
- **Commit (= landed change)** = a go-git commit on the **single trunk ref** (`refs/heads/trunk`);
  metadata: `change-id` (stable across revisions, carried in a commit trailer), `author`, `message`,
  single `parent` (trunk is linear), `landed-seq`, `paths-touched`, `idem-key`.
- **No branches in durable history.** Local work = local go-git commits (a stack); trunk only via
  landing. (go-git *supports* branches; we restrict durable history to the one trunk ref.)
- **Landed-log** = the **LTX chain**: each landed commit produces an LTX entry whose header carries
  `MinTXID/MaxTXID = landed-seq`, a **`PreApplyChecksum`** == prior entry's `PostApplyChecksum`, and
  a trailer `PostApplyChecksum`. The LTX "pages" we store are the **(landed-seq, commit-hash,
  fencing-token)** record (we are not replicating SQLite pages — we are reusing LTX's *format and
  chaining invariant* as our landed-log). Sole replication substrate + RYW cookie + audit trail.

### 4.2 The fencing token, CAS'd on durable append (C4 / P1)

Two layers, both required (identical guarantee to `14 §C4`, now on real `ltx` code):

1. **Type layer (§3.2):** `advance-landed` requires a `lease-witness`; the app cannot *originate* a
   split-brain land.
2. **Storage layer:** the LTX append carries a **monotonic fencing token** (the `MaxTXID`/landed-seq
   itself serves as the monotone fence, with the held-lease epoch folded in). The Go durable writer
   **CAS's the fence on the fsync'd append** and **re-validates the lease after fsync, before ack**.
   A stale leader's append fails the CAS and is **rejected** — detect *and refuse*, not LTX's native
   detect-and-discard. (LTX's checksum chain natively *detects* a fork; we add the CAS so the loser
   is refused at append rather than discarded after the fact — this closes the §4.3 honesty gap as
   far as it can be closed without consensus.)

```shen
\* Pure construction of the next LTX log entry (checksum-chained). brain/log.shen *\
(define next-log-entry
  PrevEntry Commit Token ->
  (let Pre  (post-checksum PrevEntry)
       Post (roll-checksum Pre Commit)
    (log-entry (+ (seq PrevEntry) 1) Commit Token Pre Post)))

\* adapters/durable-log.shen → gobody (ltx). Fenced, fsync'd, returns durability width (P2). *\
(define durable-append!
  Store Entry Token ->
  (gobody.ltx-append-fenced Store Entry Token))   \* CAS fence + fsync + replica-ack-width *\
```

```go
// gobody/ltxlog.go — the Go body. CAS on the durable head, fsync BEFORE ack, then poll acks.
func LtxAppendFenced(s *Store, entry Entry, token uint64) (width int, err error) {
    s.mu.Lock(); defer s.mu.Unlock()
    if token <= s.fenceHead { return 0, ErrStaleLeader }   // CAS: monotone fence
    if err := writeLTX(s.logFile, entry); err != nil { return 0, err }
    if err := s.logFile.Sync(); err != nil { return 0, err } // fsync BEFORE ack (durable-on-leader)
    if !s.lease.StillHeld() { return 0, ErrStaleLeader }     // re-validate after fsync
    s.fenceHead = token
    return s.replicaAckWidth(entry), nil                      // 0..N replicas acked → P2 signal
}
```

### 4.3 Replication, RYW cookie, durability width — consistency stated honestly

- **One leased land-leader** via **litefs**'s lease (Consul TTL or static primary). Only the leader
  lands; the fencing token (§4.2) makes the lease *fenced*, not merely TTL'd.
- **Replication** = replicas async-pull the **LTX landed-log** stream + the referenced go-git objects
  and apply by verifying the checksum chain (litefs's native model). **Read-your-writes** via the
  `(landed-seq, checksum)` **position cookie**: a read waits until the replica's applied-seq ≥ the
  client's last landed seq; **on timeout it falls back to the leader** with a stated staleness bound
  (P4 — no deadlock under partition).
- **Consistency, honestly:** trunk landing is linearizable *because one leader + one append-only
  trunk*, not because of consensus. **litefs replication is ASYNC** — there is a real
  **data-loss window**: a commit fsync'd on the leader but not yet pulled by any replica is lost if
  the leader's disk dies before the LTX entry propagates (litefs's documented subsecond window).
  **Mitigation, sized to moderate scale, not consensus:**
  - leader **fsyncs the go-git commit + the LTX entry before acking** (durable-on-leader);
  - optional **durability-width knob**: wait for **1 replica ack** (width 2) before ack;
  - the ack **returns the achieved durability width (P2)**, so the client can distinguish
    *durable-on-leader-only* from *durable-on-N* and apply its own policy.

  This is the proven LiteFS shape. If multi-DC HA is later required, *that* is when consensus
  (Raft/etcd) returns — deferred, not designed in. **We do not claim litefs gives us
  consensus-grade durability; we state the window and give a knob.**

---

## 5. The land queue (the heart) — same FSM, Shen-typed, Go-bodied (`brain/land.shen`)

1. **Client** builds local go-git commits; `submit`s `(base, paths, change-id, idem-key)`.
2. **Admission** (off the serialized path): `can-submit?`/`can-land?` (Shen-Prolog), blob presence,
   `admit-disjoint?` fast hint. Produces a typed, tip-tagged `acl-proof`.
3. **Land (serialized, leader-only, single goroutine owns the land-evaluator, inside
   `with-leadership`):** dedup by idem-key against trunk history (same critical section); OCC
   base-check (`base == trunk-tip`? fast-path : `merge-tree onto tip` — the real go-git ORT merge);
   clean → `commit-tree`, assign `landed-seq`, `durable-append!` (fsync + fence CAS), ack with
   achieved durability width; conflict → reject with conflicting paths/hunks.

```shen
(define land-one
  Store Submitted ->
  (with-leadership Store
    (lambda W
      (let Proof (acl-check (author Submitted) (paths Submitted) land (trunk-tip Store))
        (if (error? Proof) Proof
          (if (already-landed? Store (idem-key Submitted))     \* dedup, same section (P3) *\
              (ok-idempotent Store (idem-key Submitted))
            (let Adm  (advance-admitted Submitted (ok-val Proof))
                 Mres (merge-tree Store (base-tree Store (base Adm))
                                  (change-tree Store Adm)
                                  (trunk-tip-tree Store))
              (if (conflict? Mres)
                  (reject (conflicts-of Mres))
                  (let Mgd   (advance-merged Adm (merged-ok-tree Mres))
                       Cid   (commit-tree Store (some (trunk-tip Store)) (tree-of Mgd) (meta Adm))
                       Entry (next-log-entry (log-head Store) Cid (token-of W))
                    (durable-append! Store Entry (token-of W)))))))))))   \* atomic land (P3) *\
```

Every illegal ordering is rejected **by the type checker** before it runs: no `advance-merged` on a
non-admitted change; no `commit`/`append` without a `merged` change and a `lease-witness`. The runtime
logic is happy-path plumbing.

**Throughput:** single-leader serialized landing is fine for hundreds of devs. The Shen interpreter
adds overhead over raw Go, but **landing is not the hot path** — the VFS read path is, and it is
served from a **Go-side content-hash cache** that mostly bypasses Shen per byte (§1.3). go-git's
native commit/merge is fast; the brain only orchestrates.

---

## 6. Stacked changes / Change-Id with restack-on-land (P5) (`brain/stack.shen`)

- A developer's local work is a **stack of local go-git commits**, each carrying a stable **Change-Id**
  trailer (Gerrit-style, minted once and preserved across amends/rebases). Stacks are a client concern
  over go-git history; durable trunk stays linear.
- **Restack-on-land spec (closes P5):** when the bottom change of a stack lands (its Change-Id now
  appears in trunk), the client **rebases the remainder of the stack onto the new trunk tip**:
  1. fetch the new trunk tip + landed-seq;
  2. for each remaining local commit (bottom-up), `merge-tree`/cherry-pick it onto the advancing tip
     using go-git, **preserving its Change-Id**;
  3. if a rebased change now lands identically to what trunk already has (the leader merged an
     equivalent), detect via Change-Id and **drop it as already-landed** (P3 idempotency reused);
  4. surface any rebase conflict using the same `merge-result` sum type (§3.3) — the developer
     resolves locally, never "resubmit from scratch."
- `submit` of a stack submits the **bottom-most unlanded change** first; the land queue lands one at a
  time, and the client restacks after each landed notification (driven by the landed-log RYW cookie so
  the client restacks against a tip it can actually read).

---

## 7. Homoiconic policy-as-data (`brain/policy.shen`)

The `defprolog` ACL rules, group memberships, and conflict-class rules (§3.5) are Shen S-exprs, stored
as a blob at a reserved path (`.shengo/policy.shen`) **inside the trunk**, content-addressed like any
file.

- Policy changes go through the **same land queue and ACL gate** as code (you need `can-land?` on
  `.shengo/policy.shen`, bootstrapped by an initial admin grant). Policy history is repo history;
  blame/time-travel on policy is free.
- The land-leader **loads the rule base from the trunk tip** at each land, so policy is always the
  durably-landed version — no out-of-band ACL store to drift (honors C2: one source of truth; ACLs are
  **not** secretly authoritative in any index).

```shen
(define load-policy
  Store -> (read-shen-forms
             (gobody.tree-lookup-blob Store (trunk-tip Store) ".shengo/policy.shen")))
(define reload-policy!
  Store -> (eval-defprolog-forms (load-policy Store)))
```

This self-describing-VCS property is **native** in Shen (homoiconic) where it would be bolt-on
elsewhere — and it composes cleanly with go-git's content-addressing underneath.

---

## 8. Honoring the panel obligations (C1–C5) in Shen-on-Go terms

### C1 — go-git behind a narrow Shen seam you own
No `go-git.*` (and no Go struct type) appears in the domain. `adapters/object-store.shen` defines the
interface as Shen signatures; only that module names the `gobody` shims. **Minus Irmin's churn worry:**
go-git is stable, widely used, and **pinned to an exact commit + vendored** — there is no
Tezos-cadenced quarterly-breaking upstream under the data, and no on-disk format migration treadmill
(the on-disk format *is* the Git object format, which is frozen). The seam still buys swap-ability
(e.g. to a hand-rolled pack store) and lets a read cache sit in front (P6). CI keeps a
**format-round-trip drill** (export to git fast-import stream → reimport) as cheap insurance.

```shen
(declare put-blob    [store --> blob --> hash])
(declare get-blob    [store --> hash --> (maybe blob)])
(declare read-tree   [store --> hash --> (list tree-entry)])
(declare write-tree  [store --> (list tree-entry) --> hash])
(declare commit-tree [store --> (maybe commit-id) --> hash --> commit-meta --> commit-id])
(declare tree-merge  [store --> hash --> hash --> hash --> (result merged-tree (list merge-conflict))])
(declare gc-store    [store --> store])
```

### C2 — ONE replication system; the projection index is a local rebuildable cache
The **LTX landed-log is the sole replication substrate** (litefs streams it; replicas apply by
checksum chain). Any query index (commit graph, blame, path history) is a **derived local projection**
rebuilt by replaying the log — a plain embedded store (e.g. a local SQLite via a Go shim, or bbolt),
**never replicated independently**. ACLs are not authoritative in the index — they live in
`.shengo/policy.shen` in the trunk (§7). One source of truth.

### C3 — single goroutine owns the land path; no exotic concurrency bridge
**One goroutine owns the land-evaluator and is the only thing that mutates trunk/log.** Reads are
served from a **content-hash-keyed Go cache** (immutable objects ⇒ correct by construction) in front
of go-git; replica-streamer and FUSE goroutines never write trunk and call only pure Shen functions.
**There is no Lwt/Eio-equivalent bridge** — Go's goroutines/channels are the native runtime and Shen
compiles *into* it, so C3's biggest OCaml hazard simply does not exist (this plan shares that virtue
with `14`, but without `14`'s immature-libfuse cost). Concurrency is one runtime, one binary.

### C4 — fencing token CAS'd on durable append + type guard
§4.2: `gobody.ltx-append-fenced` CAS's the monotone fence on the fsync'd LTX append and re-validates
the litefs lease after fsync, before ack; `lease-witness` (§3.2) makes app-originated split-brain a
type error. Honest note: litefs lease + LTX checksum chain natively *detect* a fork; the CAS upgrades
that to *refuse the stale appender* at the durable head.

### C5 — real merge + real dirstate
- **Merge:** the total `merge-tree` (§3.3) wrapping **go-git's ORT/recursive 3-way merge with rename
  detection** — real, purpose-built code answering Torvalds directly; structural cases re-expressed as
  unignorable Shen sum constructors. No hand-rolled diff3.
- **Dirstate:** a real Git-index-style dirstate `(path,size,mtime,ctime,inode,blob-hash)` built in
  **P1**, working **without** the mount: `status`/`diff` stat entries (Go `os.Stat`), short-circuit on
  `(size,mtime,ctime,inode)`, re-hash only suspects → **O(changes)**. (go-git already maintains a Git
  index we can build on.) The mount (P5) later *upgrades* dirstate via FUSE write-tracking; we do not
  claim O(changes) before the index exists.

### P3 — one atomic land authority (commit → derived log entry)
`commit-tree` returns a commit-id; the LTX entry is **derived deterministically** from it inside the
same serialized critical section (§5). The go-git commit is the source of truth; the LTX entry is the
rebuildable projection of *ordering*. Idem-key in commit trailer, deduped by reading trunk history in
the same section. No dual-authority returns.

---

## 9. Fault-injection test strategy

Because the body is **Go**, fault injection is first-class and in-process (no cross-language harness):

- **Leader kill mid-append** (`test/fault/`): a Go test holds the land goroutine, kills the process
  (or the `*os.File` for the log) between `writeLTX` and `Sync`, and after `Sync` but before ack;
  assert (a) no torn LTX entry survives recovery (checksum chain rejects it), (b) a non-fsync'd entry
  is absent, (c) a fsync'd-but-unacked entry is present and recoverable.
- **Split-brain / stale leader:** spin two land goroutines with overlapping lease epochs; assert the
  stale one's `LtxAppendFenced` fails the CAS (`ErrStaleLeader`) and that the *type layer* already
  prevented it from constructing `advance-landed` without a fresh witness in tests of the brain.
- **Replica lag / partition (P4):** drop the LTX stream; assert the RYW cookie read times out and
  falls back to the leader within the stated staleness bound; assert no deadlock.
- **Durability-width (P2):** kill leader after width-1 (leader-only) vs width-2 (1 replica) acks;
  assert the data-loss window matches the configured knob and the ack signal told the client the
  truth.
- **Merge totality (`test/prop/`):** property test that `merge-tree` returns exactly one constructor
  for randomized (base,ours,theirs) triples including rename/edit and delete/modify; the Shen type
  checker statically guarantees exhaustive handling, the property test guarantees totality of the Go
  ORT driver beneath it.
- **Checksum-chain invariant:** property test that `entry[N+1].pre == entry[N].post` holds across
  randomized append/compaction sequences (reuse ltx's own verification).
- **go-git concurrent multi-reader (Spike A, then a standing benchmark):** N goroutines reading random
  path subsets through the mount path with GC running; track p99 latency and contention.

---

## 10. Phased plan (VCS-first, P0–P6) with the two gating spikes

| Phase | Deliverable | Shen-on-Go specifics |
|---|---|---|
| **P0 — Spine + the two gating spikes** | go-git behind the `object-store` seam (C1); the four `datatype` invariant skeletons (§3.1–§3.4); Shen-Prolog ACL stub (§3.5); pinned+vendored deps; CI format-round-trip drill. **Gating Spike A:** go-git concurrent multi-reader perf behind a mount (N goroutines, random path subsets, GC on). **Gating Spike B:** Shen↔Go interop ergonomics — register go-git/ltx/fuse shims as KL primitives, confirm value-oriented call patterns and per-goroutine evaluator/pure-call safety; measure Shen interpreter overhead on the read path. | The spike that *replaces* `14`'s "build a CL FUSE binding" risk is **Spike B**: prove the in-runtime Shen→Go call boundary is ergonomic and that the runtime is safe to call from goroutines for pure reads. |
| **P1 — Nice single-machine VCS** | local go-git commits + stacks; **real dirstate + O(changes) status/diff** (no mount, `os.Stat`); **total `merge-tree`** wrapping go-git ORT (§3.3); no-mount sparse checkout via lazy trees. | Pure Shen brain + go-git body; no IO outside the seam. |
| **P2 — Land queue + fencing** | `with-leadership` + `land-one`; **fencing token CAS'd on fsync'd LTX append** (§4.2); idempotency in commit trailer; ack returns durability width (P2). | The type-level lease witness (§3.2) lands here; `ltx` is the log format. |
| **P3 — ACL (Shen-Prolog) + derived index** | full path-scoped ACL (prefix/deny-wins/groups); policy-as-data in `.shengo/policy.shen` (§7); derived projection index (local, rebuildable, not replicated — C2). | Shen-Prolog becomes load-bearing. |
| **P4 — Distribution** | leased leader (litefs); LTX replica streaming (sole replication — C2); RYW cookie + timeout→leader fallback (P4); durability-width knob. | Transport = litefs/ltx; concurrency = goroutines/channels. |
| **P5 — Mount + restack** | `bazil.org/fuse` lazy mount over go-git trees; FUSE write-tracking → dirstate upgrade; sparse profiles; **restack-on-land** spec implemented (§6). | bazil/fuse is **pure Go, no cgo** — the single biggest improvement over `14`'s immature CL libfuse. |
| **P6 — Hardening** | failover drills (`test/fault/`), backpressure, audit, ops runbooks; read-path cache tuning; standing go-git multi-reader benchmark; type-checker compile-time budget. | Single static binary deploy. |

Critical path **P0→P1→P2** is a usable single-node trunk VCS *with real merge and fast status* — the
Torvalds "prove this first" deliverable. Distribution and mount follow.

---

## 11. Traceability — Shen-on-Go plan vs. panel obligations (C1–C5, P1–P7)

| Obligation | Source | How this plan honors it |
|---|---|---|
| **C1** Abstract the store; own the seam; pin/vendor/drill | Fukamachi+Minsky Blocker | `object-store` Shen interface (§8 C1); only `adapters/object-store.shen` names `gobody`; go-git pinned+vendored; **no Irmin churn** (frozen Git on-disk format); format-round-trip CI drill. |
| **C2** One replication system; index is local rebuildable cache | Torvalds+Fukamachi+Minsky | LTX landed-log (litefs) is sole replication; derived projection index local & rebuildable, never replicated; ACLs in trunk, not index (§8 C2, §7). |
| **C3** Single/pinned execution; no exotic concurrency bridge | Fukamachi+Minsky Blocker | One goroutine owns land-evaluator + trunk writes; hash-keyed read cache; **no Lwt/Eio bridge** (Shen compiles into the Go runtime) (§8 C3, §1.3). |
| **C4** Fencing token CAS'd on durable append + type guard | Aphyr Critical + Minsky | `gobody.ltx-append-fenced` CAS's monotone fence on fsync, re-validates lease before ack; `lease-witness` makes app-originated split-brain a type error (§3.2, §4.2). |
| **C5** Real merge + real dirstate; no overclaim | Torvalds Showstopper + Minsky | Total `merge-tree` wrapping **go-git ORT 3-way + rename detection** (real code) + structural conflict constructors; Git-index dirstate in P1, O(changes), works without mount (§3.3, §8 C5). |
| **P1** Fencing token for lease handoff | Aphyr | §4.2 (same as C4). |
| **P2** Ack carries durability signal | Aphyr | `ltx-append-fenced` returns achieved replica-ack width; client policy on it (§4.2–§4.3). |
| **P3** Idempotency = one atomic authority | Aphyr+Minsky | go-git commit → derived LTX entry, one atomic land step; idem-key in commit trailer, deduped in serialized section (§5, §8 P3). |
| **P4** RYW cookie deadlock under partition | Aphyr | `(landed-seq,checksum)` cookie with **timeout → leader fallback** + stated staleness bound (§4.3). |
| **P5** Stacked-change restack-on-land spec | Torvalds | Local go-git commit stacks + Change-Id; explicit restack-on-land algorithm (§6). |
| **P6** Store concurrency behind multi-reader VFS validated early | Minsky+Torvalds | **P0 Gating Spike A** (go-git concurrent multi-reader) + standing benchmark (P6); the `object-store` seam allows caching/swapping (§9, §10). |
| **P7** Type-driven domain expressed | Minsky | The four `datatype` sequent rule sets (§3.1–§3.4) — land FSM, lease witness, total merge, ACL proof — Shen's analogue of the four `.mli`. |

---

## 12. Honest risks — Shen-on-Go vs. all-OCaml (and vs. `14`'s Shen-on-SBCL)

This section is the point of the exercise. The brain is identical; the risk profile is not.

### 12.1 The Shen↔Go interop tax (real, but it is *ergonomics*, not marshaling)
Because Shen compiles *to* Go, there is **no FFI marshaling boundary** — values share one heap and one
GC. So the classic FFI taxes (serialization, copying across heaps, C-callback/GC hazards) **do not
apply**. What *does* remain:
- **Ergonomics:** writing the `gobody/` shim layer and registering KL primitives; keeping the boundary
  value-oriented (strings/bytes/opaque handles, no Go generics/interfaces leaking into Shen).
- **Runtime re-entrancy:** confirming the `shen-go` KL runtime is safe to call from multiple
  goroutines for *pure* read functions, or pooling per-goroutine evaluators. This is **Spike B** and
  is the single most important thing to de-risk in P0. If the KL runtime is not goroutine-safe even
  for pure calls, the read path must funnel through a serialized evaluator (a real throughput cost on
  the hot path, mitigated by the Go-side content cache).
- **Debuggability across the boundary:** a panic in Go vs. a Shen type error vs. a KL runtime error
  are three different failure modes; stack traces cross a translation layer. Manageable, but a tax.

### 12.2 litefs async data-loss window (honest, unchanged from the pattern)
litefs replication is **asynchronous**. A commit fsync'd on the leader but not yet streamed to any
replica is **lost** if the leader's disk dies first (litefs's documented subsecond window). We mitigate
with fsync-before-ack and an optional 1-replica-ack durability-width knob, and we **return the achieved
width** so clients know. We do **not** claim consensus-grade durability. At moderate scale this is the
right trade; if zero-loss multi-DC HA is later required, that is a future consensus layer, not this
plan. This risk is identical whether the brain is Shen, OCaml, or Go — it is a property of the chosen
distribution model, stated plainly.

### 12.3 go-git at monorepo scale (the genuine technical unknown)
go-git is mature and pure-Go, but like irmin-pack it is **not proven at 10M-file/500k-commit monorepo
scale**, and its concurrency story behind a high-fan-out multi-reader mount is the real unknown
(Spike A). Known soft spots: pack-file read performance and memory under large histories; some
operations are slower than C git. **Mitigations:** the C1 seam lets a read cache sit in front or a
backend be swapped; sparse/lazy trees keep working-set reads O(profile); P0 Spike A measures it before
the design hardens. At *moderate* scale (hundreds of devs) this is a manageable risk, not a
disqualifier — but it is the place most likely to force engineering work, so it is gated first.

### 12.4 Shen tooling / ecosystem / bus-factor (the worst axis — unchanged from `14`)
- **Tiny ecosystem.** Shen's contributor pool is *much* smaller than Go's (or OCaml's). Bus-factor is
  brutal: a handful of people maintain the language and the `shen-go` port.
- **`shen-go` maturity is now load-bearing.** The user stipulates it is production-ready; this plan
  *depends* on that stipulation. If `shen-go`'s KL runtime has gaps (goroutine safety, performance,
  primitive-registration ergonomics, debug tooling), they hit the hot path. This is the one
  assumption the whole plan rests on, and it should be re-validated in Spike B early.
- **Type-checker ergonomics.** Shen's sequent-calculus checker is powerful but **slow to compile** and
  its **errors are terse**; a bad `datatype` definition can make the checker *loop* (Turing-complete).
  The §3 invariants are worth it, but the iteration loop is slower and the learning curve steeper than
  OCaml's or Go's. Budget compile time (P6).

### 12.5 What is genuinely BETTER than all-OCaml
- **The body is real, mature, and Go.** go-git (real CAS + **real ORT 3-way merge with rename
  detection**, answering Torvalds with code, not a hand-rolled diff3), litefs/ltx (**the actual
  replication code**, not a reimplemented pattern), bazil/fuse (**pure-Go FUSE, no cgo, no libfuse FFI,
  no GC-callback hazard**). OCaml's body needs a hand-written diff3 content type, a churning
  Tezos-cadenced Irmin (with on-disk format migrations under your data), and a libfuse `ocamlfuse`
  binding plus the Lwt↔Eio bridge that Minsky called the *single most fragile cell in the OCaml runtime
  space*. **None of those four OCaml hazards exist here.**
- **No concurrency bridge at all.** Goroutines/channels are the native runtime; Shen compiles into it.
  OCaml's C3 Blocker (Lwt-native-first, Eio-behind-a-spike, bridge hazard) is simply absent.
- **Single static binary deploy.** Go's deployment story (one static binary, cross-compile, no runtime
  to install) beats both OCaml and SBCL.
- **First-class in-process fault injection** in the same language as the body (§9).
- **vs. `14` (Shen-on-SBCL): strictly better on the two things that sank `14`.** `14`'s dominant risks
  were (a) an *immature CL libfuse binding* and (b) having to *build and own* a CAS store (`shen-irmin`
  was fictional). Both vanish: bazil/fuse is mature pure-Go; go-git is a real, maintained CAS+merge
  engine. This plan keeps `14`'s coherent brain and deletes its two worst body risks.

### 12.6 What is genuinely WORSE than all-OCaml
- **Two-language cognitive surface.** The team maintains Shen *and* Go (the `gobody/` shims, the
  build pipeline Shen→KL→IR→Go). All-OCaml is one language/one toolchain — a real maintainability
  asset Minsky valued. (This plan is closer to the panel's "split-stack" option, but with the split
  *inside one binary* rather than across an IPC seam.)
- **Shen ecosystem/bus-factor is worse than OCaml's** (§12.4), which is itself small.
- **Type-checker tooling is worse than OCaml's** (slower, terser, can loop).
- **The whole thing rests on `shen-go` being production-ready** — a single stipulated assumption that,
  if false, is fatal in a way all-OCaml (mature compiler) is not.

### 12.7 Verdict
This is the **best-integrated and lowest-body-risk Shen variant** of the product: it keeps `14`'s
intellectually coherent brain (declarative Prolog policy, sequent-calculus invariants, homoiconic
policy-as-data) while giving it a **real, mature Go body** (go-git's actual 3-way merge, litefs/ltx's
actual replication, bazil's actual pure-Go FUSE) reached by **in-runtime calls with no FFI tax**. Its
remaining risks are concentrated and nameable: (1) `shen-go` runtime maturity and goroutine-safety for
pure reads (Spike B), (2) go-git at monorepo scale (Spike A), (3) the irreducible litefs async
data-loss window, and (4) Shen's small ecosystem/bus-factor and slower type-checker tooling. Against
all-OCaml it **wins decisively on the body** (no Irmin churn, no diff3-by-hand, no libfuse FFI, no
Lwt/Eio bridge, single static binary) and **loses on language-ecosystem maturity and single-toolchain
simplicity.** For a team that values the Shen brain's expressiveness and is willing to own a thin Go
shim layer, it is the strongest Shen-flavored path to shipping.

---

## Appendix — relationship to the document set
This plan is the **all-Shen-on-Go sibling** of the all-Shen-on-SBCL plan (`14`); it builds the **same
product** and discharges the **same obligations** (C1–C5, P1–P7 from `12`), keeping `14`'s Shen brain
verbatim and swapping the body from SBCL to a production-ready Go backend (`shen-go`). It re-expresses
Minsky's `.mli` skeleton (`11`) in Shen sequent calculus (§3) and grounds the distribution/merge
choices in the evidence of `06` (LiteFS/LTX are Go; go-git is the mature Git object model). It is the
Go realization of the panel's "split-stack" intuition (`12 §4`), with the data-plane (Go) and
control-plane (Shen) fused inside a single static binary rather than separated by an IPC seam.
