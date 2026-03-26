;;;; partial.lisp - Partial type generation for SKEL streaming
;;;; Auto-generates partial-* classes where all fields are optional

(in-package #:autopoiesis.skel)

;;; --------------------------------------------------------------------------
;;; Partial Class Registry
;;; --------------------------------------------------------------------------

(defvar *partial-classes* (make-hash-table :test 'eq)
  "Registry mapping original class names to their partial class metadata.")

(defclass partial-class-metadata ()
  ((original-class
    :initarg :original-class
    :reader partial-original-class
    :documentation "The original SKEL class name this partial is derived from.")
   (partial-class-name
    :initarg :partial-class-name
    :reader partial-class-name
    :documentation "The name of the generated partial class.")
   (slots
    :initarg :slots
    :initform nil
    :reader partial-class-slots
    :documentation "List of SKEL-SLOT-DEFINITION objects (all optional).")
   (documentation
    :initarg :documentation
    :initform nil
    :reader partial-class-documentation
    :documentation "Class documentation."))
  (:documentation "Metadata for a generated partial class."))

(defun register-partial-class (metadata)
  "Register a partial class metadata object."
  (setf (gethash (partial-original-class metadata) *partial-classes*) metadata))

(defun get-partial-class (original-name)
  "Get the partial class metadata for an original SKEL class name."
  (gethash original-name *partial-classes*))

(defun partial-class-p (name)
  "Return T if NAME has a registered partial class."
  (not (null (get-partial-class name))))

(defun list-partial-classes ()
  "Return a list of all original class names with partial classes."
  (loop for name being the hash-keys of *partial-classes*
        collect name))

;;; --------------------------------------------------------------------------
;;; Partial Class Name Generation
;;; --------------------------------------------------------------------------

(defun make-partial-class-name (original-name)
  "Generate the partial class name from an original class name."
  (intern (format nil "PARTIAL-~A" (symbol-name original-name))
          (symbol-package original-name)))

(defun original-class-name-from-partial (partial-name)
  "Extract the original class name from a partial class name."
  (let ((name-str (symbol-name partial-name)))
    (if (and (> (length name-str) 8)
             (string= (subseq name-str 0 8) "PARTIAL-"))
        (intern (subseq name-str 8) (symbol-package partial-name))
        nil)))

;;; --------------------------------------------------------------------------
;;; Slot Transformation for Partials
;;; --------------------------------------------------------------------------

(defun make-partial-slot-def (original-slot)
  "Transform a slot definition to be optional for partial types."
  (make-instance 'skel-slot-definition
                 :slot-name (skel-slot-name original-slot)
                 :skel-type (make-optional-type (skel-slot-type original-slot))
                 :description (skel-slot-description original-slot)
                 :required-p nil
                 :default-value nil
                 :json-key (skel-slot-json-key original-slot)))

(defun make-optional-type (type-spec)
  "Wrap a type specification to be optional if not already."
  (cond
    ((and (consp type-spec)
          (eq (car type-spec) 'or)
          (member 'null (cdr type-spec)))
     type-spec)
    ((eq type-spec t)
     t)
    ((and (consp type-spec)
          (eq (car type-spec) 'list-of))
     `(or ,type-spec null))
    (t
     `(or ,type-spec null))))

(defun partial-slot-def-to-defclass-slot (slot-def)
  "Convert a partial SKEL-SLOT-DEFINITION to a DEFCLASS slot specification."
  (let ((slot-name (skel-slot-name slot-def)))
    `(,slot-name
      :initarg ,(intern (symbol-name slot-name) :keyword)
      :initform nil
      :accessor ,slot-name)))

;;; --------------------------------------------------------------------------
;;; Partial Instance Accessor Generic Functions
;;; --------------------------------------------------------------------------

(defgeneric partial-complete-p (instance)
  (:documentation "Return T if the partial instance is considered complete."))

(defgeneric (setf partial-complete-p) (value instance)
  (:documentation "Set the completion status of a partial instance."))

(defgeneric partial-fields-received (instance)
  (:documentation "Return the list of field names that have been parsed."))

(defgeneric (setf partial-fields-received) (value instance)
  (:documentation "Set the list of received fields for a partial instance."))

;;; --------------------------------------------------------------------------
;;; Partial Metadata Slots
;;; --------------------------------------------------------------------------

(defun make-partial-metadata-slots ()
  "Create the metadata slot specifications for partial classes."
  (list
   `(%complete-p
     :initarg :%complete-p
     :initform nil
     :accessor partial-complete-p
     :documentation "T when the partial object is considered complete.")
   `(%fields-received
     :initarg :%fields-received
     :initform nil
     :accessor partial-fields-received
     :documentation "List of field names that have been successfully parsed.")))

;;; --------------------------------------------------------------------------
;;; The define-partial-class Macro
;;; --------------------------------------------------------------------------

(defmacro define-partial-class (original-class-name)
  "Generate a partial class for an existing SKEL class."
  (let ((partial-name (make-partial-class-name original-class-name)))
    `(progn
       (unless (get-skel-class ',original-class-name)
         (error 'skel-class-error
                :class-name ',original-class-name
                :message "Cannot create partial: not a registered SKEL class"))

       (eval-when (:compile-toplevel :load-toplevel :execute)
         (let* ((original-metadata (get-skel-class ',original-class-name))
                (partial-slots (mapcar #'make-partial-slot-def
                                       (skel-class-slots original-metadata)))
                (defclass-slots (append
                                 (mapcar #'partial-slot-def-to-defclass-slot partial-slots)
                                 (make-partial-metadata-slots)))
                (doc (format nil "Auto-generated partial type for streaming ~A"
                             ',original-class-name)))

           (eval `(defclass ,',partial-name ()
                    ,defclass-slots
                    (:documentation ,doc)))

           (register-partial-class
            (make-instance 'partial-class-metadata
                           :original-class ',original-class-name
                           :partial-class-name ',partial-name
                           :documentation doc
                           :slots partial-slots))))

       ',partial-name)))

;;; --------------------------------------------------------------------------
;;; Auto-generation from SKEL Class
;;; --------------------------------------------------------------------------

(defun ensure-partial-class (class-name)
  "Ensure a partial class exists for the given SKEL class."
  (unless (get-skel-class class-name)
    (error 'skel-class-error
           :class-name class-name
           :message "Not a registered SKEL class"))
  (let ((partial-name (make-partial-class-name class-name)))
    (unless (get-partial-class class-name)
      (let* ((original-metadata (get-skel-class class-name))
             (partial-slots (mapcar #'make-partial-slot-def
                                    (skel-class-slots original-metadata)))
             (doc (format nil "Auto-generated partial type for streaming ~A" class-name)))
        (eval `(defclass ,partial-name ()
                 ,(append
                   (mapcar #'partial-slot-def-to-defclass-slot partial-slots)
                   (make-partial-metadata-slots))
                 (:documentation ,doc)))
        (register-partial-class
         (make-instance 'partial-class-metadata
                        :original-class class-name
                        :partial-class-name partial-name
                        :documentation doc
                        :slots partial-slots))))
    partial-name))

(defun get-partial-type (type-spec)
  "Get the partial type for a type specification."
  (cond
    ((and (symbolp type-spec) (get-skel-class type-spec))
     (ensure-partial-class type-spec))
    ((and (consp type-spec)
          (eq (car type-spec) 'list-of)
          (symbolp (cadr type-spec))
          (get-skel-class (cadr type-spec)))
     `(list-of ,(ensure-partial-class (cadr type-spec))))
    (t type-spec)))

;;; --------------------------------------------------------------------------
;;; Partial Instance Creation
;;; --------------------------------------------------------------------------

(defun make-partial-instance (class-name &rest initargs)
  "Create a partial instance for a SKEL class."
  (let ((partial-name (ensure-partial-class class-name)))
    (apply #'make-instance partial-name initargs)))

(defun partial-instance-p (object)
  "Return T if OBJECT is an instance of a partial class."
  (let ((class-name (class-name (class-of object))))
    (and (original-class-name-from-partial class-name)
         t)))

(defun partial-to-full (partial-instance)
  "Convert a partial instance to a full SKEL instance."
  (let* ((partial-class-name (class-name (class-of partial-instance)))
         (original-name (original-class-name-from-partial partial-class-name)))
    (unless original-name
      (error 'skel-class-error
             :class-name partial-class-name
             :message "Not a partial class instance"))
    (let* ((original-metadata (get-skel-class original-name))
           (initargs nil))
      (dolist (slot (skel-class-slots original-metadata))
        (let* ((slot-name (skel-slot-name slot))
               (key (intern (symbol-name slot-name) :keyword))
               (value (slot-value partial-instance slot-name)))
          (when (and (skel-slot-required-p slot) (null value))
            (error 'skel-class-error
                   :class-name original-name
                   :message (format nil "Required field ~A is missing" slot-name)))
          (push value initargs)
          (push key initargs)))
      (apply #'make-instance original-name initargs))))

;;; --------------------------------------------------------------------------
;;; Partial Update Utilities
;;; --------------------------------------------------------------------------

(defun update-partial-field (partial-instance field-name value)
  "Update a field in a partial instance and track it in %fields-received."
  (setf (slot-value partial-instance field-name) value)
  (pushnew field-name (partial-fields-received partial-instance))
  partial-instance)

(defun partial-field-received-p (partial-instance field-name)
  "Return T if the field has been received in the partial instance."
  (member field-name (partial-fields-received partial-instance)))

(defun partial-coverage (partial-instance)
  "Return the fraction of fields that have been received (0.0 to 1.0)."
  (let* ((partial-class-name (class-name (class-of partial-instance)))
         (original-name (original-class-name-from-partial partial-class-name))
         (original-metadata (get-skel-class original-name)))
    (if original-metadata
        (let ((total-slots (length (skel-class-slots original-metadata)))
              (received (length (partial-fields-received partial-instance))))
          (if (zerop total-slots)
              1.0
              (/ received total-slots)))
        0.0)))

(defun mark-partial-complete (partial-instance)
  "Mark a partial instance as complete."
  (setf (partial-complete-p partial-instance) t)
  partial-instance)
