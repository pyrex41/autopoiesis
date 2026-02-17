;;;; provider-claude-code.lisp - Claude Code CLI provider
;;;;
;;;; Wraps the `claude` CLI tool as an inference provider.
;;;; Supports one-shot and streaming modes.

(in-package #:autopoiesis.integration)

(define-cli-provider :claude-code
  (:command "claude")
  (:modes (:one-shot :streaming))
  (:documentation "Provider for the Claude Code CLI tool.

Invokes `claude` with --output-format json for structured output.
Supports both one-shot (-p) and streaming modes.")
  (:extra-slots
    (skip-permissions :initarg :skip-permissions
                      :accessor claude-code-skip-permissions
                      :initform t
                      :documentation "Whether to pass --dangerously-skip-permissions")
    (max-budget-usd :initarg :max-budget-usd
                    :accessor claude-code-max-budget-usd
                    :initform nil
                    :documentation "Maximum budget in USD for the invocation"))
  (:build-command (provider prompt &key tools)
    "Build claude CLI command for one-shot invocation."
    (let ((args (list "-p" prompt
                      "--output-format" "json"
                      "--max-turns" (format nil "~a" (provider-max-turns provider)))))
      ;; Add skip-permissions flag
      (when (claude-code-skip-permissions provider)
        (push "--dangerously-skip-permissions" args))
      ;; Add model if specified
      (when (provider-default-model provider)
        (setf args (append args (list "--model" (provider-default-model provider)))))
      ;; Add allowed tools
      (when tools
        (let ((tool-names (provider-format-tools provider tools)))
          (when tool-names
            (setf args (append args (list "--allowedTools"
                                          (format nil "~{~a~^,~}" tool-names)))))))
      ;; Add budget
      (when (claude-code-max-budget-usd provider)
        (setf args (append args (list "--max-budget"
                                      (format nil "~a" (claude-code-max-budget-usd provider))))))
      ;; Add any extra args
      (when (provider-extra-args provider)
        (setf args (append args (provider-extra-args provider))))
      (values (provider-command provider) args)))
  (:parse-output :json-object
    (:text "result")
    (:cost "cost_usd")
    (:turns "num_turns")
    (:session-id "session_id")))
