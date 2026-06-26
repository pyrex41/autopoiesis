\* mvfs/cli.shen — P0 thin entry points (spec/06 CLI surface; clone + log).
   Full surface (status/diff/submit/stack/restack/land/resolve/sparse/acl)
   arrives in P1+. *\
(package mvfs.cli [clone log-cmd main]

(import mvfs.boundary mvfs.log mvfs.types)

\* clone: materialize a working copy at HEAD (P0 = git checkout-first; the
   virtualized mount is spec/05 P6). *\
(define clone
  { string --> string --> string }       \* remote, dest -> dest *\
  Remote Dest -> (do (shell-run "git" ["clone" Remote Dest]) Dest))

\* log: print the landed-log seq/commit chain (verifying the checksum chain). *\
(define log-cmd
  { string --> boolean }                 \* logpath -> chain-ok? *\
  Logpath -> (verify-chain Logpath))

(define main
  { (list string) --> number }
  ["clone" Remote Dest] -> (do (clone Remote Dest) 0)
  ["log" Logpath]       -> (if (log-cmd Logpath) 0 1)
  _ -> (do (output "usage: mvfs (clone <remote> <dest> | log <logpath>)~%") 1))
)
