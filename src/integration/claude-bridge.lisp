;;;; claude-bridge.lisp - Claude API integration
;;;;
;;;; Bridge for communicating with Claude.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Claude Client
;;; ═══════════════════════════════════════════════════════════════════

(defclass claude-client ()
  ((api-key :initarg :api-key
            :accessor client-api-key
            :documentation "Anthropic API key")
   (model :initarg :model
          :accessor client-model
          :initform "claude-sonnet-4-20250514"
          :documentation "Model to use")
   (base-url :initarg :base-url
             :accessor client-base-url
             :initform "https://api.anthropic.com/v1"
             :documentation "API base URL")
   (max-tokens :initarg :max-tokens
               :accessor client-max-tokens
               :initform 4096
               :documentation "Default max tokens"))
  (:documentation "Client for Claude API"))

(defun make-claude-client (&key api-key model max-tokens)
  "Create a new Claude client."
  (make-instance 'claude-client
                 :api-key (or api-key (uiop:getenv "ANTHROPIC_API_KEY"))
                 :model (or model "claude-sonnet-4-20250514")
                 :max-tokens (or max-tokens 4096)))

;;; ═══════════════════════════════════════════════════════════════════
;;; API Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun claude-complete (client messages &key system tools)
  "Send a completion request to Claude."
  (declare (ignore client messages system tools))
  ;; Placeholder - would use dexador for HTTP
  (error 'autopoiesis.core:autopoiesis-error
         :message "Claude API not yet implemented"))

(defun claude-stream (client messages callback &key system tools)
  "Stream a completion from Claude, calling CALLBACK for each chunk."
  (declare (ignore client messages callback system tools))
  ;; Placeholder
  (error 'autopoiesis.core:autopoiesis-error
         :message "Claude streaming not yet implemented"))

(defun claude-tool-use (client messages tools)
  "Send a request expecting tool use response."
  (declare (ignore client messages tools))
  ;; Placeholder
  (error 'autopoiesis.core:autopoiesis-error
         :message "Claude tool use not yet implemented"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Management
;;; ═══════════════════════════════════════════════════════════════════

(defmacro with-claude-session ((client &key api-key model) &body body)
  "Execute BODY with a Claude client bound."
  `(let ((,client (make-claude-client :api-key ,api-key :model ,model)))
     ,@body))
