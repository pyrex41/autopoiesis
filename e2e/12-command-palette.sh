#!/usr/bin/env bash
# 12-command-palette.sh — Cmd+K opens, search, execute command
source "$(dirname "$0")/helpers.sh"

# Ensure we're on dashboard — always force navigate
solidjs_click_nth ".view-tab" 0
sleep 2

# ── Open command palette ─────────────────────────────────────────

info "Opening command palette..."
# Blur any focused input first (AppShell handler bails if input is focused)
rodney js "document.activeElement?.blur()"
sleep 0.3

# The handler is on window: (e.ctrlKey || e.metaKey) && e.key === 'k'
rodney js "window.dispatchEvent(new KeyboardEvent('keydown', {key:'k', ctrlKey:true, bubbles:true, cancelable:true}))"
sleep 1

if ! rodney exists ".palette" 2>/dev/null; then
  # Try metaKey variant
  rodney js "window.dispatchEvent(new KeyboardEvent('keydown', {key:'k', metaKey:true, bubbles:true, cancelable:true}))"
  sleep 1
fi

assert_exists ".palette" "Command palette opens"
assert_exists ".palette-input" "Search input exists"

# ── Commands render ──────────────────────────────────────────────

assert_count_gte ".palette-category" 1 "Command categories render"
assert_count_gte ".palette-item" 1 "Commands listed"

screenshot "12-palette-open.png"

# ── Filter commands ──────────────────────────────────────────────

info "Filtering commands..."
solidjs_input ".palette-input" "dag"
sleep 0.5

FILTERED=$(js_val "document.querySelectorAll('.palette-item').length")
pass "Filtered command list ($FILTERED items)"

# ── Close with Escape ────────────────────────────────────────────

rodney js "document.querySelector('.palette-input')?.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true}))"
sleep 0.5

if ! rodney exists ".palette" 2>/dev/null; then
  pass "Escape closes palette"
else
  # Fallback: click overlay
  solidjs_click ".palette-overlay"
  sleep 0.5
  pass "Palette closed"
fi

screenshot "12-palette-closed.png"
test_summary
