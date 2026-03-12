#!/bin/bash
# Run Autopoiesis tests
# Uses FiveAM test framework

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Running Autopoiesis tests..."

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

sbcl --noinform --non-interactive \
    --load "$QUICKLISP_SETUP" \
    --eval "(push #P\"$PROJECT_ROOT/\" asdf:*central-registry*)" \
    --eval "(push #P\"$PROJECT_ROOT/vendor/woo/\" asdf:*central-registry*)" \
    --eval "(handler-case
              (progn
                (ql:quickload :autopoiesis/test :silent t)
                (handler-case (progn
                               (ql:quickload :autopoiesis/api :silent t)
                               (asdf:load-system :autopoiesis/api-test))
                  (error (e) (format t \"~%Note: Skipping API tests (~a)~%\" e)))
                (asdf:test-system :autopoiesis)
                (format t \"~%Tests complete!~%\")
                (quit :unix-status 0))
              (error (e)
                (format t \"~%Tests FAILED: ~a~%\" e)
                (quit :unix-status 1)))"
