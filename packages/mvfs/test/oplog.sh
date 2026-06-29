#!/usr/bin/env bash
# mvfs P-D2 (spec/08 §6) — exactly-once external effects. E2: intent->outcome journal
# on the fenced log (skip an effect whose outcome already landed; "pending" = the
# at-least-once re-attempt window). E1: out-of-guest egress capability — the lease
# holder mints a per-effect token at epoch E; the proxy admits it iff HMAC valid AND
# epoch >= current durable epoch, so a STALE leader's effects are rejected even though
# its guest can still call send(). Needs SHEN (HMAC via libcrypto). No git/pijul.
set -euo pipefail
MVFS="$(cd "$(dirname "$0")/.." && pwd)"
SHEN="${SHEN:?}"
CORE="src/scalars.shen src/boundary.shen src/checksum.shen src/types.shen src/log.shen src/fsm.shen src/read.shen src/acl.shen src/policy.shen src/vfs.shen src/dx.shen src/oplog.shen src/cli.shen"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; ln -s "$MVFS/src" src; ln -s "$MVFS/host" host
shen(){ "$SHEN" -q -e "(tc -)" $CORE src/host-lua.shen "$@" 2>&1 | tail -1; }
PASS=0; FAIL=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1 (got '$2' want '$3')"; FAIL=$((FAIL+1)); fi; }
LOG="$WORK/log"; LEASE="$WORK/lease"; echo 2 > "$LEASE.epoch"

echo "===== E2: intent -> outcome journal, exactly-once ====="
chk "fresh effect: status none"          "$(shen -e "(mvfs.effect-status \"$LOG\" \"pay1\")")" "none"
chk "fresh effect: should-emit? true"    "$(shen -e "(mvfs.should-emit? \"$LOG\" \"pay1\")")" "true"
shen -e "(mvfs.land-intent! \"$LEASE\" \"pay1\" \"charge-100\" \"$LOG\")" >/dev/null
chk "after intent: status pending"       "$(shen -e "(mvfs.effect-status \"$LOG\" \"pay1\")")" "pending"
chk "after intent: still should-emit? (effect not confirmed)" "$(shen -e "(mvfs.should-emit? \"$LOG\" \"pay1\")")" "true"
# ... external effect performed ...
shen -e "(mvfs.land-outcome! \"$LEASE\" \"pay1\" \"receipt-abc\" \"$LOG\")" >/dev/null
chk "after outcome: status done"         "$(shen -e "(mvfs.effect-status \"$LOG\" \"pay1\")")" "done"
chk "after outcome: should-emit? FALSE (exactly-once)" "$(shen -e "(mvfs.should-emit? \"$LOG\" \"pay1\")")" "false"
chk "replay returns recorded outcome"    "$(shen -e "(mvfs.outcome-of \"$LOG\" \"pay1\")")" "receipt-abc"

echo "===== E2: crash after intent, before outcome -> pending (re-attempt window) ====="
shen -e "(mvfs.land-intent! \"$LEASE\" \"pay2\" \"charge-200\" \"$LOG\")" >/dev/null
chk "pay2 status pending (system KNOWS it may have fired)" "$(shen -e "(mvfs.effect-status \"$LOG\" \"pay2\")")" "pending"
chk "pay2 should-emit? true (external endpoint must dedupe)" "$(shen -e "(mvfs.should-emit? \"$LOG\" \"pay2\")")" "true"

echo "===== E1: out-of-guest egress capability (effect ownership = lease epoch) ====="
chk "current durable epoch == 2 (head fence)" "$(shen -e "(mvfs.current-epoch \"$LOG\")")" "2"
SK="egress-secret"
# leader B (current, epoch 2) mints an egress token for effect eff1
TOKB=$(shen -e "(mvfs.with-leadership \"$LEASE\" (/. W (mvfs.mint-egress \"$SK\" W \"eff1\" \"charge-100\")))")
chk "current leader's token admitted by the proxy" "$(shen -e "(mvfs.egress-ok? \"$SK\" \"$TOKB\" \"eff1\" \"charge-100\" \"$LOG\")")" "true"
chk "tampered token rejected" "$(shen -e "(mvfs.egress-ok? \"$SK\" \"${TOKB%?}X\" \"eff1\" \"charge-100\" \"$LOG\")")" "false"
chk "wrong effect rejected"   "$(shen -e "(mvfs.egress-ok? \"$SK\" \"$TOKB\" \"eff1\" \"charge-999\" \"$LOG\")")" "false"
# STALE leader A (epoch 1, partitioned) mints a token at its old epoch
echo 1 > "$LEASE.epoch"
TOKA=$(shen -e "(mvfs.with-leadership \"$LEASE\" (/. W (mvfs.mint-egress \"$SK\" W \"eff1\" \"charge-100\")))")
echo 2 > "$LEASE.epoch"
chk "STALE leader's token REJECTED (epoch 1 < current 2) — effect ownership enforced" \
  "$(shen -e "(mvfs.egress-ok? \"$SK\" \"$TOKA\" \"eff1\" \"charge-100\" \"$LOG\")")" "false"

echo "===== oplog result: $PASS passed, $FAIL failed ====="
[ "$FAIL" -eq 0 ]
