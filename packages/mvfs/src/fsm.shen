\* mvfs/fsm.shen — THE land-queue kernel core (spec/02).
   The change-state types (submitted -> admitted -> based -> landed) and the
   capability types (acl-proof, lease-witness) use package-internal constructor
   TAGS (mk-*), so code in another package cannot forge an admitted/based
   change, an ACL proof, or a lease witness: Shen prefixes a bare tag to the
   referencing package, so a foreign [mk-witness ...] is a different tag and the
   `lease-witness` type rule rejects it. Only the transition functions advance a
   change, and each demands its precondition AS A TYPE. Hence "land without
   admission" and "land without a held lease" are both unconstructible. The type
   system is the COMPILE-TIME half of I7; the runtime storage fence in log.shen
   (fence = lease epoch, CAS'd on the durable append) is the authoritative guard
   against a GC-paused/resumed stale leader. Neither substitutes for the other
   (spec/02 §3). Constructors are list terms [tag ..]. Functions are ordered
   callee-before-caller for the typechecker. *\
(package mvfs []

\* ===== capability types FIRST (acl-proof is referenced by the state types) =====
   tags package-internal (unforgeable):
   [mk-proof ..]  : only `check` mints one (carries acl-version V, I6).
   [mk-witness E] : only `with-leadership` mints one (E = lease epoch).
   lease          : opaque host-managed handle (any string). *\
(datatype cap
  P:principal; Paths:(list path); V:number;
  =========================================
  [mk-proof P Paths V] : acl-proof;

  E:number;
  =========================================
  [mk-witness E] : lease-witness;)

(datatype lease-handle
  if (string? H) ___________________________ H : lease;)

\* ===== change-state types — one datatype per state (single-rule each;
   tags mk-* are package-internal / unforgeable) ===== *\
(datatype submitted-t
  Cid:id; Key:id; Base:hash; Tree:hash; Paths:(list path); Author:principal;
  =========================================================================
  [mk-submitted Cid Key Base Tree Paths Author] : submitted;)

(datatype admitted-t
  Cid:id; Key:id; Base:hash; Tree:hash; Paths:(list path); Author:principal; Pf:acl-proof;
  =========================================================================
  [mk-admitted Cid Key Base Tree Paths Author Pf] : admitted;)

(datatype based-t
  Cid:id; Key:id; Tree:hash; Onto:hash; Author:principal; Pf:acl-proof;
  =========================================================================
  [mk-based Cid Key Tree Onto Author Pf] : based;)

(datatype landed-t
  Cid:id; Key:id; Commit:hash; Seq:number;
  =========================================================================
  [mk-landed Cid Key Commit Seq] : landed;)

\* ===== helpers (defined before the transitions that use them) ===== *\
(define substr? { string --> string --> boolean } _ _ -> (error "host: substr?"))
(define first-line { string --> string } _ -> (error "host: first-line"))
(define merge-clean? { string --> boolean } M -> (not (substr? "CONFLICT" M)))
(define merged-tree  { string --> hash } M -> (chomp (first-line M)))
(define tip-commit { hash --> hash } _ -> (error "host: tip-commit (tree->commit)"))
(define commit-msg { id --> string } Cid -> (@s "mvfs change " Cid))
(define acquire-epoch { lease --> number } _ -> (error "host: acquire-epoch (lease)"))
(define release-lease { lease --> number --> boolean } _ _ -> (error "host: release-lease"))
(define witness-epoch { lease-witness --> number } [mk-witness E] -> E)
(define proof-aclv { acl-proof --> number } [mk-proof _ _ V] -> V)
\* `based` field accessors. land reads its fields via these rather than
   destructuring `based` in its own rule head: doing both (destructure mk-based
   AND construct a state) while `base` also constructs mk-based trips a
   shen-lua typechecker edge case; reading via accessors (as build-entry does)
   avoids it. The type discipline is unchanged. *\
(define based-cid  { based --> id }        [mk-based C _ _ _ _ _] -> C)
(define based-key  { based --> id }        [mk-based _ K _ _ _ _] -> K)
(define based-tree { based --> hash }      [mk-based _ _ T _ _ _] -> T)
(define based-onto { based --> hash }      [mk-based _ _ _ O _ _] -> O)
(define build-entry
  { landed --> based --> number --> number --> string --> landed-entry }
  [mk-landed Cid Key Commit Seq] [mk-based _ _ Tree Onto Author Pf] Epoch _ Logpath
  -> [mk-entry Seq Cid Key Commit Onto Tree [] Author (proof-aclv Pf) Epoch 0 0 0])
                                                  \* prev/post/ts filled by append-fenced! *\

\* ===== transitions (the ONLY way to advance a change) ===== *\

(define submit
  { id --> id --> hash --> hash --> (list path) --> principal --> submitted }
  Cid Key Base Tree Paths Author -> [mk-submitted Cid Key Base Tree Paths Author])

\* P0 stub: the real decidable Datalog check is spec/03; here it grants and
   records the acl-version. Returns the unforgeable proof admission requires. *\
(define check
  { principal --> (list path) --> number --> acl-proof }
  P Paths V -> [mk-proof P Paths V])

(define admit
  { submitted --> acl-proof --> admitted }
  [mk-submitted Cid Key Base Tree Paths Author] Pf
  -> [mk-admitted Cid Key Base Tree Paths Author Pf])

\* OCC base-check + git 3-way merge onto the current trunk tip-tree.
   Conflict = the post-rebase result would overwrite an unobserved value
   (git-merge-tree decides), NOT mere path overlap (spec/02 §4). *\
(define base
  { admitted --> hash --> based }            \* second arg = current trunk tip tree *\
  [mk-admitted Cid Key Base Tree Paths Author Pf] Tip
  -> (if (= Base Tip)
         [mk-based Cid Key Tree Tip Author Pf]               \* fast path: no interfering lands *\
         (let M (git-merge-tree Base Tree Tip)
              (if (merge-clean? M)
                  [mk-based Cid Key (merged-tree M) Tip Author Pf]
                  (error "conflict: needs rebase (P1 surfaces hunks)")))))

\* land REQUIRES a lease-witness and a `based` change. Writes the commit. *\
\* NOTE: the witness is destructured as [mk-witness _] (not a bare variable):
   the Shen typechecker needs a constructor pattern on the witness arg when the
   `based` arg is also a constructor pattern. It still requires a real
   lease-witness (the type), so the I7 capability discipline is intact. *\
(define land
  { lease-witness --> based --> number --> landed }
  [mk-witness _] B Seq
  -> (let Commit (git-commit-tree (based-tree B) (tip-commit (based-onto B)) (commit-msg (based-cid B)))
          [mk-landed (based-cid B) (based-key B) Commit Seq]))

\* the ONLY minter of a lease-witness: a witness exists only for the dynamic
   extent of held leadership (spec/02 §2). *\
(define with-leadership
  { lease --> (lease-witness --> A) --> A }
  L F -> (let E (acquire-epoch L)
              (let R (F [mk-witness E])
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
       (let Seq   (+ 1 (head-seq Logpath))
        (let LC    (land W B Seq)
         (let Entry (build-entry LC B E Seq Logpath)
          (if (append-fenced! Logpath Entry E)
              LC
              (error "fenced append rejected: stale leader, land aborted (I7)")))))))))
)
