;;;; provider-cursor.lisp - Cursor Agent CLI provider
;;;;
;;;; Wraps the `cursor-agent` CLI tool as an inference provider.
;;;; Uses a shorter default timeout due to hang risk.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Cursor Provider Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass cursor-provider (provider)
  ((cursor-mode :initarg :cursor-mode
                :accessor cursor-mode
                :initform nil
                :documentation "Cursor mode: nil, \"plan\", or \"ask\"")
   (force :initarg :force
          :accessor cursor-force
          :initform t
          :documentation "Whether to force non-interactive execution"))
  (:default-initargs :name "cursor" :command "cursor-agent" :timeout 120)
  (:documentation "Provider for the Cursor Agent CLI tool.

Invokes `cursor-agent` with --output-format json. Uses a shorter
default timeout (120s) due to potential hang risk."))

(defun make-cursor-provider (&key (name "cursor") (command "cursor-agent")
                               working-directory default-model
                               (max-turns 10) (timeout 120)
                               env extra-args
                               cursor-mode (force t))
  "Create a Cursor provider instance."
  (make-instance 'cursor-provider
                 :name name
                 :command command
                 :working-directory working-directory
                 :default-model default-model
                 :max-turns max-turns
                 :timeout timeout
                 :env env
                 :extra-args extra-args
                 :cursor-mode cursor-mode
                 :force force))

;;; ═══════════════════════════════════════════════════════════════════
;;; Protocol Implementation
;;; ═══════════════════════════════════════════════════════════════════

(defmethod provider-supported-modes ((provider cursor-provider))
  '(:one-shot))

(defmethod provider-build-command ((provider cursor-provider) prompt &key tools)
  "Build cursor-agent CLI command."
  (declare (ignore tools))
  (let ((args (list "-p" prompt "--output-format" "json")))
    (when (cursor-force provider)
      (push "--force" args))
    (when (cursor-mode provider)
      (setf args (append args (list "--mode" (cursor-mode provider)))))
    (when (provider-extra-args provider)
      (setf args (append args (provider-extra-args provider))))
    (values (provider-command provider) args)))

(defmethod provider-parse-output ((provider cursor-provider) raw-output)
  "Parse Cursor Agent JSON output.

   Cursor Agent outputs a JSON object with a result field."
  (handler-case
      (let* ((json (cl-json:decode-json-from-string raw-output))
             (text (or (cdr (assoc :result json)) "")))
        (make-provider-result :text text))
    (error (e)
      (make-provider-result
       :text raw-output
       :metadata (list :parse-error (format nil "~a" e))))))

(defmethod provider-to-sexpr ((provider cursor-provider))
  "Serialize Cursor provider configuration."
  (let ((base (call-next-method)))
    (append base
            (list :cursor-mode (cursor-mode provider)
                  :force (cursor-force provider)))))
