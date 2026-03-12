#!/usr/bin/env bash
# 01-health.sh — Backend + frontend health checks, page renders
source "$(dirname "$0")/helpers.sh"

# Backend and frontend already verified by run.sh orchestrator.
# Here we verify the app actually rendered in the browser.

assert_exists ".app-shell" "App shell rendered"
assert_exists ".status-bar" "Status bar present"
assert_exists ".view-switcher" "View switcher present"
assert_exists ".jarvis-bar" "Jarvis bar present"

screenshot "01-health.png"
test_summary
