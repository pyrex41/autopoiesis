#!/usr/bin/env bash
# mvfs P1 — policy lands (spec/03 §4): the ACL tied into the land kernel. A policy
# change lands through the SAME fenced path as code; acl-version is derived from the
# log (seq of the latest policy entry); effective-policy is the landed ruleset; a
# new policy land bumps acl-version and changes the decision (I6). Needs SHEN + git.
set -euo pipefail
MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?}"
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/read.shen src/acl.shen src/policy.shen src/vfs.shen src/cli.shen"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; ln -s "$MVFS/src" src; ln -s "$MVFS/host" host
git init -q .; git config user.email t@e.st; git config user.name t   # for blob CAS (git-hash-bytes)
shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1 | tail -1; }
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got '$2' want '$3')"; FAIL=$((FAIL+1)); fi; }
LOG="$WORK/landed.log"; LEASE="$WORK/lease"; echo 1 > "$LEASE.epoch"

echo "===== land policy v1 (alice may read src/) via the fenced kernel ====="
POL1='[["alice" "read" "src/" "allow"]]'
shen -e "(mvfs.policy-land! \"$LEASE\" \"p1\" $POL1 \"$LOG\")"
chk "acl-version == 1 (seq of the policy entry)" "$(shen -e "(mvfs.acl-version-of \"$LOG\")")" "1"
chk "effective-policy round-trips the ruleset"   "$(shen -e "(mvfs.effective-policy \"$LOG\")")" "[[alice read src/ allow]]"
chk "alice can read src/x under v1"              "$(shen -e "(mvfs.can-read-at? \"$LOG\" \"alice\" \"src/x\" [])")" "true"
chk "alice cannot read docs/x (not granted)"     "$(shen -e "(mvfs.can-read-at? \"$LOG\" \"alice\" \"docs/x\" [])")" "false"

echo "===== land policy v2 (revoke src/secret/) -> acl-version bumps, decision changes ====="
POL2='[["alice" "read" "src/" "allow"] ["alice" "read" "src/secret/" "deny"]]'
shen -e "(mvfs.policy-land! \"$LEASE\" \"p2\" $POL2 \"$LOG\")"
chk "acl-version bumped to 2"                     "$(shen -e "(mvfs.acl-version-of \"$LOG\")")" "2"
chk "alice still reads src/x under v2"            "$(shen -e "(mvfs.can-read-at? \"$LOG\" \"alice\" \"src/x\" [])")" "true"
chk "alice now DENIED src/secret/k under v2 (I6)" "$(shen -e "(mvfs.can-read-at? \"$LOG\" \"alice\" \"src/secret/k\" [])")" "false"

echo "===== policy entries chain in the fenced log alongside any code lands ====="
chk "log verifies (policy entries are chained)"  "$(shen -e "(mvfs.verify-chain \"$LOG\")")" "true"
chk "2 entries in the log"                        "$(shen -e "(length (mvfs.read-all \"$LOG\"))")" "2"

echo "===== policy result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
