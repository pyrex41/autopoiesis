---
date: 2026-06-25
researcher: Claude
topic: "All-Shen implementation plan for shenvfs — a trunk-only, content-addressable DVCS-VFS at moderate scale, built entirely in Shen"
plan: all-shen
status: draft
inputs:
  - thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
  - thoughts/shared/plans/dvcs-vfs/12-synthesis-v2.md
  - thoughts/shared/plans/dvcs-vfs/11-minsky-review.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
tags: [shen, shen-cl, sbcl, irmin, datalog, prolog, sequent-calculus, dvcs, vfs, trunk, fencing, moderate-scale]
last_updated: 2026-06-25
last_updated_by: Claude
---

# `shenvfs` — an all-Shen trunk-only DVCS-VFS (moderate scale)

This is the **same product** as the OCaml `mvfs` direction brief (`07`) and its reviewed synthesis
(`12`): a content-addressable, **trunk-only / no-branches**, monorepo distributed VCS with a lazy
virtual filesystem, sized for **moderate scale** (hundreds of developers) — single leased
land-leader, append-only checksum-chained landed-log, **no Raft**, lazy VFS mount, real merge, real
dirstate, path-scoped ACLs. The build language is **Shen**.

It addresses the **same panel obligations** (C1–C5, P1–P7 from `12`) and re-expresses Minsky's
"make illegal states unrepresentable" `.mli` skeleton (`11`) in Shen's **sequent-calculus type
system**. Per the user's license, it assumes native Shen ports of the external pieces
(`shen-irmin`, `shen-datalog`, `shen-fuse`/`shen-9p`, `shen-diff`) **exist** — but it is explicit
about exactly where the design still bottoms out in a host runtime (SBCL), because that honesty is
the whole point of choosing Shen with eyes open.

> Read alongside `07` (product) and `12` (settled obligations). Where this plan says "same as the
> OCaml plan," it means the architecture is identical and only the implementation language differs.

---

## 0. The one-paragraph thesis

Build the VCS core on **`shen-irmin`** (assumed port: content-addressed blob/tree/commit CAS, GC,
structural tree merge, push/pull) **behind a narrow Shen abstraction you own**, so no `shen-irmin`
symbol leaks into the domain. Express the load-bearing invariants — the land FSM, the lease
capability, the unforgeable ACL proof, the total merge result — as **Shen `datatype` sequent
rules**, so a stale-leader land or an un-ACL'd land is a *type error*, not a runtime check. Express
the policy/control plane — path-scoped ACLs (prefix inheritance, deny-wins, groups) and
conflict-class admission — as **Shen-Prolog `defprolog` rules** (built into the language; the
`shen-datalog` port is the termination-guaranteed alternative). Store those rules **as Shen
S-expressions versioned in the repo itself** (homoiconic policy-as-data). For distribution, drop
Raft: one leased leader, one **append-only landed-log** as the *sole* replication substrate, a
**fencing token CAS'd on the durable append**. Run all of it on **shen-cl / SBCL**, which is where
threads, sockets, FUSE, and syscalls actually come from — Shen contributes the language, types, and
logic; **the host contributes every byte of IO.** That seam is this plan's biggest honesty
obligation and its biggest risk.

---

## 1. Host choice and the Shen↔host FFI boundary

### 1.1 Pick: shen-cl on SBCL (primary)

Shen compiles to **K-Lambda (KLambda)**, a tiny Lisp kernel; a "Shen port" is a KLambda
implementation on a host runtime. The candidate hosts:

| Port | Host | Threading | FFI to libfuse/syscalls | Verdict |
|---|---|---|---|---|
| **shen-cl** | **Common Lisp / SBCL** | bordeaux-threads | SBCL `sb-alien` / CFFI | **Primary** — best perf, real threads, mature FFI, and it lands us back on the Autopoiesis CL substrate |
| shen-scheme | Chez | limited | Chez FFI | viable, weaker ecosystem fit |
| shen-clj | Clojure / JVM | JVM threads (good) | JNI/JNA (heavy for FUSE) | JVM GC + FUSE is awkward |
| shen-js / shen-py | Node / Python | event loop / GIL | poor for syscall-level FUSE | no |

**Choose shen-cl/SBCL.** Reasons: (a) SBCL has real native threads (`bordeaux-threads`) and a
direct alien FFI (`sb-alien`) to `libfuse`/`9p`/`fsync`/`mmap`; (b) it is the highest-performance
KLambda host; (c) it is **homoiconic Common Lisp**, so `shenvfs` lands on the *same substrate* as
the original Autopoiesis platform — the policy-as-data, snapshotting, and code-as-data story is
native, and the existing CL substrate (datom store, blob store) is reusable as the irmin backing if
desired. This is the one place the "all-Shen" choice is *strictly better integrated* than all-OCaml
for this codebase.

### 1.2 The FFI boundary — what is Shen, what is host

The "assume a native Shen port exists" license covers **libraries** (`shen-irmin`, `shen-fuse`,
etc.). It does **not** conjure a concurrency/IO model into Shen: **Shen has no native threads,
sockets, FUSE, or syscalls.** Every one of those is a thin Shen wrapper over an SBCL primitive. Be
explicit about the layering:

```
┌──────────────────────────────────────────────────────────────┐
│  PURE SHEN  (typed, total, host-agnostic)                      │
│  • land FSM (datatype sequent rules)                           │
│  • merge-result type + diff3 driver                            │
│  • ACL proof type; Shen-Prolog policy rules                    │
│  • landed-log entry construction + checksum chaining (pure)    │
│  • CLI command parsing, dirstate diffing logic                 │
├──────────────────────────────────────────────────────────────┤
│  SHEN ADAPTERS  (narrow, you own — the C1 seam)                │
│  • object-store : put/get-blob, read/write-tree, commit, merge │
│  • durable-append : fsync'd, CAS-fenced landed-log writer      │
│  • mount-bridge : readdir/read/getattr callbacks               │
│  • lease : with-leadership capability                          │
├──────────────────────────────────────────────────────────────┤
│  HOST (SBCL) — every byte of IO lives here                     │
│  • bordeaux-threads (land loop, replica pull, mount workers)   │
│  • sb-alien → libfuse / 9p  (the mount)                        │
│  • fsync / pwrite / rename  (durability)                       │
│  • usocket / dexador        (replica transport, lease store)   │
│  • shen-irmin's pack files ultimately = SBCL file IO           │
└──────────────────────────────────────────────────────────────┘
```

**Concrete FFI sketch** (the mount's `read` callback bottoms out in host alien code; the Shen side
is pure):

```shen
\* Pure Shen: given a path + offset, decide what bytes to serve.
   No IO here — returns a request the host fulfils. *\
(define vfs-read-plan
  Store Path Offset Len ->
  (let Tip   (trunk-tip Store)
       Hash  (tree-lookup-blob Store Tip Path)   \* O(depth), lazy *\
    (blob-slice-request Hash Offset Len)))

\* Host boundary (shen-cl): registered libfuse callback. This is the line
   below which we are SBCL, not Shen. shen-fuse's port provides (fuse-mount);
   the callback it invokes is host C-ABI glue. *\
(define fuse-on-read
  Store Path Offset Len ->
  (host-blob-fetch (vfs-read-plan Store Path Offset Len)))   \* host-blob-fetch = sb-alien/IO *\
```

**Honesty flag (carry forward to §7):** Fukamachi's v1 review flagged the *CL FUSE/9p situation as
weak*. Assuming `shen-fuse` exists does **not** make the underlying CL libfuse binding mature — it
relocates the same weak host binding under a Shen name. The mount is the single least-proven host
dependency, and it is *more* exposed here than in OCaml (which has maintained `ocamlfuse`).

---

## 2. Shen's real strengths, used concretely

This is where all-Shen *earns its keep* rather than being a novelty. Three genuine wins.

### 2.1 Shen-Prolog for the policy/control plane (the user's original "Shen control plane")

Shen ships a **first-class logic-programming layer** (`defprolog`, `prolog?`). The path-scoped ACL
and conflict-class rules — which the OCaml plan writes as predicates or a tiny Datalog — are written
here as **native Prolog rules, no separate engine**. (The `shen-datalog` port is the
termination-guaranteed swap-in if rule recursion ever risks non-termination; ACL rules are
stratified and finite, so Shen-Prolog is fine, and Datalog is the conservative fallback.)

**Path-scoped ACL: prefix inheritance + deny-wins + groups.** Grants are facts; effective access is
derived by longest-prefix match with deny taking precedence.

```shen
\* --- Facts (these are the policy-as-data, §2.3, loaded from the repo) --- *\
(defprolog member
  Alice eng <-- ;                         \* alice ∈ eng group *\
  Bob   eng <-- ;
  Carol sec <-- ;)

\* grant(Subject-or-Group, Action, PathPrefix, Effect) *\
(defprolog grant
  eng read  "src/"              allow <-- ;
  eng write "src/app/"          allow <-- ;
  sec read   "src/secrets/"     allow <-- ;
  eng read   "src/secrets/"     deny  <-- ;   \* deny beats the inherited eng/src allow *\
  Carol land "src/secrets/"     allow <-- ;)

\* A grant applies to a subject if it is granted directly or via group membership. *\
(defprolog applies
  Subj Action Prefix Effect <-- (grant Subj Action Prefix Effect) ;
  Subj Action Prefix Effect <-- (member Subj Group) (grant Group Action Prefix Effect) ;)

\* prefix? : is Prefix a path-prefix of Path?  (host string op behind a pure predicate) *\
(defprolog prefixp
  Prefix Path <-- (when (string-prefix? Prefix Path)) ;)

\* The effective decision: longest matching prefix wins; among equal length, deny wins.
   We collect candidate (Effect,Len) pairs and fold with deny-wins / longest-prefix. *\
(define can?
  Subj Action Path ->
  (let Cands (collect-applies Subj Action Path)   \* prolog? findall over applies+prefixp *\
    (resolve-acl Cands)))                          \* pure Shen: longest-prefix, deny-wins fold *\

\* resolve-acl: deny-wins at the longest matching prefix length. *\
(define resolve-acl
  []    -> false
  Cands -> (let Best  (max-prefix-length Cands)
                Tied  (filter (lambda C (= (snd C) Best)) Cands)
             (if (some? (lambda C (= (fst C) deny)) Tied)
                 false
                 true)))
```

`can-read?`, `can-submit?`, `can-land?` are `can?` partially applied to `read`/`submit`/`land`. The
VFS read path calls `can-read?` (deny → entry invisible); land admission calls `can-submit?` and
`can-land?`. **One rule base, two enforcement points** — exactly the OCaml design, but the logic is
*declarative Prolog* instead of imperative predicates, which is the user's stated vision and is
genuinely more legible for policy.

**Conflict-class admission** (off the serialized path; cheap pre-filter before the real merge):

```shen
\* Two changes are conflict-class-disjoint if no touched path of one is a prefix-or-equal
   of any touched path of the other. Disjoint ⇒ admit fast; overlap ⇒ defer to real merge. *\
(defprolog conflict-class
  Paths1 Paths2 <-- (member-path P1 Paths1) (member-path P2 Paths2)
                    (path-related P1 P2) ;)     \* succeeds ⇒ potential conflict *\

(define admit-disjoint?
  Paths1 Paths2 -> (not (prolog? (conflict-class Paths1 Paths2))))
```

Note: conflict-class is only a *fast admission hint*. The **authority on conflict is the real 3-way
merge** (§4), not path overlap — this is the C5/Torvalds upgrade, preserved.

### 2.2 Shen's sequent-calculus type system for the invariants (the Minsky `.mli`, in Shen)

Shen has an **optional static type checker** in which you define datatypes as **sequent-calculus
inference rules**. The checker is Turing-complete; you can encode rich invariants. This is Shen's
native way to do "illegal states unrepresentable." Here is Minsky's four-`.mli` skeleton (`11`)
re-expressed as Shen `datatype` rules.

**(a) The land FSM — illegal transitions don't typecheck.** Each state is a distinct type; you
cannot construct a `landed` change without a `merged` one, nor `merged` without `admitted`, nor
`admitted` without an `acl-proof`.

```shen
(datatype change-states

  \* A submitted change carries its base, paths, idempotency key — nothing more. *\
  ____________________________________________________________________
  (submitted ChangeId Base Paths IdemKey) : (change submitted);

  \* You can only build an `admitted` change by SUPPLYING an acl-proof.
     The acl-proof type is unforgeable (rule set (d)); there is no other
     constructor that yields (change admitted). *\
  C : (change submitted);
  Proof : acl-proof;
  =============================  (admit)
  (advance-admitted C Proof) : (change admitted);

  \* You can only build a `merged` change from an `admitted` one, plus a
     merge-result that is specifically `Merged` (rule set (c)); a `Conflict`
     merge-result has a different type and cannot be passed here. *\
  C : (change admitted);
  T : merged-tree;
  =============================  (merge)
  (advance-merged C T) : (change merged);

  \* You can only `land` a `merged` change while HOLDING a lease-witness
     (rule set (b)). No witness ⇒ no (change landed). *\
  C : (change merged);
  W : lease-witness;
  Seq : landed-seq;
  =============================  (land)
  (advance-landed C W Seq) : (change landed);)
```

**(b) The lease capability — a stale-leader land is a compile error.** `lease-witness` is abstract:
the only way to obtain one is *inside* `with-leadership`, and it cannot escape the dynamic extent.
`advance-landed` (rule `land` above) demands a `lease-witness`, so a land outside held leadership
does not typecheck.

```shen
(datatype lease

  \* No introduction rule for lease-witness is exported — it is opaque.
     The ONLY producer is with-leadership, whose type says: it hands a
     witness to a continuation and the witness is valid only there. *\

  Body : (lease-witness --> (A));
  ===========================================  (with-leadership)
  (with-leadership Store Body) : (result A lease-lost);)
```

```shen
\* Host-backed implementation; the TYPE above is the guarantee, this is the mechanism.
   Acquires the fenced lease (CAS on landed-log, §5), runs Body, re-validates after fsync. *\
(define with-leadership
  Store Body ->
  (let Tok (acquire-fenced-lease Store)        \* host: lease store + landed-log CAS *\
    (if (lease-held? Tok)
        (let W (mk-witness Tok)                  \* witness exists only in this let *\
             R (Body W)
          (if (still-fenced? Tok) (ok R) (error lease-lost)))
        (error lease-lost))))
```

Because `lease-witness` has no public constructor and `advance-landed` requires one, **the
application can no longer be the source of a split-brain land** — Aphyr's C4 split-brain becomes
unrepresentable in Shen code. (Storage-layer fencing, §5, still handles the *truly concurrent* race;
the type kills the *application-originated* case.)

**(c) Merge as a total function returning a sum.** Every `(base, ours, theirs)` maps to exactly one
constructor; there is no exception, no null, and you cannot land a tree the merge didn't bless
because only `Merged` carries a `merged-tree`.

```shen
(datatype merge-result

  T : tree;
  ________________________________  (merged)
  (merged-ok T) : merged-tree;

  \* Structural and text conflicts are explicit constructors, NOT escapes. *\
  P : path; Hs : (list hunk);
  ____________________________________________  (text-conflict)
  (text-conflict P Hs) : merge-conflict;

  P : path; K : struct-kind;        \* struct-kind = rename-rename | delete-modify | ... *\
  ____________________________________________  (struct-conflict)
  (struct-conflict P K) : merge-conflict;)
```

```shen
\* Total: returns (merged-tree | (list merge-conflict)). The structural cases
   (rename/edit, delete/modify) that shen-irmin's per-path merge is blind to are
   detected HERE, in our own code (C5). Text merge is shen-diff's diff3. *\
(define merge-tree
  Base Ours Theirs ->
  (let Struct (detect-structural Base Ours Theirs)   \* renames/deletes — our logic *\
    (if (not (empty? Struct))
        (conflicts Struct)
        (merge-blobs-diff3 Base Ours Theirs))))       \* shen-diff diff3 per path *\
```

**(d) The ACL proof — unforgeable, consumed by admission.** Only `acl-check` produces an
`acl-proof`; `advance-admitted` (rule `admit`) requires one; so "landed without ACL" is not a
representable program. The proof is **tagged with the trunk tip it was evaluated against**, so a
stale proof is detectable by type-carried data.

```shen
(datatype acl

  \* No public constructor for acl-proof. acl-check is the sole producer. *\
  S : subject; Ps : (list path); A : action; Tip : commit-id;
  ===================================================================  (acl-check)
  (acl-check S Ps A Tip) : (result acl-proof denied);)
```

```shen
\* acl-check drives the Shen-Prolog rules (§2.1); on success it mints a proof
   carrying the (subject, paths, action, tip) it was evaluated against. *\
(define acl-check
  S Ps A Tip ->
  (if (all? (lambda P (can? S A P)) Ps)
      (ok (mk-proof S Ps A Tip))      \* mk-proof is private to this module *\
      (error denied)))
```

**Net:** four `datatype` rule sets convert the four highest-risk *runtime* properties (ordered land
FSM, leader-only land, total merge, ACL-gated admission) into *compile-time* ones. This is the Shen
dividend, and it is at least as strong as OCaml's GADT/phantom approach — arguably stronger, because
Shen's checker is full sequent calculus, not pattern-bound GADTs. (Cost: §7 — the checker is slow
and its errors are terse.)

### 2.3 Homoiconic policy-as-data — rules versioned in the repo itself

Shen is homoiconic: the `defprolog` ACL rules, group memberships, and conflict-class rules of §2.1
are **S-expressions**. We store them as a blob at a reserved path (`.shenvfs/policy.shen`) **inside
the trunk**, content-addressed like any other file. Consequences:

- Policy changes go through the **same land queue and ACL gate** as code (you need `can-land?` on
  `.shenvfs/policy.shen` — bootstrapped by an initial admin grant). Policy history is the repo
  history; `blame`/time-travel on policy is free.
- The land-leader **loads the rule base from the trunk tip** at each land, so policy is always the
  durably-landed version — no out-of-band ACL store to drift (this is also how we honor C2: one
  source of truth).
- Because rules are data, an admin can *snapshot, diff, and propose* policy as an ordinary change,
  reviewed before it lands. This is the self-describing-VCS property the user wanted, and it is
  *native* in Shen where it would be bolt-on in OCaml.

```shen
(define load-policy
  Store -> (read-shen-forms (tree-lookup-blob Store (trunk-tip Store) ".shenvfs/policy.shen")))

(define reload-policy!
  Store -> (eval-defprolog-forms (load-policy Store)))   \* re-asserts the rule base *\
```

---

## 3. Honoring the panel obligations (C1–C5) in Shen terms

### C1 — `shen-irmin` behind a narrow Shen seam you own
No `shen-irmin` symbol appears in the domain. Define an `object-store` interface as Shen
functions + types; implement it on `shen-irmin` for P0.

```shen
\* domain depends ONLY on these signatures, never on shen-irmin.* *\
(declare put-blob    [store --> blob --> hash])
(declare get-blob    [store --> hash --> (maybe blob)])
(declare read-tree   [store --> hash --> (list tree-entry)])
(declare write-tree  [store --> (list tree-entry) --> hash])
(declare commit-tree [store --> (maybe commit-id) --> hash --> commit-meta --> commit-id])
(declare tree-merge  [hash --> hash --> hash --> (result hash struct-conflict)])
(declare gc-store    [store --> store])

\* The ONE module that may name shen-irmin: *\
(define put-blob Store B -> (shen-irmin.put Store B))  \* ...etc., isolated here *\
```

Dependency posture (Fukamachi's add-on to C1): pin `shen-irmin` to an exact version, vendor its
source, and add a **CI format-migration drill** (dump→neutral S-expr→reimport). Because `shen-irmin`
is *assumed* (§7), vendoring is mandatory, not optional — there is no upstream to rely on.

### C2 — ONE replication system; the projection index is a local rebuildable cache
The **append-only landed-log is the sole replication substrate.** Any query index (commit graph,
blame, path history) is a **derived local projection** rebuilt by replaying the log — on the SBCL
host this can be the existing Autopoiesis **datom store** (EAV), used purely as a local cache, never
replicated independently. No second replication path. ACLs are **not** secretly authoritative in the
index — they live in `.shenvfs/policy.shen` in the trunk (§2.3).

### C3 — single-threaded land loop on the host; no exotic concurrency
Shen has no concurrency of its own, so this is forced and *correct-by-default*: **one
`bordeaux-threads` thread on SBCL owns the land loop and is the only thing that touches the
object-store for writes.** Reads are served from a **content-hash-keyed cache** (immutable objects ⇒
correct by construction) in front of the store; replica pull and mount workers are separate host
threads that never write trunk. This is the Shen analogue of C3's "single/pinned-domain, Lwt-native
first" — except there is no Lwt/Eio bridge hazard at all, because there is no second IO runtime to
bridge. (A genuine, if accidental, simplification vs. OCaml.)

### C4 — fencing token CAS'd on the durable append (+ the type guard from §2.2b)
Two layers, both required:
1. **Type layer (§2.2b):** `advance-landed` requires a `lease-witness`; the app cannot originate a
   split-brain land.
2. **Storage layer:** the landed-log append carries a **monotonic fencing token**; the durable
   writer **CAS's** the token on the fsync'd append and **re-validates the lease after fsync, before
   ack**. A stale leader's append fails the CAS and is rejected — detect *and refuse*, not detect
   *and discard*.

```shen
\* Pure construction of the next log entry (checksum-chained, LTX-style). *\
(define next-log-entry
  PrevEntry Commit Token ->
  (let Pre  (post-checksum PrevEntry)
       Post (roll-checksum Pre Commit)
    (log-entry (+ (seq PrevEntry) 1) Commit Token Pre Post)))

\* Host: fenced, fsync'd append. Returns achieved durability width (→ C4/P2). *\
(define durable-append!
  Store Entry Token ->
  (if (cas-fence! Store (token Entry) Token)        \* host CAS on durable head *\
      (let _ (fsync-append! Store Entry)            \* host fsync BEFORE ack *\
           W (replica-ack-width Store Entry)        \* 0..N replicas acked *\
        (ok W))
      (error stale-leader)))
```

### C5 — real merge + real dirstate
- **Merge:** the total `merge-tree` of §2.2c. Text via `shen-diff` diff3; **structural conflicts
  (rename/edit, delete/modify) are our own constructors**, because `shen-irmin`'s per-path merge is
  blind to them. Prefer the pure-Shen `shen-diff` over any host xdiff FFI (smaller surface, no GC
  callback hazard).
- **Dirstate:** a real Git-index-style dirstate `(path, size, mtime, ctime, inode, blob-hash)`
  built in **P1**, working **without** the mount: `status`/`diff` stat entries, short-circuit on
  `(size,mtime,ctime,inode)`, re-hash only suspects → **O(changes)**. The `stat`s are host
  (`sb-posix`); the diffing logic is pure Shen. The mount (P5) later *upgrades* dirstate via
  write-tracking; we do not claim O(changes) before the index exists.

```shen
(define status
  Store Dirstate ->
  (let Suspects (filter (lambda E (stat-changed? E)) (entries Dirstate))   \* host stat *\
       Changed  (filter (lambda E (rehashed-differs? Store E)) Suspects)   \* host hash *\
    (classify Changed)))     \* pure Shen *\
```

### P3 — one atomic land authority (commit → derived log entry)
The land step is one atomic operation from the domain's view: `commit-tree` returns a `commit-id`
and the landed-log entry is **derived deterministically** from it (§5). The Irmin commit is the
source of truth; the log entry is the rebuildable projection of the *ordering*. No dual-authority
returns — the idempotency key lives in the commit metadata, deduped by reading trunk history inside
the same serialized critical section.

---

## 4. Data model (same as OCaml plan)

- **Blob** = file content, content-addressed (SHA-256) by `shen-irmin`. Stored once.
- **Tree** = node; lazy subtree access is O(depth) → the sparse-fetch property for free.
- **Commit (= landed change)** = a `shen-irmin` commit on the **single trunk branch**; metadata:
  `change-id` (stable across revisions), `author`, `message`, single `parent` (trunk is linear),
  `landed-seq`, `paths-touched`, `idem-key`.
- **No branches in durable history.** Local work = local commits (a stack); trunk only via landing.
- **Landed-log** = append-only, checksum-chained (LTX-inspired): each entry
  `(seq, commit-hash, fencing-token, pre-checksum, post-checksum)`, `entry[N+1].pre == entry[N].post`.
  Sole replication substrate + read-your-writes cookie + audit trail.

---

## 5. The trunk land queue (the heart) — same FSM, Shen-typed

1. **Client** builds local commits; `submit`s `(base, paths, change-id, idem-key)`.
2. **Admission** (off the serialized path): `can-submit?` (Shen-Prolog), blob presence,
   `admit-disjoint?` fast hint. Produces an `acl-proof` (typed, tip-tagged).
3. **Land (serialized, leader-only, inside `with-leadership`):**
   - dedup by idem-key against trunk history (same critical section);
   - OCC base-check: `base == trunk-tip`? fast-path : `merge-tree onto tip` (the real 3-way merge);
   - clean → `commit-tree`, assign `landed-seq`, `durable-append!` (fsync + fence CAS), ack with
     achieved durability width (P2); conflict → reject with conflicting paths/hunks.

```shen
(define land-one
  Store Submitted ->
  (with-leadership Store
    (lambda W
      (let Proof (acl-check (author Submitted) (paths Submitted) land (trunk-tip Store))
        (if (error? Proof) Proof
          (let Adm  (advance-admitted Submitted (ok-val Proof))
               Mres (merge-tree (base-tree Store (base Adm))
                                (change-tree Store Adm)
                                (trunk-tip-tree Store))
            (if (conflict? Mres)
                (reject (conflicts-of Mres))
                (let Mgd   (advance-merged Adm (merged-ok-tree Mres))
                     Cid   (commit-tree Store (some (trunk-tip Store)) (tree-of Mgd) (meta Adm))
                     Entry (next-log-entry (log-head Store) Cid (token-of W))
                  (durable-append! Store Entry (token-of W))))))))))
```

Every illegal ordering in this function is rejected **by the type checker** before it runs: you
cannot call `advance-merged` on a non-admitted change, cannot `commit`/`append` without a `merged`
change and a `lease-witness`. The runtime logic is just the *happy path plumbing*.

**Throughput:** single-leader serialized landing is fine for hundreds of developers. Shen adds
interpreter overhead over raw SBCL (§7), but landing is not the hot path — the VFS read path is, and
that is served from the host-side content cache, mostly bypassing the Shen interpreter per byte.

---

## 6. Distribution & consistency (no Raft) — same as OCaml plan

- **One leased land-leader** (lease in a host KV: etcd/Consul via `usocket`, or static primary).
  Only the leader lands; the **fencing token** (§C4) makes the lease *fenced*, not merely TTL'd.
- **Replication** = replicas async-pull the **landed-log** + new objects; **read-your-writes** via a
  `landed-seq` position cookie (wait until replica applied-seq ≥ client's last landed seq, else
  redirect to leader; **timeout → leader fallback** with a stated staleness bound — P4).
- **Consistency, stated honestly:** trunk landing is linearizable *because one leader + one
  append-only trunk*, not because of consensus. Failover has a **data-loss window** mitigated by
  fsync-on-leader-before-ack and an optional **1-replica-ack durability-width knob** (the ack
  returns the achieved width — P2 — so the client can tell durable from at-risk). This is the proven
  LiteFS shape, sized to moderate scale.

---

## 7. Where all-Shen is RISKIER than all-OCaml (brutal honesty)

This section is the point of the exercise. The architecture is identical; the *risk profile* is not.

### 7.1 The IO / FUSE / concurrency host dependency — the dominant risk
Shen has **no native IO, threads, sockets, FUSE, or syscalls.** Every one comes from SBCL. The "
assume `shen-fuse` exists" license relocates the mount binding under a Shen name but **does not
improve the underlying CL libfuse situation**, which Fukamachi's v1 review explicitly flagged as
weak. OCaml has *maintained* `ocamlfuse` and `ocaml-9p`; the CL/SBCL FUSE story is thinner and less
battle-tested. So the single least-proven component — the mount — is **strictly more exposed in
Shen-on-CL than in OCaml.** This is the biggest reason all-Shen is riskier.

### 7.2 Performance is host-bound and *worse* than raw SBCL
Shen compiles through KLambda; the Shen layer adds interpreter/dispatch overhead **on top of**
SBCL. So Shen-on-SBCL is slower than OCaml (native-compiled) *and* slower than hand-written SBCL.
For the control plane (land FSM) this is irrelevant — landing is serialized and low-rate. For the
**VFS read path** it matters, which is why §1.2/§5 push per-byte serving into a host-side cache that
mostly bypasses Shen. But any path that *does* run Shen per request pays the tax. OCaml has no such
double-overhead.

### 7.3 Ecosystem / maturity / bus-factor — the worst axis
- **Tiny ecosystem.** Shen's contributor pool is *much* smaller than OCaml's (itself small). The
  bus-factor is brutal: a handful of people maintain the ports.
- **The assumed ports don't exist.** `shen-irmin`, `shen-fuse`, `shen-diff`, `shen-datalog` are
  *assumed*. In reality you would **write them**, and that cost is large and load-bearing:
  - `shen-irmin`: porting (or wrapping) a full content-addressed Merkle store + structural merge +
    GC + push/pull is *the 12–18 months the whole strategy was meant to skip.* Wrapping the existing
    Autopoiesis CL substrate (datom + blob store) as the backing is the realistic shortcut, but that
    is **building the store**, not reusing Irmin — closer to the all-Rust-over-`gix` "own it forever"
    cost than the OCaml-over-Irmin "reuse" cost.
  - `shen-fuse`/`shen-9p`: a Shen wrapper over an SBCL libfuse FFI that is itself immature (§7.1).
  - `shen-diff`: a few hundred LOC of diff3 in Shen — the *cheapest* assumed port, genuinely fine.
  - `shen-datalog`: optional; Shen-Prolog covers it.
  **Net real cost of "assume ports exist": you inherit the obligation to build a CAS store and a
  FUSE binding in a tiny-ecosystem language.** That is the dominant hidden cost of all-Shen.

### 7.4 Type-checker ergonomics
Shen's sequent-calculus checker is **powerful but slow to compile** and its **error messages are
terse** — debugging a failed type derivation is harder than reading an OCaml type error. For a small
team, the §2.2 invariant encodings are worth it, but the iteration loop is slower and the learning
curve steeper than OCaml's. The Turing-complete checker can also *loop* on a bad datatype definition.

### 7.5 The one thing Shen does *better* — and it's real
Lands on the **homoiconic SBCL substrate** = the original Autopoiesis platform. Policy-as-data
(§2.3), snapshotting, code-as-data, and reuse of the existing CL datom/blob store as the irmin
backing and projection cache are **native**, not bolt-on. The Shen-Prolog control plane (§2.1) is
the user's original vision, first-class. And the absence of a second IO runtime means **no Lwt/Eio
bridge hazard** (the OCaml plan's C3 Blocker simply does not exist here). These are genuine wins —
but they are *integration and expressiveness* wins, not *shipping-risk* wins.

### 7.6 Honest verdict: when does all-Shen make sense?
- **All-Shen makes sense IF**: (a) the team is already deep in Shen/CL and values the homoiconic
  substrate integration with Autopoiesis above all; (b) the product can tolerate the mount being the
  weakest link for a long time (e.g., ship no-mount sparse checkout indefinitely, FUSE last and
  experimental); (c) the team is willing to *build and own* `shen-irmin` (likely by wrapping the CL
  substrate) and a CL FUSE binding, treating that as core IP rather than a dependency; (d) the
  policy/control plane being declarative Prolog + the type-level invariants are seen as primary
  product value.
- **All-Shen does NOT make sense IF**: the goal is the *lowest-risk path to a shipping
  moderate-scale product.* For that goal, **all-OCaml (with the C1–C5 discipline) is the safer bet**:
  Irmin is real and reusable (not assumed), `ocamlfuse`/`ocaml-9p` are maintained, native-compiled
  performance, a (small but) larger ecosystem and contributor pool, and a type system that buys the
  same invariant guarantees with better tooling ergonomics. The split-stack (Rust data plane + OCaml
  control plane) remains the strongest option for the *mount/perf* half.

**Bottom line:** all-Shen is the most *intellectually coherent* and *best-integrated-with-Autopoiesis*
variant, and it genuinely shines in the control plane (declarative Prolog policy, sequent-calculus
invariants, homoiconic policy-as-data). But for a moderate-scale product that must ship and be
operated by a small team, it is **higher risk than all-OCaml** — chiefly because the mount/IO half
bottoms out in an immature CL host binding and because the "assumed" `shen-irmin`/`shen-fuse` ports
are, in reality, large pieces of core IP you must build and own. **Prefer all-OCaml for shipping;
prefer all-Shen only if deep Autopoiesis/CL integration and the declarative control plane are the
product's reason to exist.**

---

## 8. Phased plan (VCS-first, same shape as the OCaml P0–P6)

| Phase | Deliverable | Shen specifics |
|---|---|---|
| **P0 — Spine** | `shen-irmin` behind the `object-store` seam (C1); the four `datatype` invariant skeletons (§2.2); a Shen-Prolog ACL ruleset stub (§2.1); **host/FFI spike** (libfuse-via-sb-alien hello-world + bordeaux-threads land-loop skeleton). Vendored+pinned `shen-irmin`; CI format-migration drill. **Gating spikes:** (a) host FUSE binding viability; (b) Shen-interpreter overhead on the read path. | The spike that *replaces* OCaml's "irmin concurrency" spike is the **CL FUSE binding** spike — the riskiest assumed port. |
| **P1 — Nice single-machine VCS** | local commits + stacks; **real dirstate + O(changes) status/diff** (no mount, host `stat`); **total `merge-tree`** with `shen-diff` diff3 + structural conflicts; no-mount sparse checkout. | All pure Shen except `stat`/hash (host). |
| **P2 — Land queue + fencing** | `with-leadership` + `land-one`; **fencing token CAS'd on fsync'd `durable-append!`**; idempotency in trunk metadata; ack returns durability width. | The type-level lease witness (§2.2b) lands here. |
| **P3 — ACL (Shen-Prolog) + derived index** | full path-scoped ACL rules (prefix/deny-wins/groups); policy-as-data in `.shenvfs/policy.shen`; derived projection index on the host datom store (rebuildable, not replicated — C2). | Shen-Prolog becomes load-bearing. |
| **P4 — Distribution** | leased leader; landed-log replica streaming (sole replication — C2); read-your-writes cookie + timeout→leader fallback (P4); durability-width knob. | Transport = host `usocket`/`dexador`. |
| **P5 — Mount** | `shen-fuse`/`shen-9p` lazy mount over host FFI; FUSE write-tracking → dirstate upgrade; sparse profiles. **Default to 9p** (simpler host binding) unless FUSE is forced. | The least-proven phase (§7.1); ship-gated behind P1 no-mount checkout. |
| **P6 — Hardening** | failover drills, backpressure, audit, ops runbooks; type-checker compile-time budget; `shen-irmin` migration drills. | — |

Critical path **P0→P1→P2** is a usable single-node trunk VCS *with real merge and fast status* — the
Torvalds "prove this first" deliverable. Distribution and mount follow.

---

## 9. Traceability — Shen plan vs. panel obligations (C1–C5, P1–P7)

| Obligation | Source | How the Shen plan honors it |
|---|---|---|
| **C1** Abstract the store; own the seam; pin/vendor/migration-drill | Fukamachi+Minsky Blocker | `object-store` Shen interface (§3, §C1); only one module names `shen-irmin`; vendored+pinned (mandatory since assumed). |
| **C2** One replication system; index is local rebuildable cache | Torvalds+Fukamachi+Minsky | Landed-log is sole replication; host datom store = derived projection, never replicated; ACLs in trunk, not index (§3 C2, §2.3). |
| **C3** Single/pinned execution; no exotic concurrency bridge | Fukamachi+Minsky Blocker | One bordeaux-threads land thread owns writes; hash-keyed read cache; **no Lwt/Eio-equivalent bridge exists** in Shen (§3 C3). |
| **C4** Fencing token CAS'd on durable append + type guard | Aphyr Critical + Minsky | `durable-append!` CAS's monotonic token on fsync, re-validates lease before ack; `lease-witness` makes app-originated split-brain a type error (§2.2b, §C4). |
| **C5** Real merge + real dirstate; no overclaim | Torvalds Showstopper + Minsky | Total `merge-tree` with `shen-diff` diff3 + structural conflict constructors; Git-index dirstate in P1, O(changes), works without mount (§2.2c, §C5, P1). |
| **P1** Fencing token for lease handoff | Aphyr | Same as C4 (§C4). |
| **P2** Ack carries durability signal | Aphyr | `durable-append!` returns achieved replica-ack width; client policy on it (§C4, §6). |
| **P3** Idempotency = one atomic authority | Aphyr+Minsky | `commit-tree`→derived log entry, one atomic land step; idem-key in commit metadata, deduped in the serialized section (§3 P3, §5). |
| **P4** Read-your-writes cookie deadlock under partition | Aphyr | `landed-seq` cookie with **timeout → leader fallback** + stated staleness bound (§6, P4 row). |
| **P5** Stacked-change restack-on-land spec | Torvalds | Local commits are a stack; spec restack when the bottom lands (P1 stacks + P5 mount write-tracking feed it). |
| **P6** Store concurrency behind multi-reader VFS validated early | Minsky+Torvalds | P0 **gating spikes**: host FUSE binding viability + Shen read-path overhead; the `object-store` seam allows caching/swapping (§8 P0). |
| **P7** Type-driven domain expressed | Minsky | The four `datatype` sequent rule sets (§2.2) — land FSM, lease witness, total merge, ACL proof — Shen's analogue of the four `.mli`. |

---

## Appendix — relationship to the document set
This plan is the **all-Shen sibling** of the OCaml direction brief (`07`) and its reviewed synthesis
(`12`); it builds the **same product** and discharges the **same obligations**, differing only in
language. It re-expresses Minsky's `.mli` skeleton (`11`) in Shen sequent calculus, and uses the
storage/merge/distribution evidence from the grounding research (`06`). The v1 layer (`00`–`05`) is
the original CL-substrate design — which, notably, this plan partially *re-embraces* at the host
level by running on shen-cl/SBCL and reusing the Autopoiesis substrate as the store backing.
