#!/usr/bin/env bash
# run.sh — Full browser E2E test using rodney (Chrome CDP CLI)
# Tests the complete flow: browser → WS → backend thread → WS response → DOM
set -euo pipefail

FRONTEND_URL="${FRONTEND_URL:-http://localhost:14403}"
BACKEND_HEALTH="${BACKEND_HEALTH:-http://localhost:14401/health}"
TIMEOUT="${TIMEOUT:-30}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-$(dirname "$0")/screenshots}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; cleanup; exit 1; }
info() { echo -e "${YELLOW}→ $1${NC}"; }

mkdir -p "$SCREENSHOT_DIR"

cleanup() {
  rodney stop 2>/dev/null || true
}
trap cleanup EXIT

# ── Wait for services ────────────────────────────────────────────

info "Waiting for backend health at $BACKEND_HEALTH ..."
for i in $(seq 1 "$TIMEOUT"); do
  if curl -sf "$BACKEND_HEALTH" &>/dev/null; then
    pass "Backend healthy"
    break
  fi
  [ "$i" -eq "$TIMEOUT" ] && fail "Backend not healthy after ${TIMEOUT}s"
  sleep 1
done

info "Waiting for frontend at $FRONTEND_URL ..."
for i in $(seq 1 "$TIMEOUT"); do
  if curl -sf "$FRONTEND_URL" &>/dev/null; then
    pass "Frontend ready"
    break
  fi
  [ "$i" -eq "$TIMEOUT" ] && fail "Frontend not ready after ${TIMEOUT}s"
  sleep 1
done

# ── Launch browser ───────────────────────────────────────────────

info "Starting Chrome via rodney..."
rodney start
sleep 2
pass "Chrome started"

# ── Navigate to app ──────────────────────────────────────────────

info "Opening $FRONTEND_URL ..."
rodney open "$FRONTEND_URL"
rodney waitload
sleep 2
rodney screenshot "$SCREENSHOT_DIR/01-loaded.png"
pass "Page loaded"

# ── Verify page rendered ─────────────────────────────────────────

info "Checking page rendered..."
rodney wait ".jarvis-input"
pass "Jarvis input bar found"
rodney screenshot "$SCREENSHOT_DIR/02-ready.png"

# ── Type message into Jarvis bar ─────────────────────────────────

info "Typing message into Jarvis bar..."
rodney focus ".jarvis-input"
rodney input ".jarvis-input" "hello from e2e test"
sleep 1
rodney screenshot "$SCREENSHOT_DIR/03-typed-message.png"
pass "Message typed"

# ── Click send button ────────────────────────────────────────────

info "Clicking send button..."
# The send button appears when input is non-empty
for i in $(seq 1 5); do
  if rodney exists ".jarvis-send-btn" 2>/dev/null; then
    break
  fi
  # Retry input — SolidJS may need the native setter approach
  rodney js "(function(){ var el=document.querySelector('.jarvis-input'); var s=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set; s.call(el,'hello from e2e test'); el.dispatchEvent(new Event('input',{bubbles:true})); return 'ok'; })()"
  sleep 1
done

if ! rodney exists ".jarvis-send-btn" 2>/dev/null; then
  rodney screenshot "$SCREENSHOT_DIR/03b-no-send-btn.png"
  fail "Send button not found (input signal may not have updated)"
fi

rodney click ".jarvis-send-btn"
sleep 1
rodney screenshot "$SCREENSHOT_DIR/04-sent.png"
pass "Message sent"

# ── Wait for Jarvis response ────────────────────────────────────

info "Waiting for Jarvis response (up to ${TIMEOUT}s)..."
RESPONSE_TEXT=""
for i in $(seq 1 "$TIMEOUT"); do
  # Check for a non-typing jarvis message
  RESPONSE_TEXT=$(rodney js "(function(){ var msgs=document.querySelectorAll('.jarvis-msg-jarvis .jarvis-msg-content'); var last=msgs[msgs.length-1]; if(last && !last.classList.contains('jarvis-typing')){ return last.textContent.trim(); } return ''; })()" 2>/dev/null || echo "")

  if [ -n "$RESPONSE_TEXT" ] && [ "$RESPONSE_TEXT" != "" ] && [ "$RESPONSE_TEXT" != "undefined" ]; then
    break
  fi
  sleep 1
done

rodney screenshot "$SCREENSHOT_DIR/05-response.png"

if [ -n "$RESPONSE_TEXT" ] && [ "$RESPONSE_TEXT" != "" ] && [ "$RESPONSE_TEXT" != "undefined" ]; then
  pass "Jarvis response received: $RESPONSE_TEXT"
else
  # Check if there's still a typing indicator
  TYPING=$(rodney js "document.querySelector('.jarvis-typing') ? 'still-typing' : 'not-typing'" 2>/dev/null || echo "unknown")
  rodney screenshot "$SCREENSHOT_DIR/05-timeout.png"
  if [ "$TYPING" = "still-typing" ]; then
    fail "Jarvis still typing after ${TIMEOUT}s — backend may not have sent response"
  else
    fail "No Jarvis response found in DOM after ${TIMEOUT}s"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo -e "${GREEN}  All E2E browser tests passed!${NC}"
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo ""
info "Screenshots saved to: $SCREENSHOT_DIR"
ls -la "$SCREENSHOT_DIR"
