\* mvfs/fsm.shen — THE land-queue kernel core (spec/02).
   The change-state types (submitted -> admitted -> based -> landed) and the
   capability types (acl-proof, lease-witness) have INTERNAL constructors
   (mk-*), so normal code cannot forge an admitted/based change, an ACL proof,
   or a lease witness. Only the exported transition functions move a change
   forward, and each demands its precondition AS A TYPE. Therefore:
     • "land without admission" is unconstructible (land wants `based`, which
       only `base` produces, which wants `admitted`, which only `admit`
       produces, which wants an `acl-proof`).
     • "land without a held lease" is unconstructible (land wants a
       `lease-witness`, minted ONLY inside `with-leadership`).
   The type system is the COMPILE-TIME half of I7; the runtime storage fence
   in log.shen (fence = lease epoch, CAS'd on the durable append) is the
   authoritative guard against a GC-paused/resumed stale leader. Neither
   substitutes for the other (spec/02 §3). *\
(package mvfs.fsm [submitted admitted based landed acl-proof lease-witness lease
                   submit check admit base land with-leadership land!]

(import mvfs.types mvfs.boundary mvfs.checksum mvfs.log)

\* ===== change-state types — constructors mk-* are NOT exported (unforgeable) ===== *\
(datatype change
  Cid:id; Key:id; Base:hash; Tree:hash; Paths:(list path); Author:principal;
  _________________________________________________________________________
  (mk-submitted Cid Key Base Tree Paths Author) : submitted;

  Cid:id; Key:id; Base:hash; Tree:hash; Paths:(list path); Author:principal; Pf:acl-proof;
  _________________________________________________________________________
  (mk-admitted Cid Key Base Tree Paths Author Pf) : admitted;

  Cid:id; Key:id; Tree:hash; Onto:hash; Author:principal; Pf:acl-proof;
  _________________________________________________________________________
  (mk-based Cid Key Tree Onto Author Pf) : based;

  Cid:id; Key:id; Commit:hash; Seq:number;
  _________________________________________________________________________
  (mk-landed Cid Key Commit Seq) : landed;)

\* ===== capability types — constructors NOT exported (unforgeable) ===== *\
(datatype cap
  P:principal; Paths:(list path); V:number;
  _________________________________________
  (mk-proof P Paths V) : acl-proof;          \* only `check` mints one; carries acl-version V (I6) *\

  E:number;
  _________________________________________
  (mk-witness E) : lease-witness;            \* only `with-leadership` mints one; E = lease epoch *\

  if (string? H)
  _________________________________________
  H : lease;)                                \* opaque lease handle (host-managed) *\

\* ===== transitions (the ONLY way to advance a change) ===== *\

(define submit
  { id --> id --> hash --> hash --> (list path) --> principal --> submitted }
  Cid Key Base Tree Paths Author -> (mk-submitted Cid Key Base Tree Paths Author))

\* P0 stub: the real decidable Datalog check is spec/03; here it grants and
   records the acl-version. Returns the unforgeable proof admission requires. *\
(define check
  { principal --> (list path) --> number --> acl-proof }
  P Paths V -> (mk-proof P Paths V))

(define admit
  { submitted --> acl-proof --> admitted }
  (mk-submitted Cid Key Base Tree Paths Author) Pf
  -> (mk-admitted Cid Key Base Tree Paths Author Pf))

\* OCC base-check + git 3-way merge onto the current trunk tip-tree.
   Conflict = the post-rebase result would overwrite an unobserved value
   (git-merge-tree decides), NOT mere path overlap (spec/02 §4). *\
(define base
  { admitted --> hash --> based }            \* second arg = current trunk tip tree *\
  (mk-admitted Cid Key Base Tree Paths Author Pf) Tip
  -> (if (= Base Tip)
         (mk-based Cid Key Tree Tip Author Pf)               \* fast path: no interfering lands *\
         (let M (git-merge-tree Base Tree Tip)
              (if (merge-clean? M)
                  (mk-based Cid Key (merged-tree M) Tip Author Pf)
                  (error "conflict: needs rebase (P1 surfaces hunks)")))))

\* land REQUIRES a lease-witness and a `based` change. Writes the commit. *\
(define land
  { lease-witness --> based --> number --> landed }
  _W (mk-based Cid Key Tree Onto Author _Pf) Seq
  -> (mk-landed Cid Key (git-commit-tree Tree (tip-commit Onto) (commit-msg Cid)) Seq))

\* the ONLY minter of a lease-witness: a witness exists only for the dynamic
   extent of held leadership (spec/02 §2). *\
(define with-leadership
  { lease --> (lease-witness --> A) --> A }
  L F -> (let E (acquire-epoch L)
              (let R (F (mk-witness E))
                   (do (release-lease L E) R))))

\* ===== land! — the effectful driver tying the FSM to the fenced log (I4/I7) =====
   Inside leadership: assign seq, run the `land` transition, build the entry at
   the witness's epoch, and fenced-append. append-fenced! re-reads the durable
   head and CASes the fence epoch atomically with fsync; a stale (GC-paused)
   leader fails the CAS -> hard error, never a silent fork. *\
(define land!
  { lease --> based --> string --> landed }   \* lease, based-change, logpath -> landed *\
  L B Logpath ->
  (with-leadership L
    (/. W
      (let E      (witness-epoch W)
       (let Seq   (+ 1 (log:head-seq Logpath))
        (let LC    (land W B Seq)
         (let Entry (build-entry LC B E Seq Logpath)
          (if (log:append-fenced! Logpath Entry E)
              LC
              (error "fenced append rejected: stale leader, land aborted (I7)")))))))))

\* ===== internal helpers (P0 stubs / glue) ===== *\
(define witness-epoch { lease-witness --> number } (mk-witness E) -> E)
(define merge-clean? { string --> boolean } M -> (not (substr? "CONFLICT" M)))
(define merged-tree  { string --> hash } M -> (chomp (first-line M)))
(define build-entry
  { landed --> based --> number --> number --> string --> landed-entry }
  (mk-landed Cid Key Commit Seq) (mk-based _ _ Tree Onto Author Pf) Epoch _ Logpath
  -> (mk-entry Seq Cid Key Commit Onto Tree [] Author (proof-aclv Pf) Epoch 0 0 0))
                                                  \* prev/post/ts filled by log:append-fenced! *\
(define proof-aclv { acl-proof --> number } (mk-proof _ _ V) -> V)

\* host/boundary stubs (P0): lease epochs + git tip lookup + misc string ops. *\
(define acquire-epoch { lease --> number } _ -> (error "host: acquire-epoch (lease)"))
(define release-lease { lease --> number --> boolean } _ _ -> (error "host: release-lease"))
(define tip-commit { hash --> hash } _ -> (error "host: tip-commit (tree->commit)"))
(define commit-msg { id --> string } Cid -> (@s "mvfs change " Cid))
(define substr? { string --> string --> boolean } _ _ -> (error "host: substr?"))
(define first-line { string --> string } _ -> (error "host: first-line"))
)
