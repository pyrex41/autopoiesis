\* mvfs/vfs.shen — the VFS mount client, checkout-first v1 (spec/05). The mount is
   TRUSTED SHELL (§5.4): a sparse, lazy, content-addressed materialize helper +
   git-index-style dirstate — NOT a brain (no authz/ordering here; that's the
   serve tier + ACL). It sits on the existing git-CAS + resolve primitives.
   Reuses prefix-of? from acl.shen (loaded before this file).

   Representations (strings):
     tree-entry  = [Path Mode Hash Size]   (from git-ls-tree-r)
     profile     = (list prefix)            (cone prefixes, e.g. "src/")
     dirstate    = (list [Path Hash Size Mtime])
     status row  = [Path State]             State in {"modified" "deleted"} *\
(package mvfs []

\* ===== sparse profile membership (§B4): any cone-prefix matches ===== *\
(define in-profile?
  { (list string) --> path --> boolean }
  [] _ -> false
  [Pre | Ps] Path -> (if (prefix-of? Pre Path) true (in-profile? Ps Path)))

(define tracked?
  { (list (list string)) --> path --> boolean }
  [] _ -> false
  [[P _ _ _] | Ds] Path -> (if (= P Path) true (tracked? Ds Path))
  [_ | Ds] Path -> (tracked? Ds Path))

\* ===== want-set (§B5): in-profile, not-yet-tracked tree entries to fetch ===== *\
(define want-set
  { (list (list string)) --> (list string) --> (list (list string)) --> (list (list string)) }
  [] _ _ -> []
  [[Path Mode Hash Size] | Es] Prof Ds
  -> (if (and (in-profile? Prof Path) (not (tracked? Ds Path)))
         [[Path Mode Hash Size] | (want-set Es Prof Ds)]
         (want-set Es Prof Ds))
  [_ | Es] Prof Ds -> (want-set Es Prof Ds))

(define wt-path { string --> path --> string } Wd Path -> (@s Wd "/" Path))

\* ===== materialize: write each blob to <workdir>/<path>, record a dirstate row
   [path hash size mtime] from the written file (size/mtime feed status). ===== *\
(define materialize!
  { (list (list string)) --> string --> (list (list string)) }
  [] _ -> []
  [[Path _ Hash _] | Es] Wd
  -> (let WF (wt-path Wd Path)
       (do (write-blob! Hash WF)
        [[Path Hash (str (file-size WF)) (str (file-mtime WF))] | (materialize! Es Wd)]))
  [_ | Es] Wd -> (materialize! Es Wd))

\* ===== checkout (v1 clone+materialize): tree + sparse profile -> dirstate =====
   widen = checkout-into an existing dirstate (want-set skips already-tracked). *\
(define checkout!
  { hash --> (list string) --> (list (list string)) --> string --> (list (list string)) }
  Tree Prof Ds Wd -> (append Ds (materialize! (want-set (git-ls-tree-r Tree) Prof Ds) Wd)))

\* ===== status (§B6) O(changes): (size,mtime) quickcheck, then hash fallback =====
   clean entries are omitted; deleted/modified reported. *\
(define entry-status
  { (list string) --> string --> (list string) }
  [Path Hash SizeS MtimeS] Wd
  -> (let WF (wt-path Wd Path)
       (if (< (file-size WF) 0)
           [Path "deleted"]
           (if (and (= (file-size WF) (str->num SizeS)) (= (file-mtime WF) (str->num MtimeS)))
               []                                   \* quickcheck hit: unchanged, no re-hash *\
               (if (= (hash-file WF) Hash) [] [Path "modified"]))))
  _ _ -> [])

(define status
  { (list (list string)) --> string --> (list (list string)) }
  [] _ -> []
  [D | Ds] Wd -> (let S (entry-status D Wd)
                   (if (= S []) (status Ds Wd) [S | (status Ds Wd)])))

\* ===== switch-revision (spec/05 §B7): rebase the working tree to a new tree =====
   For each in-profile entry of the NEW tree: keep the file if the old dirstate has
   it at the same hash (no rewrite), else materialize. Evict in-profile files that
   the new tree no longer has. Returns the new dirstate. *\
(define find-row
  { (list (list string)) --> path --> (list (list string)) }   \* [] | [row] *\
  [] _ -> []
  [[P H S M] | Ds] Path -> (if (= P Path) [[P H S M]] (find-row Ds Path))
  [_ | Ds] Path -> (find-row Ds Path))
(define row-hash { (list string) --> hash } [_ H _ _] -> H
                                            _ -> "")
(define entry-has-path?
  { (list (list string)) --> path --> boolean }
  [] _ -> false
  [[P _ _ _] | Es] Path -> (if (= P Path) true (entry-has-path? Es Path))
  [_ | Es] Path -> (entry-has-path? Es Path))

(define sync-entries
  { (list (list string)) --> (list (list string)) --> string --> (list (list string)) }
  [] _ _ -> []
  [[Path Mode Hash Size] | Es] Old Wd
  -> (let R (find-row Old Path)
       (if (and (not (= R [])) (= (row-hash (head R)) Hash))
           [(head R) | (sync-entries Es Old Wd)]                  \* unchanged: keep, no rewrite *\
           (let WF (wt-path Wd Path)
             (do (write-blob! Hash WF)
              [[Path Hash (str (file-size WF)) (str (file-mtime WF))] | (sync-entries Es Old Wd)]))))
  [_ | Es] Old Wd -> (sync-entries Es Old Wd))

(define evict-removed!
  { (list (list string)) --> (list (list string)) --> string --> boolean }
  [] _ _ -> true
  [[Path _ _ _] | Ds] NewEs Wd
  -> (do (if (entry-has-path? NewEs Path) true (rm-file! (wt-path Wd Path)))
         (evict-removed! Ds NewEs Wd))
  [_ | Ds] NewEs Wd -> (evict-removed! Ds NewEs Wd))

(define switch!
  { (list (list string)) --> hash --> (list string) --> string --> (list (list string)) }
  Old NewTree Prof Wd
  -> (let NewEs (want-set (git-ls-tree-r NewTree) Prof [])
       (do (evict-removed! Old NewEs Wd)
           (sync-entries NewEs Old Wd))))
)
