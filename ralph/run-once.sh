#!/bin/bash
# Run a single Ralph iteration (no loop)
# Useful for testing prompts or manual control
#
# Usage: ./run-once.sh [plan|build] [cli] [model] (claude|cursor|opencode, default: cursor opus 4.5)

set -e

MODE="${1:-build}"
CLI="${2:-cursor}"
MODEL="${3:-opus 4.5}"
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

if [ "$MODE" = "plan" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_plan.md"
elif [ "$MODE" = "build" ]; then
    PROMPT_FILE="$SCRIPT_DIR/PROMPT_build.md"
else
    echo "Usage: ./run-once.sh [plan|build]"
    exit 1
fi

cd "$PROJECT_ROOT"
PROMPT_CONTENT="$(cat "$PROMPT_FILE")"
 
echo "CLI: $CLI Model: $MODEL ($MODE iteration)..."
echo "Prompt: $PROMPT_FILE"
echo "---"

if [ "$CLI" = "claude" ] || [ "$CLI" = "cursor" ]; then
    "$BINARY" --model "$MODEL" -p "$PROMPT_CONTENT"
else
    "$BINARY" --model "$MODEL" run "$PROMPT_CONTENT"
fi

echo "---"
echo "Single iteration complete."
