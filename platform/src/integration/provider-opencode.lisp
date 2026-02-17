;;;; provider-opencode.lisp - OpenCode CLI provider
;;;;
;;;; Wraps the `opencode` CLI tool as an inference provider.
;;;; Supports one-shot CLI mode and optional HTTP server mode.

(in-package #:autopoiesis.integration)

(define-cli-provider :opencode
  (:command "opencode")
  ;; Modes are dynamic (depends on use-server), so omit :modes
  ;; and define provider-supported-modes manually below.
  (:documentation "Provider for the OpenCode CLI tool.

Invokes `opencode run` with --format json for structured output.
Optionally supports HTTP server mode for persistent sessions.")
  (:extra-slots
    (use-server :initarg :use-server
                :accessor opencode-use-server
                :initform nil
                :documentation "Whether to use HTTP server mode")
    (server-port :initarg :server-port
                 :accessor opencode-server-port
                 :initform 4096
                 :documentation "Port for HTTP server mode"))
  (:build-command (provider prompt)
    "Build opencode CLI command."
    (let ((args (list "run" prompt "--format" "json")))
      (when (provider-extra-args provider)
        (setf args (append args (provider-extra-args provider))))
      (values (provider-command provider) args)))
  (:parse-output :jsonl-events
    ("text"
      (let* ((part (cdr (assoc :part json)))
             (text (cdr (assoc :text part))))
        (when text (push text text-parts))))
    ("tool_call"
      (let ((part (cdr (assoc :part json))))
        (when part
          (push (list :name (cdr (assoc :name part))
                      :input (cdr (assoc :input part)))
                tool-calls))))
    ("step_finish"
      (let ((part (cdr (assoc :part json))))
        (when part
          (let ((cost (cdr (assoc :cost part))))
            (when cost (incf total-cost cost)))
          (incf turns))))))

;; Dynamic modes: streaming only when use-server is enabled
(defmethod provider-supported-modes ((provider opencode-provider))
  (if (opencode-use-server provider)
      '(:one-shot :streaming)
      '(:one-shot)))
