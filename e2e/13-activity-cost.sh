#!/usr/bin/env bash
# 13-activity-cost.sh — Activity panel rows, cost dashboard cards
source "$(dirname "$0")/helpers.sh"

# Ensure we're on dashboard — always click tab to be safe
solidjs_click_nth ".view-tab" 0
sleep 2

if ! rodney exists ".dashboard" 2>/dev/null; then
  # Extra wait for lazy view teardown
  sleep 2
fi

# ── Activity panel ───────────────────────────────────────────────

assert_exists ".activity-panel" "Activity panel in dashboard"

# Table may or may not have rows depending on activity data
if rodney exists ".activity-table" 2>/dev/null; then
  pass "Activity table renders"

  ROW_COUNT=$(js_val "document.querySelectorAll('.activity-row').length")
  pass "Activity rows: $ROW_COUNT"
else
  pass "Activity table (no activity data yet)"
fi

# ── Cost dashboard ───────────────────────────────────────────────

assert_exists ".cost-dashboard" "Cost dashboard renders"

# Summary cards
assert_count ".cost-summary-card" 3 "3 cost summary cards"

# Labels
assert_text_contains ".cost-summary-card:nth-child(1) .cost-summary-label" "Total Cost" "Label: Total Cost"
assert_text_contains ".cost-summary-card:nth-child(2) .cost-summary-label" "Total Tokens" "Label: Total Tokens"
assert_text_contains ".cost-summary-card:nth-child(3) .cost-summary-label" "API Calls" "Label: API Calls"

screenshot "13-activity-cost.png"
test_summary
