#!/bin/bash
# Ralph Wiggum Loop for Autopoiesis
# Usage: ./loop.sh [plan|build] [options]
#
# Options:
#   -n, --iterations N    Max iterations (default: 30)
#   -m, --model MODEL     Cursor model (default: opus 4.5)
#   --allow-subtasks      Allow Task tool for spawning sub-agents (build mode)
#   -c, --cli CLI         CLI tool (claude|cursor|opencode, default: cursor)
#   --dump FILE           Dump raw stream JSON to file for debugging
#
# Stop conditions:
#   - Max iterations reached (always enforced, default 30)
#   - Agent writes ralph/.stop file (signals "nothing left to do")
#   - Ctrl-C
#
# Examples:
#   ./loop.sh plan -n 3                  # Run 3 planning iterations
#   ./loop.sh build -n 10 -m opus        # Run 10 build iterations with opus
#   ./loop.sh build --allow-subtasks     # Build with sub-agent support

set -e

# Defaults
MODE="build"
MAX_ITERATIONS=30
MODEL=""  # Set based on mode if not specified
ALLOW_SUBTASKS=false
CLI="cursor"
DUMP_FILE=""
STOP_FILE=""  # Set after SCRIPT_DIR is known

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        plan|build)
            MODE="$1"
            shift
            ;;
        -n|--iterations)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        -m|--model)
            MODEL="$2"
            shift 2
            ;;
        --allow-subtasks)
            ALLOW_SUBTASKS=true
            shift
            ;;
        -c|--cli)
            CLI="$2"
            shift 2
            ;;
        --dump)
            DUMP_FILE="$2"
            shift 2
            ;;
        -h|--help)
            head -15 "$0" | tail -14
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STOP_FILE="$SCRIPT_DIR/.stop"

# Clean up any stale stop file from a previous run
rm -f "$STOP_FILE"

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

CLI="${CLI:-cursor}"
case $CLI in
  claude|cursor|opencode) ;;
  *) log_error "Invalid CLI: $CLI (use claude|cursor|opencode)"; exit 1 ;;
esac

BINARY="$CLI"
if [ "$CLI" = "cursor" ]; then
  BINARY="cursor-agent"
fi
 
# Select prompt, permissions, and default model based on mode
if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_plan.md"
    # Plan mode: full permissions
    if [ "$CLI" = "claude" ] || [ "$CLI" = "cursor" ]; then
      ARGS="--dangerously-skip-permissions --output-format stream-json --verbose --include-partial-messages"
    else
      ARGS=""
    fi
    [ -z "$MODEL" ] && MODEL="opus 4.5"
    log_info "Starting PLANNING mode (full permissions)"
elif [ "$MODE" = "build" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_build.md"
    # Build mode: Edit, Write, Bash (+ Task if --allow-subtasks), sonnet for speed
    [ -z "$MODEL" ] && MODEL="opus 4.5"
    if [ "$CLI" = "cursor" ]; then
        ARGS="--force --output-format stream-json --stream-partial-output"
        log_info "Starting BUILD mode"
    else
        if [ "$ALLOW_SUBTASKS" = true ]; then
            ARGS='--allowedTools "Edit,Write,Bash,Task" --output-format stream-json --verbose --include-partial-messages'
            log_info "Starting BUILD mode (with subtasks)"
        else
            ARGS='--allowedTools "Edit,Write,Bash" --output-format stream-json --verbose --include-partial-messages'
            log_info "Starting BUILD mode"
        fi
    fi
else
    log_error "Unknown mode: $MODE (use 'plan' or 'build')"
    exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
    log_error "Prompt file not found: $PROMPT_FILE"
    exit 1
fi
 
PROMPT_CONTENT="$(cat "$PROMPT_FILE")"
 
log_info "CLI: $CLI Model: $MODEL | Max iterations: $MAX_ITERATIONS"



# Ensure we're in project root
cd "$PROJECT_ROOT"

iteration=0
while true; do
    iteration=$((iteration + 1))

    # Check stop file (agent wrote it — nothing left to do)
    if [ -f "$STOP_FILE" ]; then
        log_success "Stop file found ($(cat "$STOP_FILE" 2>/dev/null || echo "no reason given")). Stopping."
        rm -f "$STOP_FILE"
        break
    fi

    # Check iteration limit (always enforced)
    if [ "$iteration" -gt "$MAX_ITERATIONS" ]; then
        log_success "Completed $MAX_ITERATIONS iterations. Stopping."
        break
    fi

    # Build display args
    DISPLAY_ARGS="--iteration $iteration --mode $MODE --model $MODEL"
    [ -n "$DUMP_FILE" ] && DISPLAY_ARGS="$DISPLAY_ARGS --dump $DUMP_FILE"

    # Run CLI with the prompt
    if [ "$CLI" = "claude" ] || [ "$CLI" = "cursor" ]; then
        if "$BINARY" --model "$MODEL" $ARGS -p "$PROMPT_CONTENT" \
            | python3 "$SCRIPT_DIR/stream_display.py" $DISPLAY_ARGS; then
            log_success "Iteration $iteration completed successfully"
        else
            exit_code=$?
            log_warn "Iteration $iteration exited with code $exit_code"
            # Continue anyway - failures are part of the loop
        fi
    else
        if "$BINARY" --model "$MODEL" $ARGS run "$PROMPT_CONTENT"; then
            log_success "Iteration $iteration completed successfully"
        else
            exit_code=$?
            log_warn "Iteration $iteration exited with code $exit_code"
            # Continue anyway - failures are part of the loop
        fi
    fi

    # Check stop file before sleeping (don't waste time if agent said to stop)
    if [ -f "$STOP_FILE" ]; then
        continue  # jump to top of loop where stop file is handled
    fi

    # Brief pause between iterations
    sleep 2
done

log_success "Ralph loop finished after $iteration iterations"
