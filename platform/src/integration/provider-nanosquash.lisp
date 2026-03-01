;;;; provider-nanosquash.lisp - Nanosquash sandbox execution provider
;;;;
;;;; When :cl-nanosquash is loaded, calls squashd manager directly.
;;;; Falls back to `nanosquash` CLI subprocess if not available.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Nanosquash Provider Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass nanosquash-provider (provider)
  ((sandbox-id :initarg :sandbox-id
               :accessor nanosquash-sandbox-id
               :initform nil
               :documentation "Active sandbox ID for native mode")
   (layers :initarg :layers
           :accessor nanosquash-layers
           :initform #("000-base-alpine")
           :documentation "SquashFS layers for sandbox creation")
   (squash-config :initarg :squash-config
                  :accessor nanosquash-squash-config
                  :initform nil
                  :documentation "Optional squash-config for env/file injection")
   (ephemeral :initarg :ephemeral
              :accessor nanosquash-ephemeral
              :initform t
              :documentation "Destroy sandbox after use"))
  (:default-initargs :name "nanosquash" :command "nanosquash" :timeout 300)
  (:documentation "Provider for nanosquash sandbox execution.

Native CL path via cl-nanosquash when available, CLI fallback otherwise."))

(defun make-nanosquash-provider (&key (name "nanosquash") (command "nanosquash")
                                      (timeout 300) working-directory default-model
                                      (max-turns 10) env extra-args
                                      sandbox-id (layers #("000-base-alpine"))
                                      squash-config (ephemeral t))
  "Create a nanosquash provider instance."
  (make-instance 'nanosquash-provider
                 :name name :command command :timeout timeout
                 :working-directory working-directory
                 :default-model default-model
                 :max-turns max-turns :env env :extra-args extra-args
                 :sandbox-id sandbox-id :layers layers
                 :squash-config squash-config :ephemeral ephemeral))

(defun nanosquash-native-p ()
  "Return T if cl-nanosquash is loaded and available."
  (not (null (find-package :nanosquash))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider Protocol
;;; ═══════════════════════════════════════════════════════════════════

(defmethod provider-supported-modes ((provider nanosquash-provider))
  '(:one-shot))

(defmethod provider-invoke ((provider nanosquash-provider) prompt
                            &key tools mode agent-id)
  "Invoke via native CL when available, subprocess fallback otherwise."
  (declare (ignore tools mode))
  (if (nanosquash-native-p)
      (%nanosquash-native-invoke provider prompt agent-id)
      (call-next-method)))

(defun %nanosquash-native-invoke (provider prompt agent-id)
  "Direct CL invocation via cl-nanosquash."
  ;; Emit provider-request event
  (when (and agent-id (find-package :autopoiesis.integration))
    (handler-case
        (emit-event :provider-request
                    :provider "nanosquash"
                    :agent-id agent-id
                    :prompt prompt)
      (error () nil)))
  (let* ((ns-pkg (find-package :nanosquash))
         (create-fn (symbol-function (find-symbol "CREATE" ns-pkg)))
         (exec-fn (symbol-function (find-symbol "EXEC-COMMAND" ns-pkg)))
         (destroy-fn (symbol-function (find-symbol "DESTROY" ns-pkg)))
         ;; Create or reuse sandbox
         (sid (or (nanosquash-sandbox-id provider)
                  (funcall create-fn
                           :layers (nanosquash-layers provider))))
         (result nil))
    (unwind-protect
         (progn
           ;; Inject config if present
           (when (nanosquash-squash-config provider)
             (let ((config-fn (symbol-function
                               (find-symbol "INJECT-CONFIG" ns-pkg))))
               (funcall config-fn sid (nanosquash-squash-config provider))))
           ;; Execute prompt as shell command
           (let ((output (funcall exec-fn sid prompt)))
             (setf result (make-provider-result
                           :text (if (stringp output) output
                                     (format nil "~a" output))
                           :provider-name "nanosquash"))))
      ;; Cleanup: destroy if ephemeral and we created it
      (when (and (nanosquash-ephemeral provider)
                 (not (nanosquash-sandbox-id provider)))
        (handler-case (funcall destroy-fn sid)
          (error () nil))))
    ;; Emit provider-response event
    (when (and agent-id (find-package :autopoiesis.integration))
      (handler-case
          (emit-event :provider-response
                      :provider "nanosquash"
                      :agent-id agent-id
                      :result result)
        (error () nil)))
    result))

;;; ═══════════════════════════════════════════════════════════════════
;;; Subprocess Fallback
;;; ═══════════════════════════════════════════════════════════════════

(defmethod provider-build-command ((provider nanosquash-provider) prompt
                                   &key tools)
  "Build nanosquash CLI command for subprocess fallback."
  (declare (ignore tools))
  (values "nanosquash" (list "exec"
                             (or (nanosquash-sandbox-id provider) "ap")
                             prompt)))

(defmethod provider-parse-output ((provider nanosquash-provider) raw-output)
  "Parse nanosquash output as plain text."
  (make-provider-result :text raw-output
                        :provider-name "nanosquash"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defmethod provider-to-sexpr ((provider nanosquash-provider))
  (let ((base (call-next-method)))
    (append base (list :sandbox-id (nanosquash-sandbox-id provider)
                       :layers (nanosquash-layers provider)
                       :ephemeral (nanosquash-ephemeral provider)))))
