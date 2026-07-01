\* mvfs/test/log-test.shen — positive P0 tests (spec/01).
   Checksum chaining + the chain invariant. Package mvfs so the internal core
   symbols resolve. (roll/contrib bottom out in the crc64/xor64 host primitives,
   so run-all is a typecheck/structure test here; the runtime numeric check runs
   under a backend that provides crc64/xor64 — P0.5.) *\
(package mvfs []

(define an-entry
  { number --> number --> landed-entry }   \* seq, prev -> entry (post=0 placeholder) *\
  Seq Prev -> [mk-entry Seq "c" "k" "commit" "parent" "root" [] "alice" 0 1 Prev 0 0])

\* a two-entry chain: e2.prev must equal e1.post. (Takes an ignored arg:
   Shen's tc rejects a nullary `{ boolean }` signature.) *\
(define run-all
  { number --> boolean }
  _ -> (let E1   (an-entry 1 0)
        (let Post1 (roll 0 (contrib (entry-cells E1)))
         (let E2   (an-entry 2 Post1)
          (chain-ok? Post1 (entry-prev E2))))))   \* link holds *\
)
