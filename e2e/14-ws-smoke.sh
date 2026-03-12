#!/usr/bin/env bash
# 14-ws-smoke.sh — WebSocket smoke test (wraps existing ws-smoke.ts)
source "$(dirname "$0")/helpers.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_HOST="${WS_HOST:-localhost}"
WS_PORT="${WS_PORT:-14401}"

# Check if ws-smoke.ts exists
if [ ! -f "$SCRIPT_DIR/ws-smoke.ts" ]; then
  info "ws-smoke.ts not found, skipping"
  pass "WS smoke test skipped (no ws-smoke.ts)"
  test_summary
  exit 0
fi

# Check bun availability
if ! command -v bun &>/dev/null; then
  info "bun not found, skipping WS smoke"
  pass "WS smoke test skipped (bun not installed)"
  test_summary
  exit 0
fi

# Run the existing WS smoke test
info "Running WebSocket smoke test via bun..."
WS_URL="ws://${WS_HOST}:${WS_PORT}/ws" TIMEOUT="$TIMEOUT" \
  bun run "$SCRIPT_DIR/ws-smoke.ts"

WS_EXIT=$?
if [ $WS_EXIT -eq 0 ]; then
  pass "WebSocket smoke test passed"
else
  fail "WebSocket smoke test failed (exit code: $WS_EXIT)"
fi

test_summary
