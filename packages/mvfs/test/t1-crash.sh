#!/usr/bin/env bash
# mvfs P1 — T1: two-store crash-atomicity (Aphyr's ship-decider).
# A land touches TWO durable stores: the fenced landed-log (TRUTH) and the pijul
# pristine (a rebuildable CACHE). They must crash-agree. We inject a crash at
# each window by running the land as discrete steps and stopping mid-sequence,
# then run recovery and assert the invariants.
#
# Land order (log-first, Aphyr): (A) speculative admit -> (B) append entry to log
# [fence CAS + fsync] = linearization point -> (C) apply change to pristine -> ack.
#
#   W1  crash after (B) before (C): log says landed, pristine missing the change.
#       Recovery FORWARD re-applies (idempotent). Assert: change present, state
#       matches the entry's recorded Root. (I4: no lost acked/logged land.)
#   W2  stale leader applies to the pristine with NO log entry (orphan).
#       Recovery BACKWARD sweep unrecords it. Assert: orphan gone, trunk state
#       back to the log's last Root. (I1/I2: no un-logged content in the trunk.)
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

# ---- repo: git (for nothing here) + pijul trunk "main" with a base change ----
"$PIJUL" init >/dev/null 2>&1
printf 'A\nB\nC\nD\nE\nF\nG\n' > a.txt; "$PIJUL" add a.txt >/dev/null 2>&1
"$PIJUL" record -a -m base --author tester >/dev/null 2>&1
BASE=$("$PIJUL" log --channel main --hash-only --limit 1 2>/dev/null)
LOG="$WORK/landed.log"

# candidate C1 (recorded against base; edits line 2). Its would-be trunk state =
# apply onto a throwaway probe forked from main.
"$PIJUL" fork --channel main c1 >/dev/null 2>&1
"$PIJUL" channel switch c1 >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
printf 'A\nB1\nC\nD\nE\nF\nG\n' > a.txt
C1=$("$PIJUL" record -a -m c1 --author tester 2>&1 | hashof)
"$PIJUL" channel switch main >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
"$PIJUL" fork --channel main probe1 >/dev/null 2>&1
"$PIJUL" apply --channel probe1 "$C1" >/dev/null 2>&1
STATE1=$("$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen -e "(mvfs.pijul-state \"probe1\")" 2>&1 | tail -1)
"$PIJUL" channel delete probe1 >/dev/null 2>&1
echo "BASE=$BASE  C1=$C1  STATE1=$STATE1"
[ -n "$STATE1" ] || { echo "FATAL: empty STATE1 (pijul-state extraction broken) — aborting to avoid false passes"; exit 2; }

ENTRY1="[mvfs.mk-entry 1 \"c1\" \"k1\" \"$C1\" \"$BASE\" \"$STATE1\" [] \"alice\" 0 1 0 0 0]"

echo "===== W1: crash after log-append, before pristine-apply ====="
# (B) append entry to the fenced log at epoch 1 — and then CRASH (do NOT apply).
shen -e "(mvfs.append-fenced! \"$LOG\" $ENTRY1 1)" >/dev/null
echo "  crash injected (pristine never got C1)"
chk "C1 in trunk pristine before recovery" "$(in_trunk "$C1")" "no"
chk "log verifies (truth survived)" "$(shen -e "(mvfs.verify-chain \"$LOG\")")" "true"
# recovery: forward re-apply from the log.
shen -e "(mvfs.recover! \"$LOG\" \"main\" \"$BASE\")" >/dev/null
chk "C1 in trunk pristine after recovery" "$(in_trunk "$C1")" "yes"
chk "trunk state == entry Root (I5/I8)" "$(shen -e "(mvfs.pijul-state \"main\")")" "$STATE1"

echo "===== W2: stale leader applies an orphan to the pristine, no log entry ====="
# orphan candidate C2 (edits line 6), applied straight to main WITHOUT logging.
"$PIJUL" fork --channel main c2 >/dev/null 2>&1
"$PIJUL" channel switch c2 >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
printf 'A\nB1\nC\nD\nE\nF2\nG\n' > a.txt
C2=$("$PIJUL" record -a -m c2 --author tester 2>&1 | hashof)
"$PIJUL" channel switch main >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
"$PIJUL" apply --channel main "$C2" >/dev/null 2>&1
echo "  orphan C2=$C2 applied to pristine, NOT in the log"
chk "orphan C2 in pristine before recovery" "$(in_trunk "$C2")" "yes"
# recovery: backward orphan sweep (C2 has no log entry).
shen -e "(mvfs.recover! \"$LOG\" \"main\" \"$BASE\")" >/dev/null
chk "orphan C2 swept after recovery (I1/I2)" "$(in_trunk "$C2")" "no"
chk "C1 still present (logged land kept)" "$(in_trunk "$C1")" "yes"
chk "trunk state back to log's last Root" "$(shen -e "(mvfs.pijul-state \"main\")")" "$STATE1"

echo "===== T1 result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
