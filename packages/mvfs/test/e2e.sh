#!/usr/bin/env bash
# mvfs P1 end-to-end: run the REAL FSM against REAL git + REAL pijul + a REAL
# fsync'd durable log, via the shen-lua host backend (src/host-lua.shen +
# host/host.lua). Proves three things that previously only typechecked:
#   (A) the pijul patch-theory merge oracle decides clean-vs-conflict STRUCTURALLY
#   (B) the fenced-log land path lands a change (real git commit + chained append)
#       and verify-chain accepts the log
#   (C) I7: a stale lease epoch is rejected by the fenced CAS append
#
# Requires: the bootstrapped shen-lua toolchain (SHEN), git, pijul on PATH, and
# an ssh-agent identity for pijul record. Run from packages/mvfs.
set -euo pipefail

MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?set SHEN to the shen-lua launcher (bin/shen)}"
PIJUL="${PIJUL:?set PIJUL to the pijul binary}"
export PIJUL_CONFIG_DIR="${PIJUL_CONFIG_DIR:?set PIJUL_CONFIG_DIR (with an identity)}"
export PATH="$(dirname "$PIJUL"):$PATH"   # so host.lua's `pijul`/`git` shell-out resolves
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/cli.shen"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
hashof(){ grep -oE 'Hash: [A-Z0-9]+' | awk '{print $2}'; }

# ---- real git repo (HEAD + a tree for the land commit) --------------------
git init -q .; git config user.email t@e.st; git config user.name tester
printf 'A\nB\nC\nD\nE\nF\nG\n' > a.txt; git add a.txt; git commit -q -m base
TREE=$(git rev-parse 'HEAD^{tree}')

# ---- real pijul repo (same dir): trunk + an advanced trunk + 2 candidates --
"$PIJUL" init >/dev/null 2>&1
"$PIJUL" add a.txt >/dev/null 2>&1
"$PIJUL" record -a -m base --author tester >/dev/null 2>&1
# advanced trunk: edits line 2 (B)
"$PIJUL" fork --channel main trunkadv >/dev/null 2>&1
"$PIJUL" channel switch trunkadv >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
printf 'A\nB-trunk\nC\nD\nE\nF\nG\n' > a.txt
"$PIJUL" record -a -m trunkedit --author tester >/dev/null 2>&1
# CONFLICT candidate (recorded against base): also edits line 2 (same line)
"$PIJUL" fork --channel main candC >/dev/null 2>&1
"$PIJUL" channel switch candC >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
printf 'A\nB-cand\nC\nD\nE\nF\nG\n' > a.txt
HC=$("$PIJUL" record -a -m candConflict --author tester 2>&1 | hashof)
# CLEAN candidate (recorded against base): edits line 6 (F) — well separated
"$PIJUL" fork --channel main candX >/dev/null 2>&1
"$PIJUL" channel switch candX >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
printf 'A\nB\nC\nD\nE\nF-clean\nG\n' > a.txt
HX=$("$PIJUL" record -a -m candClean --author tester 2>&1 | hashof)
"$PIJUL" channel switch main >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1

echo "TREE=$TREE  HC(conflict)=$HC  HX(clean)=$HX"

run_shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1; }
# host-lua.shen loads host/host.lua relative to cwd; symlink it in.
ln -s "$MVFS/src" src; ln -s "$MVFS/host" host

LOG="$WORK/landed.log"

echo "===== (A) pijul structural merge oracle ====="
echo -n "  clean candidate onto advanced trunk -> admits? "
run_shen -e "(mvfs.pijul-admits? \"trunkadv\" \"$HX\")" | tail -1
echo -n "  conflict candidate onto advanced trunk -> admits? "
run_shen -e "(mvfs.pijul-admits? \"trunkadv\" \"$HC\")" | tail -1

echo "===== (B) fenced-log land path (git-merge oracle, fast path) ====="
# Base=Tip=TREE => base fast-path; land writes a real git commit; append-fenced!
# chains + fsyncs the entry; verify-chain reads it back.
run_shen \
  -e "(mvfs.land! \"$WORK/lease\" (mvfs.base (mvfs.admit (mvfs.submit \"c1\" \"k1\" \"$TREE\" \"$TREE\" [] \"alice\") (mvfs.check \"alice\" [] 0)) \"$TREE\" mvfs.git-merge) \"$LOG\")" \
  -e "(mvfs.verify-chain \"$LOG\")" | tail -3
echo "  --- on-disk landed log (cells separated by US/RS shown as ^_/^^) ---"
cat -v "$LOG" | sed 's/\^\^/\n/g' | sed 's/^/    /'

echo "===== (C) I7: stale lease epoch rejected by fenced CAS ====="
# After (B) the head fence is 1. append-fenced! with a stale epoch 0 must be
# rejected (0 < head fence 1). Entry built as a datatype literal (constructors
# are list terms, not callable functions).
ENTRY="[mvfs.mk-entry 2 \"c2\" \"k2\" \"deadbeef\" \"parent\" \"root\" [] \"bob\" 0 0 0 0 0]"
echo -n "  append-fenced! at stale epoch 0 (head fence=1) -> "
run_shen -e "(mvfs.append-fenced! \"$LOG\" $ENTRY 0)" | tail -1
echo -n "  durable-cas-append! with WRONG expected-fence 0 (on-disk fence=1) -> "
run_shen -e "(mvfs.durable-cas-append! \"$LOG\" 0 5 \"x\")" | tail -1

echo "===== done ====="
