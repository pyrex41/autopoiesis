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
)
