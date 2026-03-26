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

# Register all packages/ subdirectories and vendor/ for ASDF discovery
sbcl --noinform --non-interactive \
    --load "$QUICKLISP_SETUP" \
    --eval "(dolist (dir (directory #P\"$PROJECT_ROOT/packages/*/\"))
              (push dir asdf:*central-registry*))" \
    --eval "(push #P\"$PROJECT_ROOT/vendor/\" asdf:*central-registry*)" \
    --eval "(handler-case
              (progn
                ;; Load and run core tests
                (ql:quickload :autopoiesis/test :silent t)
                ;; Try loading optional extension tests
                (dolist (ext '(:autopoiesis/api-test
                               :autopoiesis/swarm-test
                               :autopoiesis/supervisor-test
                               :autopoiesis/crystallize-test
                               :autopoiesis/team-test
                               :autopoiesis/jarvis-test
                               :autopoiesis/holodeck-test
                               :autopoiesis/eval-test
                               :autopoiesis/paperclip-test))
                  (handler-case (ql:quickload ext :silent t)
                    (error (e) (format t \"~%Note: Skipping ~a (~a)~%\" ext e))))
                (asdf:test-system :autopoiesis)
                (format t \"~%Tests complete!~%\")
                (quit :unix-status 0))
              (error (e)
                (format t \"~%Tests FAILED: ~a~%\" e)
                (quit :unix-status 1)))"
