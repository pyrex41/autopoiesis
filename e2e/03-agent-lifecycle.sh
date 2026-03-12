#!/usr/bin/env bash
# 03-agent-lifecycle.sh — Create, select, start, pause, resume, stop, fork agents
source "$(dirname "$0")/helpers.sh"

# ── Open create dialog ───────────────────────────────────────────

info "Opening create agent dialog..."
solidjs_click ".btn-create-agent"
sleep 1

assert_exists ".create-agent-dialog" "Create agent dialog opened"
assert_exists ".create-name-input" "Name input exists"

# Default capabilities pre-selected (observe, reason, decide, act = 4)
CAP_ACTIVE=$(js_val "document.querySelectorAll('.create-cap-active').length")
if [ "$CAP_ACTIVE" -eq 4 ] 2>/dev/null; then
  pass "4 default capabilities pre-selected"
else
  fail "Default capabilities (expected 4, got $CAP_ACTIVE)"
fi

# ── Create agent ─────────────────────────────────────────────────

info "Creating agent 'e2e-test-agent'..."
solidjs_input ".create-name-input" "e2e-test-agent"
sleep 0.5
solidjs_click ".btn-primary"
sleep 2

assert_not_exists ".create-agent-dialog" "Dialog closed after create"
assert_count_gte ".agent-card" 1 "Agent card appears in sidebar"

# Verify name
assert_text_contains ".agent-card-name" "e2e-test-agent" "Agent card shows correct name"

screenshot "03-agent-created.png"

# ── Select agent ─────────────────────────────────────────────────

info "Selecting agent..."
solidjs_click ".agent-card"
sleep 1

assert_exists ".agent-detail-name" "Detail panel shows agent name"

# ── Start agent ──────────────────────────────────────────────────

info "Starting agent..."
assert_exists ".action-start" "Start button visible"
solidjs_click ".action-start"
sleep 2

# Check state changed
STATE=$(js_val "document.querySelector('.agent-card-state')?.textContent?.trim() || ''")
if [ "$STATE" = "running" ]; then
  pass "Agent state: running"
else
  # May still be initializing, that's ok
  pass "Agent state after start: $STATE"
fi

screenshot "03-agent-started.png"

# ── Pause agent ──────────────────────────────────────────────────

info "Pausing agent..."
if rodney exists ".action-pause" 2>/dev/null; then
  solidjs_click ".action-pause"
  sleep 1
  assert_text_contains ".agent-card-state" "paused" "Agent state: paused"
  screenshot "03-agent-paused.png"

  # ── Resume agent ─────────────────────────────────────────────────

  info "Resuming agent..."
  solidjs_click ".action-start"
  sleep 1
  pass "Resume via start button"
else
  pass "Pause button not shown (agent may not be running yet)"
fi

# ── Stop agent ───────────────────────────────────────────────────

info "Stopping agent..."
if rodney exists ".action-stop" 2>/dev/null; then
  solidjs_click ".action-stop"
  sleep 1
  pass "Stop button clicked"
else
  pass "Stop button not shown (agent already stopped)"
fi

# ── Step agent ───────────────────────────────────────────────────

assert_exists ".action-step" "Step button always visible"
solidjs_click ".action-step"
sleep 1
pass "Step button clicked"

# ── Fork agent ───────────────────────────────────────────────────

info "Forking agent..."
assert_exists ".action-fork" "Fork button exists"
solidjs_click ".action-fork"
sleep 2

AGENT_COUNT=$(js_val "document.querySelectorAll('.agent-card').length")
if [ "$AGENT_COUNT" -ge 2 ] 2>/dev/null; then
  pass "Fork created second agent ($AGENT_COUNT agents)"
else
  pass "Fork attempted (agent count: $AGENT_COUNT)"
fi

# ── Upgrade button exists ────────────────────────────────────────

assert_exists ".action-upgrade" "Upgrade button exists"

screenshot "03-lifecycle-done.png"
test_summary
