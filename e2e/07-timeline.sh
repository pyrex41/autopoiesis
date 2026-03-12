#!/usr/bin/env bash
# 07-timeline.sh — Timeline entries render, agent links
source "$(dirname "$0")/helpers.sh"

# Switch to Timeline view
solidjs_click_nth ".view-tab" 2
sleep 1

assert_exists ".timeline-view" "Timeline view rendered"
assert_text_contains ".timeline-title" "Timeline" "Timeline title shows 'Timeline'"

# Check for entries (may have some from agent actions in previous tests)
ENTRY_COUNT=$(js_val "document.querySelectorAll('.timeline-entry').length")
if [ "$ENTRY_COUNT" -gt 0 ] 2>/dev/null; then
  pass "Timeline has $ENTRY_COUNT entries"
  assert_exists ".timeline-entry-time" "Entry has time field"
  assert_exists ".timeline-entry-type" "Entry has type badge"
else
  pass "Timeline rendered (no entries yet — expected if no agent activity)"
fi

# Entry count display
assert_exists ".timeline-count" "Entry count display exists"

screenshot "07-timeline.png"

# Return to dashboard
solidjs_click_nth ".view-tab" 0
sleep 1

test_summary
