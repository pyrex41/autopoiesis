\* mvfs/test/illegal.shen — the FOUR illegal programs (spec/02 §1).
   This file MUST be REJECTED by the typechecker. `make typecheck-negative`
   succeeds only when loading this (with tc on, after the core) FAILS.
   illegal-1..3 live in package mvfs so the core transitions resolve and the
   rejection is a genuine TYPE violation. illegal-4 lives in a foreign package
   so the witness constructor tag is foreign (not the real lease-witness).
   Do NOT "fix" these — they are negative tests. *\
(package mvfs []

\* (1) land WITHOUT admission: `land` wants a `based` change, but a freshly
   `submit`ted change has type `submitted`. Type error: submitted =/= based. *\
(define illegal-1
  { lease-witness --> landed }
  W -> (land W (submit "c1" "k1" "t-base" "t-tree" [] "alice") 1))

\* (2) land WITHOUT a lease: `land`'s first arg must be a `lease-witness`, but
   an `acl-proof` (from `check`) is a different type. Type error. *\
(define illegal-2
  { based --> landed }
  B -> (land (check "alice" [] 7) B 1))

\* (3) base WITHOUT admission: `base` wants `admitted`; a `submitted` change is
   not admitted. Type error: submitted =/= admitted. *\
(define illegal-3
  { hash --> based }
  Tip -> (base (submit "c3" "k3" "t-base" "t-tree" [] "alice") Tip git-merge)))

\* (4) FORGE a lease-witness from a FOREIGN package: the tag `mk-witness` here
   binds to mvfs.forge.mk-witness, a different tag than the core's
   mvfs.mk-witness, so it is NOT a `lease-witness` and the return type is
   violated. You cannot mint authority outside `with-leadership`. *\
(package mvfs.forge []
(define illegal-4
  { number --> lease-witness }
  E -> [mk-witness E]))
