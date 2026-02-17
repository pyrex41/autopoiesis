#!/bin/bash
# Build Autopoiesis
# Loads the system in SBCL and checks for compilation errors

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Building Autopoiesis..."

# Check if SBCL is available
if ! command -v sbcl &> /dev/null; then
    echo "ERROR: SBCL not found. Please install SBCL."
    exit 1
fi

# Check if quicklisp is set up
QUICKLISP_SETUP="$HOME/quicklisp/setup.lisp"
if [ ! -f "$QUICKLISP_SETUP" ]; then
    echo "ERROR: Quicklisp not found at $QUICKLISP_SETUP"
    echo "Please install Quicklisp: https://www.quicklisp.org/beta/"
    exit 1
fi

# Try to load the system
sbcl --noinform --non-interactive \
    --load "$QUICKLISP_SETUP" \
    --eval "(push #P\"$PROJECT_ROOT/\" asdf:*central-registry*)" \
    --eval "(handler-case
              (progn
                (ql:quickload :autopoiesis :silent t)
                (format t \"~%Build successful!~%\")
                (quit :unix-status 0))
              (error (e)
                (format t \"~%Build FAILED: ~a~%\" e)
                (quit :unix-status 1)))"
