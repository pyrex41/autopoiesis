\* mvfs/log.shen — the landed-log: append-only, checksum-chained, fenced
   durable append (spec/01, spec/02 §3). The fence (lease epoch) is CAS'd
   against the durable head ATOMICALLY with fsync via the audited
   durable-cas-append! primitive (boundary.shen). *\
(package mvfs.log [append-fenced! verify-chain head-seq head-post head-fence]

(import mvfs.boundary mvfs.checksum mvfs.types)

(define *genesis-post* { number } -> 0)   \* checksum seed for an empty log *\

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

\* verify-chain: fold the log checking N+1.prev == N.post and recomputing post. *\
(define verify-chain
  { string --> boolean }
  Path -> (fold-chain (read-all Path) (*genesis-post*)))

(define fold-chain
  { (list landed-entry) --> number --> boolean }
  [] _ -> true
  [E | Es] PriorPost
  -> (if (chain-ok? PriorPost (entry-prev E))
         (if (= (entry-post E) (roll PriorPost (contrib (entry-cells E))))
             (fold-chain Es (entry-post E))
             false)
         false))

\* head accessors (genesis defaults for an empty log). *\
(define head-seq   { string --> number } Path -> (head-num Path entry-seq 0))
(define head-post  { string --> number } Path -> (head-num Path entry-post (*genesis-post*)))
(define head-fence { string --> number } Path -> (head-num Path entry-fence 0))

(define head-num
  { string --> (landed-entry --> number) --> number --> number }
  Path Acc Default
  -> (let H (durable-head Path)
          (if (= H "") Default (Acc (unframe H)))))

\* set prev/post on an (otherwise built) entry. *\
(define with-chain
  { landed-entry --> number --> number --> landed-entry }
  (mk-entry Seq Cid Key Commit Parent Root Paths Author AclV Fence _ _ Ts) Prev Post
  -> (mk-entry Seq Cid Key Commit Parent Root Paths Author AclV Fence Prev Post Ts))

\* framing: a record = contrib-cells ++ [prev post] joined by US, RS-terminated.
   unframe reverses it. (split is a host string op.) *\
(define frame
  { landed-entry --> string }
  E -> (@s (contrib (append (entry-cells E)
                            [(n->string (entry-prev E)) (n->string (entry-post E))]))
           (n->string 30)))

(define unframe
  { string --> landed-entry }
  S -> (cells->entry (split (n->string 31) (chomp-rs S))))

\* read-all / cells->entry / split / chomp-rs are P0 glue; split is host-provided. *\
(define read-all { string --> (list landed-entry) } _ -> (error "P0: read-all (host log scan)"))
(define cells->entry { (list string) --> landed-entry } _ -> (error "P0: cells->entry parser"))
(define split { string --> string --> (list string) } _ _ -> (error "host: split"))
(define chomp-rs { string --> string } S -> S)
)
