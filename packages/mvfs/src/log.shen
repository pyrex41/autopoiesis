\* mvfs/log.shen — the landed-log: append-only, checksum-chained, fenced
   durable append (spec/01, spec/02 §3). The fence (lease epoch) is CAS'd
   against the durable head ATOMICALLY with fsync via the audited
   durable-cas-append! primitive (boundary.shen). Genesis post-checksum seed
   for an empty log is 0. Functions are ordered callee-before-caller (the Shen
   typechecker needs each callee's signature in scope). *\
(package mvfs []

\* ---- P0 glue / host string ops (leaves) ---- *\
(define read-all { string --> (list landed-entry) } _ -> (error "P0: read-all (host log scan)"))
(define cells->entry { (list string) --> landed-entry } _ -> (error "P0: cells->entry parser"))
(define split { string --> string --> (list string) } _ _ -> (error "host: split"))
(define chomp-rs { string --> string } S -> S)

\* framing: a record = contrib-cells ++ [prev post] joined by US, RS-terminated. *\
(define unframe
  { string --> landed-entry }
  S -> (cells->entry (split (n->string 31) (chomp-rs S))))

(define frame
  { landed-entry --> string }
  E -> (@s (contrib (append (entry-cells E)
                            [(str (entry-prev E)) (str (entry-post E))]))
           (n->string 30)))

\* ---- head accessors (genesis defaults for an empty log) ---- *\
(define head-seq
  { string --> number }
  Path -> (let H (durable-head Path) (if (= H "") 0 (entry-seq (unframe H)))))

(define head-post   \* 0 = genesis seed *\
  { string --> number }
  Path -> (let H (durable-head Path) (if (= H "") 0 (entry-post (unframe H)))))

(define head-fence
  { string --> number }
  Path -> (let H (durable-head Path) (if (= H "") 0 (entry-fence (unframe H)))))

\* set prev/post on an (otherwise built) entry. *\
(define with-chain
  { landed-entry --> number --> number --> landed-entry }
  [mk-entry Seq Cid Key Commit Parent Root Paths Author AclV Fence _ _ Ts] Prev Post
  -> [mk-entry Seq Cid Key Commit Parent Root Paths Author AclV Fence Prev Post Ts])

\* verify-chain: fold the log checking N+1.prev == N.post and recomputing post. *\
(define fold-chain
  { (list landed-entry) --> number --> boolean }
  [] _ -> true
  [E | Es] PriorPost
  -> (if (chain-ok? PriorPost (entry-prev E))
         (if (= (entry-post E) (roll PriorPost (contrib (entry-cells E))))
             (fold-chain Es (entry-post E))
             false)
         false))

(define verify-chain
  { string --> boolean }
  Path -> (fold-chain (read-all Path) 0))

\* ---- I3 idempotency-key index over the durable log ----
   at-most-once land: a retried submission carries the same idempotency-key; if
   the log already has an entry for it, the land is a no-op (return the prior
   entry). This is the AUTHORITATIVE I3 guard (pijul apply-idempotency is only a
   merge-layer backstop — a re-recorded change can get a different hash). *\
(define key-find-in
  { id --> (list landed-entry) --> (list landed-entry) }   \* [] = not found, [E] = found *\
  _ [] -> []
  K [E | Es] -> (if (= K (entry-key E)) [E] (key-find-in K Es)))

(define key-find
  { string --> id --> (list landed-entry) }   \* logpath key -> [] | [entry] *\
  Path K -> (key-find-in K (read-all Path)))

(define key-present?
  { string --> id --> boolean }
  Path K -> (cons? (key-find Path K)))

\* append-fenced!: re-read durable head; reject if our epoch is behind the
   head's fence; roll the post-checksum over this entry's contrib; then
   atomically {CAS fence, append framed bytes, fsync}. false => a concurrent
   leader advanced the head; the caller (fsm.land!) aborts the land (I7). *\
(define append-fenced!
  { string --> landed-entry --> number --> boolean }   \* logpath entry epoch *\
  Path E0 Epoch ->
  (let PriorPost  (head-post Path)
   (let PriorFence (head-fence Path)
    (if (< Epoch PriorFence)
        false
        (let Post (roll PriorPost (contrib (entry-cells E0)))
         (let E1  (with-chain E0 PriorPost Post)
          (durable-cas-append! Path PriorFence Epoch (frame E1))))))))
)
