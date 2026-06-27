\* mvfs/host-lore.shen — the lore storage backend host (spec/00 §5.4, doc 33).
   OPTIONAL. Loaded only when the lore-be fragment backend is enabled; not part
   of the core CORE load (the trunk land path is git, daemon-free). These verbs
   shell out to the verified `lore` CLI (v0.8.4) and therefore require a running
   loreserver (zero-config local mode is fine: `loreserver` on :41337).

   Why a separate host: lore's WRITE path is working-tree-oriented
   (materialize -> dirty -> stage -> commit), unlike git's stdin plumbing, so
   the bytes->addr put cannot be a pure boundary primitive — it touches the
   working tree. cas-put-blob for lore-be deliberately errors and points here.

   Address shape: <64hex BLAKE3>-<32hex context>; whole objects use the zero
   context. Reads (cas-read-blob/cas-locate, lore-be) live in boundary.shen. *\
(package mvfs []

\* Create/register a repository on the (local) loreserver at the given lore URL,
   e.g. "lore://127.0.0.1:41337/myrepo". Requires a running loreserver. *\
(define lore-repo-create
  { string --> string }                           \* url -> server report *\
  Url -> (shell-run "lore" ["repository" "create" Url]))

\* Put bytes into the fragment store via the working tree: write the bytes to
   Path, mark it dirty, and stage it. Returns the staged-repository-state hash
   (the Merkle tree root). The per-file BLAKE3 address is obtained with
   lore-hash-path. (Writing the bytes to Path is the caller's materialization
   step — lore stages from the working tree, by design.) *\
(define lore-stage-path
  { path --> string }                             \* path -> staged-state root report *\
  Path -> (do (shell-run "lore" ["dirty" Path])
              (shell-run "lore" ["stage" Path])))

\* The BLAKE3 content address of a working-tree path (does not store). The CLI
   prints a multi-line "Path:/Size:/Hash:" report; callers parse the Hash line.
   Kept as the raw report here so parsing stays in one place (the read tier). *\
(define lore-hash-path
  { path --> string }                             \* path -> `file hash` report *\
  Path -> (shell-run "lore" ["file" "hash" Path]))

\* Commit the staged state as a new revision; returns the revision/signature
   report. The trunk-of-record is still git (doc 33) — this is the fragment
   tier's own durability for large/binary content. *\
(define lore-commit
  { string --> string }                           \* message -> revision report *\
  Msg -> (shell-run "lore" ["commit" Msg]))

\* Materialize a fragment address back to a destination path (sparse hydration).
   This is the VFS-adjacent verb: pull only the bytes you need, on demand. *\
(define lore-hydrate
  { hash --> path --> string }                    \* address dest -> report *\
  Addr Dest -> (shell-run "lore" ["file" "write" "--address" Addr "--output" Dest]))
)
