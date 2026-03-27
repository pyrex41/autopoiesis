#!/bin/bash
# Run Autopoiesis tests
# Uses FiveAM test framework

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts/ is inside packages/core/, so project root is three levels up
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

cd "$REPO_ROOT"

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

# Register all package directories with ASDF
sbcl --noinform --non-interactive \
    --load "$QUICKLISP_SETUP" \
    --eval "(dolist (dir '(\"$REPO_ROOT/packages/core/\"
                          \"$REPO_ROOT/packages/substrate/\"
                          \"$REPO_ROOT/packages/api-server/\"
                          \"$REPO_ROOT/packages/eval/\"
                          \"$REPO_ROOT/packages/sandbox/\"
                          \"$REPO_ROOT/packages/jarvis/\"
                          \"$REPO_ROOT/packages/swarm/\"
                          \"$REPO_ROOT/packages/team/\"
                          \"$REPO_ROOT/packages/supervisor/\"
                          \"$REPO_ROOT/packages/crystallize/\"
                          \"$REPO_ROOT/packages/holodeck/\"
                          \"$REPO_ROOT/packages/paperclip/\"
                          \"$REPO_ROOT/packages/research/\"
                          \"$REPO_ROOT/vendor/platform-vendor/woo/\"))
              (push (pathname dir) asdf:*central-registry*))" \
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
