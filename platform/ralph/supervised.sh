#!/bin/bash
# Supervised Ralph loop - pauses for human approval after each iteration
#
# Usage: ./supervised.sh [plan|build] [max_iterations] [cli] [model] (claude|cursor|opencode, default: cursor opus 4.5)

set -e

MODE="${1:-build}"
MAX_ITERATIONS="${2:-0}"
CLI="${3:-cursor}"
MODEL="${4:-opus 4.5}"
case $CLI in
  claude|cursor|opencode) ;;
  *) echo "Invalid CLI: $CLI (use claude|cursor|opencode)"; exit 1 ;;
esac

BINARY="$CLI"
if [ "$CLI" = "cursor" ]; then
  BINARY="cursor-agent"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STOP_FILE="$SCRIPT_DIR/.stop"

# Clean up any stale stop file
rm -f "$STOP_FILE"

if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_plan.md"
elif [ "$MODE" = "build" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_build.md"
else
    echo "Usage: ./supervised.sh [plan|build] [max_iterations]"
    exit 1
fi

cd "$PROJECT_ROOT"
PROMPT_CONTENT="$(cat "$PROMPT_FILE")"
 
iteration=0
while true; do
    iteration=$((iteration + 1))

    # Check stop file
    if [ -f "$STOP_FILE" ]; then
        echo "Stop file found ($(cat "$STOP_FILE" 2>/dev/null || echo "agent signaled done")). Stopping."
        rm -f "$STOP_FILE"
        break
    fi

    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$iteration" -gt "$MAX_ITERATIONS" ]; then
        echo "Reached max iterations ($MAX_ITERATIONS). Stopping."
        break
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  ITERATION $iteration ($MODE mode)"
    echo "════════════════════════════════════════════════════════════"
    echo ""

    # Run CLI for supervised execution
    if [ "$CLI" = "claude" ] || [ "$CLI" = "cursor" ]; then
        "$BINARY" --model "$MODEL" --output-format stream-json --verbose --include-partial-messages -p "$PROMPT_CONTENT" \
            | python3 "$SCRIPT_DIR/stream_display.py" --iteration "$iteration" --mode "$MODE" --model "$MODEL"
    else
        "$BINARY" --model "$MODEL" run "$PROMPT_CONTENT"
    fi

    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo "Iteration $iteration complete."
    echo ""

    # Show what changed
    echo "Git status:"
    git status --short 2>/dev/null || echo "(not a git repo)"
    echo ""

    # Human approval
    echo "Options:"
    echo "  [Enter] Continue to next iteration"
    echo "  [r]     Review changes (git diff)"
    echo "  [c]     Commit pending changes"
    echo "  [q]     Quit loop"
    echo ""
    read -p "Choice: " choice

    case "$choice" in
        r|R)
            git diff
            read -p "Press Enter to continue..."
            ;;
        c|C)
            git add -A
            read -p "Commit message: " msg
            git commit -m "$msg"
            ;;
        q|Q)
            echo "Stopping loop."
            break
            ;;
        *)
            # Continue
            ;;
    esac

    sleep 1
done

echo "Ralph loop finished after $iteration iterations."
