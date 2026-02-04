;;;; provider-claude-code.lisp - Claude Code CLI provider
;;;;
;;;; Wraps the `claude` CLI tool as an inference provider.
;;;; Supports one-shot and streaming modes.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Claude Code Provider Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass claude-code-provider (provider)
  ((skip-permissions :initarg :skip-permissions
                     :accessor claude-code-skip-permissions
                     :initform t
                     :documentation "Whether to pass --dangerously-skip-permissions")
   (max-budget-usd :initarg :max-budget-usd
                   :accessor claude-code-max-budget-usd
                   :initform nil
                   :documentation "Maximum budget in USD for the invocation"))
  (:default-initargs :name "claude-code" :command "claude")
  (:documentation "Provider for the Claude Code CLI tool.

Invokes `claude` with --output-format json for structured output.
Supports both one-shot (-p) and streaming modes."))

(defun make-claude-code-provider (&key (name "claude-code") (command "claude")
                                    working-directory default-model
                                    (max-turns 10) (timeout 300)
                                    env extra-args
                                    (skip-permissions t) max-budget-usd)
  "Create a Claude Code provider instance."
  (make-instance 'claude-code-provider
                 :name name
                 :command command
                 :working-directory working-directory
                 :default-model default-model
                 :max-turns max-turns
                 :timeout timeout
                 :env env
                 :extra-args extra-args
                 :skip-permissions skip-permissions
                 :max-budget-usd max-budget-usd))

;;; ═══════════════════════════════════════════════════════════════════
;;; Protocol Implementation
;;; ═══════════════════════════════════════════════════════════════════

(defmethod provider-supported-modes ((provider claude-code-provider))
  '(:one-shot :streaming))

(defmethod provider-build-command ((provider claude-code-provider) prompt &key tools)
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

(defmethod provider-parse-output ((provider claude-code-provider) raw-output)
  "Parse Claude Code JSON output.

   Claude Code outputs a single JSON object with fields:
   result, cost_usd (mapped as cost--usd by cl-json), num_turns, session_id"
  (handler-case
      (let* ((json (cl-json:decode-json-from-string raw-output))
             (result-text (or (cdr (assoc :result json)) ""))
             ;; cl-json converts snake_case with underscores to hyphens,
             ;; and the underscore between words becomes double-hyphen
             (cost (or (cdr (assoc :cost--usd json))
                       (cdr (assoc :cost-usd json))))
             (turns (or (cdr (assoc :num--turns json))
                        (cdr (assoc :num-turns json))))
             (session (cdr (assoc :session--id json))))
        (make-provider-result
         :text result-text
         :turns turns
         :cost cost
         :session-id session))
    (error (e)
      ;; If JSON parsing fails, return raw output as text
      (make-provider-result
       :text raw-output
       :metadata (list :parse-error (format nil "~a" e))))))

(defmethod provider-to-sexpr ((provider claude-code-provider))
  "Serialize Claude Code provider configuration."
  (let ((base (call-next-method)))
    (append base
            (list :skip-permissions (claude-code-skip-permissions provider)
                  :max-budget-usd (claude-code-max-budget-usd provider)))))
