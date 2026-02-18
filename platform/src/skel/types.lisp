;;;; types.lisp - Type system for skeleton LLM functions
;;;; Provides typed parsing and validation of LLM responses

(in-package #:autopoiesis.skel)

;;; ============================================================================
;;; Type Registry
;;; ============================================================================

(defvar *skel-types* (make-hash-table :test 'eq)
  "Registry of defined skeleton types.")

(defclass skel-type ()
  ((name
    :initarg :name
    :reader type-name
    :type symbol
    :documentation "The type name symbol")
   (parser
    :initarg :parser
    :reader type-parser
    :type function
    :documentation "Function to parse string -> value")
   (validator
    :initarg :validator
    :reader type-validator
    :type (or null function)
    :initform nil
    :documentation "Optional function to validate parsed value")
   (description
    :initarg :description
    :reader type-description
    :type string
    :initform ""
    :documentation "Human-readable description for prompts"))
  (:documentation "A skeleton type that can parse and validate LLM output."))

(defun register-skel-type (type)
  "Register a skel-type in the global registry."
  (setf (gethash (type-name type) *skel-types*) type))

(defun get-skel-type (name)
  "Retrieve a skel-type by name. Returns NIL if not found."
  (gethash name *skel-types*))

;;; ============================================================================
;;; Type Definition Macro
;;; ============================================================================

(defmacro define-skel-type (name (&key description) &body parser-body)
  "Define a new skeleton type with a parser.

NAME is the type symbol.
DESCRIPTION is a human-readable string describing the type.
PARSER-BODY is code that takes a string INPUT and returns the parsed value."
  (let ((type-var (gensym "TYPE")))
    `(let ((,type-var (make-instance 'skel-type
                        :name ',name
                        :description ,(or description "")
                        :parser (lambda (input)
                                  (declare (ignorable input))
                                  ,@parser-body))))
       (register-skel-type ,type-var)
       ,type-var)))

;;; ============================================================================
;;; Conditions
;;; ============================================================================

(define-condition skel-error (error)
  ((message :initarg :message :reader skel-error-message))
  (:report (lambda (c s)
             (format s "Skeleton error: ~A" (skel-error-message c))))
  (:documentation "Base condition for skeleton function errors."))

(define-condition skel-type-error (skel-error)
  ((type-name :initarg :type-name :reader skel-type-error-type)
   (value :initarg :value :reader skel-type-error-value))
  (:report (lambda (c s)
             (format s "Type error for ~A: ~A~%Value: ~S"
                     (skel-type-error-type c)
                     (skel-error-message c)
                     (skel-type-error-value c))))
  (:documentation "Signaled when type parsing or validation fails."))

(define-condition skel-parse-error (skel-error)
  ((raw-response :initarg :raw-response :reader skel-parse-error-raw))
  (:report (lambda (c s)
             (format s "Parse error: ~A~%Raw response: ~S"
                     (skel-error-message c)
                     (skel-parse-error-raw c))))
  (:documentation "Signaled when LLM response cannot be parsed."))

(define-condition skel-validation-error (skel-error)
  ((value :initarg :value :reader skel-validation-error-value)
   (constraint :initarg :constraint :reader skel-validation-error-constraint))
  (:report (lambda (c s)
             (format s "Validation error: ~A~%Value: ~S~%Constraint: ~A"
                     (skel-error-message c)
                     (skel-validation-error-value c)
                     (skel-validation-error-constraint c))))
  (:documentation "Signaled when a value fails validation."))

;;; ============================================================================
;;; Built-in Types
;;; ============================================================================

(define-skel-type :string (:description "A text string")
  (string-trim '(#\Space #\Tab #\Newline #\Return) input))

(define-skel-type :integer (:description "An integer number")
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) input)))
    (handler-case
        (parse-integer trimmed :junk-allowed nil)
      (error ()
        (error 'skel-type-error
               :type-name :integer
               :value input
               :message (format nil "Cannot parse '~A' as integer" trimmed))))))

(define-skel-type :float (:description "A floating-point number")
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) input)))
    (handler-case
        (read-from-string trimmed)
      (error ()
        (error 'skel-type-error
               :type-name :float
               :value input
               :message (format nil "Cannot parse '~A' as float" trimmed))))))

(define-skel-type :boolean (:description "A boolean value (true/false)")
  (let ((trimmed (string-downcase
                  (string-trim '(#\Space #\Tab #\Newline #\Return) input))))
    (cond
      ((member trimmed '("true" "yes" "1" "t") :test #'string=) t)
      ((member trimmed '("false" "no" "0" "nil" "f") :test #'string=) nil)
      (t (error 'skel-type-error
                :type-name :boolean
                :value input
                :message (format nil "Cannot parse '~A' as boolean" trimmed))))))

(define-skel-type :json (:description "A JSON object or array")
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) input)))
    (handler-case
        (cl-json:decode-json-from-string trimmed)
      (error (e)
        (error 'skel-type-error
               :type-name :json
               :value input
               :message (format nil "Cannot parse JSON: ~A" e))))))

;;; ============================================================================
;;; Composite Type Constructors
;;; ============================================================================

(defun list-of (element-type)
  "Create a type for lists of ELEMENT-TYPE.
Returns a skel-type that parses JSON arrays."
  (let ((base-type (if (symbolp element-type)
                       (get-skel-type element-type)
                       element-type)))
    (unless base-type
      (error 'skel-type-error
             :type-name :list-of
             :value element-type
             :message "Unknown element type"))
    (make-instance 'skel-type
      :name (intern (format nil "LIST-OF-~A" (type-name base-type)) :keyword)
      :description (format nil "A list of ~A values" (type-description base-type))
      :parser (lambda (input)
                (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) input)))
                  (handler-case
                      (let ((parsed (cl-json:decode-json-from-string trimmed)))
                        (if (listp parsed)
                            (mapcar (lambda (item)
                                      (funcall (type-parser base-type)
                                               (if (stringp item)
                                                   item
                                                   (princ-to-string item))))
                                    parsed)
                            (error 'skel-type-error
                                   :type-name :list-of
                                   :value input
                                   :message "Expected a JSON array")))
                    (error ()
                      (let ((lines (remove-if #'(lambda (s) (zerop (length s)))
                                             (mapcar (lambda (s)
                                                       (string-trim '(#\Space #\Tab) s))
                                                     (uiop:split-string trimmed
                                                                        :separator '(#\Newline))))))
                        (mapcar (type-parser base-type) lines)))))))))

(defun one-of (&rest options)
  "Create a type that accepts one of the given OPTIONS."
  (make-instance 'skel-type
    :name :one-of
    :description (format nil "One of: ~{~A~^, ~}" options)
    :parser (lambda (input)
              (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) input)))
                (if (member trimmed options :test #'string-equal)
                    trimmed
                    (error 'skel-type-error
                           :type-name :one-of
                           :value input
                           :message (format nil "Expected one of ~{~A~^, ~}" options)))))))

(defun optional (base-type &optional default)
  "Create a type that allows nil/empty values with an optional DEFAULT."
  (let ((base (if (symbolp base-type)
                  (get-skel-type base-type)
                  base-type)))
    (unless base
      (error 'skel-type-error
             :type-name :optional
             :value base-type
             :message "Unknown base type"))
    (make-instance 'skel-type
      :name (intern (format nil "OPTIONAL-~A" (type-name base)) :keyword)
      :description (format nil "Optional ~A" (type-description base))
      :parser (lambda (input)
                (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) input)))
                  (if (or (zerop (length trimmed))
                          (string-equal trimmed "null")
                          (string-equal trimmed "nil"))
                      default
                      (funcall (type-parser base) trimmed)))))))

;;; ============================================================================
;;; Enum Type Definition
;;; ============================================================================

(defmacro define-skel-enum (name (&rest supers) values &rest options)
  "Define a SKEL enum type that accepts specific keyword values."
  (declare (ignore supers))
  (let* ((description (getf options :description "An enumeration type"))
         (value-list (if (listp (car values)) (car values) values))
         (value-strings (mapcar (lambda (v)
                                  (string-downcase (symbol-name v)))
                                value-list)))
    `(progn
       (register-skel-type
        (make-instance 'skel-type
          :name ',name
          :description ,description
          :parser (lambda (input)
                    (let ((trimmed (string-downcase
                                    (string-trim '(#\Space #\Tab #\Newline #\Return)
                                                 input))))
                      (cond
                        ,@(mapcar (lambda (kw)
                                    `((string= trimmed ,(string-downcase (symbol-name kw)))
                                      ,kw))
                                  value-list)
                        (t (error 'skel-type-error
                                  :type-name ',name
                                  :value input
                                  :message (format nil "Expected one of: ~{~A~^, ~}"
                                                   ',value-strings))))))))
       ',name)))

;;; ============================================================================
;;; Type Parsing Utility
;;; ============================================================================

(defun parse-typed-value (type-spec input)
  "Parse INPUT string according to TYPE-SPEC.
Returns the parsed value or signals skel-type-error."
  (let ((skel-type (etypecase type-spec
                     (keyword (or (get-skel-type type-spec)
                                  (error 'skel-type-error
                                         :type-name type-spec
                                         :value nil
                                         :message "Unknown type")))
                     (skel-type type-spec)
                     (cons (apply (car type-spec) (cdr type-spec))))))
    (funcall (type-parser skel-type) input)))
