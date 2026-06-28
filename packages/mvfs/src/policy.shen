\* mvfs/policy.shen — policy lands: tie the ACL into the land kernel (spec/03 §4).
   A policy change lands through the SAME fenced land path as code (linearizable),
   as a landed-entry marked by the reserved path ".mvfs/policy" whose Commit is a
   CAS blob holding the ruleset. Then:
     acl-version      = the seq of the most recent policy entry (I6 fence).
     effective-policy = the ruleset from that entry's blob.
   A read evaluates `can-read?` against the effective policy at the current
   acl-version; the read tier already fences tokens on acl-version (read.shen).
   v1 stores a full ruleset snapshot per policy entry (latest wins); delta-folding
   (spec §4) is a later refinement. Depends on acl.shen (loaded before this). *\
(package mvfs []

\* ===== ruleset <-> blob serialization (rule per line, TAB-joined cells) ===== *\
(define rule->line { (list string) --> string } [S A P E] -> (join (n->string 9) [S A P E])
                                                _ -> "")
(define rules->lines { (list (list string)) --> (list string) }
  [] -> []
  [R | Rs] -> [(rule->line R) | (rules->lines Rs)])
(define policy->blob { (list (list string)) --> string }
  Rules -> (join (n->string 10) (rules->lines Rules)))
(define lines->rules { (list string) --> (list (list string)) }
  [] -> []
  ["" | Ls] -> (lines->rules Ls)
  [L | Ls] -> [(split (n->string 9) L) | (lines->rules Ls)])
(define blob->policy { string --> (list (list string)) }
  "" -> []
  B -> (lines->rules (split (n->string 10) B)))

\* ===== policy land (fenced, linearizable — same kernel as code) ===== *\
(define policy-entry
  { number --> id --> hash --> number --> landed-entry }   \* seq key blob epoch *\
  Seq Key Blob Epoch
  -> [mk-entry Seq "policy" Key Blob "" "" [".mvfs/policy"] "system" Seq Epoch 0 0 0])

(define policy-land!
  { lease --> id --> (list (list string)) --> string --> landed }   \* lease key ruleset logpath *\
  L Key Rules Logpath
  -> (with-leadership L
       (/. W
         (let E    (witness-epoch W)
          (let Seq  (+ 1 (head-seq Logpath))
           (let Blob (git-hash-bytes (policy->blob Rules))
            (let Entry (policy-entry Seq Key Blob E)
             (if (append-fenced! Logpath Entry E)
                 [mk-landed "policy" Key Blob Seq]
                 (error "I7: policy land rejected (stale leader)")))))))))

\* ===== read the effective policy + acl-version from the durable log ===== *\
(define path-has?
  { string --> (list path) --> boolean }
  _ [] -> false
  X [X | _] -> true
  X [_ | R] -> (path-has? X R))
(define is-policy? { landed-entry --> boolean } E -> (path-has? ".mvfs/policy" (entry-paths E)))

(define latest-policy-entry
  { (list landed-entry) --> (list landed-entry) }   \* [] | [highest-seq policy entry] *\
  [] -> []
  [E | Es] -> (let Rest (latest-policy-entry Es)
                (if (is-policy? E)
                    (if (= Rest [])
                        [E]
                        (if (> (entry-seq E) (entry-seq (head Rest))) [E] Rest))
                    Rest)))

(define acl-version-of
  { string --> number }
  Logpath -> (let LP (latest-policy-entry (read-all Logpath))
               (if (= LP []) 0 (entry-seq (head LP)))))

(define effective-policy
  { string --> (list (list string)) }
  Logpath -> (let LP (latest-policy-entry (read-all Logpath))
               (if (= LP []) [] (blob->policy (git-cat-file (entry-commit (head LP)))))))

\* the integrated read decision: can P read Path under the policy currently landed? *\
(define can-read-at?
  { string --> id --> path --> (list (list id)) --> boolean }
  Logpath P Path Mem -> (can-read? P Path (effective-policy Logpath) Mem))
)
