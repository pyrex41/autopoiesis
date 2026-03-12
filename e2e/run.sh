#!/usr/bin/env bash
# run.sh — E2E test orchestrator
# Runs all test files in dependency order via rodney (Chrome CDP CLI)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

TESTS=(
  01-health
  02-dashboard
  03-agent-lifecycle
  04-agent-detail
  05-views
  06-dag-view
  07-timeline
  08-tasks
  09-conductor
  10-teams
  11-jarvis
  12-command-palette
  13-activity-cost
  14-ws-smoke
)

# Allow running a subset: ./run.sh 01-health 02-dashboard
if [ $# -gt 0 ]; then
  TESTS=("$@")
fi

SUITE_PASSED=0
SUITE_FAILED=0
SUITE_SKIPPED=0
FAILED_TESTS=()

cleanup() {
  rodney stop 2>/dev/null || true
}
trap cleanup EXIT

# Kill any lingering rodney/Chrome from previous runs
rodney stop 2>/dev/null || true
sleep 1

# ── Wait for services ────────────────────────────────────────────

section "Waiting for services"

info "Backend at $BACKEND_HEALTH ..."
for i in $(seq 1 "$TIMEOUT"); do
  if curl -sf "$BACKEND_HEALTH" &>/dev/null; then
    pass "Backend healthy"
    break
  fi
  [ "$i" -eq "$TIMEOUT" ] && { echo -e "${RED}Backend not healthy after ${TIMEOUT}s${NC}"; exit 1; }
  sleep 1
done

info "Frontend at $FRONTEND_URL ..."
for i in $(seq 1 "$TIMEOUT"); do
  if curl -sf "$FRONTEND_URL" &>/dev/null; then
    pass "Frontend ready"
    break
  fi
  [ "$i" -eq "$TIMEOUT" ] && { echo -e "${RED}Frontend not ready after ${TIMEOUT}s${NC}"; exit 1; }
  sleep 1
done

# ── Launch browser ───────────────────────────────────────────────

section "Starting Chrome"

rodney start
sleep 2
pass "Chrome started"

rodney open "$FRONTEND_URL"
rodney waitload
sleep 2
pass "Page loaded"

screenshot "00-initial.png"

# ── Run test suites ──────────────────────────────────────────────

for t in "${TESTS[@]}"; do
  script="$SCRIPT_DIR/${t}.sh"
  if [ ! -f "$script" ]; then
    echo -e "  ${YELLOW}⊘ $t (skipped — file not found)${NC}"
    SUITE_SKIPPED=$((SUITE_SKIPPED + 1))
    continue
  fi

  section "$t"

  if bash "$script"; then
    SUITE_PASSED=$((SUITE_PASSED + 1))
  else
    SUITE_FAILED=$((SUITE_FAILED + 1))
    FAILED_TESTS+=("$t")
    [ "${STOP_ON_FAIL:-}" = "1" ] && break
  fi
done

# ── Summary ──────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo -e "  Test suites: ${GREEN}$SUITE_PASSED passed${NC}, ${RED}$SUITE_FAILED failed${NC}, ${YELLOW}$SUITE_SKIPPED skipped${NC}"
if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
  echo -e "  ${RED}Failed: ${FAILED_TESTS[*]}${NC}"
fi
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo ""
info "Screenshots: $SCREENSHOT_DIR"

[ "$SUITE_FAILED" -eq 0 ]
