#!/usr/bin/env bash
# mvfs P1 — read tier cross-language edge check. The shen-lua BRAIN mints a serve
# token; the OpenResty EDGE verifier (serve/verify.lua) verifies it under plain
# LuaJIT. Proves the wire contract (b64url(msg)."."HMAC-hex, msg=US-join(hash,
# principal,acl,expiry,nonce)) is identical across the two implementations, so a
# token minted by the brain is accepted by nginx unchanged — and tamper rejected.
#
# Requires SHEN + luajit + git.
set -euo pipefail
MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?}"; LUAJIT="${LUAJIT:?set LUAJIT to the luajit binary}"
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/read.shen src/cli.shen"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; ln -s "$MVFS/src" src; ln -s "$MVFS/host" host; ln -s "$MVFS/serve" serve
shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1 | tail -1; }
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got '$2' want '$3')"; FAIL=$((FAIL+1)); fi; }

KEY="secret-serve-key"; BLOB="55877046cbaf9558760f579997e1c5d00b64f289"; PRINC="alice"
EXP=$(( $(date +%s) + 300 )); NONCE="edge-nonce-1"
# brain mints the token
TOKEN=$(shen -e "(mvfs.mint-token \"$KEY\" \"$BLOB\" \"$PRINC\" 0 $EXP \"$NONCE\")")
echo "brain-minted token: ${TOKEN:0:40}..."

# edge (luajit + serve/verify.lua) verifies it
edge_verify(){ # token expected_hash principal store  (passed via env: luajit -e takes no positional script)
  MVFS_KEY="$KEY" TOK="$1" EH="$2" PR="$3" ST="$4" "$LUAJIT" -e '
    local V = dofile("serve/verify.lua")
    local ok = V.verify(os.getenv("MVFS_KEY"), os.getenv("TOK"), os.getenv("EH"), os.getenv("PR"), 0, os.getenv("ST"))
    io.write(ok and "true" or "false")
  '
}

chk "edge verifies brain-minted token"        "$(edge_verify "$TOKEN" "$BLOB" "$PRINC" "$WORK/e1")" "true"
chk "edge rejects replay (single-use, same store)" "$(edge_verify "$TOKEN" "$BLOB" "$PRINC" "$WORK/e1")" "false"
chk "edge rejects tampered token"             "$(edge_verify "${TOKEN%?}X" "$BLOB" "$PRINC" "$WORK/e2")" "false"
chk "edge rejects wrong hash"                 "$(edge_verify "$TOKEN" "deadbeef" "$PRINC" "$WORK/e3")" "false"
chk "edge rejects wrong principal"            "$(edge_verify "$TOKEN" "$BLOB" "mallory" "$WORK/e4")" "false"

echo "===== read-edge result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
