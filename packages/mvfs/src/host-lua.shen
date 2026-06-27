\* mvfs/host-lua.shen — the REAL shen-lua host backend (spec/00 §5.4).
   Loads host/host.lua, then REDEFINES the boundary/log/fsm host stubs (which
   error by default) with implementations that delegate to Lua via (lua.call ..).
   This turns the typechecked core into something that RUNS against real git +
   real pijul + a real fsync'd durable log. Loaded under tc- (runtime), after the
   core, from the packages/mvfs directory (so "host/host.lua" resolves).
   `lua.call` is declared external so the package doesn't prefix it to
   mvfs.lua.call. *\
(package mvfs [lua.call]

(lua.call "dofile" ["host/host.lua"])

\* ---- shell + string ops ---- *\
(define shell-run { string --> (list string) --> string }
  Cmd Args -> (lua.call "mvfs.shell_run" [Cmd Args]))
(define shell-run-stdin { string --> (list string) --> string --> string }
  Cmd Args In -> (lua.call "mvfs.shell_run_stdin" [Cmd Args In]))
(define string-length { string --> number } S -> (lua.call "mvfs.strlen" [S]))
(define substring { string --> number --> number --> string } S A B -> (lua.call "mvfs.substr" [S A B]))
(define after-tag { string --> string --> string } Tag S -> (lua.call "mvfs.after_tag" [Tag S]))
(define first-line { string --> string } S -> (lua.call "mvfs.first_line" [S]))
(define substr? { string --> string --> boolean } N H -> (lua.call "mvfs.has_substr" [H N]))

\* ---- checksums ---- *\
(define crc64 { string --> number } S -> (lua.call "mvfs.crc64" [S]))
(define xor64 { number --> number --> number } A B -> (lua.call "mvfs.xor64" [A B]))

\* ---- durable fenced log ---- *\
(define durable-head { string --> string } Path -> (lua.call "mvfs.log_head" [Path]))
(define durable-cas-append! { string --> number --> number --> string --> boolean }
  Path Exp New Framed -> (lua.call "mvfs.cas_append" [Path Exp New Framed]))

\* ---- log scan / parse (cell order from types.shen entry-cells + frame) ---- *\
(define s->n { string --> number } S -> (lua.call "mvfs.str_to_num" [S]))
(define split { string --> string --> (list string) } Sep S -> (lua.call "mvfs.split" [Sep S]))
(define cells->paths { string --> (list path) }
  "" -> []
  S  -> (split (n->string 30) S))
(define cells->entry
  { (list string) --> landed-entry }
  [C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12 C13]
  -> [mk-entry (s->n C1) C2 C3 C4 C5 C6 (cells->paths C7) C8 (s->n C9) (s->n C10) (s->n C12) (s->n C13) (s->n C11)])
(define unframe-all
  { (list string) --> (list landed-entry) }
  [] -> []
  [R | Rs] -> [(unframe R) | (unframe-all Rs)])
(define read-all { string --> (list landed-entry) }
  Path -> (unframe-all (lua.call "mvfs.log_records" [Path])))

\* ---- pijul structural conflict probe (Aphyr MF-2) ---- *\
(define pijul-graph-conflicted? { string --> boolean } Ch -> (lua.call "mvfs.pijul_conflicted" [Ch]))

\* ---- order-independent trunk state hash (extract the "State:" line) ---- *\
(define pijul-state { string --> hash } Ch -> (lua.call "mvfs.pijul_state" [Ch]))

\* ---- two-store recovery (Aphyr: log = truth, pristine = rebuildable cache) ----
   A pijul land records the change-hash in the entry's Commit field and the
   post-apply trunk state in Root (reusing the frozen schema; no change needed).
   recover! makes the pristine agree with the log:
     forward  — re-apply every logged change to the trunk (idempotent: a present
                change is a no-op). Fixes W1 (log fsync'd, pristine apply lost).
     backward — unrecord any trunk change with NO log entry (an orphan from a
                crash after pristine-apply-before-log, or a stale leader). Fixes
                W2. You can always drop an un-blessed pristine change; you can
                never invent a log entry for one. *\
(define pijul-deps-in-trunk? { hash --> string --> boolean }
  Cand Ch -> (lua.call "mvfs.pijul_deps_in_trunk" [Cand Ch]))

\* ---- MF-4a blob store + MF-4b recovery gate + T1 crash seam ---- *\
(define blob-put! { hash --> string --> boolean } H Log -> (lua.call "mvfs.blob_put" [H Log]))
(define blob-has? { hash --> string --> boolean } H Log -> (lua.call "mvfs.blob_has" [H Log]))
(define blob-matches? { hash --> string --> boolean } H Log -> (lua.call "mvfs.blob_matches" [H Log]))
(define blob-restore! { hash --> string --> boolean } H Log -> (lua.call "mvfs.blob_restore" [H Log]))
(define crash-point { string --> boolean } Name -> (lua.call "mvfs.crash_point" [Name]))
(define recovered? { string --> boolean } Log -> (lua.call "mvfs.is_recovered" [Log]))
(define mark-recovered! { string --> boolean } Log -> (lua.call "mvfs.mark_recovered" [Log]))
(define sync-pristine! { string --> boolean } _ -> (lua.call "mvfs.sync_pristine" []))

\* ---- read tier (spec/04, spec/05) ---- *\
(define resolve-path { hash --> path --> hash } Root Path -> (lua.call "mvfs.resolve_path" [Root Path]))
(define hmac-sha256 { string --> string --> string } K M -> (lua.call "mvfs.hmac_sha256" [K M]))
(define b64url { string --> string } S -> (lua.call "mvfs.b64url" [S]))
(define unb64url { string --> string } S -> (lua.call "mvfs.unb64url" [S]))
(define consttime-eq { string --> string --> boolean } A B -> (lua.call "mvfs.consttime_eq" [A B]))
(define now-secs { string --> number } _ -> (lua.call "mvfs.now_secs" []))
(define str->num { string --> number } S -> (lua.call "mvfs.str_to_num" [S]))
(define random-nonce { string --> string } _ -> (lua.call "mvfs.random_nonce" []))
(define nonce-seen? { string --> string --> boolean } Store N -> (lua.call "mvfs.nonce_seen" [Store N]))
(define nonce-record! { string --> string --> boolean } Store N -> (lua.call "mvfs.nonce_record" [Store N]))

\* ---- VFS mount client (spec/05) ---- *\
(define git-ls-tree-r { hash --> (list (list string)) } T -> (lua.call "mvfs.git_ls_tree_r" [T]))
(define write-blob! { hash --> string --> boolean } H Dest -> (lua.call "mvfs.write_blob" [H Dest]))
(define hash-file { string --> hash } P -> (lua.call "mvfs.hash_file" [P]))
(define file-size { string --> number } P -> (lua.call "mvfs.file_size" [P]))
(define file-mtime { string --> number } P -> (lua.call "mvfs.file_mtime" [P]))
(define save-dirstate! { (list (list string)) --> string --> boolean } Rows Path -> (lua.call "mvfs.dirstate_save" [Rows Path]))
(define load-dirstate { string --> (list (list string)) } Path -> (lua.call "mvfs.dirstate_load" [Path]))
(define version-ok? { string --> boolean } Log -> (lua.call "mvfs.version_ok" [Log]))
(define version-pin! { string --> boolean } Log -> (lua.call "mvfs.version_pin" [Log]))
(define pijul-unrecord { string --> hash --> boolean }
  Ch H -> (do (shell-run "pijul" ["unrecord" "--channel" Ch H]) true))
(define trunk-changes { string --> hash --> (list hash) }
  Ch Base -> (lua.call "mvfs.pijul_trunk_changes" [Ch Base]))
(define h-member? { hash --> (list hash) --> boolean }
  _ [] -> false
  X [Y | Ys] -> (if (= X Y) true (h-member? X Ys)))
(define entry-commits { (list landed-entry) --> (list hash) }
  [] -> []
  [E | Es] -> [(entry-commit E) | (entry-commits Es)])
(define restore-bodies { string --> (list landed-entry) --> boolean }   \* MF-4a restore *\
  _ [] -> true
  Log [E | Es] -> (do (blob-restore! (entry-commit E) Log) (restore-bodies Log Es)))
(define ensure-applied { string --> (list landed-entry) --> boolean }   \* forward *\
  _ [] -> true
  Ch [E | Es] -> (do (pijul-apply Ch (entry-commit E)) (ensure-applied Ch Es)))
(define sweep-orphans { string --> (list hash) --> (list hash) --> boolean }   \* backward *\
  _ _ [] -> true
  Ch Keep [H | Hs] -> (do (if (h-member? H Keep) true (pijul-unrecord Ch H))
                          (sweep-orphans Ch Keep Hs)))
(define recover!
  { string --> string --> hash --> boolean }   \* logpath trunk-channel base-change -> ok *\
  Logpath Ch Base
  -> (if (not (version-ok? Logpath))                 \* MF-5: refuse a log written by an incompatible pijul *\
         (error "MF-5: log meta pins a different pijul hash-algo/version than the running pijul")
         (do (version-pin! Logpath)                  \* MF-5: pin current version on a fresh log *\
          (let Entries (read-all Logpath)
            (do (restore-bodies Logpath Entries)     \* MF-4a: restore missing bodies from blobs *\
             (do (ensure-applied Ch Entries)         \* forward: re-apply logged changes (W1) *\
              (do (sweep-orphans Ch (entry-commits Entries) (trunk-changes Ch Base))  \* backward: orphans (W2) *\
               (mark-recovered! Logpath))))))))      \* MF-4b: open the write gate *\

\* ---- git tip + lease epoch ---- *\
(define tip-commit { hash --> hash } _ -> (chomp (shell-run "git" ["rev-parse" "HEAD"])))
(define acquire-epoch { lease --> number } L -> (lua.call "mvfs.acquire_epoch" [L]))
(define release-lease { lease --> number --> boolean } _ _ -> true)
)
