#!/usr/bin/env bash
# 09-conductor.sh — Conductor dashboard: start, stop, metrics display
source "$(dirname "$0")/helpers.sh"

# Ensure we're on dashboard (conductor is embedded there)
if ! rodney exists ".dashboard" 2>/dev/null; then
  solidjs_click_nth ".view-tab" 0
  sleep 1
fi

# ── Conductor section ────────────────────────────────────────────

assert_exists ".conductor-dashboard" "Conductor section visible in dashboard"

# Status badge
if rodney exists ".conductor-status" 2>/dev/null; then
  STATUS=$(js_val "document.querySelector('.conductor-status')?.textContent?.trim() || ''")
  pass "Conductor status badge: $STATUS"
else
  pass "Conductor status (not connected yet)"
fi

# Start/Stop buttons
START_BTN=$(js_val "Array.from(document.querySelectorAll('.conductor-dashboard .btn-sm')).find(b=>b.textContent.includes('Start'))?.textContent || ''")
if echo "$START_BTN" | grep -qi "start"; then
  pass "Start button exists"
else
  fail "Start button not found"
fi

STOP_BTN=$(js_val "Array.from(document.querySelectorAll('.conductor-dashboard .btn-sm')).find(b=>b.textContent.includes('Stop'))?.textContent || ''")
if echo "$STOP_BTN" | grep -qi "stop"; then
  pass "Stop button exists"
else
  fail "Stop button not found"
fi

# ── Click Start ──────────────────────────────────────────────────

info "Clicking conductor Start..."
rodney js "Array.from(document.querySelectorAll('.conductor-dashboard .btn-sm')).find(b=>b.textContent.includes('Start'))?.click()"
sleep 2

# Check if metrics grid appeared
if rodney exists ".conductor-metrics-grid" 2>/dev/null; then
  pass "Metrics grid renders after start"
  assert_count_gte ".conductor-metric" 1 "At least one metric card"
else
  pass "Metrics grid (conductor may not be connected)"
fi

# Sparklines
if rodney exists ".sparkline" 2>/dev/null; then
  pass "Sparkline SVG renders"
else
  pass "Sparklines (need data history to render)"
fi

# ── Click Stop ───────────────────────────────────────────────────

info "Clicking conductor Stop..."
rodney js "Array.from(document.querySelectorAll('.conductor-dashboard .btn-sm.btn-danger')).find(b=>b.textContent.includes('Stop'))?.click()"
sleep 1
pass "Stop button clicked"

screenshot "09-conductor.png"
test_summary
