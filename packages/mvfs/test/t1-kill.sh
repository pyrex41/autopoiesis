#!/usr/bin/env bash
# mvfs P1 — T1-kill: REAL crash (SIGKILL) two-store atomicity, the fidelity
# upgrade over t1-crash.sh's deterministic step-stops. pland! has a fault seam
# (crash-point "after-append", inert unless CRASH_AT is set) BETWEEN the fsync'd
# fenced log append and the pristine apply. We run pland! with CRASH_AT set so the
# process is SIGKILL'd (kill -9, no cleanup, no flush) right in window W1, then a
# FRESH recovery process must restore the pristine from the log.
#
# Asserts:
#   the land process actually died by SIGKILL (exit 137);
#   the fenced log entry SURVIVED the kill (it was fsync'd before the crash);
#   the change is NOT in the pristine (the apply never ran — the crash window);
#   after recovery (forward re-apply), the change is present AND the trunk state
#   equals the entry's recorded Root (I4/I5/I8 hold across a real crash).
#
# Requires SHEN, PIJUL, PIJUL_CONFIG_DIR (ssh-agent identity), git+pijul on PATH.
set -euo pipefail
MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?}"; PIJUL="${PIJUL:?}"; export PIJUL_CONFIG_DIR="${PIJUL_CONFIG_DIR:?}"
export PATH="$(dirname "$PIJUL"):$PATH"
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/cli.shen"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; ln -s "$MVFS/src" src; ln -s "$MVFS/host" host
hashof(){ grep -oE 'Hash: [A-Z0-9]+' | awk '{print $2}'; }
shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1 | tail -1; }
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS: $1 ($2)"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got '$2' want '$3')"; FAIL=$((FAIL+1)); fi; }
in_trunk(){ "$PIJUL" log --channel main --hash-only 2>/dev/null | grep -qx "$1" && echo yes || echo no; }

"$PIJUL" init >/dev/null 2>&1
printf 'A\nB\nC\nD\nE\nF\nG\n' > a.txt; "$PIJUL" add a.txt >/dev/null 2>&1
"$PIJUL" record -a -m base --author tester >/dev/null 2>&1
BASE=$("$PIJUL" log --channel main --hash-only --limit 1 2>/dev/null)
LOG="$WORK/landed.log"; LEASE="$WORK/lease"; echo 1 > "$LEASE.epoch"
"$PIJUL" fork --channel main c1 >/dev/null 2>&1
"$PIJUL" channel switch c1 >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
printf 'A\nB1\nC\nD\nE\nF\nG\n' > a.txt
C1=$("$PIJUL" record -a -m c1 --author tester 2>&1 | hashof)
"$PIJUL" channel switch main >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
shen -e "(mvfs.recover! \"$LOG\" \"main\" \"$BASE\")" >/dev/null   # open the write gate
echo "BASE=$BASE C1=$C1"

echo "===== SIGKILL pland! at the post-append window (real kill -9) ====="
set +e
CRASH_AT=after-append "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen \
  -e "(mvfs.pland! \"$LEASE\" \"c1\" \"k1\" \"$C1\" \"alice\" 0 \"main\" \"$LOG\")" >/dev/null 2>&1
RC=$?
set -e
chk "land process died by SIGKILL" "$RC" "137"
chk "fenced log entry SURVIVED the kill" "$(shen -e "(length (mvfs.read-all \"$LOG\"))")" "1"
chk "log still verifies after crash" "$(shen -e "(mvfs.verify-chain \"$LOG\")")" "true"
chk "change NOT in pristine (apply never ran)" "$(in_trunk "$C1")" "no"

echo "===== fresh recovery process restores the pristine ====="
ROOT=$(shen -e "(mvfs.entry-root (head (mvfs.read-all \"$LOG\")))")
shen -e "(mvfs.recover! \"$LOG\" \"main\" \"$BASE\")" >/dev/null
chk "change present after recovery (I4)" "$(in_trunk "$C1")" "yes"
chk "trunk state == entry Root (I5/I8)" "$(shen -e "(mvfs.pijul-state \"main\")")" "$ROOT"

echo "===== MF-4a: the blob byte-backup is independent of pijul's change store ====="
chk "blob bytes match the live change body" "$(shen -e "(mvfs.blob-matches? \"$C1\" \"$LOG\")")" "true"
rm -rf .pijul/changes
chk "blob still present after rm -rf .pijul/changes" "$(shen -e "(mvfs.blob-has? \"$C1\" \"$LOG\")")" "true"
chk "live change body is gone (blob is the off-pijul backup)" "$(shen -e "(mvfs.blob-matches? \"$C1\" \"$LOG\")")" "false"

echo "===== T1-kill result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
