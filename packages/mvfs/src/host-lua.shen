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

\* ---- git tip + lease epoch ---- *\
(define tip-commit { hash --> hash } _ -> (chomp (shell-run "git" ["rev-parse" "HEAD"])))
(define acquire-epoch { lease --> number } L -> (lua.call "mvfs.acquire_epoch" [L]))
(define release-lease { lease --> number --> boolean } _ _ -> true)
)
