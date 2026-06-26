\* mvfs/boundary.shen — the audited Shen<->shell surface (spec/00 §5.4).
   These are the ONLY side-effecting / native primitives in mvfs. Everything
   else is pure Shen. The raw host primitives error by default and are
   overridden per backend (src/host-lua.shen via LuaJIT FFI/os/io;
   src/host-cl.shen via uiop/ironclad). The git verbs are built on shell-run
   and constitute the trusted CAS oracle. *\
(package mvfs.boundary [shell-run shell-run-stdin
                        durable-head durable-cas-append!
                        crc64 xor64
                        git-hash-object git-hash-bytes git-cat-file
                        git-mktree git-commit-tree git-merge-tree
                        verify-blob chomp]

\* ===== raw host primitives (backend MUST override) ===== *\

(define shell-run
  { string --> (list string) --> string }        \* cmd args -> stdout; errors on nonzero exit *\
  _ _ -> (error "mvfs.boundary.shell-run: provided by backend host"))

(define shell-run-stdin
  { string --> (list string) --> string --> string }  \* cmd args stdin -> stdout *\
  _ _ _ -> (error "mvfs.boundary.shell-run-stdin: provided by backend host"))

(define durable-head
  { string --> string }                           \* logpath -> last framed record ("" if empty) *\
  _ -> (error "mvfs.boundary.durable-head: provided by backend host"))

\* The fenced durable append (spec/02 §3): ATOMIC {read head, check fence,
   append framed bytes, fsync}. Returns true iff Expected matches the durable
   head's fence AND New >= Expected; on success the bytes are fsync'd. *\
(define durable-cas-append!
  { string --> number --> number --> string --> boolean }  \* logpath expected-fence new-fence framed -> ok? *\
  _ _ _ _ -> (error "mvfs.boundary.durable-cas-append!: provided by backend host"))

(define crc64
  { string --> number }                           \* ISO/ECMA CRC-64 of bytes *\
  _ -> (error "mvfs.boundary.crc64: provided by backend host"))

(define xor64
  { number --> number --> number }                \* 64-bit XOR *\
  _ _ -> (error "mvfs.boundary.xor64: provided by backend host"))

\* ===== git CAS verbs (trusted oracle, built on shell-run) ===== *\

(define git-hash-object
  { string --> hash }                             \* file-path -> hash (writes object) *\
  P -> (chomp (shell-run "git" ["hash-object" "-w" P])))

(define git-hash-bytes
  { string --> hash }                             \* bytes -> hash (writes object, via stdin) *\
  Bytes -> (chomp (shell-run-stdin "git" ["hash-object" "-w" "--stdin"] Bytes)))

(define git-cat-file
  { hash --> string }                             \* hash -> contents *\
  H -> (shell-run "git" ["cat-file" "-p" H]))

(define git-mktree
  { string --> hash }                             \* tree-spec on stdin -> tree hash *\
  Spec -> (chomp (shell-run-stdin "git" ["mktree"] Spec)))

(define git-commit-tree
  { hash --> hash --> string --> hash }           \* tree parent msg -> commit hash *\
  Tree Parent Msg -> (chomp (shell-run "git" ["commit-tree" Tree "-p" Parent "-m" Msg])))

(define git-merge-tree
  { hash --> hash --> hash --> string }           \* base ours theirs -> merged-tree | conflict report *\
  Base Ours Theirs ->
    (shell-run "git" ["merge-tree" "--write-tree" "--merge-base" Base Ours Theirs]))

\* ===== I5: content integrity — a hash names exactly one byte string ===== *\
(define verify-blob
  { hash --> string --> boolean }                 \* hash bytes -> re-hash matches? *\
  H Bytes -> (= H (git-hash-bytes Bytes)))

\* ===== tiny pure helper: drop a single trailing newline ===== *\
(define chomp
  { string --> string }
  "" -> ""
  S -> (if (= (last-char S) (n->string 10))
           (drop-last S)
           S))

(define last-char { string --> string } S -> (pos S (- (string-length S) 1)))
(define drop-last { string --> string } S -> (substring S 0 (- (string-length S) 1)))

\* substring/string-length are host-provided string ops; on shen-lua these map
   to native Lua string slices, on shen-cl to CL subseq/length. Declared here
   so the typechecker is satisfied; backend supplies the fast impl. *\
(define string-length { string --> number } _ -> (error "host: string-length"))
(define substring { string --> number --> number --> string } _ _ _ -> (error "host: substring"))
)
