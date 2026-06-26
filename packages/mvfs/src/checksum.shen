\* mvfs/checksum.shen — the rolling-checksum CHAINING PROTOCOL (spec/01 §5).
   crc64/xor64 are trusted host primitives (boundary.shen); the chaining logic
   here — the canonical contrib field set and the prev==post chain invariant —
   is pure, proven Shen. The contrib field list is NORMATIVE for the
   differential oracle (spec/00 §5.1, spec/07). *\
(package mvfs.checksum [contrib roll chain-ok?]

(import mvfs.boundary)

\* CONTRIB: the canonical serialization of a landed-entry over ALL fields
   EXCEPT prev-checksum / post-checksum. Fields are joined by US (\x1f) in the
   exact frozen order; lists are joined by RS (\x1e). This string is the input
   to crc64. (Keystone §5.1: hash = git SHA-256 hex; numbers as decimal.) *\
(define contrib
  { (list string) --> string }     \* the pre-serialized field cells, in frozen order *\
  Cells -> (join (n->string 31) Cells))

\* roll: post = xor64(prev, crc64(contrib))  — commutative & O(changed). *\
(define roll
  { number --> string --> number }  \* prev-checksum, contrib-bytes -> post-checksum *\
  Prev Contrib -> (xor64 Prev (crc64 Contrib)))

\* the chain invariant linking consecutive entries (spec/01 §5): N+1.prev == N.post. *\
(define chain-ok?
  { number --> number --> boolean } \* prior-entry.post, this-entry.prev -> ok? *\
  PriorPost ThisPrev -> (= PriorPost ThisPrev))

\* join: deterministic separator-join over string cells. *\
(define join
  { string --> (list string) --> string }
  _ []        -> ""
  _ [X]       -> X
  Sep [X | Xs] -> (@s X Sep (join Sep Xs)))
)
