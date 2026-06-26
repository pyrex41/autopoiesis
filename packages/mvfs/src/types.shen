\* mvfs/types.shen — freely-constructible data types: scalar carriers, the
   public merge-result, and the landed-log entry record (spec/00 §5.1).
   The land-FSM *state* types and the *capability* types are NOT here — they
   live in fsm.shen with package-internal constructors so they cannot be
   forged from another package (Shen prefixes a foreign tag to the local
   package, so the type rule won't accept it). Shen datatype constructors are
   list terms [tag ...], not (tag ...). *\
(package mvfs []

\* scalar synonyms (hash/id/principal/path = string) come from scalars.shen,
   loaded first. *\

\* ===== merge-result — public data (produced by fsm.base via git-merge-tree) ===== *\
(datatype merge-result
  T : hash;
  ===================
  [merged T] : merge-result;

  C : (list path);
  ===================
  [conflicted C] : merge-result;)

\* ===== the landed-log entry (spec/00 §5.1 frozen shape) =====
   Field order is NORMATIVE; the contrib field set (everything except
   prev/post checksum) feeds the rolling checksum (checksum.shen). *\
(datatype landed-entry
  Seq : number; Cid : id; Key : id; Commit : hash; Parent : hash; Root : hash;
  Paths : (list path); Author : principal; AclV : number; Fence : number;
  Prev : number; Post : number; Ts : number;
  ==============================================================================
  [mk-entry Seq Cid Key Commit Parent Root Paths Author AclV Fence Prev Post Ts]
    : landed-entry;)

\* ===== accessors the log needs ===== *\
(define entry-seq   { landed-entry --> number } [mk-entry S _ _ _ _ _ _ _ _ _ _ _ _] -> S)
(define entry-fence { landed-entry --> number } [mk-entry _ _ _ _ _ _ _ _ _ F _ _ _] -> F)
(define entry-prev  { landed-entry --> number } [mk-entry _ _ _ _ _ _ _ _ _ _ P _ _] -> P)
(define entry-post  { landed-entry --> number } [mk-entry _ _ _ _ _ _ _ _ _ _ _ Q _] -> Q)

\* entry-cells: the contrib field set in frozen order, pre-serialized to string
   cells (excludes Prev/Post). Feeds (contrib ...). Numbers -> decimal,
   path lists -> RS-joined. *\
(define join-paths
  { (list path) --> string }
  Ps -> (join (n->string 30) Ps))   \* RS (\x1e) separated *\

(define entry-cells
  { landed-entry --> (list string) }
  [mk-entry Seq Cid Key Commit Parent Root Paths Author AclV Fence _ _ Ts]
  -> [(str Seq) Cid Key Commit Parent Root
      (join-paths Paths) Author (str AclV) (str Fence) (str Ts)])
)
