\* mvfs/test/log-test.shen — positive P0 tests (spec/01).
   Checksum chaining + the chain invariant. (Tests that need the durable host
   primitives — append/fsync/CAS — run under the backend in P0.5.) *\
(package mvfs.test [run-all]

(import mvfs.checksum mvfs.types)

(define an-entry
  { number --> number --> landed-entry }   \* seq, prev -> entry (post filled below) *\
  Seq Prev -> (mk-entry Seq "c" "k" "commit" "parent" "root" [] "alice" 0 1 Prev 0 0))

\* a two-entry chain: e2.prev must equal e1.post. *\
(define run-all
  { boolean }
  -> (let P0 0
       (let E1   (an-entry 1 P0)
        (let Post1 (roll P0 (contrib (entry-cells E1)))
         (let E2   (an-entry 2 Post1)
          (let Post2 (roll Post1 (contrib (entry-cells E2)))
           (and (chain-ok? Post1 (entry-prev E2))            \* link holds *\
                (and (not (= Post1 P0))                       \* checksum advanced *\
                     (not (= Post2 Post1))))))))))           \* and advanced again *\
)
