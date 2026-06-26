\* mvfs/types.shen — freely-constructible data types: scalar carriers, the
   public merge-result, and the landed-log entry record (spec/00 §5.1).
   The land-FSM *state* types and the *capability* types are NOT here — they
   live in fsm.shen with internal constructors so they cannot be forged. *\
(package mvfs.types [hash id principal path
                     merge-result merged conflicted
                     landed-entry mk-entry
                     entry-seq entry-fence entry-prev entry-post entry-cells]

(import mvfs.checksum)

\* ===== scalar carriers (v1: git SHA-256 hex strings / opaque strings) ===== *\
(datatype scalar
  if (string? H) ______________ H : hash;
  if (string? I) ______________ I : id;
  if (string? P) ______________ P : principal;
  if (string? P) ______________ P : path;)

\* ===== merge-result — public data (produced by fsm.base via git-merge-tree) ===== *\
(datatype merge-result
  T : hash;
  ___________________
  (merged T) : merge-result;

  C : (list path);
  ___________________
  (conflicted C) : merge-result;)

\* ===== the landed-log entry (spec/00 §5.1 frozen shape) =====
   Field order is NORMATIVE; the contrib field set (everything except
   prev/post checksum) feeds the rolling checksum (checksum.shen). *\
(datatype landed-entry
  Seq : number; Cid : id; Key : id; Commit : hash; Parent : hash; Root : hash;
  Paths : (list path); Author : principal; AclV : number; Fence : number;
  Prev : number; Post : number; Ts : number;
  ______________________________________________________________________________
  (mk-entry Seq Cid Key Commit Parent Root Paths Author AclV Fence Prev Post Ts)
    : landed-entry;)

\* ===== accessors the log needs ===== *\
(define entry-seq   { landed-entry --> number } (mk-entry S _ _ _ _ _ _ _ _ _ _ _ _) -> S)
(define entry-fence { landed-entry --> number } (mk-entry _ _ _ _ _ _ _ _ _ F _ _ _) -> F)
(define entry-prev  { landed-entry --> number } (mk-entry _ _ _ _ _ _ _ _ _ _ P _ _) -> P)
(define entry-post  { landed-entry --> number } (mk-entry _ _ _ _ _ _ _ _ _ _ _ Q _) -> Q)

\* entry-cells: the contrib field set in frozen order, pre-serialized to string
   cells (excludes Prev/Post). Feeds (checksum:contrib ...). Numbers -> decimal,
   path lists -> RS-joined. *\
(define entry-cells
  { landed-entry --> (list string) }
  (mk-entry Seq Cid Key Commit Parent Root Paths Author AclV Fence _ _ Ts)
  -> [(n->string Seq) Cid Key Commit Parent Root
      (join-paths Paths) Author (n->string AclV) (n->string Fence) (n->string Ts)])

(define join-paths
  { (list path) --> string }
  Ps -> (checksum.join (n->string 30) Ps))   \* RS (\x1e) separated *\
)
