#!/usr/bin/env bash
# mvfs P1 — policy / ACL matcher (spec/03): longest-prefix-deny-wins, default-deny,
# group membership, root prefix; plus the §6a conformance differential (the fast
# matcher acl-decide MUST agree with the independent oracle acl-oracle on every
# query). Pure decision logic; needs only SHEN (string ops via the host).
set -euo pipefail
MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?}"
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/read.shen src/acl.shen src/cli.shen"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; ln -s "$MVFS/src" src; ln -s "$MVFS/host" host
shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1 | tail -1; }
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got '$2' want '$3')"; FAIL=$((FAIL+1)); fi; }

# can-read? P Path Policy Members
cr(){ shen -e "(mvfs.can-read? \"$1\" \"$2\" $3 $4)"; }

echo "===== §1.2 longest-prefix-deny-wins ====="
# broad allow on src/, specific deny on src/secret/
POL='[["alice" "read" "src/" "allow"] ["alice" "read" "src/secret/" "deny"]]'
chk "allow inherits down: src/main.lua"        "$(cr alice "src/main.lua" "$POL" "[]")" "true"
chk "specific deny wins: src/secret/key"       "$(cr alice "src/secret/key" "$POL" "[]")" "false"
chk "outside any grant: docs/x -> deny"        "$(cr alice "docs/x" "$POL" "[]")" "false"

echo "===== §1.2 deny-then-allow: more-specific allow overrides broad deny ====="
POL2='[["alice" "read" "src/" "deny"] ["alice" "read" "src/public/" "allow"]]'
chk "allow more specific: src/public/x"        "$(cr alice "src/public/x" "$POL2" "[]")" "true"
chk "broad deny holds: src/private/x"          "$(cr alice "src/private/x" "$POL2" "[]")" "false"

echo "===== §1.2 deny-wins on a TIE (same prefix, allow+deny) ====="
POL3='[["alice" "read" "src/" "allow"] ["alice" "read" "src/" "deny"]]'
chk "tie at same depth -> DENY"                "$(cr alice "src/x" "$POL3" "[]")" "false"

echo "===== §1.1 group membership (one-hop) ====="
POLG='[["teamx" "read" "src/teamx/" "allow"]]'
MEM='[["alice" "teamx"]]'
chk "member via group: alice in teamx"         "$(cr alice "src/teamx/f" "$POLG" "$MEM")" "true"
chk "non-member denied: bob not in teamx"      "$(cr bob "src/teamx/f" "$POLG" "[]")" "false"

echo "===== default-deny / fail-closed + root prefix ====="
chk "empty policy -> deny"                      "$(cr alice "anything" "[]" "[]")" "false"
chk "root prefix \"\" covers all"              "$(cr alice "deep/nested/x" '[["alice" "read" "" "allow"]]' "[]")" "true"

echo "===== §6a conformance: acl-decide ≡ acl-oracle over a query matrix ====="
# a richer policy spanning groups, nesting, ties, and a write rule
CP='[["alice" "read" "src/" "allow"] ["alice" "read" "src/secret/" "deny"] ["teamx" "read" "src/teamx/" "allow"] ["alice" "read" "src/teamx/" "deny"] ["alice" "write" "src/" "allow"] ["bob" "read" "" "allow"]]'
CM='[["alice" "teamx"]]'
QS='[["alice" "read" "src/a"] ["alice" "read" "src/secret/k"] ["alice" "read" "src/teamx/z"] ["bob" "read" "anything"] ["bob" "read" "src/secret/k"] ["alice" "write" "src/x"] ["alice" "admin" "src/x"] ["mallory" "read" "src/a"] ["alice" "read" ""] ["alice" "read" "src/secret"]]'
chk "matcher agrees with oracle on all queries" "$(shen -e "(mvfs.acl-conform? $CP $CM $QS)")" "true"

echo "===== acl result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
