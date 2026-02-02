;;;; capability.lisp - Capability system
;;;;
;;;; Capabilities are named functions that agents can invoke.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Capability Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass capability ()
  ((name :initarg :name
         :accessor capability-name
         :documentation "Unique name for this capability")
   (function :initarg :function
             :accessor capability-function
             :documentation "Function to invoke")
   (permissions :initarg :permissions
                :accessor capability-permissions
                :initform nil
                :documentation "Required permissions")
   (description :initarg :description
                :accessor capability-description
                :initform ""
                :documentation "Human-readable description"))
  (:documentation "A capability that an agent can invoke"))

(defun make-capability (name function &key permissions description)
  "Create a new capability."
  (make-instance 'capability
                 :name name
                 :function function
                 :permissions permissions
                 :description (or description "")))

;;; ═══════════════════════════════════════════════════════════════════
;;; Global Capability Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *capability-registry* (make-hash-table :test 'equal)
  "Global registry of available capabilities.")

(defun register-capability (capability &key (registry *capability-registry*))
  "Register a capability in the registry."
  (setf (gethash (capability-name capability) registry) capability))

(defun unregister-capability (name &key (registry *capability-registry*))
  "Remove a capability from the registry."
  (remhash name registry))

(defun find-capability (name &key (registry *capability-registry*))
  "Find a capability by name."
  (gethash name registry))

(defun list-capabilities (&key (registry *capability-registry*))
  "List all registered capabilities."
  (loop for cap being the hash-values of registry
        collect cap))

(defun invoke-capability (name &rest args)
  "Invoke a capability by name with arguments."
  (let ((cap (find-capability name)))
    (unless cap
      (error 'autopoiesis.core:autopoiesis-error
             :message (format nil "Unknown capability: ~a" name)))
    (apply (capability-function cap) args)))
