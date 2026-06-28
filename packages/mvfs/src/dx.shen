\* mvfs/dx.shen — durable execution P-D0 (spec/08): the MOAT, verifiably.
   A worker's rootfs base is a trunk revision (git tree); its mutable state is the
   working tree. A CHECKPOINT lands the content-addressed OVERLAY DELTA of the
   working tree vs the base, through the fenced kernel (like policy-land!). RESTORE
   reconstructs the working tree from base + delta, FAITHFULLY applying deletions
   (the bug Torvalds flagged: plain-file checkout silently loses deletions).

   The composefs/EROFS/overlayfs kernel mounts and Firecracker memory snapshot are
   the REUSE half (spec/08 §0/§1) — deployment, not built here. What is built &
   tested here is the BUILD half: the deterministic overlay-delta serializer, the
   fenced checkpoint commit, and faithful delete/restore. Uses only git + plain
   dirs (no privileged mounts), so it runs in CI.

   delta entry = [Kind Path Hash]   Kind in {"set" "del"}   (del Hash = "") *\
(package mvfs []

\* ===== compute the overlay delta: working tree (Wd) vs base git tree ===== *\
(define base-hash-of
  { (list (list string)) --> path --> hash }   \* base entries, path -> base blob hash ("" if absent) *\
  [] _ -> ""
  [[P _ H _] | Es] Path -> (if (= P Path) H (base-hash-of Es Path))
  [_ | Es] Path -> (base-hash-of Es Path))

\* deletions: base paths that are absent from the working tree (faithful whiteouts) *\
(define deletions
  { (list (list string)) --> string --> (list (list string)) }
  [] _ -> []
  [[P _ _ _] | Es] Wd -> (if (< (file-size (wt-path Wd P)) 0)
                             [["del" P ""] | (deletions Es Wd)]
                             (deletions Es Wd))
  [_ | Es] Wd -> (deletions Es Wd))

\* sets: working files whose hash differs from base (added or modified). Uses
   git-hash-object (-w) so the content is STORED in CAS (C1: the blob must be
   durable before the checkpoint lands), not merely hashed. *\
(define sets
  { (list string) --> (list (list string)) --> string --> (list (list string)) }
  [] _ _ -> []
  [P | Ps] Base Wd -> (let H (git-hash-object (wt-path Wd P))
                        (if (= H (base-hash-of Base P))
                            (sets Ps Base Wd)
                            [["set" P H] | (sets Ps Base Wd)])))

(define compute-delta
  { hash --> string --> (list (list string)) }   \* base-tree, workdir -> delta entries *\
  Base Wd -> (let BE (git-ls-tree-r Base)
               (append (sets (list-files-r Wd) BE Wd) (deletions BE Wd))))

\* ===== deterministic serialization (canonical: host-sorted, normalized) ===== *\
(define delta-line { (list string) --> string } [K P H] -> (join (n->string 9) [K P H])
                                                _ -> "")
(define delta-lines { (list (list string)) --> (list string) }
  [] -> []
  [D | Ds] -> [(delta-line D) | (delta-lines Ds)])
(define serialize-delta
  { (list (list string)) --> string }
  Delta -> (sort-lines (join (n->string 10) (delta-lines Delta))))
(define store-delta!
  { (list (list string)) --> hash }                 \* serialize -> CAS blob (content-addressed) *\
  Delta -> (git-hash-bytes (serialize-delta Delta)))

\* ===== checkpoint = a fenced land of the delta (Commit=delta, Parent=base) ===== *\
(define checkpoint-entry
  { number --> id --> hash --> hash --> number --> landed-entry }
  Seq Key Base Delta Epoch
  -> [mk-entry Seq "checkpoint" Key Delta Base "" [".mvfs/checkpoint"] "system" Seq Epoch 0 0 0])

(define checkpoint!
  { lease --> id --> hash --> string --> string --> landed }   \* lease key base-tree workdir logpath *\
  L Key Base Wd Logpath
  -> (with-leadership L
       (/. W
         (let E    (witness-epoch W)
          (let Seq  (+ 1 (head-seq Logpath))
           (let Delta (store-delta! (compute-delta Base Wd))    \* C1: delta blob in CAS before append *\
            (let Entry (checkpoint-entry Seq Key Base Delta E)
             (if (append-fenced! Logpath Entry E)
                 [mk-landed "checkpoint" Key Delta Seq]
                 (error "I7: checkpoint rejected (stale leader)")))))))))

\* ===== restore: reconstruct the working tree from base + delta ===== *\
(define parse-delta-lines
  { (list string) --> (list (list string)) }
  [] -> []
  ["" | Ls] -> (parse-delta-lines Ls)
  [L | Ls] -> [(split (n->string 9) L) | (parse-delta-lines Ls)])
(define parse-delta
  { string --> (list (list string)) }
  "" -> []
  S -> (parse-delta-lines (split (n->string 10) S)))

\* apply a delta to a (freshly base-materialized) working tree. `del` REMOVES the
   file — a deleted file does NOT reappear (the correctness property). *\
(define apply-delta!
  { (list (list string)) --> string --> boolean }
  [] _ -> true
  [["set" P H] | Ds] Wd -> (do (write-blob! H (wt-path Wd P)) (apply-delta! Ds Wd))
  [["del" P _] | Ds] Wd -> (do (rm-file! (wt-path Wd P)) (apply-delta! Ds Wd))
  [_ | Ds] Wd -> (apply-delta! Ds Wd))

\* C2 verify-before-resume: the delta blob must re-hash to the entry's Commit. *\
(define verify-checkpoint?
  { landed-entry --> boolean }
  E -> (= (git-hash-bytes (git-cat-file (entry-commit E))) (entry-commit E)))

(define restore-checkpoint!
  { landed-entry --> string --> boolean }            \* entry, dest workdir -> ok *\
  E Wd -> (if (not (verify-checkpoint? E))
              (error "C2: checkpoint delta failed verify-before-resume")
              (do (checkout! (entry-parent E) [""] [] Wd)             \* materialize base (full) *\
                  (apply-delta! (parse-delta (git-cat-file (entry-commit E))) Wd))))
)
