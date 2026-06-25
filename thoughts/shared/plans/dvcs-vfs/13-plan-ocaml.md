---
date: 2026-06-25
researcher: Claude
topic: "mvfs — all-OCaml build plan for a content-addressable, trunk-only monorepo DVCS with a virtual filesystem (moderate scale)"
status: draft
plan: all-ocaml
inputs:
  - thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
  - thoughts/shared/plans/dvcs-vfs/12-synthesis-v2.md
  - thoughts/shared/plans/dvcs-vfs/11-minsky-review.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
  - thoughts/shared/plans/dvcs-vfs/08-aphyr-review-v2.md
  - thoughts/shared/plans/dvcs-vfs/09-torvalds-review-v2.md
  - thoughts/shared/plans/dvcs-vfs/10-fukamachi-review-v2.md
tags: [plan, ocaml, irmin, litefs, dvcs, vfs, trunk, fencing, merge, dirstate, stacks, shen]
last_updated: 2026-06-25
last_updated_by: Claude
---

# mvfs — All-OCaml Build Plan (moderate scale)

This is a build plan, not a brief. It assumes the direction (`07`) and the panel's settled
obligations (`12` §2 C1–C5, §3 P1–P7, §5 amended P0) as **requirements**, and implements the type
skeleton from Minsky (`11`). Where a reviewer settled a question, this plan executes it rather than
re-opening it. The chosen stack is **all-OCaml** (the synthesis §4 option 1), Lwt-native and
single-domain first, with Irmin abstracted behind a seam we own.

The plan is opinionated on purpose. Defaults are stated, not deferred. Someone can start Monday on
P0.

---

## 0. The non-negotiables (baked in, not re-litigated)

| # | Obligation (source) | How this plan bakes it in |
|---|---|---|
| 1 | **Abstract Irmin** behind `Object_store`; no `Irmin.*` in `domain.mli`; pin + `opam.locked` + vendored irmin-pack + CI dump→neutral→reimport drill (C1, Fukamachi B1, Minsky B2) | `lib/object_store/` is the *only* module that `open Irmin`. `domain.mli` references only our `Hash.t`, `Tree.t`, `Commit_id.t`. P0 ships the pin, the lockfile, the vendored submodule, and the migration drill as CI gates. |
| 2 | **One replication system** — landed-log is the sole substrate; SQLite is a pure local rebuildable cache replayed from it (C2, Fukamachi S3, Torvalds F5) | `lib/landed_log/` is the only thing that crosses the network. `lib/index_cache/` (SQLite) is built by replaying landed-log; it is never replicated and never authoritative. ACLs live in Irmin under a reserved path, not in SQLite. |
| 3 | **Lwt-native, single-domain first**; Eio only behind a measured spike; P0 pure-Lwt vs lwt_eio benchmark (C3, Fukamachi S2, Minsky B3) | One domain owns the Lwt loop and is the only thing touching Irmin. VFS reads served from a content-hash-keyed cache (`lib/index_cache` blob cache) in front of the bridge. Spike S2 in P0 decides Lwt-only vs bridge. |
| 4 | **Fencing token** monotonic in landed-log, CAS'd on durable append, lease re-validated after fsync before ack; `Lease.witness` abstract capability (C4, Aphyr Critical, Minsky type #2) | `lib/lease/` exposes `with_leadership` handing an unstorable `witness`; `land_` demands it (compile error otherwise). `lib/landed_log/append` is CAS'd on `Fencing.t` and re-validates lease post-fsync. |
| 5 | **Real merge**: total `merge_tree : base→ours→theirs → (Tree, conflict list) result` with structural-conflict constructors; pure-OCaml diff3 (C5, Torvalds F1, Minsky type #3) | `lib/merge/` owns `merge_tree`, a rename-detecting tree pass over a pure-OCaml diff3 content merge. No libgit2/ctypes unless a measured P1 benchmark forces it. |
| 6 | **Real dirstate in P1** (Git-index-style, works without mount); mount upgrades it later (C5, Torvalds F2) | `lib/dirstate/` ships in P1: stat + `(size,mtime,ctime,inode)` short-circuit, re-hash only suspects, optional watcher. O(changes) is *not* claimed before the index exists; mount write-tracking is a P5 upgrade. |
| 7 | **One land authority**: atomic commit→derived landed-log entry; other rebuildable (P3, Minsky M4) | `Object_store.commit` returns a `Commit_id.t`; the landed-log entry is *derived deterministically* from it inside the same serialized critical section. Irmin is truth; the SQLite index and (optionally) a rebuilt log tail are derived. |
| 8 | **Gating spikes** in P0/P1: (a) irmin-pack concurrent multi-reader w/ GC; (b) pure-Lwt vs Eio (C3, P6 spike, Minsky F7) | Spike S1 (concurrency) and Spike S2 (runtime) are P0 deliverables with go/no-go criteria. Neither is a P5 discovery. |
| 9 | **Optional little Shen**: one place, off the hot path, optional, plain-OCaml default (user) | `lib/acl/` ships a plain-OCaml predicate evaluator as the default and the *only* hot-path code. An **optional** out-of-process Shen-Prolog policy oracle can express complex ACL/admission rules declaratively; it is consulted only at land admission (not on VFS reads), behind a flag, and its verdict is reduced to the same `Acl.proof`. Shen is never load-bearing. |

---

## 1. Project layout

### `dune-project`

```dune
(lang dune 3.14)
(name mvfs)
(generate_opam_files true)
(source (github your-org/mvfs))
(authors "mvfs team")
(maintainers "mvfs team")
(license MIT)

(package
 (name mvfs)
 (synopsis "Trunk-only content-addressable monorepo DVCS with a virtual filesystem")
 (depends
  (ocaml (= 5.1.1))            ; pinned exactly: Eio/effect handlers are compiler-version sensitive
  (dune (>= 3.14))
  ;; --- object store (vendored + pinned; see opam.locked) ---
  (irmin (= 3.10.0))
  (irmin-pack (= 3.10.0))
  ;; --- runtime: Lwt-native first ---
  (lwt (>= 5.7.0))
  (logs (>= 0.7.0))
  (fmt (>= 0.9.0))
  ;; --- merge: pure-OCaml diff, NO libgit2 in P0/P1 ---
  (mvfs-diff3 :pin)           ; vendored pure-OCaml diff3, our own sublibrary
  ;; --- local derived index ---
  (caqti (>= 2.1.0))
  (caqti-lwt (>= 2.1.0))
  (caqti-driver-sqlite3 (>= 2.1.0))
  ;; --- CLI ---
  (cmdliner (>= 1.2.0))
  ;; --- crypto / encoding ---
  (digestif (>= 1.2.0))      ; BLAKE2b/SHA256 for content hashing where we hash ourselves
  ;; --- leader lease (P4): pluggable, etcd/consul client behind an interface ---
  (cohttp-lwt-unix (>= 6.0.0))
  ;; --- testing ---
  (alcotest :with-test)
  (qcheck-alcotest :with-test)))

;; The MOUNT is a SEPARATE package so the core CLI never drags libfuse into its closure.
(package
 (name mvfs-mount)
 (synopsis "9p/FUSE mount for mvfs (power-user feature, separate dependency closure)")
 (depends
  (mvfs (= :version))
  (lwt-9p :pin)              ; mirage/ocaml-9p, Lwt-native, no C FUSE dependency — DEFAULT mount
  ;; ocamlfuse is an alternative impl behind the same Vfs interface, NOT a co-shipped second tech
  ))
```

**Packaging discipline (Fukamachi S5, F4):**

- Commit `opam.locked` (via `opam lock`). CI builds **from the lockfile on a cold opam root**, never
  a floating solve. A weekly "try to bump the lockfile" CI job makes upgrades a green/red signal.
- The OCaml compiler is pinned to a single 5.x in the switch and the lockfile.
- irmin-pack source is **vendored** (git submodule under `vendor/irmin/`, dune-vendored) so a repo
  move / opam yank / forced upgrade cannot brick the build and we can carry a one-line patch.
- Two packages: `mvfs` (core CLI, **no FUSE in its closure** — runs on locked-down CI and macOS
  laptops) and `mvfs-mount` (9p default; libfuse only if a deploy forces FUSE). One mount tech is
  *live*; the other is an alternate impl behind the same `Vfs` signature (Minsky F5: not "two mount
  techs carried as live options").

### `lib/` module tree

```
lib/
  domain/            domain.mli + domain.ml   — ONLY our types. No Irmin.*. The skeleton.
                       Hash, Path, Commit_id, Change_id, Idem_key, Landed_seq, Fencing,
                       Tree, Commit_meta, change GADT, Reject, conflict, Acl.proof signatures
  object_store/      object_store.mli         — module type Object_store (the seam)
                     irmin_store.ml           — THE ONLY module that `open Irmin`; impl of the seam
                     migration.ml             — dump→neutral(tar of hash→bytes + manifest)→reimport
  merge/             merge.mli                — total merge_tree
                     diff3.ml                 — pure-OCaml diff3 (vendored sublib mvfs-diff3)
                     rename_detect.ml         — similarity over CHANGED paths (ort-style), O(changes)
                     tree_merge.ml            — structural pass: rename-rename, delete-modify, add-add
  dirstate/          dirstate.mli             — Git-index-style index; stat short-circuit; watcher hook
                     index_file.ml            — on-disk index format (path,size,mtime,ctime,inode,hash)
                     watcher.ml               — optional inotify/FSEvents dirty-set (irmin-watcher)
  lease/             lease.mli                — abstract witness; with_leadership region guard
                     consul.ml / static.ml    — lease providers behind Lease.Provider
  landed_log/        landed_log.mli           — append-only, checksum-chained, fencing-CAS'd log
                     entry.ml                 — (seq, commit_hash, fencing, prev_csum, post_csum)
                     replica.ml               — pull stream + chain verify + apply
  acl/               acl.mli                  — abstract proof; check; longest-prefix deny-wins
                     predicates.ml            — plain-OCaml evaluator (DEFAULT, hot path)
                     shen_oracle.ml           — OPTIONAL out-of-process Shen-Prolog admission oracle
  land/              land.mli                 — the land FSM driver: submit→admit→merge→land_
                     queue.ml                 — serialized submission queue (single leader)
  replica/           replica.mli             — node role (leader|replica), read-your-writes cookie
                     ryw.ml                   — cookie wait w/ timeout→leader fallback→explicit fail
  stack/             stack.mli                — local commit stacks; Change-Id; restack-on-land
  index_cache/       index_cache.mli          — SQLite derived cache (commit graph, blame, path hist)
                     blob_cache.ml            — content-hash-keyed read cache in front of the bridge
                     rebuild.ml               — replay landed-log → rebuild SQLite (Fossil model)
  vfs/               vfs.mli                  — mount-agnostic tree/blob serving interface
                     sparse.ml                — no-mount sparse checkout (P1)
                     write_track.ml           — P5 mount write-tracking → dirstate upgrade
bin/
  mvfs.ml            — cmdliner CLI: clone log status diff commit submit stack land
  mvfs_leader.ml     — leader daemon (land queue + lease + landed-log)
  mvfs_replica.ml    — replica daemon (pull + apply + serve reads)
mount/               — mvfs-mount package: 9p server (default) over Vfs; ocamlfuse alt impl
test/
  unit/              per-module Alcotest + QCheck
  fault/             fault-injection suite: fencing, handoff, idempotency, RYW, split-brain
  bench/             S1 (irmin-pack concurrent multi-reader+GC), S2 (Lwt vs lwt_eio), land/read perf
```

---

## 2. The domain `.mli` skeleton (`lib/domain/domain.mli`)

This is the contract. It contains **no `Irmin.*` types**. Every load-bearing invariant is a type.
These compile against opaque submodules; the bodies live in their respective `lib/` modules.

```ocaml
(* lib/domain/domain.mli
   The domain vocabulary. NOTHING from Irmin appears here. The object_store seam
   converts between these types and Irmin underneath. *)

module Hash : sig
  type t                                  (* content address, opaque *)
  val to_hex : t -> string
  val of_hex : string -> t option
  val equal : t -> t -> bool
end

module Path : sig
  type t                                  (* normalized repo-relative path *)
  val of_string : string -> (t, [`Invalid] ) result
  val to_string : t -> string
  module Set : Set.S with type elt = t
end

module Commit_id : sig type t val hash : t -> Hash.t val equal : t -> t -> bool end
module Change_id : sig type t val fresh : unit -> t val to_string : t -> string end
module Idem_key  : sig type t val of_string : string -> t end
module Landed_seq : sig type t val zero : t val succ : t -> t val (<) : t -> t -> bool end
module Fencing   : sig
  (* monotonic fencing token; obtained from the lease provider, carried into the log *)
  type t
  val to_int64 : t -> int64
  val (<) : t -> t -> bool
end

module Tree : sig
  type t                                  (* an immutable tree value; opaque to the domain *)
  type entry = Blob of Hash.t | Subtree of Hash.t
  val root_hash : t -> Hash.t
end

module Commit_meta : sig
  type t = {
    change_id    : Change_id.t;
    author       : string;
    message      : string;
    idem_key     : Idem_key.t;
    paths_touched: Path.Set.t;
  }
end

(* ---- ACL: an unforgeable proof, only the evaluator can mint one (Minsky type #4) ---- *)
module Acl : sig
  type proof                              (* abstract: ONLY check produces this *)
  type subject
  type action = Submit | Read
  module Denied : sig type t val to_string : t -> string end
  (* the proof is tagged with the tip it was evaluated against, so staleness is detectable *)
  val proof_tip : proof -> Commit_id.t
  val check : subject -> Path.Set.t -> action -> tip:Commit_id.t
           -> (proof, Denied.t) result Lwt.t
end

(* ---- Merge conflicts: explicit structural constructors (Minsky type #3, Torvalds F1) ---- *)
module Conflict : sig
  type hunk
  type t =
    | Text       of { path : Path.t; hunks : hunk list }
    | Rename_rename of { old_path : Path.t; ours : Path.t; theirs : Path.t }
    | Delete_modify of { path : Path.t; deleted_by : [`Ours | `Theirs] }
    | Add_add    of { path : Path.t }
end

(* ---- Reject reasons for admission ---- *)
module Reject : sig
  type t = Acl_denied of Acl.Denied.t | Missing_blob of Hash.t | Bad_base of Commit_id.t
end

(* ====================================================================== *)
(* The land FSM as a GADT with phantom states (Minsky type #1).           *)
(* Each state carries exactly its data; illegal transitions do not type.  *)
(* ====================================================================== *)

type submitted
type admitted
type merged
type landed

type _ change =
  | Submitted : { change_id : Change_id.t; base : Commit_id.t;
                  paths : Path.Set.t; idem_key : Idem_key.t } -> submitted change
  | Admitted  : { change_id : Change_id.t; base : Commit_id.t;
                  paths : Path.Set.t; idem_key : Idem_key.t;
                  acl_ok : Acl.proof } -> admitted change
  | Merged    : { change_id : Change_id.t; idem_key : Idem_key.t;
                  tree : Tree.t; onto : Commit_id.t } -> merged change
  | Landed    : { change_id : Change_id.t; commit : Commit_id.t;
                  seq : Landed_seq.t; durable_width : int } -> landed change
```

### `lib/object_store/object_store.mli` (the seam — C1)

```ocaml
(* The ONLY interface the domain knows about storage. irmin_store.ml is the sole impl.
   No Irmin type escapes this signature. *)
module type S = sig
  open Domain
  type t
  val v        : path:string -> t Lwt.t

  val put_blob : t -> bytes -> Hash.t Lwt.t
  val get_blob : t -> Hash.t -> bytes option Lwt.t
  val has_blob : t -> Hash.t -> bool Lwt.t

  val read_tree  : t -> Hash.t -> (string * Tree.entry) list Lwt.t
  val write_tree : t -> (string * Tree.entry) list -> Hash.t Lwt.t
  val tree_of    : t -> Commit_id.t -> Tree.t Lwt.t

  (* commit returns THE commit id; the landed-log entry is derived from it (one authority, P3/M4) *)
  val commit   : t -> parent:Commit_id.t option -> tree:Hash.t -> meta:Commit_meta.t
              -> Commit_id.t Lwt.t

  val trunk_tip : t -> Commit_id.t Lwt.t
  val history_find_idem : t -> Idem_key.t -> Commit_id.t option Lwt.t  (* dedup read *)

  val gc   : t -> unit Lwt.t
  val push : t -> remote:string -> unit Lwt.t
  val pull : t -> remote:string -> unit Lwt.t
end
```

### `lib/lease/lease.mli` (the capability — C4, Minsky type #2)

```ocaml
module type S = sig
  type t
  type witness                            (* ABSTRACT: cannot be forged, stored, or escape *)

  (* The witness lives only inside the callback, only while the lease provably holds.
     A rank-2 / region encoding prevents it escaping (Domain.change/landed values may
     not close over it). *)
  val with_leadership :
    t -> (witness -> 'a Lwt.t) -> ('a, [`Lost_lease | `Not_leader]) result Lwt.t

  (* the fencing token bound to THIS witness; monotonic across handoffs *)
  val fencing : witness -> Domain.Fencing.t

  (* re-validate AFTER fsync, BEFORE ack (Aphyr Finding 1c). Fails if lease lost mid-land. *)
  val still_valid : witness -> bool Lwt.t
end
```

### `lib/merge/merge.mli` (total — C5, Minsky type #3)

```ocaml
open Domain
(* Total: every (base,ours,theirs) maps to exactly one constructor. No exceptions, no nulls.
   Returns the Tree only on Ok, so you cannot land a tree the merge did not bless. *)
val merge_tree :
  base:Tree.t -> ours:Tree.t -> theirs:Tree.t ->
  obj:(module Object_store.S) ->        (* to read/write subtrees + blobs *)
  (Tree.t, Conflict.t list) result Lwt.t
```

### `lib/land/land.mli` (the FSM driver — ties it together)

```ocaml
open Domain
val admit : submitted change -> Acl.proof -> (admitted change, Reject.t) result
val merge : admitted change -> onto:Commit_id.t ->
            (merged change, Conflict.t list) result Lwt.t   (* total; calls Merge.merge_tree *)
(* land_ DEMANDS the witness — there is no land_ without it. A stale leader cannot
   construct a witness, so split-brain-by-application is a COMPILE ERROR (Minsky #2).
   Internally: atomic { Object_store.commit ; Landed_log.append ~fencing CAS } + lease re-validate. *)
val land_ : leader:Lease.witness -> merged change ->
            (landed change, [`Lost_lease | `Stale_fencing | `Conflict of Conflict.t list]) result Lwt.t
```

### `lib/acl/acl.mli` and the optional Shen oracle

```ocaml
(* predicates.ml: the DEFAULT and hot-path evaluator. Longest-prefix, deny-wins, over
   grants stored in Irmin under a reserved path /.mvfs/acl/. SQLite indexes them; Irmin owns them. *)

(* shen_oracle.ml (OPTIONAL, off by default, off the hot path):
   When admission rules grow beyond simple prefix grants (e.g. "members of team X may submit to
   path P only during business hours unless approver Y signed off"), an out-of-process Shen-Prolog
   process (shen-cl) can express them declaratively as Horn clauses. mvfs consults it ONLY at land
   admission, behind --acl-oracle=shen, and reduces its verdict to the SAME Acl.proof. Verdicts are
   cached per (subject, paths, tip). Plain OCaml predicates remain the default and the fallback if
   the oracle is unreachable. Shen is never on a VFS read and never load-bearing. *)
val oracle_check :
  Domain.Acl.subject -> Domain.Path.Set.t -> Domain.Acl.action -> tip:Domain.Commit_id.t ->
  (Domain.Acl.proof, Domain.Acl.Denied.t) result Lwt.t
```

---

## 3. The land FSM and replication protocol (concrete)

### 3.1 Submit → land (serialized, leader only)

```
client                         leader (single, leased)                        store
  |  submit{base, paths,            |                                            |
  |         change_id, idem_key} -->|  enqueue (queue.ml; serialized)            |
  |                                 |  -- dedup read (one authority) ----------> | history_find_idem(idem_key)
  |                                 |     if found -> return Landed{seq} (no-op, re-return original)
  |                                 |  -- admit: Acl.check(paths, tip) ---------> | reads /.mvfs/acl/ at THIS tip
  |                                 |     -> Acl.proof OR Reject.Acl_denied
  |                                 |  -- presence: has_blob(referenced) -------> | Reject.Missing_blob on miss
  |                                 |  -- OCC base-check: base == trunk_tip?
  |                                 |       yes -> fast path (tree = ours)
  |                                 |       no  -> Merge.merge_tree(base, ours, tip)  (REAL merge)
  |                                 |              -> Ok tree | Error conflicts -> reject w/ conflicts
  |                                 |  === ATOMIC LAND (inside with_leadership witness) ===
  |                                 |    1. commit = Object_store.commit(parent=tip, tree, meta)
  |                                 |    2. fsync Irmin
  |                                 |    3. entry = derive(commit, seq=tip+1, fencing(witness))
  |                                 |    4. Landed_log.append entry  -- CAS on Fencing being current max
  |                                 |         (stale fencing -> `Stale_fencing -> land FAILS, no ack)
  |                                 |    5. fsync landed-log
  |                                 |    6. Lease.still_valid witness ?  (re-validate post-fsync)
  |                                 |         lost -> `Lost_lease -> land FAILS, no ack
  |                                 |    7. (width>=2) await >=1 replica ack
  |  <-- ack{seq, durable_on:[...], width} --                                     |
  |      (ack carries achieved durability width — Aphyr Finding 2)
```

Key points the types enforce / the protocol guarantees:

- **One authority (P3, M4):** `Object_store.commit` is the single write of truth; the landed-log
  entry is *derived* from the returned `Commit_id.t`. The SQLite index and any rebuilt log tail are
  rebuildable projections. Steps 1–4 are inside one serialized critical section against one store
  handle, so the dedup read (step 0) and the append are a single linearization point.
- **Fencing (C4, Aphyr Critical):** `Fencing.t` comes from the held `witness`. The landed-log append
  in step 4 is a **CAS**: it succeeds only if `fencing >= current_max_fencing` in the durable log. A
  resumed stale leader presents an old fencing token → append **fails to commit** (not
  commits-then-resyncs-away). Step 6 re-validates the lease after both fsyncs and before ack.
- **Durability width (P2, Aphyr Major):** default **width 2** (leader fsync + ≥1 replica ack). The
  ack reports `{seq, durable_on, width}` so a CI gate can refuse to proceed on width 1. Correlated
  loss of the ack set (shared rack/PDU/AZ) is named as outside the model.
- **Idempotency across handoff (Aphyr Major 3):** a timed-out submit is **`unknown`**, not failed.
  The CLI re-queries by `idem_key` on the (possibly new) leader before retrying. Re-landing the same
  key when present is a **no-op that re-returns the original seq**. Downstream side effects (CI,
  deploy, tags) are keyed on `landed_seq`, not on submit, so a duplicate land cannot double-fire.

### 3.2 Replica pull + read-your-writes

```
replica:  loop { pull landed-log tail from leader (HTTP stream) ;
                 verify checksum chain (entry N+1.prev == entry N.post) ;
                 pull referenced Irmin objects (Object_store.pull) ;
                 apply -> advance applied_seq ;
                 rebuild SQLite index incrementally from applied entries (Fossil model) }

read-your-writes (ryw.ml):
  client carries cookie = last landed_seq it observed.
  read on replica:
    if applied_seq >= cookie -> serve
    else wait up to T_ryw (default 2s)
       -> if caught up: serve
       -> else: fall back to a LEASE-VALIDATED leader read (leader re-confirms fencing at read time)
       -> if leader unreachable too: FAIL explicitly "cannot satisfy read-your-writes under partition"
                                     (availability sacrificed for requested consistency — stated, not deadlocked)
  non-cookie reads are UNBOUNDED-stale (we do not claim "bounded" without a bound — Aphyr Major 4).
  optional: replicas self-evict from the read pool when (leader_tip - applied_seq) > lag_budget.
```

**Split-brain recovery semantics (Aphyr Minor 5), stated:** if two forks exist at a seq, the
**current lease-holder's chain wins**; the losing fork's commits are **discarded, not merged** (the
chain is linear). Affected authors are **notified** ("your landed commit X at seq N was rolled back
due to a leadership split; re-submit"), and the event is logged to the audit trail as a split-brain
event, distinct from a normal resync. The fencing CAS makes this path rare (a stale leader fails to
append rather than forking); recovery is the backstop, not the primary mechanism.

**The lease inequality (Aphyr Critical 1d), pinned:** `lease_TTL > max_clock_error + max_pause +
renewal_RTT`. For a single-DC moderate deploy: `lease_TTL = 10s`, `max_clock_error = 250ms` (NTP),
`renewal_RTT = 50ms`, budgeted `max_pause = 2s` → 10s > 2.3s holds with margin. Violating it is the
documented split-brain window.

---

## 4. Stacked changes / Change-Id (Torvalds open item)

A **stack** is an ordered chain of local Irmin commits, each carrying a stable `Change_id.t` in
`Commit_meta`. The Change-Id survives review revisions; the `Idem_key.t` dedups a single land
attempt. (Two distinct fields, the Gerrit distinction.)

### Operations (`lib/stack/stack.mli`)

```ocaml
open Domain
type t                                     (* an ordered list of local commits A<-B<-C *)
val of_local : Commit_id.t list -> t
val change_ids : t -> Change_id.t list

(* Landing a stack lands BOTTOM-UP through the queue, one change at a time, each able to
   bounce independently. If B conflicts on land, C is left orphaned for the next restack. *)
val land_stack : t -> leader_client:Leader_client.t ->
  (landed change list, [`Conflict of Change_id.t * Conflict.t list]) result Lwt.t

(* RESTACK-ON-LAND: when the bottom A lands (possibly AMENDED during review, so trunk-A != local-A),
   the client:
     1. learns A landed by matching trunk's commit Change-Id == A's Change-Id (drops local A);
     2. re-parents B,C onto the new trunk tip via PER-COMMIT 3-way merge (Merge.merge_tree),
        preserving each commit's Change-Id;
     3. surfaces conflicts per-commit (not "resubmit from scratch").
   Restack quality == merge quality: rename/delete handling (Merge) is doubly load-bearing here. *)
val restack : t -> onto:Commit_id.t -> obj:(module Object_store.S) ->
  (t, [`Conflict of Change_id.t * Conflict.t list]) result Lwt.t
```

This makes "stacks" a real workflow (the tool maintains the stack as parts land and mutate), not
"three local commits."

---

## 5. Phased plan (P0–P6)

VCS-first ordering preserved: spine+seam+types+spikes → nice single-machine VCS → land-queue →
ACL+index → distribution → mount → hardening.

### P0 — Spine, seam, types, gating spikes *(≈4–6 wks)*

**Deliverables (all testable):**
- `lib/object_store/`: `Object_store.S` signature + `irmin_store.ml` impl on irmin-pack. No `Irmin.*`
  outside this module (enforced by a CI grep check: `Irmin` appears only under `object_store/`).
- `lib/domain/domain.mli`: the full skeleton above **compiles** with stub bodies. The four
  illegal-program tests (land without witness, land before merge, merge before admit, ACL-less land)
  are written as `(* expect compile error *)` cases that the build asserts do NOT compile.
- Dependency posture: `opam.locked` committed; irmin-pack vendored under `vendor/`; **CI cold-cache
  build from lockfile**; pinned compiler. **Format-migration drill** (`migration.ml`):
  dump→tar(hash→bytes)+manifest→reimport round-trip, asserted equal in CI.
- CLI `mvfs clone` / `mvfs log` against a local irmin-pack store with the change-id commit model.
- **Spike S1 (gating):** irmin-pack concurrent multi-reader benchmark with GC running — N domains/
  fibers reading random path subsets of a synthetic large tree while GC runs. **Go/no-go:** p99 read
  latency under target fan-out within budget; if it fails, the seam lets us front a cache or swap the
  backend before any read code hardens.
- **Spike S2 (gating):** pure-Lwt vs `lwt_eio` for the read+land path, benchmarked. **Go/no-go:** if
  Eio's multicore win is marginal at moderate scale, **stay pure-Lwt and drop the bridge** (removes
  the single most OCaml-specific risk). Decision recorded.

**Risk:** the spikes are where the OCaml bet is validated or not. S1 failing means irmin-pack-behind-
a-mount is in doubt (mitigated by the seam + blob cache). Effort: medium; the type skeleton is fiddly
but bounded.

### P1 — A single-machine VCS that's actually nice *(≈6–8 wks)*

- **Real dirstate** (`lib/dirstate/`): Git-index format `(path,size,mtime,ctime,inode,hash)`; stat +
  short-circuit; re-hash only suspects. Works **without** a mount. Optional inotify/FSEvents watcher
  for an O(changes) dirty-set on a no-mount checkout. **Claim:** P1 `status` is *O(repo-files to
  stat)* (or O(changes) with the watcher), **not** the EdenFS journal — that is a P5 upgrade. Stated
  honestly.
- **Real merge** (`lib/merge/`): total `merge_tree`; **pure-OCaml diff3** (vendored `mvfs-diff3`);
  **rename detection** (similarity over the changed-path set, ort-style, O(changes)); structural
  conflict constructors (rename-rename, delete-modify, add-add). CRLF/encoding/trailing-newline/binary
  edge cases handled in the diff3 layer. A measured benchmark decides if libgit2-xdiff is ever needed
  (default: not).
- **Local commits + stacks** (`lib/stack/`): stack model, Change-Id, **restack** (per-commit 3-way
  merge), land-a-stack bottom-up. Restack ships here, not "someday" — without it stacks are a demo.
- **No-mount sparse checkout** (`vfs/sparse.ml`): materialize-on-demand by Irmin lazy subtrees,
  O(profile) not O(repo).
- CLI: `status`, `diff`, `commit`, `stack`, `restack`.

**Risk:** rename/delete merge is the genuinely hard 20% (Torvalds F1). Pure-OCaml diff3 quality and
rename detection are the schedule risk here. Effort: high.

### P2 — Trunk land-queue + fencing (single node) *(≈4–6 wks)*

- `lib/land/` + `lib/landed_log/` + `lib/lease/` (static provider first).
- The serialized submit→admit→OCC→merge→atomic{commit + fencing-CAS append}→ack protocol (§3.1),
  **fencing token** and **post-fsync lease re-validation** in place even single-node (so P4 inherits
  them).
- Idempotency in trunk metadata; timed-out-submit = `unknown`; no-op-on-present re-land.
- Conflict surfacing (text + structural) to the client.
- **Fault-injection suite begins** (`test/fault/`): inject a pause between commit-fsync and append;
  assert no double-ack, no fork, dedup correctness.

**Risk:** getting the atomic critical section + CAS exactly right. Effort: medium.

### P3 — Path ACLs + SQLite derived index *(≈3–5 wks)*

- `lib/acl/predicates.ml`: longest-prefix, deny-wins, over grants stored **in Irmin** under
  `/.mvfs/acl/` (versioned, replicated with the objects, rebuildable). `Acl.proof` minted only here,
  tagged with tip. Leader evaluates ACLs against the **same tip it lands onto**, from its own
  authoritative state (never a stale replica).
- `lib/index_cache/`: SQLite (caqti) commit-graph/blame/path-history index, **rebuilt by replaying
  the landed-log** (`rebuild.ml`). Never replicated, never authoritative. Plus `blob_cache.ml`, the
  content-hash-keyed read cache that fronts the Lwt bridge.
- **Optional** `shen_oracle.ml`: off by default, behind `--acl-oracle=shen`, consulted only at land
  admission, verdict reduced to `Acl.proof`, cached, with plain-OCaml fallback. Documented as
  non-load-bearing.

**Risk:** low–medium. The ACL-in-Irmin decision closes Torvalds F5 / Aphyr residual cleanly. Effort:
medium.

### P4 — Distribution (leased leader, landed-log replicas, RYW) *(≈5–7 wks)*

- `lib/lease/consul.ml` (or etcd): real leased leader; the inequality pinned and configured.
- `lib/landed_log/replica.ml`: pull stream + chain verify + object pull + apply; SQLite rebuilt
  incrementally on each replica from its applied landed-log.
- `lib/replica/ryw.ml`: read-your-writes cookie with `T_ryw` timeout → lease-validated leader read →
  explicit fail. Durability-width knob (default 2); ack carries achieved width. Lag-budget self-
  eviction optional.
- Split-brain recovery semantics + author notification + audit event.
- **Fault-injection suite extended:** leader pause past TTL during land (assert fencing CAS rejects
  the stale append, no fork); kill leader post-ack-pre-replication at width 1 vs 2 (assert ack width
  honesty); retry-across-handoff (assert dedup or honest duplicate-with-stated-width).

**Risk:** this is the distributed-systems crux. The fault-injection suite is the gate. Effort: high.

### P5 — VFS mount (9p default) + write-tracking dirstate upgrade *(≈5–7 wks)*

- `mvfs-mount` package: **9p server** (`ocaml-9p`, Lwt-native, no libfuse) over the `Vfs` interface;
  lazy blob fetch on `read()`, directory listings from Irmin trees, sparse profiles via lazy subtrees.
  ocamlfuse is an alternate impl behind the same `Vfs` signature, not co-shipped as a second live tech.
- `vfs/write_track.ml`: FUSE/9p write-tracking **upgrades** the P1 dirstate to the EdenFS journal
  model → now O(changes) status is *honestly* delivered (and only now is that claim made).
- **Mount perf spike in week 2 of P5** (not at the end): synthetic large tree, measure
  `readdir`/`read` latency and the bridge under concurrent load; the S1/S2 decisions feed this.

**Risk:** irmin-pack-behind-a-mount perf (S1) is the residual; the blob cache (P3) is the mitigation.
9p sidesteps the libfuse/macFUSE matrix. Effort: high.

### P6 — Hardening *(≈4–6 wks)*

- Failover drills, backpressure, audit completeness, ops runbooks, metrics (`land_commit_to_ack_ms`,
  `vfs_read_cache_hit_ratio`), the weekly lockfile-bump CI signal, the periodic format-migration drill.
- The full fault-injection suite as a CI gate; a load test (land N, read M concurrently).

**Risk:** mostly execution. Effort: medium.

### Test strategy

- **Unit** (Alcotest + QCheck per module): merge totality (QCheck: every random base/ours/theirs
  yields exactly one constructor), diff3 correctness against a reference corpus, dirstate
  short-circuit correctness, ACL longest-prefix/deny-wins, landed-log chain invariants.
- **Property** tests for the four type invariants: the illegal programs must not compile (CI asserts
  build failure on the negative cases).
- **Fault-injection** (`test/fault/`, the safety gate): fencing (stale leader append rejected),
  handoff (no double-ack, no fork, RYW timeout→fallback→fail), idempotency (retry-across-handoff is
  dedup-or-honest-duplicate), split-brain (deterministic winner, loser discarded + notified). This
  suite is the distributed-systems acceptance criterion — runnable in a week per Aphyr's own note
  that the failure space is small and enumerable.
- **Benchmarks** (`test/bench/`): S1, S2 as P0 gates; land/read perf instrumented from P2.

---

## 6. Traceability: obligations C1–C5 + surviving problems P1–P7

| Obligation | Where honored in this plan |
|---|---|
| **C1** Abstract Irmin + dep posture | §0.1, §1 (`object_store/` sole Irmin user; `opam.locked`; vendored; migration drill in P0; CI grep gate) |
| **C2** One replication system; SQLite local cache | §0.2, §1 (`landed_log` only network path; `index_cache/rebuild.ml`; ACLs in Irmin not SQLite) |
| **C3** Lwt-native single-domain; Eio behind spike | §0.3, P0 Spike S2, §3.2 single-domain Irmin actor + blob cache |
| **C4** Fencing token + `Lease.witness` capability | §0.4, §2 `lease.mli`, §3.1 steps 4&6, P2/P4 fencing CAS |
| **C5** Total merge + real dirstate | §0.5/§0.6, §2 `merge.mli`, P1 `merge/` + `dirstate/`; O(changes) claim deferred to P5 |
| **P1** Fencing for lease handoff (Aphyr) | §3.1 step 4 CAS; P4 fault-injection |
| **P2** Ack carries durability width | §3.1 ack `{seq,durable_on,width}`; default width 2; P4 |
| **P3** One atomic authority | §0.7, §3.1 (commit→derived log entry, one critical section) |
| **P4** RYW deadlock → timeout/fallback | §3.2 `T_ryw` → leader read → explicit fail; "unbounded-stale" stated |
| **P5** Restack-on-land spec | §4 `stack.mli` (`restack`, land bottom-up, Change-Id match), P1 |
| **P6** irmin-pack concurrency unvalidated | P0 Spike S1 (gating, not P5 discovery); seam enables cache/swap |
| **P7** Type-driven domain expressed | §2 (land FSM GADT, `Lease.witness`, total `merge_tree`, `Acl.proof`) |

---

## 7. Effort / risk summary

| Phase | Effort | Top risk |
|---|---|---|
| P0 spine+seam+types+spikes | medium | S1 (irmin-pack concurrency) fails → read-path doubt; mitigated by seam |
| P1 nice single-machine VCS | high | rename/delete merge + diff3 quality (the hard 20%) |
| P2 land-queue + fencing | medium | atomic critical section + CAS correctness |
| P3 ACL + SQLite index | medium | low; ACL-in-Irmin closes the source-of-truth seam |
| P4 distribution | high | the distributed-systems crux; fault-injection is the gate |
| P5 mount + write-tracking | high | irmin-pack-behind-a-mount perf (residual of S1) |
| P6 hardening | medium | execution |

**Residual risks (eyes open):**

1. **irmin-pack as a concurrent multi-reader behind a mount is the single biggest unknown.** It is
   validated for Tezos's sequential single-writer ledger, not thousands of concurrent path-subset
   reads. The S1 spike is in P0 *because* of this; the `Object_store` seam + the content-hash blob
   cache are the mitigation (swap backend or front a cache without touching the FSM). If S1 fails
   hard, the honest fallback is to reimplement only the object-store slice or reconsider the
   split-stack option from `12` §4 — but the merge/FSM/ACL work is already ours and survives either
   way.
2. **The Lwt↔Eio bridge** if S2 says we need Eio: a single-domain Irmin actor + blob cache bounds it,
   but it remains the most OCaml-specific operational hazard. The P0 spike exists to let us *not*
   take it.
3. **Pure-OCaml diff3 + rename detection quality** is the P1 schedule risk; libgit2-xdiff is the
   measured escape hatch, paid for in FFI surface only if forced.
4. **Failover data-loss window** is real and accepted (not hidden): width-2 default, ack carries
   width, the inequality is pinned, split-brain recovery is specified and notifies authors. This is a
   knob, not consensus — stated as such.

---

## 8. The single biggest risk

**irmin-pack's concurrency story under a multi-reader VFS is unvalidated, and it is load-bearing for
the entire read path / mount.** Everything else in the all-OCaml path is bounded plumbing with a named
fix; this one is an empirical unknown about someone else's database on an axis they never optimized.
The plan front-loads it (Spike S1 in P0, gating) and insulates against it (the `Object_store` seam +
content-hash blob cache), so a bad result is survivable rather than fatal — but it is the experiment
that most determines whether all-OCaml is the right call versus the split-stack fallback.
