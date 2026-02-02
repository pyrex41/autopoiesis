#!/bin/bash
# Run a single Ralph iteration (no loop)
# Useful for testing prompts or manual control
#
# Usage: ./run-once.sh [plan|build]

set -e

MODE="${1:-build}"
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

cat "$PROMPT_FILE" | claude -p

echo "---"
echo "Single iteration complete."
