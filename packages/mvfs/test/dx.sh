#!/usr/bin/env bash
# mvfs P-D0 (spec/08) — durable execution, the MOAT, verifiably (no privileged mounts):
# the overlay-delta serializer + fenced checkpoint + FAITHFUL deletion/restore.
# Base rootfs = a git tree; working tree = a plain dir; checkpoint = land(delta);
# restore = base + delta with deletions honored. (composefs/Firecracker = reuse,
# deployment-only, not exercised here.) Requires SHEN + git.
set -euo pipefail
MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?}"
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/read.shen src/acl.shen src/policy.shen src/vfs.shen src/dx.shen src/cli.shen"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; ln -s "$MVFS/src" src; ln -s "$MVFS/host" host
git init -q .; git config user.email t@e.st; git config user.name t
shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1 | tail -1; }
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got '$2' want '$3')"; FAIL=$((FAIL+1)); fi; }
gone(){ [ -e "$1" ] && echo present || echo gone; }

# base rootfs revision (a trunk tree)
mkdir -p app lib
printf 'A1\n' > app/a.txt; printf 'B1\n' > app/b.txt; printf 'C1\n' > lib/c.txt
git add app lib; git commit -q -m base
BASE=$(git rev-parse 'HEAD^{tree}')
LOG="$WORK/landed.log"; LEASE="$WORK/lease"; echo 1 > "$LEASE.epoch"
echo "BASE=$BASE"

echo "===== materialize base into the live working tree (wt) ====="
shen -e "(mvfs.checkout! \"$BASE\" [\"\"] [] \"wt\")" >/dev/null
chk "wt/app/a.txt == A1"  "$(cat wt/app/a.txt)" "A1"
chk "wt/app/b.txt == B1"  "$(cat wt/app/b.txt)" "B1"
chk "wt/lib/c.txt == C1"  "$(cat wt/lib/c.txt)" "C1"

echo "===== mutate the working tree: modify a, add d, DELETE b ====="
printf 'A2\n' > wt/app/a.txt          # modify
printf 'D1\n' > wt/app/d.txt          # add
rm wt/app/b.txt                       # delete (the faithful-whiteout case)

echo "===== checkpoint! = fenced land of the overlay delta ====="
shen -e "(mvfs.checkpoint! \"$LEASE\" \"ck1\" \"$BASE\" \"wt\" \"$LOG\")"
chk "log has 1 checkpoint entry" "$(shen -e "(length (mvfs.read-all \"$LOG\"))")" "1"
chk "log verifies (checkpoint chained)" "$(shen -e "(mvfs.verify-chain \"$LOG\")")" "true"
chk "C2 verify-checkpoint? true" "$(shen -e "(mvfs.verify-checkpoint? (head (mvfs.read-all \"$LOG\")))")" "true"
echo "  --- delta blob contents (set/del nodes) ---"
DHASH=$(shen -e "(mvfs.entry-commit (head (mvfs.read-all \"$LOG\")))")
git cat-file blob "$DHASH" | sed 's/\t/ /g' | sed 's/^/    /'

echo "===== determinism: serialize the same delta twice -> identical hash ====="
H1=$(shen -e "(mvfs.store-delta! (mvfs.compute-delta \"$BASE\" \"wt\"))")
H2=$(shen -e "(mvfs.store-delta! (mvfs.compute-delta \"$BASE\" \"wt\"))")
chk "delta hash is deterministic" "$H1" "$H2"
chk "delta hash == entry Commit"  "$H1" "$DHASH"

echo "===== restore into a FRESH tree: base + delta, deletions honored ====="
shen -e "(mvfs.restore-checkpoint! (head (mvfs.read-all \"$LOG\")) \"restored\")" >/dev/null
chk "restored/app/a.txt == A2 (modified)"  "$(cat restored/app/a.txt)" "A2"
chk "restored/app/d.txt == D1 (added)"     "$(cat restored/app/d.txt)" "D1"
chk "restored/lib/c.txt == C1 (unchanged)" "$(cat restored/lib/c.txt)" "C1"
chk "restored/app/b.txt is GONE (deletion faithful — the Torvalds bug)" "$(gone restored/app/b.txt)" "gone"

echo "===== dx result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
