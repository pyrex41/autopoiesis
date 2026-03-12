#!/usr/bin/env bash
# helpers.sh — Shared utilities for E2E browser tests
# Source this from each test file: source "$(dirname "$0")/helpers.sh"

set -euo pipefail

FRONTEND_URL="${FRONTEND_URL:-http://localhost:14403}"
BACKEND_HEALTH="${BACKEND_HEALTH:-http://localhost:14401/health}"
TIMEOUT="${TIMEOUT:-30}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/screenshots}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

_PASS_COUNT=0
_FAIL_COUNT=0

pass() { echo -e "  ${GREEN}✓ $1${NC}"; _PASS_COUNT=$((_PASS_COUNT + 1)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; _FAIL_COUNT=$((_FAIL_COUNT + 1)); return 1; }
info() { echo -e "${YELLOW}→ $1${NC}"; }
section() { echo -e "\n${CYAN}── $1 ──${NC}"; }

test_summary() {
  local total=$((_PASS_COUNT + _FAIL_COUNT))
  if [ "$_FAIL_COUNT" -eq 0 ]; then
    echo -e "\n${GREEN}  $total/$total passed${NC}"
  else
    echo -e "\n${RED}  $_PASS_COUNT/$total passed, $_FAIL_COUNT failed${NC}"
    return 1
  fi
}

mkdir -p "$SCREENSHOT_DIR"

# ── SolidJS click helpers ────────────────────────────────────────

solidjs_click() {
  # Workaround for SolidJS event delegation ($$click)
  local selector="$1"
  rodney js "(function(){ var el=document.querySelector('$selector'); if(!el) return 'not-found'; var key=String.fromCharCode(36,36)+'click'; if(el[key]){el[key]({target:el,currentTarget:el,preventDefault:function(){},stopPropagation:function(){}}); return 'delegated';} el.click(); return 'native'; })()"
}

solidjs_click_nth() {
  # Click nth element matching selector (0-indexed)
  local selector="$1" n="$2"
  rodney js "(function(){ var els=document.querySelectorAll('$selector'); var el=els[$n]; if(!el) return 'not-found'; var key=String.fromCharCode(36,36)+'click'; if(el[key]){el[key]({target:el,currentTarget:el,preventDefault:function(){},stopPropagation:function(){}}); return 'delegated';} el.click(); return 'native'; })()"
}

solidjs_input() {
  # Set input value using native setter to trigger SolidJS signals
  local selector="$1" text="$2"
  rodney js "(function(){ var el=document.querySelector('$selector'); if(!el) return 'not-found'; var s=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set; s.call(el,'$text'); el.dispatchEvent(new Event('input',{bubbles:true})); return 'ok'; })()"
}

# ── Assertion helpers ────────────────────────────────────────────

wait_for() {
  # Wait up to N seconds for selector to exist
  local selector="$1" timeout="${2:-10}"
  for i in $(seq 1 "$timeout"); do
    rodney exists "$selector" 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

wait_for_text() {
  # Wait up to N seconds for selector to contain non-empty text
  local selector="$1" timeout="${2:-10}"
  for i in $(seq 1 "$timeout"); do
    local text
    text=$(rodney js "document.querySelector('$selector')?.textContent?.trim() || ''" 2>/dev/null || echo "")
    [ -n "$text" ] && [ "$text" != "" ] && [ "$text" != "undefined" ] && return 0
    sleep 1
  done
  return 1
}

assert_exists() {
  local selector="$1" label="$2"
  if rodney exists "$selector" 2>/dev/null; then
    pass "$label"
  else
    fail "$label (selector: $selector)"
  fi
}

assert_not_exists() {
  local selector="$1" label="$2"
  if rodney exists "$selector" 2>/dev/null; then
    fail "$label (selector: $selector should not exist)"
  else
    pass "$label"
  fi
}

assert_text_contains() {
  local selector="$1" expected="$2" label="$3"
  local text
  text=$(rodney js "document.querySelector('$selector')?.textContent || ''" 2>/dev/null || echo "")
  if echo "$text" | grep -qi "$expected"; then
    pass "$label"
  else
    fail "$label (expected '$expected', got: '$text')"
  fi
}

assert_count() {
  local selector="$1" expected="$2" label="$3"
  local count
  count=$(rodney js "document.querySelectorAll('$selector').length" 2>/dev/null || echo "0")
  if [ "$count" -eq "$expected" ] 2>/dev/null; then
    pass "$label"
  else
    fail "$label (expected $expected, got $count)"
  fi
}

assert_count_gte() {
  local selector="$1" expected="$2" label="$3"
  local count
  count=$(rodney js "document.querySelectorAll('$selector').length" 2>/dev/null || echo "0")
  if [ "$count" -ge "$expected" ] 2>/dev/null; then
    pass "$label ($count)"
  else
    fail "$label (expected >= $expected, got $count)"
  fi
}

js_val() {
  # Run JS expression and return trimmed result
  rodney js "$1" 2>/dev/null | tr -d '\n' || echo ""
}

screenshot() {
  local name="$1"
  rodney screenshot "$SCREENSHOT_DIR/$name" 2>/dev/null || true
}
