#!/bin/bash
# Ralph Wiggum Loop for Autopoiesis
# Usage: ./loop.sh [plan|build] [max_iterations] [model]
#
# Examples:
#   ./loop.sh plan 3      # Run 3 planning iterations
#   ./loop.sh build 10 xai/grok-4-1-fast    # Run 10 build iterations
#   ./loop.sh build xai/grok-4-1-fast       # Run build indefinitely (ctrl-c to stop)

set -e

MODE="${1:-build}"
MAX_ITERATIONS="${2:-0}"  # 0 = infinite
MODEL="${3:-xai/grok-4-1-fast}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[RALPH]${NC} $1"; }
log_success() { echo -e "${GREEN}[RALPH]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[RALPH]${NC} $1"; }
log_error() { echo -e "${RED}[RALPH]${NC} $1"; }

# Select prompt based on mode
if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_plan.md"
    log_info "Starting PLANNING mode"
elif [ "$MODE" = "build" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_build.md"
    log_info "Starting BUILD mode"
else
    log_error "Unknown mode: $MODE (use 'plan' or 'build')"
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    log_error "Prompt file not found: $PROMPT_FILE"
    exit 1
fi

# Ensure we're in project root
cd "$PROJECT_ROOT"

iteration=0
while true; do
    iteration=$((iteration + 1))

    # Check iteration limit
    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$iteration" -gt "$MAX_ITERATIONS" ]; then
        log_success "Completed $MAX_ITERATIONS iterations. Stopping."
        break
    fi

    log_info "═══════════════════════════════════════════════════════════"
    log_info "Iteration $iteration (Mode: $MODE)"
    log_info "═══════════════════════════════════════════════════════════"

    # Run opencode with the prompt
    # run subcommand for non-interactive execution

    if opencode --model "$MODEL" run "$(cat "$PROMPT_FILE")"; then
        log_success "Iteration $iteration completed successfully"
    else
        exit_code=$?
        log_warn "Iteration $iteration exited with code $exit_code"
        # Continue anyway - failures are part of the loop
    fi

    # Brief pause between iterations
    sleep 2

    log_info ""
done

log_success "Ralph loop finished after $iteration iterations"
