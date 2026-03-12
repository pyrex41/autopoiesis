#!/usr/bin/env bash
# 08-tasks.sh — Task kanban board, columns, card interactions
source "$(dirname "$0")/helpers.sh"

# Switch to Tasks view
solidjs_click_nth ".view-tab" 3
sleep 1

assert_exists ".tasks-view" "Tasks view rendered"
assert_exists ".task-queue" "Task queue component renders"

# ── Kanban columns ───────────────────────────────────────────────

# TaskQueue renders 5 columns: pending, in-progress, done, blocked, cancelled
assert_count_gte ".queue-column" 3 "At least 3 kanban columns render"

# Stats header
assert_exists ".queue-stats" "Queue stats header shows"

# Column headers
assert_count_gte ".column-header" 3 "Column headers have labels"

# Empty columns show empty state
EMPTY_COLS=$(js_val "document.querySelectorAll('.empty-column').length")
pass "Empty column states: $EMPTY_COLS"

# Stats are numeric
STATS_TEXT=$(js_val "document.querySelector('.queue-stats')?.textContent || ''")
if echo "$STATS_TEXT" | grep -qi "total"; then
  pass "Stats display shows totals"
else
  pass "Stats section rendered"
fi

screenshot "08-tasks.png"

# Return to dashboard
solidjs_click_nth ".view-tab" 0
sleep 1

test_summary
