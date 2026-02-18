;;;; class.lisp - SKEL class definition macro
;;;; Defines schemas as CLOS classes with metadata for prompt generation

(in-package #:autopoiesis.skel)

;;; --------------------------------------------------------------------------
;;; Conditions (skel-error defined in types.lisp, not duplicated here)
;;; --------------------------------------------------------------------------

(define-condition skel-class-error (skel-error)
  ((class-name :initarg :class-name :reader skel-error-class-name))
  (:report (lambda (condition stream)
             (format stream "SKEL class error for ~A: ~A"
                     (skel-error-class-name condition)
                     (skel-error-message condition))))
  (:documentation "Signaled when there's an error with SKEL class definition."))

;;; --------------------------------------------------------------------------
;;; SKEL Slot Metadata
;;; --------------------------------------------------------------------------

(defclass skel-slot-definition ()
  ((slot-name
    :initarg :slot-name
    :reader skel-slot-name
    :documentation "The name of the slot.")
   (skel-type
    :initarg :skel-type
    :initform 't
    :reader skel-slot-type
    :documentation "The SKEL type specifier for this slot.")
   (description
    :initarg :description
    :initform nil
    :reader skel-slot-description
    :documentation "Human-readable description for prompt generation.")
   (required-p
    :initarg :required-p
    :initform nil
    :reader skel-slot-required-p
    :documentation "Whether this slot is required (non-nil value expected).")
   (default-value
    :initarg :default-value
    :initform nil
    :reader skel-slot-default-value
    :documentation "Default value if not provided by LLM.")
   (json-key
    :initarg :json-key
    :initform nil
    :reader skel-slot-json-key
    :documentation "JSON key name for serialization (defaults to slot-name)."))
  (:documentation "Metadata for a SKEL class slot."))

(defun skel-slot-effective-json-key (slot-def)
  "Get the effective JSON key for serialization."
  (or (skel-slot-json-key slot-def)
      (lisp-name-to-json-key (skel-slot-name slot-def))))

(defun lisp-name-to-json-key (name)
  "Convert a Lisp symbol name to JSON camelCase key."
  (let* ((str (string-downcase (symbol-name name)))
         (parts (ppcre:split "-" str)))
    (format nil "~A~{~:(~A~)~}"
            (first parts)
            (rest parts))))

;;; --------------------------------------------------------------------------
;;; SKEL Class Metadata
;;; --------------------------------------------------------------------------

(defclass skel-class-metadata ()
  ((class-name
    :initarg :class-name
    :reader skel-class-name
    :documentation "The name of the SKEL class.")
   (slots
    :initarg :slots
    :initform nil
    :reader skel-class-slots
    :documentation "List of SKEL-SLOT-DEFINITION objects.")
   (documentation
    :initarg :documentation
    :initform nil
    :reader skel-class-documentation
    :documentation "Class documentation for prompt generation.")
   (superclasses
    :initarg :superclasses
    :initform nil
    :reader skel-class-superclasses
    :documentation "List of SKEL superclass names."))
  (:documentation "Metadata stored for each SKEL class."))

;;; --------------------------------------------------------------------------
;;; SKEL Class Registry
;;; --------------------------------------------------------------------------

(defvar *skel-classes* (make-hash-table :test 'eq)
  "Registry mapping class names to their SKEL metadata.")

(defun register-skel-class (metadata)
  "Register a SKEL class metadata object."
  (setf (gethash (skel-class-name metadata) *skel-classes*) metadata))

(defun get-skel-class (name)
  "Get the SKEL metadata for a class by name."
  (gethash name *skel-classes*))

(defun skel-class-p (name)
  "Return T if NAME is a registered SKEL class."
  (not (null (get-skel-class name))))

(defun list-skel-classes ()
  "Return a list of all registered SKEL class names."
  (loop for name being the hash-keys of *skel-classes*
        collect name))

;;; --------------------------------------------------------------------------
;;; Slot Spec Parsing
;;; --------------------------------------------------------------------------

(defun parse-slot-spec (slot-spec)
  "Parse a slot specification from define-skel-class syntax."
  (destructuring-bind (slot-name &key (type t) description required default json-key)
      slot-spec
    (make-instance 'skel-slot-definition
                   :slot-name slot-name
                   :skel-type type
                   :description description
                   :required-p required
                   :default-value default
                   :json-key json-key)))

(defun slot-def-to-defclass-slot (slot-def)
  "Convert a SKEL-SLOT-DEFINITION to a DEFCLASS slot specification."
  (let ((slot-name (skel-slot-name slot-def))
        (default (skel-slot-default-value slot-def)))
    `(,slot-name
      :initarg ,(intern (symbol-name slot-name) :keyword)
      :initform ,default
      :accessor ,slot-name)))

;;; --------------------------------------------------------------------------
;;; The define-skel-class Macro
;;; --------------------------------------------------------------------------

(defmacro define-skel-class (name superclasses slot-specs &rest options)
  "Define a SKEL class - a CLOS class with metadata for LLM structured output."
  (let* ((parsed-slots (mapcar #'parse-slot-spec slot-specs))
         (defclass-slots (mapcar #'slot-def-to-defclass-slot parsed-slots))
         (doc (second (assoc :documentation options))))
    `(progn
       (defclass ,name ,superclasses
         ,defclass-slots
         ,@(when doc `((:documentation ,doc))))

       (register-skel-class
        (make-instance 'skel-class-metadata
                       :class-name ',name
                       :superclasses ',superclasses
                       :documentation ,doc
                       :slots (list ,@(mapcar (lambda (slot)
                                               `(make-instance 'skel-slot-definition
                                                               :slot-name ',(skel-slot-name slot)
                                                               :skel-type ',(skel-slot-type slot)
                                                               :description ,(skel-slot-description slot)
                                                               :required-p ,(skel-slot-required-p slot)
                                                               :default-value ,(skel-slot-default-value slot)
                                                               :json-key ,(skel-slot-json-key slot)))
                                             parsed-slots))))

       ',name)))

;;; --------------------------------------------------------------------------
;;; Introspection Utilities
;;; --------------------------------------------------------------------------

(defun get-skel-slot (class-name slot-name)
  "Get the SKEL slot definition for a specific slot in a class."
  (let ((metadata (get-skel-class class-name)))
    (when metadata
      (find slot-name (skel-class-slots metadata)
            :key #'skel-slot-name))))

(defun skel-class-required-slots (class-name)
  "Return a list of required slot names for a SKEL class."
  (let ((metadata (get-skel-class class-name)))
    (when metadata
      (loop for slot in (skel-class-slots metadata)
            when (skel-slot-required-p slot)
            collect (skel-slot-name slot)))))

(defun skel-class-slot-names (class-name)
  "Return a list of all slot names for a SKEL class."
  (let ((metadata (get-skel-class class-name)))
    (when metadata
      (mapcar #'skel-slot-name (skel-class-slots metadata)))))

;;; --------------------------------------------------------------------------
;;; Instance Creation Utilities
;;; --------------------------------------------------------------------------

(defun make-skel-instance (class-name &rest initargs)
  "Create an instance of a SKEL class with the given initargs."
  (let ((metadata (get-skel-class class-name)))
    (unless metadata
      (error 'skel-class-error
             :class-name class-name
             :message "Not a registered SKEL class"))
    (dolist (slot (skel-class-slots metadata))
      (when (skel-slot-required-p slot)
        (let* ((slot-name (skel-slot-name slot))
               (key (intern (symbol-name slot-name) :keyword)))
          (unless (getf initargs key)
            (error 'skel-class-error
                   :class-name class-name
                   :message (format nil "Required slot ~A not provided" slot-name))))))
    (apply #'make-instance class-name initargs)))

(defun skel-instance-to-plist (instance)
  "Convert a SKEL class instance to a property list."
  (let* ((class-name (class-name (class-of instance)))
         (metadata (get-skel-class class-name)))
    (unless metadata
      (error 'skel-class-error
             :class-name class-name
             :message "Not a registered SKEL class"))
    (loop for slot in (skel-class-slots metadata)
          for slot-name = (skel-slot-name slot)
          for json-key = (skel-slot-effective-json-key slot)
          collect (intern json-key :keyword)
          collect (slot-value instance slot-name))))

;;; --------------------------------------------------------------------------
;;; Type Validation and Coercion
;;; --------------------------------------------------------------------------

(defun primitive-type-p (type-spec)
  "Return T if TYPE-SPEC is a primitive type symbol."
  (member type-spec '(string integer float boolean t nil null)))

(defun validate-slot-value (value type-spec &key (allow-nil t))
  "Validate VALUE against TYPE-SPEC."
  (cond
    ((null value)
     (if allow-nil
         t
         (error 'skel-class-error
                :class-name nil
                :message "Value cannot be nil")))
    ((eq type-spec t) t)
    ((eq type-spec 'string)
     (if (stringp value) t
         (error 'skel-class-error
                :class-name nil
                :message (format nil "Expected string, got ~A" (type-of value)))))
    ((eq type-spec 'integer)
     (if (integerp value) t
         (error 'skel-class-error
                :class-name nil
                :message (format nil "Expected integer, got ~A" (type-of value)))))
    ((eq type-spec 'float)
     (if (floatp value) t
         (error 'skel-class-error
                :class-name nil
                :message (format nil "Expected float, got ~A" (type-of value)))))
    ((eq type-spec 'boolean)
     (if (or (eq value t) (eq value nil)) t
         (error 'skel-class-error
                :class-name nil
                :message (format nil "Expected boolean, got ~A" (type-of value)))))
    ((or (eq type-spec 'null) (eq type-spec nil))
     (if (null value) t
         (error 'skel-class-error
                :class-name nil
                :message (format nil "Expected null, got ~A" (type-of value)))))
    ((and (consp type-spec) (eq (car type-spec) 'or))
     (let ((valid nil))
       (dolist (subtype (cdr type-spec))
         (handler-case
             (when (validate-slot-value value subtype :allow-nil allow-nil)
               (setf valid t)
               (return))
           (skel-class-error () nil)))
       (if valid t
           (error 'skel-class-error
                  :class-name nil
                  :message (format nil "Value ~S does not match any type in ~S"
                                   value type-spec)))))
    ((and (consp type-spec) (eq (car type-spec) 'list-of))
     (if (listp value)
         (let ((element-type (cadr type-spec)))
           (dolist (elem value t)
             (validate-slot-value elem element-type :allow-nil nil)))
         (error 'skel-class-error
                :class-name nil
                :message (format nil "Expected list, got ~A" (type-of value)))))
    ((and (symbolp type-spec) (skel-class-p type-spec))
     (if (typep value type-spec) t
         (error 'skel-class-error
                :class-name type-spec
                :message (format nil "Expected ~A, got ~A" type-spec (type-of value)))))
    (t t)))

(defun coerce-slot-value (value type-spec)
  "Attempt to coerce VALUE to TYPE-SPEC."
  (cond
    ((null value) nil)
    ((eq type-spec t) value)
    ((eq type-spec 'string)
     (if (stringp value)
         value
         (princ-to-string value)))
    ((eq type-spec 'integer)
     (etypecase value
       (integer value)
       (float (round value))
       (string (parse-integer value :junk-allowed nil))))
    ((eq type-spec 'float)
     (etypecase value
       (float value)
       (integer (float value))
       (string (read-from-string value))))
    ((eq type-spec 'boolean)
     (etypecase value
       (boolean value)
       (string (cond
                 ((member value '("true" "yes" "1" "t") :test #'string-equal) t)
                 ((member value '("false" "no" "0" "nil" "f") :test #'string-equal) nil)
                 (t (error 'skel-class-error
                           :class-name nil
                           :message (format nil "Cannot coerce ~S to boolean" value)))))))
    (t value)))

;;; --------------------------------------------------------------------------
;;; Prompt Generation Utilities
;;; --------------------------------------------------------------------------

(defun format-type-for-prompt (type-spec)
  "Format a type specifier for human-readable prompt generation."
  (cond
    ((eq type-spec t) "any")
    ((eq type-spec 'string) "string")
    ((eq type-spec 'integer) "integer")
    ((eq type-spec 'float) "number")
    ((eq type-spec 'boolean) "boolean")
    ((eq type-spec 'null) "null")
    ((and (consp type-spec) (eq (car type-spec) 'or))
     (format nil "~{~A~^ or ~}" (mapcar #'format-type-for-prompt (cdr type-spec))))
    ((and (consp type-spec) (eq (car type-spec) 'list-of))
     (format nil "array of ~A" (format-type-for-prompt (cadr type-spec))))
    ((and (symbolp type-spec) (skel-class-p type-spec))
     (format nil "~A object" (string-downcase (symbol-name type-spec))))
    (t (string-downcase (princ-to-string type-spec)))))

(defun format-slot-for-prompt (slot-def &key (include-type t) (include-required t))
  "Format a slot definition for prompt generation."
  (with-output-to-string (s)
    (format s "~A" (skel-slot-effective-json-key slot-def))
    (when include-type
      (format s " (~A)" (format-type-for-prompt (skel-slot-type slot-def))))
    (when (and include-required (skel-slot-required-p slot-def))
      (format s " [required]"))
    (when (skel-slot-description slot-def)
      (format s ": ~A" (skel-slot-description slot-def)))))

(defun format-class-schema (class-name &key (style :text) (include-docs t))
  "Generate a schema description for a SKEL class."
  (let ((metadata (get-skel-class class-name)))
    (unless metadata
      (return-from format-class-schema nil))
    (with-output-to-string (s)
      (case style
        (:text
         (format s "~A" (string-downcase (symbol-name class-name)))
         (when (and include-docs (skel-class-documentation metadata))
           (format s ": ~A" (skel-class-documentation metadata)))
         (format s "~%")
         (dolist (slot (skel-class-slots metadata))
           (format s "  - ~A~%" (format-slot-for-prompt slot))))

        (:json
         (format s "{~%")
         (let ((slots (skel-class-slots metadata)))
           (loop for slot in slots
                 for i from 0
                 do (format s "  \"~A\": <~A>"
                            (skel-slot-effective-json-key slot)
                            (format-type-for-prompt (skel-slot-type slot)))
                    (when (skel-slot-description slot)
                      (format s "  // ~A" (skel-slot-description slot)))
                    (when (< i (1- (length slots)))
                      (format s ","))
                    (format s "~%")))
         (format s "}"))

        (:brief
         (format s "~A: " (string-downcase (symbol-name class-name)))
         (format s "~{~A~^, ~}"
                 (mapcar (lambda (slot)
                           (format nil "~A:~A"
                                   (skel-slot-effective-json-key slot)
                                   (format-type-for-prompt (skel-slot-type slot))))
                         (skel-class-slots metadata))))))))

;;; --------------------------------------------------------------------------
;;; Advanced Introspection Functions
;;; --------------------------------------------------------------------------

(defun skel-class-slots-of-type (class-name type-spec &key (exact nil))
  "Return slots from CLASS-NAME that match TYPE-SPEC."
  (let ((metadata (get-skel-class class-name)))
    (unless metadata
      (return-from skel-class-slots-of-type nil))
    (loop for slot in (skel-class-slots metadata)
          when (if exact
                   (equal (skel-slot-type slot) type-spec)
                   (type-matches-p (skel-slot-type slot) type-spec))
          collect slot)))

(defun type-matches-p (slot-type target-type)
  "Check if SLOT-TYPE matches or contains TARGET-TYPE."
  (cond
    ((equal slot-type target-type) t)
    ((and (consp slot-type) (eq (car slot-type) 'or))
     (member target-type (cdr slot-type) :test #'equal))
    ((and (consp slot-type) (eq (car slot-type) 'list-of))
     (equal (cadr slot-type) target-type))
    (t nil)))

(defun skel-class-slots-with-description (class-name &key (pattern nil))
  "Return slots from CLASS-NAME that have descriptions."
  (let ((metadata (get-skel-class class-name)))
    (unless metadata
      (return-from skel-class-slots-with-description nil))
    (loop for slot in (skel-class-slots metadata)
          when (and (skel-slot-description slot)
                    (or (null pattern)
                        (search pattern (skel-slot-description slot)
                                :test #'char-equal)))
          collect slot)))

(defun skel-class-optional-slots (class-name)
  "Return a list of optional (non-required) slot names for a SKEL class."
  (let ((metadata (get-skel-class class-name)))
    (when metadata
      (loop for slot in (skel-class-slots metadata)
            unless (skel-slot-required-p slot)
            collect (skel-slot-name slot)))))

(defun skel-class-slots-with-defaults (class-name)
  "Return slots that have explicit default values."
  (let ((metadata (get-skel-class class-name)))
    (when metadata
      (loop for slot in (skel-class-slots metadata)
            when (skel-slot-default-value slot)
            collect slot))))

(defun skel-slot-metadata (class-name slot-name)
  "Return a plist of all metadata for a specific slot."
  (let ((slot (get-skel-slot class-name slot-name)))
    (when slot
      (list :name (skel-slot-name slot)
            :type (skel-slot-type slot)
            :description (skel-slot-description slot)
            :required (skel-slot-required-p slot)
            :default (skel-slot-default-value slot)
            :json-key (skel-slot-effective-json-key slot)))))

(defun skel-class-metadata-plist (class-name)
  "Return a plist of all metadata for a SKEL class."
  (let ((metadata (get-skel-class class-name)))
    (when metadata
      (list :name (skel-class-name metadata)
            :documentation (skel-class-documentation metadata)
            :superclasses (skel-class-superclasses metadata)
            :slots (mapcar (lambda (slot)
                             (skel-slot-metadata class-name (skel-slot-name slot)))
                           (skel-class-slots metadata))))))

;;; --------------------------------------------------------------------------
;;; JSON Schema Generation
;;; --------------------------------------------------------------------------

(defun type-to-json-schema (type-spec)
  "Convert a SKEL type specifier to a JSON Schema type definition."
  (cond
    ((eq type-spec t) '(("type" . "any")))
    ((eq type-spec 'string) '(("type" . "string")))
    ((eq type-spec 'integer) '(("type" . "integer")))
    ((eq type-spec 'float) '(("type" . "number")))
    ((eq type-spec 'boolean) '(("type" . "boolean")))
    ((or (eq type-spec 'null) (eq type-spec nil))
     '(("type" . "null")))
    ((and (consp type-spec) (eq (car type-spec) 'or))
     `(("oneOf" . ,(mapcar #'type-to-json-schema (cdr type-spec)))))
    ((and (consp type-spec) (eq (car type-spec) 'list-of))
     `(("type" . "array")
       ("items" . ,(type-to-json-schema (cadr type-spec)))))
    ((and (symbolp type-spec) (skel-class-p type-spec))
     (skel-class-to-json-schema type-spec))
    (t '(("type" . "any")))))

(defun skel-class-to-json-schema (class-name)
  "Generate a JSON Schema representation of a SKEL class."
  (let ((metadata (get-skel-class class-name)))
    (unless metadata
      (return-from skel-class-to-json-schema nil))
    (let ((properties nil)
          (required nil))
      (dolist (slot (skel-class-slots metadata))
        (let ((prop-def (type-to-json-schema (skel-slot-type slot))))
          (when (skel-slot-description slot)
            (push (cons "description" (skel-slot-description slot)) prop-def))
          (when (skel-slot-default-value slot)
            (push (cons "default" (skel-slot-default-value slot)) prop-def))
          (push (cons (skel-slot-effective-json-key slot) prop-def) properties)
          (when (skel-slot-required-p slot)
            (push (skel-slot-effective-json-key slot) required))))
      `(("type" . "object")
        ("properties" . ,(nreverse properties))
        ,@(when required
            `(("required" . ,(nreverse required))))
        ,@(when (skel-class-documentation metadata)
            `(("description" . ,(skel-class-documentation metadata))))))))
