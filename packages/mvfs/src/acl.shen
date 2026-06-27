\* mvfs/acl.shen — the policy / ACL matcher (spec/03). Decidable authorization:
   longest-prefix-deny-wins over a finite policy, default-deny / fail-closed.
   The spec frames the decision as "filter + max + any — a comparator over a
   finite candidate set, NOT a search" (§1.2), so it is a total, terminating
   function — decidable by construction.

   Per spec/00 §6a the matcher is conformance-tested against an oracle: we ship
   TWO structurally-different implementations — `acl-decide` (the fast matcher,
   compared via allow-max vs deny-max) and `acl-oracle` (gather candidates, find
   the winning depth, deny-wins) — and test/acl.sh diffs them across a policy×
   query matrix (the §6a CI-blocking differential). They must always agree.

   Representations (all strings; id/path/action are string synonyms):
     rule   = [Subject Action Prefix Effect]   Effect in {"allow" "deny"}
     policy = (list rule)
     member = [Principal Group]                 (one-hop group membership, §1.1)
     members = (list member) *\
(package mvfs []

(define imax { number --> number --> number } A B -> (if (> A B) A B))

\* ===== path prefix matching (§2.1): exact, or a dir-prefix (trailing /) ====== *\
(define starts-with?
  { string --> string --> boolean }
  Pre S -> (if (> (string-length Pre) (string-length S))
               false
               (= Pre (substring S 0 (string-length Pre)))))
(define dir-prefix? { string --> boolean } P -> (if (= P "") false (= (last-char P) "/")))
(define prefix-of?
  { string --> path --> boolean }
  "" _    -> true                                   \* root prefix covers everything *\
  Pre Path -> (if (= Pre Path) true (if (dir-prefix? Pre) (starts-with? Pre Path) false)))

\* ===== subject matching (§1.1): the principal, or a group it belongs to ====== *\
(define mem-pair?
  { id --> id --> (list (list id)) --> boolean }
  _ _ [] -> false
  P G [[P2 G2] | R] -> (if (and (= P P2) (= G G2)) true (mem-pair? P G R))
  P G [_ | R] -> (mem-pair? P G R))
(define subject-matches?
  { id --> id --> (list (list id)) --> boolean }
  P Subj Mem -> (if (= P Subj) true (mem-pair? P Subj Mem)))

\* ===== acl-decide: the fast matcher (allow-max vs deny-max) ===== *\
(define max-len-for
  { id --> string --> path --> (list (list id)) --> string --> (list (list string)) --> number --> number }
  _ _ _ _ _ [] Acc -> Acc
  P Act Path Mem Eff [[Subj A Pre E] | Rs] Acc
  -> (if (and (= A Act) (and (= E Eff) (and (subject-matches? P Subj Mem) (prefix-of? Pre Path))))
         (max-len-for P Act Path Mem Eff Rs (imax Acc (string-length Pre)))
         (max-len-for P Act Path Mem Eff Rs Acc))
  P Act Path Mem Eff [_ | Rs] Acc -> (max-len-for P Act Path Mem Eff Rs Acc))

(define acl-decide
  { id --> path --> string --> (list (list string)) --> (list (list id)) --> boolean }
  P Path Act Policy Mem
  -> (let AllowMax (max-len-for P Act Path Mem "allow" Policy -1)
       (let DenyMax (max-len-for P Act Path Mem "deny" Policy -1)
         (and (>= AllowMax 0) (> AllowMax DenyMax)))))     \* default-deny; deny-wins on tie *\

\* ===== acl-oracle: the independent reference (gather -> winning depth -> deny?) ===== *\
(define gather
  { id --> string --> path --> (list (list id)) --> (list (list string)) --> (list (list string)) }
  _ _ _ _ [] -> []
  P Act Path Mem [[Subj A Pre E] | Rs]
  -> (if (and (= A Act) (and (subject-matches? P Subj Mem) (prefix-of? Pre Path)))
         [[Subj A Pre E] | (gather P Act Path Mem Rs)]
         (gather P Act Path Mem Rs))
  P Act Path Mem [_ | Rs] -> (gather P Act Path Mem Rs))
(define cand-longest
  { (list (list string)) --> number --> number }
  [] Acc -> Acc
  [[_ _ Pre _] | Rs] Acc -> (cand-longest Rs (imax Acc (string-length Pre)))
  [_ | Rs] Acc -> (cand-longest Rs Acc))
(define any-deny-at
  { (list (list string)) --> number --> boolean }
  [] _ -> false
  [[_ _ Pre "deny"] | Rs] L -> (if (= (string-length Pre) L) true (any-deny-at Rs L))
  [_ | Rs] L -> (any-deny-at Rs L))
(define acl-oracle
  { id --> path --> string --> (list (list string)) --> (list (list id)) --> boolean }
  P Path Act Policy Mem
  -> (let Cands (gather P Act Path Mem Policy)
       (if (= Cands [])
           false
           (not (any-deny-at Cands (cand-longest Cands -1))))))

\* ===== the read-tier entry point: can-read? = acl-decide for action "read" =====
   This produces the `allow?` boolean that read.shen's read-decide consumes (I9). *\
(define can-read?
  { id --> path --> (list (list string)) --> (list (list id)) --> boolean }
  P Path Policy Mem -> (acl-decide P Path "read" Policy Mem))

\* ===== §6a conformance: the matcher MUST agree with the oracle on every query =====
   This is the runtime differential / kill-switch logic: if any query diverges,
   conformance fails (in production: fall back to the oracle, fail closed). Each
   query = [Principal Path Action]. *\
(define acl-conform?
  { (list (list string)) --> (list (list id)) --> (list (list string)) --> boolean }
  _ _ [] -> true
  Policy Mem [[P Path Act] | Qs]
  -> (if (= (acl-decide P Path Act Policy Mem) (acl-oracle P Path Act Policy Mem))
         (acl-conform? Policy Mem Qs)
         false)
  _ _ [_ | _] -> false)
)
