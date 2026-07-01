#!/usr/bin/env bash
# mvfs P1 — T3: TOCTOU race (admission vs land) + MF-5 version pinning.
#
# A candidate can be conflict-free at ADMISSION time (tip = T) and conflicting at
# LAND time (tip = T+1) because a competing change landed in between. pland!'s
# MF-3 land-point re-check (against the COMMITTED tip, inside the lease) must catch
# this — admission-time freedom is NOT stable across tip advance.
#
# Asserts:
#   clean@T   — pijul-admits? CA against the base tip is true;
#   a competing change CB (same line) lands, advancing the tip;
#   conflict@T+1 — pijul-admits? CA against the advanced tip is now false;
#   pland! CA is REJECTED at the land point (MF-3): CA not in pristine, log
#   unchanged — the race did NOT land a conflict.
#   MF-5 — the log meta pins the producing pijul version; a log whose meta names
#   a different version is REFUSED by recover! (the state-hash audit chain is
#   version-pinned).
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
record_cand(){ "$PIJUL" fork --channel main "$1" >/dev/null 2>&1
  "$PIJUL" channel switch "$1" >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1
  printf "$2" > a.txt; "$PIJUL" record -a -m "$1" --author tester 2>&1 | hashof
  "$PIJUL" channel switch main >/dev/null 2>&1; "$PIJUL" reset >/dev/null 2>&1; }

"$PIJUL" init >/dev/null 2>&1
printf 'A\nB\nC\nD\nE\n' > a.txt; "$PIJUL" add a.txt >/dev/null 2>&1
"$PIJUL" record -a -m base --author tester >/dev/null 2>&1
BASE=$("$PIJUL" log --channel main --hash-only --limit 1 2>/dev/null)
LOG="$WORK/landed.log"; LEASE="$WORK/lease"; echo 2 > "$LEASE.epoch"
CA=$(record_cand ca 'A\nBa\nC\nD\nE\n')   # edits line 2
CB=$(record_cand cb 'A\nBb\nC\nD\nE\n')   # edits line 2 (same line -> conflicts with CA)
shen -e "(mvfs.recover! \"$LOG\" \"main\" \"$BASE\")" >/dev/null    # gate open + version pinned
echo "BASE=$BASE CA=$CA CB=$CB"

echo "===== clean@T: CA is admissible against the base tip ====="
chk "admits? CA @ tip=base" "$(shen -e "(mvfs.pijul-admits? \"main\" \"$CA\")")" "true"

echo "===== competing land: CB lands, advancing the tip (T -> T+1) ====="
shen -e "(mvfs.pland! \"$LEASE\" \"cb\" \"kb\" \"$CB\" \"bob\" 0 \"main\" \"$LOG\")" >/dev/null
chk "CB landed" "$(in_trunk "$CB")" "yes"
chk "log has 1 entry" "$(nentries)" "1"

echo "===== conflict@T+1: CA now conflicts with the advanced tip ====="
chk "admits? CA @ tip=base+CB now false" "$(shen -e "(mvfs.pijul-admits? \"main\" \"$CA\")")" "false"

echo "===== pland! CA is rejected at the land point (MF-3), race did not land ====="
shen -e "(mvfs.pland! \"$LEASE\" \"ca\" \"ka\" \"$CA\" \"alice\" 0 \"main\" \"$LOG\")" >/dev/null 2>&1 || true
chk "CA NOT in pristine" "$(in_trunk "$CA")" "no"
chk "log still 1 entry (no conflict landed)" "$(nentries)" "1"

echo "===== MF-5: a log whose meta names a different pijul version is refused ====="
chk "log meta records the producing pijul version" "$(grep -c '^pijul ' "$LOG.meta" 2>/dev/null || echo 0)" "1"
printf 'pijul 9.9.9-incompatible' > "$LOG.meta"
OUT=$("$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen -e "(mvfs.recover! \"$LOG\" \"main\" \"$BASE\")" 2>&1 || true)
echo "$OUT" | grep -q "MF-5" && R=refused || R=accepted
chk "recover! refuses the incompatible-version log" "$R" "refused"

echo "===== T3 result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
