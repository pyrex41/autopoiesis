#!/usr/bin/env bash
# 06-dag-view.sh — DAG canvas, toolbar, branches, mock/live toggle
source "$(dirname "$0")/helpers.sh"

# Switch to DAG view
solidjs_click_nth ".view-tab" 1
sleep 2

assert_exists ".dag-view" "DAG view rendered"

# ── Toolbar ──────────────────────────────────────────────────────

assert_exists ".toolbar" "Toolbar renders"

# Mock button — DAGView auto-loads mock data on mount
MOCK_BTN=$(js_val "Array.from(document.querySelectorAll('.btn-toolbar')).find(b=>b.textContent.includes('Mock'))?.textContent || ''")
if echo "$MOCK_BTN" | grep -qi "mock"; then
  pass "Mock button exists in toolbar"
else
  fail "Mock button not found"
fi

# ── Canvas ───────────────────────────────────────────────────────

assert_exists ".dag-canvas-wrap" "Canvas wrapper renders"
assert_exists ".dag-canvas-wrap canvas" "Canvas element exists"

# ── Branch list ──────────────────────────────────────────────────

assert_exists ".branch-list" "Branch list renders"
assert_count_gte ".branch-item" 1 "At least 1 branch item"

# ── Toolbar controls ─────────────────────────────────────────────

# Layout dropdown
LAYOUT_SELECT=$(js_val "document.querySelector('.toolbar select')?.tagName || ''")
if [ "$LAYOUT_SELECT" = "SELECT" ]; then
  pass "Layout dropdown exists"
else
  fail "Layout dropdown not found"
fi

# Fit button
FIT_BTN=$(js_val "Array.from(document.querySelectorAll('.btn-toolbar')).find(b=>b.textContent.includes('Fit'))?.textContent || ''")
if echo "$FIT_BTN" | grep -qi "fit"; then
  pass "Fit button exists"
else
  fail "Fit button not found"
fi

# Inspector toggle
INSPECTOR_BTN=$(js_val "Array.from(document.querySelectorAll('.btn-toolbar')).find(b=>b.textContent.includes('Inspector'))?.textContent || ''")
if echo "$INSPECTOR_BTN" | grep -qi "inspector"; then
  pass "Inspector toggle button exists"
else
  fail "Inspector toggle not found"
fi

# Diff button
DIFF_BTN=$(js_val "Array.from(document.querySelectorAll('.btn-toolbar')).find(b=>b.textContent.includes('Diff'))?.textContent || ''")
if echo "$DIFF_BTN" | grep -qi "diff"; then
  pass "Diff button exists"
else
  fail "Diff button not found"
fi

screenshot "06-dag-view.png"

# Return to dashboard
solidjs_click_nth ".view-tab" 0
sleep 1

test_summary
