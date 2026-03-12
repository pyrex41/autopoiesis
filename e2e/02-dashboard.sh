#!/usr/bin/env bash
# 02-dashboard.sh — Dashboard view renders with stat cards and sections
source "$(dirname "$0")/helpers.sh"

# Dashboard is the default view
assert_exists ".dashboard" "Dashboard is default view"

# Stat cards
assert_count ".stat-card" 4 "4 stat cards render"
assert_text_contains ".stat-card:nth-child(1) .stat-card-label" "Total Agents" "Stat label: Total Agents"
assert_text_contains ".stat-card:nth-child(2) .stat-card-label" "Running" "Stat label: Running"
assert_text_contains ".stat-card:nth-child(3) .stat-card-label" "Paused" "Stat label: Paused"
assert_text_contains ".stat-card:nth-child(4) .stat-card-label" "Events" "Stat label: Events"

# Empty state or agent grid
assert_exists ".dashboard-agent-grid" "Agent grid section renders"

# Sections
assert_exists ".conductor-dashboard" "Conductor dashboard section renders"
assert_exists ".activity-panel" "Activity panel renders"
assert_exists ".cost-dashboard" "Cost dashboard renders"

# Connection indicator
assert_exists ".connection-indicator" "Connection indicator present"

# Status bar brand
assert_text_contains ".status-bar-brand" "AUTOPOIESIS" "Status bar shows brand"

screenshot "02-dashboard.png"
test_summary
