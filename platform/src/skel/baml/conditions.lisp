;;;; conditions.lisp - Error conditions for BAML import system

(in-package #:autopoiesis.skel.baml)

;;; ============================================================================
;;; Base Condition
;;; ============================================================================

(define-condition baml-error (error)
  ((message :initarg :message
            :reader baml-error-message
            :initform nil
            :documentation "Human-readable error message"))
  (:report (lambda (condition stream)
             (format stream "BAML error: ~A"
                     (or (baml-error-message condition) "unknown error"))))
  (:documentation "Base condition for all BAML-related errors."))

;;; ============================================================================
;;; Tokenizer Conditions
;;; ============================================================================

(define-condition baml-tokenize-error (baml-error)
  ((line :initarg :line
         :reader baml-tokenize-error-line
         :initform nil)
   (column :initarg :column
           :reader baml-tokenize-error-column
           :initform nil)
   (content :initarg :content
            :reader baml-tokenize-error-content
            :initform nil))
  (:report (lambda (condition stream)
             (format stream "BAML tokenize error at line ~A, column ~A: ~A~@[ (near: ~S)~]"
                     (baml-tokenize-error-line condition)
                     (baml-tokenize-error-column condition)
                     (or (baml-error-message condition) "unexpected token")
                     (baml-tokenize-error-content condition))))
  (:documentation "Signaled when tokenization fails on invalid input."))

;;; ============================================================================
;;; Parser Conditions
;;; ============================================================================

(define-condition baml-parse-error (baml-error)
  ((expected :initarg :expected
             :reader baml-parse-error-expected
             :initform nil)
   (found :initarg :found
          :reader baml-parse-error-found
          :initform nil)
   (context :initarg :context
            :reader baml-parse-error-context
            :initform nil))
  (:report (lambda (condition stream)
             (format stream "BAML parse error~@[ in ~A~]: ~A~@[, expected ~A~]~@[, found ~A~]"
                     (baml-parse-error-context condition)
                     (or (baml-error-message condition) "syntax error")
                     (baml-parse-error-expected condition)
                     (baml-parse-error-found condition))))
  (:documentation "Signaled when parsing encounters invalid BAML syntax."))

;;; ============================================================================
;;; Type Conversion Conditions
;;; ============================================================================

(define-condition baml-type-error (baml-error)
  ((baml-type :initarg :baml-type
              :reader baml-type-error-baml-type
              :initform nil)
   (reason :initarg :reason
           :reader baml-type-error-reason
           :initform nil))
  (:report (lambda (condition stream)
             (format stream "BAML type error: cannot convert type ~S~@[: ~A~]"
                     (baml-type-error-baml-type condition)
                     (or (baml-type-error-reason condition)
                         (baml-error-message condition)))))
  (:documentation "Signaled when a BAML type cannot be converted to SKEL type."))

;;; ============================================================================
;;; Import Conditions
;;; ============================================================================

(define-condition baml-import-error (baml-error)
  ((path :initarg :path
         :reader baml-import-error-path
         :initform nil)
   (cause :initarg :cause
          :reader baml-import-error-cause
          :initform nil))
  (:report (lambda (condition stream)
             (format stream "BAML import error~@[ for ~A~]: ~A~@[~%Caused by: ~A~]"
                     (baml-import-error-path condition)
                     (or (baml-error-message condition) "failed to import")
                     (baml-import-error-cause condition))))
  (:documentation "Signaled when importing a BAML file fails."))
