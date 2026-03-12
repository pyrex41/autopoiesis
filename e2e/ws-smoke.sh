#!/usr/bin/env bash
# ws-smoke.sh — Raw WebSocket smoke test (no browser needed)
# Tests: connect → start_chat → chat_prompt → chat_response
set -euo pipefail

WS_HOST="${WS_HOST:-localhost}"
WS_PORT="${WS_PORT:-14401}"
TIMEOUT="${TIMEOUT:-30}"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${YELLOW}→ $1${NC}"; }
pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# Wait for backend health
info "Waiting for backend at http://${WS_HOST}:${WS_PORT}/health ..."
for i in $(seq 1 "$TIMEOUT"); do
  if curl -sf "http://${WS_HOST}:${WS_PORT}/health" &>/dev/null; then
    pass "Backend healthy"
    break
  fi
  [ "$i" -eq "$TIMEOUT" ] && fail "Backend not healthy after ${TIMEOUT}s"
  sleep 1
done

# Run bun WS test
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WS_URL="ws://${WS_HOST}:${WS_PORT}/ws" TIMEOUT="$TIMEOUT" \
  bun run "$SCRIPT_DIR/ws-smoke.ts"
