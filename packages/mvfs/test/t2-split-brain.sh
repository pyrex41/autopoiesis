#!/usr/bin/env bash
# mvfs P1 — T2: fenced split-brain + idempotency, driven through pland! (the
# unified two-phase land: I3 key dedup -> MF-1 deps -> MF-3 land-point re-check ->
# fenced log append [linearization point] -> pristine apply).
#
# Asserts:
#   I7  a STALE leader (old lease epoch) is rejected by the fence CAS, and —
#       because pland! is LOG-FIRST — its land never reaches the pristine apply,
#       so it leaves NO orphan (stronger than "swept later"): the rejection is
#       clean. Trunk + log are untouched by the stale leader.
#   I3  a retried land (same idempotency-key) is a no-op: pland! returns the prior
#       landed, appends NO new entry, applies nothing.
#   live forward progress still works: the fenced leader lands a second change.
#   MF-3 a candidate that conflicts with the committed tip is rejected at land.
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
nentries(){ shen -e "(length (mvfs.read-all \"$LOG\"))"; }
record_cand(){ # $1=channel-name $2=line-edit-content -> echoes change hash
  "$PIJUL" fork --channel main "$1" >/dev/null 2>&1
  "$PIJUL" channel switch "$1" >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
  printf "$2" > a.txt
  "$PIJUL" record -a -m "$1" --author tester 2>&1 | hashof
  "$PIJUL" channel switch main >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
}

# ---- repo: pijul trunk "main" + base ----
"$PIJUL" init >/dev/null 2>&1
printf 'A\nB\nC\nD\nE\nF\nG\n' > a.txt; "$PIJUL" add a.txt >/dev/null 2>&1
"$PIJUL" record -a -m base --author tester >/dev/null 2>&1
LOG="$WORK/landed.log"; LEASE="$WORK/lease"
C1=$(record_cand c1 'A\nB1\nC\nD\nE\nF\nG\n')        # edits line 2
C2=$(record_cand c2 'A\nB\nC\nD\nE\nF2\nG\n')        # edits line 6 (independent of C1)
CX=$(record_cand cx 'A\nB\nC\nD\nE\nFx\nG\n')        # edits line 6 (CONFLICTS with C2)
echo "C1=$C1  C2=$C2  CX=$CX"

echo "===== leader B (epoch 2) lands C1 via pland! ====="
echo 2 > "$LEASE.epoch"
shen -e "(mvfs.pland! \"$LEASE\" \"c1\" \"k1\" \"$C1\" \"alice\" 0 \"main\" \"$LOG\")"
chk "C1 in trunk pristine" "$(in_trunk "$C1")" "yes"
chk "log has 1 entry" "$(nentries)" "1"
S1=$(shen -e "(mvfs.pijul-state \"main\")"); echo "  trunk state S1=$S1"
[ -n "$S1" ] || { echo "FATAL: empty state"; exit 2; }

echo "===== I7: STALE leader A (epoch 1) tries to land C2 ====="
echo 1 > "$LEASE.epoch"
shen -e "(mvfs.pland! \"$LEASE\" \"c2\" \"k2\" \"$C2\" \"bob\" 0 \"main\" \"$LOG\")" >/dev/null || true
chk "stale leader's C2 NOT in pristine (log-first, no orphan)" "$(in_trunk "$C2")" "no"
chk "log still 1 entry (stale append rejected)" "$(nentries)" "1"
chk "trunk state unchanged" "$(shen -e "(mvfs.pijul-state \"main\")")" "$S1"

echo "===== I3: leader B retries landing C1 (same key k1) ====="
echo 2 > "$LEASE.epoch"
shen -e "(mvfs.pland! \"$LEASE\" \"c1\" \"k1\" \"$C1\" \"alice\" 0 \"main\" \"$LOG\")"
chk "retry appends NO new entry (still 1)" "$(nentries)" "1"
chk "trunk state unchanged by retry" "$(shen -e "(mvfs.pijul-state \"main\")")" "$S1"

echo "===== live: fenced leader B (epoch 2) lands C2 for real ====="
shen -e "(mvfs.pland! \"$LEASE\" \"c2\" \"k2\" \"$C2\" \"bob\" 0 \"main\" \"$LOG\")"
chk "C2 now in pristine" "$(in_trunk "$C2")" "yes"
chk "log has 2 entries" "$(nentries)" "2"
S2=$(shen -e "(mvfs.pijul-state \"main\")"); echo "  trunk state S2=$S2"

echo "===== MF-3: leader B tries CX, which conflicts with the committed tip (C2) ====="
shen -e "(mvfs.pland! \"$LEASE\" \"cx\" \"kx\" \"$CX\" \"bob\" 0 \"main\" \"$LOG\")" >/dev/null || true
chk "conflicting CX NOT in pristine (MF-3 reject)" "$(in_trunk "$CX")" "no"
chk "log still 2 entries" "$(nentries)" "2"
chk "trunk state unchanged (still S2)" "$(shen -e "(mvfs.pijul-state \"main\")")" "$S2"

echo "===== T2 result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
