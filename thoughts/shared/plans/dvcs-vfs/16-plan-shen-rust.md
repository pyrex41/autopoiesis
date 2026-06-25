---
date: 2026-06-25
researcher: Claude
topic: "All-Shen-on-Rust implementation plan for shenrs-vfs — a trunk-only, content-addressable DVCS-VFS at moderate scale, with Shen as the brain compiling to a Rust body (gix/fuser/ltx-rs)"
plan: all-shen-on-rust
status: draft
inputs:
  - thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
  - thoughts/shared/plans/dvcs-vfs/12-synthesis-v2.md
  - thoughts/shared/plans/dvcs-vfs/11-minsky-review.md
  - thoughts/shared/plans/dvcs-vfs/14-plan-shen.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
tags: [shen, shen-rust, rust, gix, gitoxide, fuser, ltx-rs, datalog, prolog, sequent-calculus, dvcs, vfs, trunk, fencing, moderate-scale]
last_updated: 2026-06-25
last_updated_by: Claude
---

# `shenrs-vfs` — an all-Shen-on-Rust trunk-only DVCS-VFS (moderate scale)

This is the **same product** as `07` (direction brief) and its settled synthesis `12`: a
content-addressable, **trunk-only / no-branches**, monorepo distributed VCS with a lazy virtual
filesystem, sized for **moderate scale** (hundreds of developers) — single leased land-leader,
append-only checksum-chained landed-log, **no Raft**, lazy VFS mount, real 3-way merge, real
dirstate, path-scoped ACLs. The build language is **Shen**; the host/runtime is **Rust** (via the
**stipulated, production-ready `shen-rust` backend**).

It is the **sibling of `14`** (all-Shen-on-SBCL): the *Shen brain is reused verbatim* —
`defprolog` ACLs, sequent-calculus `datatype` invariants, homoiconic policy-as-data — and the
**body is swapped SBCL → Rust**. Where `14` bottomed out in `sb-alien`/libfuse/`usocket`, this plan
bottoms out in **`gix` (gitoxide), `fuser`, the `ltx-rs` lineage, and `tokio`**. Because Shen
compiles *to* Rust, the brain calls those crates **in-runtime** — there is **no external process,
no FFI boundary, no IPC**. That single fact is the reason to prefer Rust over the SBCL and Go
variants, and it is what this plan exploits.

It discharges the **same panel obligations** (C1–C5, P1–P7 from `12`) and re-expresses Minsky's
"make illegal states unrepresentable" `.mli` skeleton (`11`) in Shen's **sequent-calculus
`datatype` rules**. It assumes `shen-rust` exists and is production-ready (user stipulation); it
does **not** assume the Rust *crates* are wrapped for free — wrapping `gix`/`fuser`/`ltx-rs` behind
Shen seams is real, scoped work, and §1 is honest about exactly where the dynamic-Shen ↔
ownership-Rust impedance lives.

> Read alongside `07` (product), `12` (settled obligations), `14` (the Shen brain this reuses).
> Where this says "same as `14`", the *Shen* code is identical and only the *body* differs.

---

## 0. The one-paragraph thesis

Keep the Shen brain from `14` unchanged — the land FSM as `datatype` sequent rules, the unforgeable
`acl-proof`, the `lease-witness` capability (stale-leader land = type error), the total
`merge-result`, the `defprolog` path-scoped ACLs, and homoiconic policy-as-data in
`.shenrs/policy.shen`. **Swap the body to Rust.** The defining advantage: because `shen-rust`
compiles Shen's KLambda kernel to Rust, the brain's adapter calls land **inside the same Rust
runtime** as **`gix`** (gitoxide: content-addressed blob/tree/commit object model + history +
**textual 3-way merge with rename detection** — Torvalds' "no merge" answered by a *mature* engine,
not hand-rolled diff3), **`fuser`** (best-in-class Rust FUSE — the strongest mount story of any
backend), and the **`ltx-rs`** append-only checksum-chained transaction log (the litevfs lineage,
in Rust) as the *starting point* you build the leased-primary replication on top of. No GC pauses
matter for a VFS serving syscalls; `tokio` gives async concurrency; the artifact is a static single
binary. The cost, paid honestly: Shen is dynamic and GC'd, Rust is ownership/borrow-checked, and
**`shen-rust` must reconcile the two** — Shen values live on a runtime-managed heap and crate calls
must marshal across that seam without violating Rust's aliasing rules. That reconciliation (§1) is
the subtle, genuinely-hard part, and the rest of the plan is built to keep it on a narrow, well-typed
boundary.

---

## 1. Host/runtime model and the Shen↔Rust boundary (the genuinely tricky part — be honest)

### 1.1 What `shen-rust` actually is, and what "compiles to Rust" buys

Shen compiles to **KLambda (K-Lambda)**, a tiny applicative Lisp kernel (~46 primitives). A "Shen
port" is a KLambda runtime on a host. `shen-rust` is, by stipulation, a production-ready KLambda
runtime **written in Rust**. Two readings of "Shen compiles to Rust", and the honest one matters:

- **(a) Interpreted KLambda on a Rust runtime.** Shen source → KLambda → walked/dispatched by a
  Rust evaluator over a `Value` enum. This is the realistic, robust reading and what most KLambda
  ports do. The "compiles to Rust" then means *the runtime is Rust*, and Shen↔crate calls are
  Rust function calls dispatched through that runtime.
- **(b) Ahead-of-time transpilation KLambda → Rust source.** Each Shen function becomes a Rust
  `fn` over the runtime `Value` type. Faster, but every function still closes over the **same
  dynamic `Value` representation** and the **same runtime GC** — it does *not* turn Shen into
  borrow-checked Rust. AOT changes the perf profile, not the impedance.

**Either way, the brain runs over a single dynamic `Value` type managed by `shen-rust`'s runtime.**
We do **not** assume Shen functions become ownership-typed Rust. That assumption would be the lie
this section exists to refuse.

The thing "in-runtime" genuinely buys over shen-on-Go and shen-on-SBCL: **the crates we call
(`gix`, `fuser`, `ltx-rs`, `tokio`) are Rust crates compiled into the same binary as the
`shen-rust` runtime.** A Shen adapter calling `gix` is one Rust frame calling another Rust frame in
the same address space, same allocator domain, same `tokio` reactor — **no FFI marshaling across a C
ABI (unlike SBCL's `sb-alien`), no subprocess/IPC (unlike a Go litefs daemon), no serialization.**
That is the structural win (§9).

### 1.2 The impedance mismatch — Shen's dynamic GC'd values vs Rust's ownership (candid)

This is the subtle part and the dominant *new* risk versus `14`. Lay it out plainly.

| Axis | Shen (the brain) | Rust (the body) | The reconciliation `shen-rust` must do |
|---|---|---|---|
| **Memory** | Values on a runtime-managed heap; lifetime = reachability | Values owned, moved, borrowed; lifetime = lexical/region | All Shen values live in `shen-rust`'s `Value` arena; they are **never** handed to Rust as borrowed references that outlive a call |
| **Mutation** | Free re-binding; `value`/`set` globals | `&mut` exclusivity (no aliasing) | Crate state (a `gix::Repository`, a `fuser` session, an `ltx` writer) is owned by Rust, **never** stored in a Shen `Value`; Shen holds an **opaque handle (integer/token)** into a Rust-side registry |
| **GC** | Runtime traces and frees Shen values | RAII / `Drop`, no tracing GC | Rust resources are dropped by Rust (registry eviction or explicit `close`), **not** by Shen's GC; a Shen value never *owns* a Rust resource's lifetime |
| **Errors** | Shen `error`/`trap-error`; dynamic | `Result<T,E>`/`panic` | Crate `Result`/`Err` marshaled into Shen `(error ...)` / `(ok ...)`; **panics must be caught at the seam** (`catch_unwind`) so a `gix` panic cannot unwind through KLambda |
| **Concurrency** | KLambda is single-threaded; no native threads | `tokio` tasks, `Send`/`Sync`, threads | All threading is **Rust-side**; Shen runs the land FSM on **one** runtime thread; cross-thread results re-enter Shen via a single-consumer channel drained on the Shen thread (§1.4) |

**The load-bearing design rule (the whole §1):**

> **The handle/registry seam.** No Rust resource (a `gix::Repository`, a `fuser::Session`, an
> `ltx::Writer`, a `tokio` task handle) is ever embedded in a Shen `Value`. Rust owns them in a
> side **registry** (`HashMap<u64, Resource>` behind the runtime), keyed by an opaque `u64` token.
> Shen holds only the token (a plain Shen number/atom). Every adapter call is `token + plain Shen
> data in → plain Shen data out`. Bytes cross as Shen byte-vectors/strings copied into/out of the
> registry; **borrows never escape a single adapter call.**

This is exactly the FFI-handle discipline a hand-written Rust↔dynamic-language bridge uses (cf.
PyO3's `Py<T>`, Neon's `JsBox`, magnus's `TypedData` for Ruby). It costs a **copy at the boundary**
for blob bytes — the honest perf tax (§9) — and in exchange the ownership model is never violated and
the brain stays pure dynamic Shen. The copy is on the *land/control* path mostly; the hot **VFS
read** path is served by a Rust-side cache that mostly bypasses Shen entirely (§1.3, §5).

Because of this rule, "Shen's dynamic runtime on Rust's ownership model" is **not** reconciled by
making Shen values borrow-checked (impossible) — it is reconciled by **never letting the two memory
models touch**: Shen values stay in Shen's heap, Rust resources stay in Rust's registry, and the
seam trades only plain values + opaque tokens. That is the honest answer to the question.

### 1.3 The layering (what is Shen, what is Rust)

```
┌──────────────────────────────────────────────────────────────────────┐
│  PURE SHEN  (typed, total, host-agnostic — IDENTICAL to plan 14)       │
│  • land FSM (datatype sequent rules)                                    │
│  • merge-result type + structural-conflict constructors                │
│  • acl-proof type; lease-witness type; defprolog ACL / conflict-class  │
│  • landed-log entry construction + checksum chaining (pure arithmetic) │
│  • CLI command parsing, dirstate diffing logic, restack logic          │
├──────────────────────────────────────────────────────────────────────┤
│  SHEN ADAPTERS  (narrow Shen functions; the ONLY callers of §1.4 prims)│
│  • object-store : put/get-blob, read/write-tree, commit, merge (C1)    │
│  • durable-append : fsync'd, CAS-fenced landed-log writer              │
│  • mount-bridge : readdir/read/getattr plans                          │
│  • lease : with-leadership capability                                  │
├──────────────────────────────────────────────────────────────────────┤
│  shen-rust PRIMITIVES  (KLambda extern fns; the marshaling seam §1.2)  │
│  • rs/gix-*   rs/ltx-*   rs/fuser-*   rs/fsync-*   rs/chan-*           │
│  • each: token + Shen values in → Shen values out; catch_unwind        │
├──────────────────────────────────────────────────────────────────────┤
│  RUST BODY  (real crates, same binary, no IPC, no C ABI)               │
│  • gix (gitoxide): blob/tree/commit CAS, history, 3-way merge+rename   │
│  • fuser: the FUSE mount (best-in-class Rust)                          │
│  • ltx-rs lineage: append-only checksum-chained landed-log substrate   │
│  • tokio: land loop task, replica pull tasks, mount worker tasks       │
│  • Rust-side: resource registry, content-hash read cache, fsync IO    │
└──────────────────────────────────────────────────────────────────────┘
```

The PURE SHEN and SHEN ADAPTERS layers are **byte-for-byte the brain from `14`**. Only the bottom
two layers change (SBCL→Rust). That is the deliverable claim: *reuse the brain, swap the body.*

### 1.4 The primitive seam — concrete `shen-rust` extern signatures

`shen-rust` exposes a small set of **KLambda extern functions** (the only place Rust crate types
appear). Sketch of the Rust side (each is `#[catch_unwind]`-wrapped; each returns a Shen `Value`):

```rust
// Rust side — registered as KLambda primitives. NONE leak gix/fuser types to Shen.
// Shen sees: tokens (u64 as Shen number), byte-vectors, strings, tagged tuples.

fn rs_gix_open(path: ShenStr) -> ShenValue          // -> token (registry handle) | (error ..)
fn rs_gix_put_blob(repo: Token, bytes: ShenBytes) -> ShenValue   // -> hash-string
fn rs_gix_get_blob(repo: Token, hash: ShenStr) -> ShenValue      // -> bytes | (nothing)
fn rs_gix_read_tree(repo: Token, hash: ShenStr) -> ShenValue     // -> (list (name . entry))
fn rs_gix_write_tree(repo: Token, entries: ShenList) -> ShenValue// -> hash-string
fn rs_gix_commit(repo: Token, parent: ShenVal, tree: ShenStr, meta: ShenList) -> ShenValue
fn rs_gix_merge3(repo: Token, base: ShenStr, ours: ShenStr, theirs: ShenStr) -> ShenValue
        // -> (merged <tree-hash>) | (text-conflict <path> <hunks>) | (struct-conflict <path> <kind>)
        // gix does the diff3 + rename detection; structural kinds surfaced as Shen tags

fn rs_ltx_open(path: ShenStr) -> ShenValue          // -> token
fn rs_ltx_head(log: Token) -> ShenValue             // -> (seq token pre post) of last entry
fn rs_ltx_cas_append(log: Token, entry: ShenList, fence: ShenNum) -> ShenValue
        // CAS fence on durable head; fsync BEFORE return; -> (ok width) | (error stale-leader)

fn rs_fuser_mount(repo: Token, mnt: ShenStr, cbreg: Token) -> ShenValue  // spawns tokio task
fn rs_fsync_path(path: ShenStr) -> ShenValue
fn rs_stat(path: ShenStr) -> ShenValue              // -> (size mtime ctime ino) for dirstate
fn rs_chan_drain(ch: Token) -> ShenValue            // single-consumer: Rust task results -> Shen
```

**Threading discipline (C3, forced-correct):** Shen/KLambda is single-threaded. All `tokio` tasks
(land loop is itself the Shen thread; replica pull and mount workers are Rust tasks) communicate
results back to the **one Shen thread** through a `tokio::sync::mpsc` channel; the Shen thread
`rs_chan_drain`s it in its loop. **Shen never sees two threads.** This eliminates the entire class
of "dynamic-runtime-in-N-threads" bugs and is *why* there is no Lwt/Eio-style bridge hazard here —
there is no second *Shen* runtime, only Rust tasks feeding one Shen consumer.

### 1.5 Honesty flags carried to §9

- The **handle/registry copy tax** at the Shen↔Rust seam is real (every blob byte crosses by copy
  on the control path). Mitigated by keeping the VFS read hot path Rust-side (§5), not by pretending
  it's zero.
- **`catch_unwind` is mandatory at every primitive** — a `gix`/`fuser` panic unwinding into KLambda
  is undefined; the seam must convert panics to Shen `(error ...)`. This is a real correctness
  obligation, not boilerplate.
- Wrapping `gix`/`fuser`/`ltx-rs` behind these primitives is **scoped engineering work you own**
  (the C1 seam, §3) — the stipulation gives us a working `shen-rust`, not pre-wrapped crates.

---

## 2. The Shen brain (reused from `14`, unchanged) — concrete sketches

These are identical to `14`; reproduced so this plan is self-contained. They run on `shen-rust`
exactly as they ran on shen-cl.

### 2.1 Shen-Prolog `defprolog` for the policy/control plane

Path-scoped ACL: **prefix inheritance + deny-wins + groups.** Grants are facts; effective access is
longest-prefix match with deny precedence.

```shen
(defprolog member
  Alice eng <-- ;
  Bob   eng <-- ;
  Carol sec <-- ;)

\* grant(Subject-or-Group, Action, PathPrefix, Effect) *\
(defprolog grant
  eng read  "src/"            allow <-- ;
  eng write "src/app/"        allow <-- ;
  sec read  "src/secrets/"    allow <-- ;
  eng read  "src/secrets/"    deny  <-- ;     \* deny beats inherited eng/src allow *\
  Carol land "src/secrets/"   allow <-- ;)

(defprolog applies
  Subj Action Prefix Effect <-- (grant Subj Action Prefix Effect) ;
  Subj Action Prefix Effect <-- (member Subj Group) (grant Group Action Prefix Effect) ;)

(defprolog prefixp
  Prefix Path <-- (when (string-prefix? Prefix Path)) ;)

(define can?
  Subj Action Path ->
  (let Cands (collect-applies Subj Action Path)   \* prolog? findall over applies+prefixp *\
    (resolve-acl Cands)))

(define resolve-acl
  []    -> false
  Cands -> (let Best (max-prefix-length Cands)
                Tied (filter (lambda C (= (snd C) Best)) Cands)
             (if (some? (lambda C (= (fst C) deny)) Tied) false true)))
```

`can-read?`/`can-submit?`/`can-land?` are `can?` partially applied. One rule base, two enforcement
points (VFS read; land admission). Conflict-class admission is the same fast pre-filter as `14`
(`admit-disjoint?` over `conflict-class`), and is only a *hint* — the authority on conflict is the
real `gix` 3-way merge (§4, C5).

### 2.2 Shen sequent-calculus `datatype` rules — illegal states unrepresentable (the Minsky `.mli`, in Shen)

**(a) Land FSM — illegal transitions don't typecheck.**

```shen
(datatype change-states

  ____________________________________________________________________
  (submitted ChangeId Base Paths IdemKey) : (change submitted);

  C : (change submitted); Proof : acl-proof;
  =============================================  (admit)
  (advance-admitted C Proof) : (change admitted);

  C : (change admitted); T : merged-tree;
  =============================================  (merge)
  (advance-merged C T) : (change merged);

  C : (change merged); W : lease-witness; Seq : landed-seq;
  =============================================  (land)
  (advance-landed C W Seq) : (change landed);)
```

**(b) Lease capability — a stale-leader land is a compile error.** `lease-witness` is opaque, only
produced inside `with-leadership`; `advance-landed` demands one.

```shen
(datatype lease
  Body : (lease-witness --> (A));
  ===========================================  (with-leadership)
  (with-leadership Store Body) : (result A lease-lost);)
```

```shen
(define with-leadership
  Store Body ->
  (let Tok (acquire-fenced-lease Store)        \* adapter -> rs_ltx_cas_append fence path *\
    (if (lease-held? Tok)
        (let W (mk-witness Tok)
             R (Body W)
          (if (still-fenced? Tok) (ok R) (error lease-lost)))
        (error lease-lost))))
```

**(c) Merge as a total function returning a sum.**

```shen
(datatype merge-result
  T : tree;
  ________________________________  (merged)
  (merged-ok T) : merged-tree;

  P : path; Hs : (list hunk);
  ____________________________________________  (text-conflict)
  (text-conflict P Hs) : merge-conflict;

  P : path; K : struct-kind;       \* rename-rename | delete-modify | rename-edit | ... *\
  ____________________________________________  (struct-conflict)
  (struct-conflict P K) : merge-conflict;)
```

**The Rust upgrade (vs `14`):** in `14`, structural-conflict *detection* (rename/edit,
delete/modify) was **our own Shen code** because Irmin's per-path merge is blind to renames. Here,
**`gix` does textual 3-way merge AND rename detection natively** (`rs_gix_merge3`), returning either
`(merged hash)`, `(text-conflict ...)`, or `(struct-conflict ...)`. The Shen `merge-tree` becomes a
*total marshaling* of `gix`'s result into the `merge-result` datatype — less hand-rolled diff3,
more mature engine. This is the single biggest VCS-correctness win of the Rust body (C5/Torvalds).

```shen
(define merge-tree
  Store Base Ours Theirs ->
  (classify-merge (rs-gix-merge3 Store Base Ours Theirs)))   \* total: tag -> datatype ctor *\
```

**(d) ACL proof — unforgeable, consumed by admission, tip-tagged.**

```shen
(datatype acl
  S : subject; Ps : (list path); A : action; Tip : commit-id;
  ===================================================================  (acl-check)
  (acl-check S Ps A Tip) : (result acl-proof denied);)
```

```shen
(define acl-check
  S Ps A Tip ->
  (if (all? (lambda P (can? S A P)) Ps)
      (ok (mk-proof S Ps A Tip))
      (error denied)))
```

Net: four `datatype` rule sets convert the four highest-risk *runtime* properties into
*compile-time* ones — the same Shen dividend as `14`, host-independent (the checker runs at Shen
compile time, before any Rust executes).

### 2.3 Homoiconic policy-as-data — rules versioned in the repo

The `defprolog` rules + group memberships live as Shen S-expressions in a blob at
`.shenrs/policy.shen`, content-addressed in the trunk via `gix`. Policy changes go through the same
land queue + ACL gate as code (`can-land?` on `.shenrs/policy.shen`); the leader reloads the rule
base from the trunk tip at each land (C2: one source of truth). `blame`/time-travel on policy is
free because policy *is* repo history.

```shen
(define load-policy
  Store -> (read-shen-forms (tree-lookup-blob Store (trunk-tip Store) ".shenrs/policy.shen")))
(define reload-policy!
  Store -> (eval-defprolog-forms (load-policy Store)))
```

---

## 3. Project layout

```
shenrs-vfs/
├─ Cargo.toml                         # the single Rust binary crate
├─ rust/
│  ├─ main.rs                         # boot: init shen-rust runtime, register primitives, run REPL/CLI
│  ├─ runtime.rs                      # shen-rust integration; Value <-> registry marshaling (§1.2)
│  ├─ registry.rs                     # HashMap<u64, Resource>; the handle seam; Drop discipline
│  ├─ prim_gix.rs                     # rs_gix_*  (gitoxide: blob/tree/commit/merge3/rename)
│  ├─ prim_ltx.rs                     # rs_ltx_*  (ltx-rs lineage: cas_append/head/replicate)
│  ├─ prim_fuser.rs                   # rs_fuser_* (FUSE session, callback dispatch -> chan -> Shen)
│  ├─ prim_io.rs                      # rs_fsync_path / rs_stat / rs_chan_* / catch_unwind helpers
│  └─ replication.rs                  # leased-primary + landed-log streaming (BUILT on ltx-rs)
├─ shen/                              # THE BRAIN — identical modules to plan 14
│  ├─ types.shen                      # datatype: change-states, lease, merge-result, acl  (§2.2)
│  ├─ policy.shen                     # defprolog: member/grant/applies/prefixp; can?         (§2.1)
│  ├─ object-store.shen               # C1 seam: put/get-blob, read/write-tree, commit, merge (§ C1)
│  ├─ land.shen                       # land-one, with-leadership, next-log-entry, durable-append (§5)
│  ├─ dirstate.shen                   # real Git-index dirstate; O(changes) status/diff       (§ C5)
│  ├─ stack.shen                      # local commit stacks; Change-Id; restack-on-land       (§6.5)
│  ├─ replication.shen                # leader/cookie/durability-width logic (calls rs_ltx_*) (§6)
│  └─ cli.shen                        # clone/status/diff/submit/land command parsing
├─ policy-repo-seed/.shenrs/policy.shen   # bootstrap admin policy (homoiconic, §2.3)
└─ tests/
   ├─ shen/                           # type-derivation tests, merge totality, ACL tables
   └─ rust/                           # fault injection: fence CAS races, fsync-crash, replica lag
```

**Crate dependencies (real):** `gix` (gitoxide; object DB + `gix-merge`/`gix-diff` for 3-way +
rename), `fuser` (FUSE), an `ltx`/`ltx-rs`-lineage crate (vendored as the landed-log starting
point — you **build** leased-primary replication on it), `tokio` (async runtime), plus the
stipulated `shen-rust` runtime crate. No `git2`/libgit2 unless a `gix` gap forces it (prefer pure-
Rust `gix` to avoid a C dep — note §9 maturity risk).

---

## 4. Data model (same as `07`/`14`)

- **Blob** = file content, content-addressed by `gix` (the git object model; SHA-1 today, gitoxide's
  SHA-256 transition underway — pin and track, §9). Stored once.
- **Tree** = git tree object; lazy subtree access via `gix` is O(depth) → sparse-fetch for free.
- **Commit (= landed change)** = a `gix` commit on the **single trunk ref** (`refs/heads/trunk`).
  Metadata (in commit message trailers / a sidecar note): `change-id` (stable across revisions),
  `author`, `message`, single `parent` (trunk is linear), `landed-seq`, `paths-touched`, `idem-key`.
- **No branches in durable history.** Local work = local commits (a stack); trunk only via landing.
- **Landed-log** = the **ltx-rs-lineage** append-only, checksum-chained log: each entry
  `(seq, commit-hash, fencing-token, pre-checksum, post-checksum)`, `entry[N+1].pre == entry[N].post`
  (LTX's `PreApplyChecksum == prior PostApplyChecksum` invariant, repurposed from pages to commits).
  Sole replication substrate + read-your-writes cookie + audit trail.

`gix` is the object-store truth; the landed-log is the **ordering/replication projection** derived
from it (P3: one atomic authority). Any query index (commit graph/blame) is a local rebuildable
cache (C2).

---

## 5. The trunk land queue (the heart) — Shen-typed, gix/ltx-backed

Same FSM as `14`/`07`. The function is pure happy-path plumbing; every illegal ordering is rejected
by the Shen type checker before it runs.

```shen
(define land-one
  Store Submitted ->
  (with-leadership Store
    (lambda W
      (let Proof (acl-check (author Submitted) (paths Submitted) land (trunk-tip Store))
        (if (error? Proof) Proof
          (let Adm  (advance-admitted Submitted (ok-val Proof))
               Mres (merge-tree Store (base-tree Store (base Adm))
                                       (change-tree Store Adm)
                                       (trunk-tip-tree Store))      \* rs_gix_merge3 *\
            (if (conflict? Mres)
                (reject (conflicts-of Mres))
                (let Mgd   (advance-merged Adm (merged-ok-tree Mres))
                     Cid   (commit-tree Store (some (trunk-tip Store)) (tree-of Mgd) (meta Adm))
                     Entry (next-log-entry (log-head Store) Cid (token-of W))
                  (durable-append! Store Entry (token-of W))))))))))   \* rs_ltx_cas_append *\
```

Land steps:
1. **Client** builds local `gix` commits; `submit`s `(base, paths, change-id, idem-key)`.
2. **Admission** (off serialized path): `can-submit?` (Shen-Prolog), blob presence via
   `rs_gix_get_blob`, `admit-disjoint?` fast hint. Produces a tip-tagged `acl-proof`.
3. **Land (serialized, leader-only, inside `with-leadership`):** dedup by idem-key against trunk
   history (same critical section); OCC base-check (`base == trunk-tip`? fast path : `rs_gix_merge3`
   onto tip — the **real 3-way merge with rename detection**); clean → `rs_gix_commit`, assign
   `landed-seq`, `rs_ltx_cas_append` (fsync + fence CAS), ack with achieved durability width (P2);
   conflict → reject with conflicting paths/hunks.

**Hot-path note:** landing is serialized and low-rate (fine for hundreds of devs). The **VFS read
path** is the hot path and is served by the **Rust-side content-hash read cache** (immutable git
objects ⇒ correct by construction), mostly bypassing the Shen interpreter per byte — the answer to
"Shen-per-syscall would be slow" and the reason the §1.2 copy tax is tolerable.

---

## 6. Land FSM + replication protocol (built on ltx-rs + gix), fencing, RYW, durability width

### 6.1 Leased primary (you BUILD this on the ltx-rs lineage)

Unlike a shen-on-Go variant where you'd reuse the whole superfly/litefs daemon, here `ltx-rs` gives
you the **log format + checksum chain + apply primitive**, and you **build the leased-primary +
replica streaming on top.** Lease lives in a host KV (etcd/Consul via a `tokio` client, or a static
primary for single-DC). Only the leader lands.

### 6.2 Fencing token CAS'd on durable append (Aphyr C4/P1) — two layers, both required

1. **Type layer (§2.2b):** `advance-landed` requires a `lease-witness`; the app cannot *originate*
   split-brain.
2. **Storage layer:** the landed-log append carries a **monotonic fencing token**; `rs_ltx_cas_append`
   **CAS's** the token on the fsync'd durable head and **re-validates the lease after fsync, before
   ack**. A stale leader's append fails the CAS and is **refused** (not detected-then-discarded).

```shen
(define next-log-entry
  PrevEntry Commit Token ->
  (let Pre  (post-checksum PrevEntry)
       Post (roll-checksum Pre Commit)
    (log-entry (+ (seq PrevEntry) 1) Commit Token Pre Post)))

(define durable-append!
  Store Entry Token ->
  (rs-ltx-cas-append (log-token Store) Entry Token))   \* Rust: CAS fence + fsync-before-ack
                                                          -> (ok width) | (error stale-leader) *\
```

The Rust `rs_ltx_cas_append`: (a) verify `Token > durable_head_token` (CAS); (b) write entry, fsync;
(c) re-check lease still held post-fsync; (d) return achieved replica-ack `width` (0..N) → **P2**:
the ack carries the durability signal so the client can distinguish durable-on-N from at-risk.

### 6.3 Replication (sole substrate — C2)

Replicas async-pull the **landed-log** + new `gix` objects (a thin LTX-style stream over the
`tokio` transport; new git objects fetched by hash on demand). **One** replication path. The
projection index (commit graph/blame) is a **local rebuildable cache** rebuilt by replaying the log
— never replicated independently. ACLs are **not** in the index; they live in `.shenrs/policy.shen`
in trunk (§2.3).

### 6.4 Read-your-writes cookie + deadlock avoidance (P4)

A `landed-seq` position cookie: a read on a replica waits until `applied-seq ≥ client's last landed
seq`, else **timeout → leader fallback** with a stated staleness bound (avoids the partition
deadlock). Linearizable trunk landing holds *because one leader + one append-only trunk*, not
consensus; failover has a data-loss window mitigated by fsync-before-ack + the optional 1-replica-ack
durability-width knob (proven LiteFS shape).

### 6.5 Stacked changes / Change-Id with restack-on-land (P5/Torvalds)

Local work is a **stack** of `gix` commits, each carrying a stable **Change-Id** (in a commit
trailer, Gerrit-style). When the **bottom** of a stack lands, the remaining commits must
**restack** onto the new trunk tip:

```shen
(define restack-on-land
  Store Stack LandedChangeId ->
  (let Rest (drop-landed Stack LandedChangeId)           \* commits above the landed one *\
       Tip  (trunk-tip Store)
    (rebase-stack Store Rest Tip)))                       \* per-commit gix cherry-pick/merge3 onto Tip *\

\* rebase-stack: for each remaining commit, 3-way merge its tree onto the moving tip;
   a conflict surfaces as a merge-conflict for the dev (NOT a silent drop). Change-Id is
   preserved across the rewrite so review identity survives the restack. *\
```

The restack reuses `merge-tree` (= `rs_gix_merge3`) per commit, so rename-aware merge applies to
restacks too. Change-Id stability across the rewrite is what lets review tooling track a change
through restacks.

---

## 7. Phased plan (VCS-first, same shape as `07`/`14` P0–P6)

| Phase | Deliverable | Shen-on-Rust specifics |
|---|---|---|
| **P0 — Spine** | `gix` behind the `object-store` Shen seam (C1); the four `datatype` invariant skeletons (§2.2); `defprolog` ACL stub (§2.1); **the §1 interop harness** (registry + marshaling + `catch_unwind` for `rs_gix_*`); vendored+pinned `gix`/`ltx-rs`; CI object-format-migration drill. **Gating spikes (a)+(b) below.** | The spike that *replaces* `14`'s "CL FUSE binding" spike is the **Shen↔Rust marshaling-ergonomics spike** — the riskiest *new* axis. |
| **P1 — Nice single-machine VCS** | local commits + stacks; **real dirstate + O(changes) status/diff** (no mount; `rs_stat` short-circuit on `(size,mtime,ctime,ino)`, re-hash suspects only); **total `merge-tree` via `rs_gix_merge3`** (text + rename + structural conflicts); no-mount sparse checkout via lazy `gix` trees. | Merge is **gix-native**, not hand-rolled diff3 — the big jump over `14`. |
| **P2 — Land queue + fencing** | `with-leadership` + `land-one`; **fencing token CAS'd on fsync'd `rs_ltx_cas_append`**; idempotency in commit metadata; ack returns durability width. | Type-level `lease-witness` lands here; `ltx-rs` chain reused for the log. |
| **P3 — ACL (Shen-Prolog) + derived index** | full path-scoped ACL (prefix/deny-wins/groups); policy-as-data in `.shenrs/policy.shen`; derived projection index (rebuildable, not replicated — C2). | Shen-Prolog load-bearing; index can be a Rust-side `sqlite`/`sled` cache (local only). |
| **P4 — Distribution** | leased leader; landed-log replica streaming over `tokio` (sole replication — C2); RYW cookie + timeout→leader fallback (P4); durability-width knob. | You **build** leased-primary on `ltx-rs`; transport = `tokio`. |
| **P5 — Mount** | **`fuser`** lazy mount; FUSE callbacks dispatched through the Rust→Shen channel (or served Rust-side from cache for reads); write-tracking → dirstate upgrade; sparse profiles. | **Strongest mount story of any backend** — `fuser` is mature; the least-proven phase elsewhere is the *most* solid here. |
| **P6 — Hardening** | failover drills, backpressure, audit, ops runbooks; type-checker compile-time budget; `gix` format-migration drills; panic-safety audit of every primitive. | — |

**Critical path P0→P1→P2** = a usable single-node trunk VCS *with real (gix) merge and fast status*
— the Torvalds "prove this first" deliverable.

### The two gating spikes (decide before code hardens)

- **Spike (a) — gix concurrent multi-reader perf behind a fuser mount.** Benchmark concurrent
  random-path `gix` reads at target fan-out behind a `fuser` mount, with a Rust-side content cache.
  This is the C2/P6 obligation and `gix`'s read story is *better* characterized than irmin-pack's,
  but the **mount + concurrent reader** combination is still the gating measurement. The C1 seam
  lets you cache/swap if it doesn't hold.
- **Spike (b) — Shen↔Rust interop ergonomics (the subtle one, §1).** Concretely measure/validate:
  (i) marshaling a 1MB blob across the registry seam (copy cost on land path); (ii) `gix`/`fuser`
  panic → Shen `(error)` via `catch_unwind` (no UB); (iii) the single-consumer channel drain
  latency (Rust task results → Shen thread); (iv) developer ergonomics of writing a new `rs_*`
  primitive (how much boilerplate per crate call). **This spike is the go/no-go on the whole
  "Shen-dynamic-on-Rust-ownership" thesis** — if marshaling is too lossy or panic-safety too fragile,
  the variant is worse than `14`, not better.

### Fault-injection tests (Rust-side, P2/P4/P6)

- **Fence CAS race:** two would-be leaders append concurrently; assert exactly one CAS wins, the
  stale one gets `(error stale-leader)`, the checksum chain is intact.
- **fsync-crash:** kill the process between `gix_commit` and `ltx_cas_append`; assert recovery
  rebuilds the log projection from `gix` (P3: one authority) with no half-landed observable state.
- **Replica lag / partition:** RYW cookie under partition → timeout → leader fallback (no deadlock,
  P4); assert stated staleness bound.
- **Panic injection:** force a `gix` panic mid-merge; assert it surfaces as a Shen `merge`/`error`
  value, never UB across KLambda.
- **Restack conflict:** land the bottom of a stack so a higher commit conflicts; assert restack
  surfaces a conflict (not a silent drop), Change-Id preserved.

---

## 8. Traceability — Shen-on-Rust plan vs panel obligations (C1–C5, P1–P7)

| Obligation | Source | How this plan honors it |
|---|---|---|
| **C1** Abstract the store; own the seam; pin/vendor/migration-drill | Fukamachi+Minsky Blocker | `object-store.shen` is the only domain interface; only `prim_gix.rs` names `gix`; vendored+pinned; CI object-format-migration drill (§3, §7 P0). |
| **C2** One replication system; index is local rebuildable cache | Torvalds+Fukamachi+Minsky | Landed-log (ltx-rs lineage) is sole replication; commit-graph index is a Rust-side local cache rebuilt by replay, never replicated; ACLs in trunk policy blob (§6.3, §2.3). |
| **C3** Single/pinned execution; no exotic concurrency bridge | Fukamachi+Minsky Blocker | KLambda is single-threaded; one Shen thread owns the land FSM; all `tokio` tasks feed it via one mpsc channel; **no second Shen runtime, no Lwt/Eio-style bridge** (§1.4). |
| **C4** Fencing token CAS'd on durable append + type guard | Aphyr Critical + Minsky | `rs_ltx_cas_append` CAS's monotonic token on fsync, re-validates lease before ack; `lease-witness` makes app-originated split-brain a type error (§2.2b, §6.2). |
| **C5** Real merge + real dirstate; no overclaim | Torvalds Showstopper + Minsky | `rs_gix_merge3` = mature 3-way merge **with rename detection** (better than `14`'s hand-rolled diff3); total `merge-tree`; Git-index dirstate in P1, O(changes), works without mount (§2.2c, §7 P1). |
| **P1** Fencing token for lease handoff | Aphyr | Same as C4 (§6.2). |
| **P2** Ack carries durability signal | Aphyr | `rs_ltx_cas_append` returns achieved replica-ack width; client policy on it (§6.2). |
| **P3** Idempotency = one atomic authority | Aphyr+Minsky | `gix` commit is truth; landed-log entry derived deterministically; idem-key in commit metadata, deduped in serialized section; fsync-crash test asserts no dual-authority (§4, §5, §7). |
| **P4** RYW cookie deadlock under partition | Aphyr | `landed-seq` cookie with timeout→leader fallback + stated staleness bound (§6.4). |
| **P5** Stacked-change restack-on-land spec | Torvalds | `restack-on-land` rebases the stack via per-commit `rs_gix_merge3`; Change-Id preserved (§6.5). |
| **P6** Store concurrency behind multi-reader VFS validated early | Minsky+Torvalds | Gating **spike (a)** — `gix` concurrent reads behind `fuser`; C1 seam allows caching/swap (§7). |
| **P7** Type-driven domain expressed | Minsky | The four `datatype` sequent rule sets (§2.2) — land FSM, lease witness, total merge, ACL proof. |

---

## 9. Honest risks — and what's genuinely better/worse than shen-on-Go and all-OCaml

This section is the point. The architecture is identical to `14`; the *risk profile* shifts with the
body. Brutal honesty per axis.

### 9.1 The dominant NEW risk: Shen-dynamic-on-Rust-ownership interop (§1)

This is the hardest part and the thing to be most candid about. **`shen-rust` cannot turn Shen into
borrow-checked Rust** — Shen values are dynamic, GC'd, freely re-bound; Rust is ownership/aliasing.
The reconciliation is *not* a clever unification; it is a **discipline of never letting the two
memory models touch** (the handle/registry seam, §1.2). That works, and it's the same pattern PyO3/
Neon/magnus use, but it has real costs:
- **Copy tax at the seam** — blob bytes cross by copy on the control path (mitigated by the Rust-side
  read cache for the hot VFS path, not eliminated).
- **Panic safety is a standing obligation** — every `rs_*` primitive must `catch_unwind`; a missed
  one is UB across KLambda. This is a correctness surface that simply doesn't exist in all-OCaml.
- **Ergonomics unknown** — how pleasant it is to write `rs_gix_merge3` and marshal its three-way
  result into the Shen `merge-result` datatype is **spike (b)**, and it's the go/no-go on the whole
  thesis. If `shen-rust`'s extern-primitive API is clumsy, you pay this tax on every crate call
  forever.
If spike (b) fails, **this variant is strictly worse than `14`** (which at least had SBCL's mature,
homoiconic, same-language `sb-alien` story and no ownership impedance). The stipulation buys a
working `shen-rust`; it does **not** buy pleasant marshaling.

### 9.2 Building vs reusing the replication layer

`ltx-rs` gives you the **log format + checksum chain + apply** — but you **build** the leased-primary
+ replica streaming + fencing on top (unlike a shen-on-Go variant, where you could reuse the entire
superfly/litefs daemon as a running process). That's *more* code than Go's reuse, *less* than from
scratch. The honest framing: you trade "reuse a whole daemon (Go)" for "reuse a format + own the
distribution logic (Rust)" — more control, more code, more bugs that are yours.

### 9.3 gix maturity for merge/rename and the SHA-1→SHA-256 transition

`gix` (gitoxide) is **actively, well-resourced**, with a real object DB and a maturing
`gix-merge`/`gix-diff` story — but its **3-way merge + rename detection is younger than libgit2's**
and younger than git's own. If `gix-merge` has gaps at your scale, the fallback is `git2` (libgit2),
which **reintroduces a C dependency and the GC-callback hazard** the pure-Rust path avoided. Also:
git's **SHA-1→SHA-256** object-format transition is in flight; pin the format, plan a migration
drill (§7 P6). Net: merge is *more mature than `14`'s hand-rolled diff3* but *less mature than a
libgit2 binding* — a real, bounded risk, with a (costly) fallback.

### 9.4 Shen ecosystem / bus-factor (worst axis, unchanged from `14`)

Shen's contributor pool is *tiny* — much smaller than OCaml's (itself small) and far smaller than
Rust's. The brain is bus-factor-fragile. The `shen-rust` backend is stipulated production-ready, but
in reality a tiny-ecosystem KLambda-on-Rust port is itself a load-bearing dependency with a thin
maintainer base. The Rust *crates* (`gix`/`fuser`/`tokio`) are healthy; the **Shen layer and the
`shen-rust` runtime are the bus-factor risk**, not the body.

### 9.5 Performance: better than shen-on-SBCL, with caveats

- **No GC pauses in the body** — `gix`/`fuser`/`tokio` are Rust; a VFS serving syscalls doesn't
  stall on a runtime GC for the *IO* path. This genuinely matters for a mount and is a real win over
  shen-on-SBCL (whose libfuse path stalls on SBCL GC) and over JVM-hosted Shen.
- **But the Shen *brain* still has a GC** (`shen-rust`'s runtime manages `Value`s). Control-path Shen
  pays interpreter + GC overhead, same as any KLambda port. Irrelevant for serialized landing;
  relevant only if a request runs Shen per byte (it doesn't — §5).
- **Static single binary**, best-in-class IO perf, `tokio` async concurrency — packaging/perf are the
  best of any variant.

### 9.6 What's genuinely BETTER than shen-on-Go

1. **In-runtime crate calls, no IPC.** Shen↔gix↔fuser↔ltx are all one binary, one address space. The
   shen-on-Go variant either (a) reuses the litefs *daemon* as a separate process (IPC seam,
   serialization, two failure domains) or (b) calls Go libs across a runtime boundary with its own
   marshaling. Rust's "compile the brain and body into one binary" is structurally cleaner.
2. **`fuser` is the best FUSE in any of these ecosystems** — the strongest mount story, period.
   This is the single clearest win: the mount (the riskiest component in `14` on CL, and merely
   adequate in Go) is the *most* solid here.
3. **`gix` 3-way merge + rename detection** beats hand-rolling diff3 (the `14` path) and is more
   idiomatic than wiring a Go merge lib.
4. **No GC pauses on the syscall path** (§9.5) — Go *has* a GC with (small) pauses; for a latency-
   sensitive VFS, Rust's no-GC body is a real edge over Go.

**Worse than shen-on-Go:** Go's runtime is *also* GC'd/dynamic-friendly, so the Shen↔Go value
marshaling is **less impedance-mismatched** than Shen↔Rust (Go has no borrow checker to offend).
The §9.1 ownership-impedance tax is **specific to Rust** — shen-on-Go pays a smaller interop tax. And
Go lets you *reuse the whole litefs daemon*, less code than building on `ltx-rs`.

### 9.7 What's genuinely BETTER/WORSE than all-OCaml

- **Better than all-OCaml:** the **mount** (`fuser` ≫ `ocamlfuse`), the **merge engine** (`gix` is a
  real git object model + rename-aware merge; OCaml's Irmin needs a custom diff3 content type and
  has *narrower* structural merge), **no Lwt/Eio bridge hazard** (the all-OCaml plan's C3 Blocker
  simply doesn't exist — there's one Shen thread + tokio tasks), **packaging** (one static Rust
  binary vs an opam/dune deployment), and **the declarative control plane** (Shen-Prolog ACLs +
  sequent-calculus invariants + homoiconic policy-as-data — OCaml's GADTs buy the same invariant
  guarantees but the policy-as-data story is bolt-on, not native).
- **Worse than all-OCaml:** **ecosystem/bus-factor** (OCaml ≫ Shen, and Irmin is *real and reusable*
  whereas the Shen brain + `shen-rust` are thin-maintainer), **tooling ergonomics** (OCaml's type
  errors are far better than Shen's terse sequent-calculus checker, which can also *loop* on a bad
  datatype), and **the interop tax** (all-OCaml is one language one runtime; this is Shen-dynamic
  marshaled across a Rust ownership boundary — §9.1). The synthesis `12` explicitly preferred
  **all-OCaml for the lowest-risk shipping path**, and that judgment stands: this variant wins on
  *mount + merge + no-bridge + declarative control plane*, and loses on *ecosystem + tooling +
  interop simplicity*.

### 9.8 Honest verdict

**shenrs-vfs is the best-mounted, best-merging variant** (gix + fuser, in-runtime, no GC pauses on
the syscall path) **and keeps the most expressive control plane** (Shen-Prolog + sequent-calculus +
homoiconic policy). Its **defining risk is the Shen-dynamic ↔ Rust-ownership interop** (§9.1, spike
b): the reconciliation works only by the handle/registry discipline, costs a boundary copy and a
standing panic-safety obligation, and is *more* impedance-mismatched than shen-on-Go (Go has no
borrow checker) — though *cleaner than shen-on-SBCL's mount* and *better-mounted than all-OCaml*.
Prefer this variant **iff** (a) the team values the declarative Shen control plane + the best-in-
class `fuser`/`gix` body, and (b) spike (b) shows `shen-rust`'s extern-primitive marshaling is
ergonomic and panic-safe. If spike (b) fails, fall back to all-OCaml (`12`'s shipping preference) or
shen-on-Go (smaller interop tax, reuse-litefs). **The single biggest risk is §9.1 — whether
`shen-rust` can marshal Shen's dynamic values to/from `gix`/`fuser`/`ltx-rs` ergonomically and
panic-safely across the ownership boundary; everything else is bounded, that one is existential to
the thesis.**

---

## Appendix — relationship to the document set

This plan is the **all-Shen-on-Rust sibling** of `14` (all-Shen-on-SBCL): it **reuses the Shen brain
verbatim** (§2 = `14` §2) and **swaps the body SBCL→Rust** (§1, §3, §6 bodies). It builds the **same
product** as `07` and discharges the **same obligations** as `12` (C1–C5, P1–P7, traced in §8). It
re-expresses Minsky's `.mli` skeleton (`11`) in Shen sequent calculus (§2.2), and uses the storage/
distribution evidence from `06` (the litevfs/LTX lineage is Rust — `ltx-rs` — which is precisely why
the replication substrate is *closer to reuse* here than on any other host).
