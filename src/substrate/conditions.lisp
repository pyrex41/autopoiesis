;;;; conditions.lisp - Substrate condition hierarchy
;;;;
;;;; Self-contained conditions for the substrate. When loaded as part of
;;;; autopoiesis, these still integrate with CL's condition system normally.

(in-package #:autopoiesis.substrate)

;;; Base substrate condition
(define-condition substrate-condition (condition)
  ((message :initarg :message :reader substrate-condition-message :initform "")
   (entity-id :initarg :entity-id :reader condition-entity-id :initform nil)
   (attribute :initarg :attribute :reader condition-attribute :initform nil))
  (:documentation "Base condition for substrate operations"))

(define-condition substrate-error (substrate-condition error)
  ()
  (:report (lambda (c s)
             (format s "Substrate error~@[ (entity: ~A)~]: ~A"
                     (condition-entity-id c)
                     (substrate-condition-message c))))
  (:documentation "Substrate error condition"))

;;; Validation error with restarts for schema mismatches
(define-condition substrate-validation-error (substrate-error)
  ((expected-type :initarg :expected-type :reader validation-expected-type
                  :initform nil)
   (actual-value :initarg :actual-value :reader validation-actual-value
                 :initform nil))
  (:report (lambda (c s)
             (format s "Validation error for ~A: expected ~A, got ~A"
                     (condition-attribute c)
                     (validation-expected-type c)
                     (type-of (validation-actual-value c)))))
  (:documentation "Schema validation error with expected type and actual value"))

;;; Unknown entity type with classification restarts
(define-condition unknown-entity-type (substrate-condition)
  ((attributes :initarg :attributes :reader unknown-type-attributes
               :initform nil))
  (:report (lambda (c s)
             (format s "Unknown entity type for entity ~A with attributes: ~A"
                     (condition-entity-id c)
                     (unknown-type-attributes c))))
  (:documentation "Signaled when an entity's type is not registered"))
