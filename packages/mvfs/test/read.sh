#!/usr/bin/env bash
# mvfs P1 — read tier (spec/04, spec/05): the BRAIN decision path end to end on a
# real git tree. Proves §5.2 resolve, §5.3 serve-token mint+verify, I8 as-of basis
# gate, and I9 authorize-then-resolve + single-use token — all in shen-lua.
# (The nginx zero-copy serve half lives in serve/; verify.lua is exercised under
#  luajit by test/read-edge.sh as a cross-language check.)
#
# Requires SHEN + git + luajit. No pijul/ssh-agent needed (read tier is git-CAS).
set -euo pipefail
MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?}"
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/read.shen src/cli.shen"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; ln -s "$MVFS/src" src; ln -s "$MVFS/host" host
shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1 | tail -1; }
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got '$2' want '$3')"; FAIL=$((FAIL+1)); fi; }
chk_pre(){ case "$2" in "$3"*) echo "  PASS: $1";PASS=$((PASS+1));; *) echo "  FAIL: $1 (got '$2' want prefix '$3')";FAIL=$((FAIL+1));; esac; }

# real git monorepo tree
git init -q .; git config user.email t@e.st; git config user.name t
mkdir -p a/b; printf 'BLOB-CONTENTS\n' > a/b/f.txt; printf 'top\n' > top.txt
git add .; git commit -q -m base
ROOT=$(git rev-parse 'HEAD^{tree}')
BLOB=$(git rev-parse "$ROOT:a/b/f.txt")
KEY="secret-serve-key"; PRINC="alice"; NONCE="nonce-$(date +%s)-1"; STORE="$WORK/nonces"
echo "ROOT=$ROOT BLOB=$BLOB"

echo "===== §5.2 resolve: path -> blob hash ====="
chk "resolve a/b/f.txt == git blob" "$(shen -e "(mvfs.resolve-path \"$ROOT\" \"a/b/f.txt\")")" "$BLOB"
chk "resolve missing path == \"\"" "$(shen -e "(mvfs.resolve-path \"$ROOT\" \"no/such\")")" ""

echo "===== read-decide: allowed read (basis ok) -> serve + token ====="
# read-decide Key Princ Root Path ReqSeq ReqAcl AppSeq AppAcl Allow Nonce
RES=$(shen -e "(mvfs.read-decide \"$KEY\" \"$PRINC\" \"$ROOT\" \"a/b/f.txt\" 1 0 5 0 true \"$NONCE\")")
chk_pre "decision is serve" "$RES" "[mvfs.serve"
SBLOB=$(echo "$RES" | sed 's/^\[mvfs.serve //; s/\]$//' | awk '{print $1}')
TOKEN=$(echo "$RES" | sed 's/^\[mvfs.serve //; s/\]$//' | awk '{print $2}')
chk "served blob == resolved blob" "$SBLOB" "$BLOB"
chk "token is non-empty" "$([ -n "$TOKEN" ] && echo yes || echo no)" "yes"

echo "===== §5.3 verify: fresh token accepted, then single-use (replay) rejected ====="
chk "verify fresh token (records nonce in STORE)" "$(shen -e "(mvfs.verify-token \"$KEY\" \"$TOKEN\" \"$BLOB\" \"$PRINC\" 0 \"$STORE\")")" "true"
chk "replay SAME token on SAME store rejected (I9 single-use)" "$(shen -e "(mvfs.verify-token \"$KEY\" \"$TOKEN\" \"$BLOB\" \"$PRINC\" 0 \"$STORE\")")" "false"

echo "===== §5.3 verify: tamper / wrong-hash / wrong-principal / stale-acl rejected ====="
TTAMP="${TOKEN%?}X"   # flip last char
chk "tampered token rejected" "$(shen -e "(mvfs.verify-token \"$KEY\" \"$TTAMP\" \"$BLOB\" \"$PRINC\" 0 \"$WORK/n4\")")" "false"
chk "wrong expected-hash rejected" "$(shen -e "(mvfs.verify-token \"$KEY\" \"$TOKEN\" \"deadbeef\" \"$PRINC\" 0 \"$WORK/n5\")")" "false"
chk "wrong principal rejected" "$(shen -e "(mvfs.verify-token \"$KEY\" \"$TOKEN\" \"$BLOB\" \"mallory\" 0 \"$WORK/n6\")")" "false"
chk "token minted at acl 0, required acl 1 rejected (stale policy)" "$(shen -e "(mvfs.verify-token \"$KEY\" \"$TOKEN\" \"$BLOB\" \"$PRINC\" 1 \"$WORK/n7\")")" "false"

echo "===== §5.3 verify: expired token rejected ====="
EXPTOK=$(shen -e "(mvfs.mint-token \"$KEY\" \"$BLOB\" \"$PRINC\" 0 1 \"nonce-exp\")")   # expiry=1 (1970)
chk "expired token rejected" "$(shen -e "(mvfs.verify-token \"$KEY\" \"$EXPTOK\" \"$BLOB\" \"$PRINC\" 0 \"$WORK/n8\")")" "false"

echo "===== I8 as-of basis gate + I9 authorize-then-resolve ====="
chk "basis-behind (req seq 5 > applied 1) -> deny" \
  "$(shen -e "(mvfs.read-decide \"$KEY\" \"$PRINC\" \"$ROOT\" \"a/b/f.txt\" 5 0 1 0 true \"n\")" | sed 's/ .*/]/')" "[mvfs.deny]"
chk "acl-deny (Allow=false) -> deny, no resolve" \
  "$(shen -e "(mvfs.read-decide \"$KEY\" \"$PRINC\" \"$ROOT\" \"a/b/f.txt\" 1 0 5 0 false \"n\")" | sed 's/ .*/]/')" "[mvfs.deny]"
chk "allowed but missing path -> deny not-found" \
  "$(shen -e "(mvfs.read-decide \"$KEY\" \"$PRINC\" \"$ROOT\" \"no/such\" 1 0 5 0 true \"n\")" | sed 's/ .*/]/')" "[mvfs.deny]"

echo "===== read result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
