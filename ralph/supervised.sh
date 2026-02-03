#!/bin/bash
# Supervised Ralph loop - pauses for human approval after each iteration
#
# Usage: ./supervised.sh [plan|build] [max_iterations] [model]

set -e

MODE="${1:-build}"
MAX_ITERATIONS="${2:-0}"
MODEL="${3:-xai/grok-4-1-fast}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_plan.md"
elif [ "$MODE" = "build" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_build.md"
else
    echo "Usage: ./supervised.sh [plan|build] [max_iterations]"
    exit 1
fi

cd "$PROJECT_ROOT"

iteration=0
while true; do
    iteration=$((iteration + 1))

    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$iteration" -gt "$MAX_ITERATIONS" ]; then
        echo "Reached max iterations ($MAX_ITERATIONS). Stopping."
        break
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  ITERATION $iteration ($MODE mode)"
    echo "════════════════════════════════════════════════════════════"
    echo ""

    # Run opencode for supervised execution
    opencode --model "$MODEL" run "$(cat "$PROMPT_FILE")"

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
