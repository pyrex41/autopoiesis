#!/bin/bash
# Run a single Ralph iteration (no loop)
# Useful for testing prompts or manual control
#
# Usage: ./run-once.sh [plan|build] [model]

set -e

MODE="${1:-build}"
MODEL="${2:-xai/grok-4-1-fast}"
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

echo "Running single $MODE iteration..."
echo "Prompt: $PROMPT_FILE"
echo "---"

opencode --model "$MODEL" run "$(cat "$PROMPT_FILE")"

echo "---"
echo "Single iteration complete."
