\* mvfs/test/illegal.shen — the FOUR illegal programs (spec/02 §1).
   This file MUST be REJECTED by the typechecker. `make typecheck-negative`
   succeeds only when loading this (with type checking ON) FAILS.
   Each clause below is an illegal program; the comment states why it must not
   typecheck. Do NOT "fix" these — they are negative tests. *\
(package mvfs.test.illegal []

(import mvfs.fsm mvfs.types)

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
  Tip -> (base (submit "c3" "k3" "t-base" "t-tree" [] "alice") Tip))

\* (4) FORGE a lease-witness: `mk-witness` is the witness constructor but it is
   NOT exported from mvfs.fsm. Referencing it here is an unbound symbol -> the
   loader/typechecker rejects the file. (You cannot mint authority outside
   `with-leadership`.) *\
(define illegal-4
  { number --> lease-witness }
  E -> (mk-witness E))
)
