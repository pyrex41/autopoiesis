\* mvfs/boundary.shen — the audited Shen<->shell surface (spec/00 §5.4).
   These are the ONLY side-effecting / native primitives in mvfs. Everything
   else is pure Shen. The raw host primitives error by default and are
   overridden per backend (src/host-lua.shen via LuaJIT FFI/os/io;
   src/host-cl.shen via uiop/ironclad). The git verbs are built on shell-run
   and constitute the trusted CAS oracle. *\
(package mvfs []

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

(define git-cat-type
  { hash --> string }                             \* hash -> object type (errors if absent) *\
  H -> (chomp (shell-run "git" ["cat-file" "-t" H])))

\* ===== lore CAS verbs (fragment store; spec/00 §5.4, doc 33) =====
   lore is server-of-record (a local loreserver). These shell out to the
   verified `lore` CLI (v0.8.4). Reads are address-keyed; writes are
   working-tree-oriented (materialize -> dirty -> stage), so the bytes->addr
   put lives in the host (src/host-lore.shen), not here. A lore address is
   <64hex BLAKE3>-<32hex context>; whole objects use the zero context. *\

(define lore-cat-file
  { hash --> string }                             \* address -> bytes (file write to stdout) *\
  Addr -> (shell-run "lore" ["file" "write" "--address" Addr "--output" "-"]))

(define lore-query
  { hash --> string }                             \* address -> immutable-store status report *\
  Addr -> (shell-run "lore" ["repository" "store" "immutable" "query" Addr]))

\* ===== pluggable storage backend (doc 33) =====
   git-be:  self-contained CAS + merge oracle (default; no daemon).
   lore-be: BLAKE3 fragment store for large/binary content + sparse hydration.
   NOTE: 3-way text merge stays git-only BY DESIGN — git-commit-tree /
   git-merge-tree are NOT routed through this selector (see doc 33). Only the
   blob/fragment storage tier is pluggable. *\
(datatype storage-backend
  ___________________________
  git-be : storage-backend;

  ___________________________
  lore-be : storage-backend;)

(define cas-read-blob
  { storage-backend --> hash --> string }         \* address -> bytes *\
  git-be  H -> (git-cat-file H)
  lore-be A -> (lore-cat-file A))

(define cas-locate
  { storage-backend --> hash --> string }         \* address -> presence/status report *\
  git-be  H -> (git-cat-type H)
  lore-be A -> (lore-query A))

(define cas-put-blob
  { storage-backend --> string --> hash }         \* bytes -> address *\
  git-be  Bytes -> (git-hash-bytes Bytes)
  lore-be _     -> (error "mvfs.cas-put-blob: lore writes are working-tree-oriented; use host-lore.lore-stage-path"))

\* ===== git merge helpers (the git arm of the merge oracle) =====
   Relocated from fsm.shen so the merge-oracle dispatch (below) is self-contained
   and loads before fsm.shen. substr?/first-line are host string ops. *\
(define substr? { string --> string --> boolean } _ _ -> (error "host: substr?"))
(define first-line { string --> string } _ -> (error "host: first-line"))
(define merge-clean? { string --> boolean } M -> (not (substr? "CONFLICT" M)))
(define merged-tree  { string --> hash } M -> (chomp (first-line M)))

\* ===== pijul merge-oracle verbs (patch theory; doc 34) =====
   We SHELL OUT to the `pijul` CLI (libpijul is GPL-2.0 — exec, never link;
   Torvalds review). Changes are BLAKE3-base32 addressed; `record` prints
   "Hash: <h>". Conflicts are first-class graph states; we detect them
   STRUCTURALLY (Aphyr MF-2: never grep >>>>>>> markers). pijul is used as a
   pure merge subroutine: ONE channel as trunk, no pijul branches/remotes/
   identity leak upward (Torvalds). Recording needs an ssh-agent identity
   supplied by the host. All verbs run in a repo cwd owned by the boundary. *\

(define after-tag { string --> string --> string } _ _ -> (error "host: after-tag (substring after marker)"))

(define pijul-parse-hash
  { string --> hash }                             \* "...\nHash: <h>\n..." -> h *\
  Out -> (chomp (after-tag "Hash: " Out)))

(define pijul-record
  { principal --> string --> hash }               \* author msg -> change-hash (working-copy diff) *\
  Author Msg -> (pijul-parse-hash (shell-run "pijul" ["record" "-a" "-m" Msg "--author" Author])))

(define pijul-apply
  { string --> hash --> boolean }                 \* channel hash -> ok (idempotent: present hash = no-op, I3) *\
  Channel H -> (do (shell-run "pijul" ["apply" "--channel" Channel H]) true))

(define pijul-fork
  { string --> string --> boolean }               \* from new -> ok (O(log n) Sanakirja CoW) *\
  From New -> (do (shell-run "pijul" ["fork" "--channel" From New]) true))

(define pijul-drop-channel
  { string --> boolean }                           \* drop a speculative probe channel *\
  Channel -> (do (shell-run "pijul" ["channel" "delete" Channel]) true))

(define pijul-state
  { string --> hash }                              \* channel -> order-independent state/version hash *\
  Channel -> (chomp (shell-run "pijul" ["log" "--channel" Channel "--state" "--limit" "1"])))

\* STRUCTURAL conflict query (Aphyr MF-2): the host backend inspects the pristine
   graph for any conflict class (order / zombie / name / overlap), NOT marker
   text. Errors by default; the backend provides the real graph query. *\
(define pijul-graph-conflicted? { string --> boolean } _ -> (error "host: pijul-graph-conflicted? (structural)"))
(define pijul-conflicts?
  { string --> boolean }                           \* channel -> any conflict in the pristine? *\
  Channel -> (pijul-graph-conflicted? Channel))

(define spec-channel { hash --> string } H -> (@s "mvfs-probe-" H))

\* Speculative admission (Aphyr MF-3 land-point re-check uses this too): fork the
   tip, apply the candidate, ask the graph if it conflicts, discard the fork.
   No mutation of the trunk. Order-independent => the answer is a true OCC test. *\
(define pijul-admits?
  { string --> hash --> boolean }                  \* tip-channel candidate -> clean? *\
  Tip Cand -> (let Spec (spec-channel Cand)
                (do (pijul-fork Tip Spec)
                 (do (pijul-apply Spec Cand)
                  (let Clean (not (pijul-conflicts? Spec))
                   (do (pijul-drop-channel Spec) Clean))))))

\* Idempotent land-apply: apply candidate to the trunk channel; return the
   resulting (order-independent) state hash. Re-apply of a present change is a
   no-op (merge-layer I3 backstop; idempotency-key in log.shen is authoritative). *\
(define pijul-land-state
  { string --> hash --> hash }                     \* trunk-channel candidate -> new-state-hash *\
  Trunk Cand -> (do (pijul-apply Trunk Cand) (pijul-state Trunk)))

\* Speculative would-be state WITHOUT mutating the trunk: fork the tip, apply the
   candidate, read the (order-independent) state, discard the fork. Used by pland!
   to record the post-apply Root in the landed-entry BEFORE the real apply. *\
(define pijul-probe-state
  { string --> hash --> hash }                     \* trunk-channel candidate -> would-be state *\
  Trunk Cand -> (let Spec (spec-channel Cand)
                  (do (pijul-fork Trunk Spec)
                   (do (pijul-apply Spec Cand)
                    (let S (pijul-state Spec)
                     (do (pijul-drop-channel Spec) S))))))

\* MF-1: are all of the candidate's pijul dependencies already in the trunk? If
   not, a real apply would silently pull un-seq'd changes into the trunk (I1/I2
   violation). Host-provided (parses `pijul change`'s dependency section). *\
(define pijul-deps-in-trunk?
  { hash --> string --> boolean }                  \* candidate trunk-channel -> all deps present? *\
  _ _ -> (error "host: pijul-deps-in-trunk?"))

\* ===== MF-4a: fenced blob store (off-pijul byte backup of change bodies) =====
   blob-put! mirrors a raw change body into <logpath>.blobs/<hash> BEFORE the log
   append, so the durable truth is the log + this store (not pijul's own store).
   blob-restore! is the recovery counterpart. *\
(define blob-put!
  { hash --> string --> boolean }                  \* change-hash logpath -> stored? *\
  _ _ -> (error "host: blob-put!"))
(define blob-restore!
  { hash --> string --> boolean }                  \* change-hash logpath -> restored/present? *\
  _ _ -> (error "host: blob-restore!"))

\* ===== T1 fault-injection seam — INERT in production (no-op unless CRASH_AT) ===== *\
(define crash-point
  { string --> boolean }                           \* named window -> true (host SIGKILLs iff CRASH_AT matches) *\
  _ -> true)

\* ===== MF-4b: recovery-before-writes gate ===== *\
(define recovered?
  { string --> boolean }                           \* logpath -> has recovery run this epoch? *\
  _ -> (error "host: recovered?"))
(define mark-recovered!
  { string --> boolean }                           \* logpath -> set the recovery token *\
  _ -> (error "host: mark-recovered!"))

\* ===== MF-4c: best-effort fsync of the pijul pristine after a land apply ===== *\
(define sync-pristine!
  { string --> boolean }                           \* logpath (placeholder; repo = cwd) -> synced *\
  _ -> true)                                        \* default no-op; host fsyncs the pristine *\

\* ===== MF-5: pin the pijul hash-algo/version in the log meta ===== *\
(define version-ok?
  { string --> boolean }                           \* logpath -> meta absent or == current pijul *\
  _ -> (error "host: version-ok?"))
(define version-pin!
  { string --> boolean }                           \* logpath -> record current pijul version if absent *\
  _ -> (error "host: version-pin!"))

\* ===== pluggable merge oracle (doc 34) — ORTHOGONAL to storage-backend =====
   git-merge:   git 3-way heuristic (merge-tree). Default; daemon-free; the kept
                fallback (Torvalds: keep git warm).
   pijul-merge: patch-theory associative merge; conflicts first-class &
                order-independent. For pijul, Ours = candidate change-hash and
                Theirs = trunk-tip channel, carried under the `hash` type. *\
(datatype merge-oracle
  ___________________________
  git-merge : merge-oracle;

  ___________________________
  pijul-merge : merge-oracle;)

(define oracle-admits?
  { merge-oracle --> hash --> hash --> hash --> boolean }   \* oracle base ours theirs -> clean? *\
  git-merge   Base Ours Theirs -> (merge-clean? (git-merge-tree Base Ours Theirs))
  pijul-merge _    Cand Tip     -> (pijul-admits? Tip Cand))

(define oracle-merged
  { merge-oracle --> hash --> hash --> hash --> hash }       \* oracle base ours theirs -> merged-id *\
  git-merge   Base Ours Theirs -> (merged-tree (git-merge-tree Base Ours Theirs))
  pijul-merge _    Cand Tip     -> (pijul-land-state Tip Cand))

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
