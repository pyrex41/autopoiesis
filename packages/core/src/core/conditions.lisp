;;;; conditions.lisp - Error and condition hierarchy for Autopoiesis
;;;;
;;;; Defines the condition system used throughout Autopoiesis,
;;;; including base conditions, specific error types, and restarts.

(in-package #:autopoiesis.core)

;;; ═══════════════════════════════════════════════════════════════════
;;; Base Conditions
;;; ═══════════════════════════════════════════════════════════════════

(define-condition autopoiesis-condition ()
  ((message :initarg :message
            :reader condition-message
            :initform ""
            :documentation "Human-readable message describing the condition"))
  (:documentation "Base condition for all Autopoiesis conditions"))

(define-condition autopoiesis-error (autopoiesis-condition error)
  ()
  (:report (lambda (c s)
             (format s "Autopoiesis error: ~a" (condition-message c))))
  (:documentation "Base error for all Autopoiesis errors"))

(define-condition autopoiesis-warning (autopoiesis-condition warning)
  ()
  (:report (lambda (c s)
             (format s "Autopoiesis warning: ~a" (condition-message c))))
  (:documentation "Base warning for all Autopoiesis warnings"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Specific Error Types
;;; ═══════════════════════════════════════════════════════════════════

(define-condition serialization-error (autopoiesis-error)
  ((object :initarg :object
           :reader error-object
           :documentation "The object that failed to serialize"))
  (:report (lambda (c s)
             (format s "Serialization error: ~a (object: ~a)"
                     (condition-message c)
                     (error-object c))))
  (:documentation "Error during S-expression serialization"))

(define-condition deserialization-error (autopoiesis-error)
  ((input :initarg :input
          :reader error-input
          :documentation "The input that failed to deserialize"))
  (:report (lambda (c s)
             (format s "Deserialization error: ~a"
                     (condition-message c))))
  (:documentation "Error during S-expression deserialization"))

(define-condition validation-error (autopoiesis-error)
  ((errors :initarg :errors
           :reader validation-errors
           :initform nil
           :documentation "List of validation error messages"))
  (:report (lambda (c s)
             (format s "Validation error: ~{~a~^, ~}"
                     (validation-errors c))))
  (:documentation "Error during code or data validation"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Restart Utilities
;;; ═══════════════════════════════════════════════════════════════════

(defun establish-autopoiesis-restarts (thunk)
  "Run THUNK with standard Autopoiesis restarts established."
  (restart-case (funcall thunk)
    (continue-anyway ()
      :report "Continue execution despite the error"
      nil)
    (use-value (value)
      :report "Use a specific value instead"
      :interactive (lambda ()
                     (format t "Enter a value: ")
                     (list (eval (read))))
      value)
    (retry ()
      :report "Retry the operation"
      (funcall thunk))))

(defmacro with-autopoiesis-restarts (&body body)
  "Execute BODY with standard Autopoiesis restarts available."
  `(establish-autopoiesis-restarts (lambda () ,@body)))
