#!/usr/bin/env bash
# mvfs P-D0 — T-D1: durable-layer fault test (spec/08 §10). Asserts the checkpoint
# fails CLOSED on corrupt/lost artifacts (C1/C2), the delta is deterministic
# (the CI bit-identity harness), and entry tampering is caught by the log's
# checksum chain. Runnable on git + plain dirs (no privileged mounts). Needs SHEN+git.
set -euo pipefail
MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?}"
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/read.shen src/acl.shen src/policy.shen src/vfs.shen src/dx.shen src/cli.shen"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; ln -s "$MVFS/src" src; ln -s "$MVFS/host" host
git init -q .; git config user.email t@e.st; git config user.name t
shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1 | tail -1; }
# returns "ok" iff the shen eval printed exactly true (else "fail-closed")
shen_ok(){ local o; o="$("$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1)"; case "$o" in *true*) echo ok;; *) echo fail-closed;; esac; }
objrm(){ rm -f ".git/objects/${1:0:2}/${1:2}"; }
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got '$2' want '$3')"; FAIL=$((FAIL+1)); fi; }

mkdir -p app; printf 'A1\n' > app/a.txt; printf 'B1\n' > app/b.txt
git add app; git commit -q -m base; BASE=$(git rev-parse 'HEAD^{tree}')
LEASE="$WORK/lease"; echo 1 > "$LEASE.epoch"

mk(){ # make a checkpoint in log $1: modify a, add c, delete b -> returns nothing
  rm -rf wt; shen -e "(mvfs.checkout! \"$BASE\" [\"\"] [] \"wt\")" >/dev/null
  printf 'A2\n' > wt/app/a.txt; printf 'C1\n' > wt/app/c.txt; rm wt/app/b.txt
  shen -e "(mvfs.checkpoint! \"$LEASE\" \"ck\" \"$BASE\" \"wt\" \"$1\")" >/dev/null
}

echo "===== determinism (CI bit-identity): same delta -> same hash ====="
mk "$WORK/log1"
D1=$(shen -e "(mvfs.store-delta! (mvfs.compute-delta \"$BASE\" \"wt\"))")
D2=$(shen -e "(mvfs.store-delta! (mvfs.compute-delta \"$BASE\" \"wt\"))")
chk "delta hash deterministic" "$D1" "$D2"

echo "===== baseline: an intact checkpoint restores ok ====="
chk "restore intact -> ok" "$(shen_ok -e "(mvfs.restore-checkpoint! (head (mvfs.read-all \"$WORK/log1\")) \"r1\")")" "ok"
chk "  r1/app/a.txt == A2" "$(cat r1/app/a.txt)" "A2"
chk "  r1/app/b.txt gone"  "$([ -e r1/app/b.txt ] && echo present || echo gone)" "gone"

echo "===== T-D1a: LOST delta blob -> restore fails closed (C2 verify-before-resume) ====="
DHASH=$(shen -e "(mvfs.entry-commit (head (mvfs.read-all \"$WORK/log1\")))")
# extract the set-content hash for app/a.txt from the delta before we nuke it
AHASH=$(git cat-file blob "$DHASH" | awk -F'\t' '$2=="app/a.txt"{print $3}')
objrm "$DHASH"
chk "restore with missing delta blob -> fail-closed" "$(shen_ok -e "(mvfs.restore-checkpoint! (head (mvfs.read-all \"$WORK/log1\")) \"r2\")")" "fail-closed"
chk "  r2 not materialized (verify ran before checkout)" "$([ -e r2/app/a.txt ] && echo present || echo absent)" "absent"

echo "===== T-D1b: LOST set-content blob -> restore fails closed ====="
mk "$WORK/log2"
AH2=$(git cat-file blob "$(shen -e "(mvfs.entry-commit (head (mvfs.read-all \"$WORK/log2\")))")" | awk -F'\t' '$2=="app/a.txt"{print $3}')
objrm "$AH2"
chk "restore with missing content blob -> fail-closed" "$(shen_ok -e "(mvfs.restore-checkpoint! (head (mvfs.read-all \"$WORK/log2\")) \"r3\")")" "fail-closed"
chk "  r3 NOT materialized (pre-flight refused before checkout; no partial tree)" "$([ -e r3 ] && echo present || echo absent)" "absent"

echo "===== T-D1c: entry tampering caught by the log checksum chain (I5) ====="
chk "intact log verifies" "$(shen -e "(mvfs.verify-chain \"$WORK/log2\")")" "true"
# flip a byte in the log record (corrupt the committed entry)
printf 'X' | dd of="$WORK/log2" bs=1 seek=3 count=1 conv=notrunc 2>/dev/null
chk "tampered log FAILS verify-chain" "$(shen -e "(mvfs.verify-chain \"$WORK/log2\")")" "false"

echo "===== T-D1 result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
