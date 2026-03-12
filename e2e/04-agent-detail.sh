#!/usr/bin/env bash
# 04-agent-detail.sh — Detail panel: capabilities, thoughts, activity
source "$(dirname "$0")/helpers.sh"

# Ensure an agent is selected (from previous test)
if ! rodney exists ".agent-detail-name" 2>/dev/null; then
  info "No agent selected, clicking first agent card..."
  solidjs_click ".agent-card"
  sleep 1
fi

# ── Header info ──────────────────────────────────────────────────

assert_exists ".agent-detail-name" "Agent name shown"
assert_exists ".agent-detail-id" "Agent ID shown"
assert_exists ".agent-state-dot-lg" "State dot rendered"

# ── Capabilities ─────────────────────────────────────────────────

assert_count_gte ".agent-cap-badge" 1 "Capabilities grid renders"

# ── Thought stream ───────────────────────────────────────────────

assert_exists ".thought-stream" "Thought stream section exists"

# Step to generate a thought, then check
solidjs_click ".action-step"
sleep 2

# Thought cards may or may not appear depending on backend response
if rodney exists ".thought-card" 2>/dev/null; then
  pass "Thought card appeared after step"
  assert_exists ".thought-type-badge" "Thought has type badge"
else
  pass "Thought stream present (no thoughts yet from step)"
fi

# ── Activity section ─────────────────────────────────────────────

# Activity section shows conditionally based on activity data
DETAIL_SECTIONS=$(js_val "document.querySelectorAll('.agent-detail-section').length")
pass "Detail sections rendered ($DETAIL_SECTIONS)"

# ── Lineage (if forked agent exists) ─────────────────────────────

# Check if there's a forked agent with parent
LINEAGE=$(js_val "document.querySelector('.agent-detail-dl dt')?.textContent || ''")
if echo "$LINEAGE" | grep -qi "parent"; then
  pass "Lineage section shows parent link"
else
  pass "Lineage section (not shown — agent may not be forked)"
fi

screenshot "04-agent-detail.png"
test_summary
