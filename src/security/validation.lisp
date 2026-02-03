;;;; validation.lisp - Input validation framework for Autopoiesis
;;;;
;;;; Provides a declarative input validation system with type checking,
;;;; constraints, and sanitization.
;;;; Phase 10.2: Security Hardening

(in-package #:autopoiesis.security)

;;; ═══════════════════════════════════════════════════════════════════
;;; Validation Result
;;; ═══════════════════════════════════════════════════════════════════

(defclass validation-result ()
  ((valid-p :initarg :valid-p
            :accessor validation-result-valid-p
            :type boolean
            :documentation "Whether validation passed")
   (value :initarg :value
          :accessor validation-result-value
          :documentation "The validated (possibly coerced) value")
   (errors :initarg :errors
           :accessor validation-result-errors
           :initform nil
           :type list
           :documentation "List of validation error messages"))
  (:documentation "Result of input validation."))

(defun make-validation-result (valid-p value &optional errors)
  "Create a validation result."
  (make-instance 'validation-result
                 :valid-p valid-p
                 :value value
                 :errors (ensure-list errors)))

(defun validation-success (value)
  "Create a successful validation result."
  (make-validation-result t value nil))

(defun validation-failure (value &rest errors)
  "Create a failed validation result."
  (make-validation-result nil value errors))

(defmethod print-object ((result validation-result) stream)
  (print-unreadable-object (result stream :type t)
    (format stream "~:[INVALID~;VALID~]~@[ ~{~a~^, ~}~]"
            (validation-result-valid-p result)
            (validation-result-errors result))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Validation Condition
;;; ═══════════════════════════════════════════════════════════════════

(define-condition validation-error (error)
  ((input :initarg :input
          :reader validation-error-input
          :documentation "The input that failed validation")
   (spec :initarg :spec
         :reader validation-error-spec
         :documentation "The validation spec that was violated")
   (errors :initarg :errors
           :reader validation-error-errors
           :documentation "List of validation error messages"))
  (:documentation "Signaled when input validation fails.")
  (:report (lambda (condition stream)
             (format stream "Validation failed for input ~s: ~{~a~^; ~}"
                     (validation-error-input condition)
                     (validation-error-errors condition)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Core Validation Function
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-input (input spec)
  "Validate INPUT against SPEC.
   
   SPEC is a list starting with a type keyword, followed by constraint options.
   
   Supported specs:
     (:string &key max-length min-length pattern allow-empty)
     (:integer &key min max)
     (:number &key min max)
     (:boolean)
     (:keyword &key options)
     (:symbol &key package)
     (:list &key element-type min-length max-length)
     (:plist &key required-keys optional-keys key-specs)
     (:alist &key required-keys optional-keys key-specs)
     (:one-of &key options)
     (:any)
     (:and &rest specs) - all specs must pass
     (:or &rest specs) - at least one spec must pass
     (:not spec) - spec must fail
     (:nullable spec) - NIL or spec must pass
   
   Arguments:
     input - The value to validate
     spec  - Validation specification
   
   Returns: validation-result object"
  (let ((type (first spec))
        (options (rest spec)))
    (case type
      (:string (validate-string input options))
      (:integer (validate-integer input options))
      (:number (validate-number input options))
      (:boolean (validate-boolean input options))
      (:keyword (validate-keyword input options))
      (:symbol (validate-symbol input options))
      (:list (validate-list input options))
      (:plist (validate-plist input options))
      (:alist (validate-alist input options))
      (:one-of (validate-one-of input options))
      (:any (validation-success input))
      (:and (validate-and input options))
      (:or (validate-or input options))
      (:not (validate-not input options))
      (:nullable (validate-nullable input options))
      (t (validation-failure input (format nil "Unknown validation type: ~s" type))))))

(defun valid-p (input spec)
  "Predicate: check if INPUT is valid according to SPEC."
  (validation-result-valid-p (validate-input input spec)))

;;; ═══════════════════════════════════════════════════════════════════
;;; String Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-string (input options)
  "Validate a string input."
  (let ((max-length (getf options :max-length))
        (min-length (getf options :min-length 0))
        (pattern (getf options :pattern))
        (allow-empty (getf options :allow-empty t))
        (errors nil))
    
    ;; Type check
    (unless (stringp input)
      (return-from validate-string
        (validation-failure input "Expected a string")))
    
    ;; Empty check
    (when (and (zerop (length input)) (not allow-empty))
      (push "String cannot be empty" errors))
    
    ;; Length checks
    (when (and min-length (< (length input) min-length))
      (push (format nil "String must be at least ~d characters" min-length) errors))
    
    (when (and max-length (> (length input) max-length))
      (push (format nil "String must be at most ~d characters" max-length) errors))
    
    ;; Pattern check
    (when (and pattern (not (cl-ppcre:scan pattern input)))
      (push (format nil "String does not match pattern ~s" pattern) errors))
    
    (if errors
        (apply #'validation-failure input (nreverse errors))
        (validation-success input))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Numeric Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-integer (input options)
  "Validate an integer input."
  (let ((min (getf options :min))
        (max (getf options :max))
        (errors nil))
    
    ;; Type check
    (unless (integerp input)
      (return-from validate-integer
        (validation-failure input "Expected an integer")))
    
    ;; Range checks
    (when (and min (< input min))
      (push (format nil "Integer must be at least ~d" min) errors))
    
    (when (and max (> input max))
      (push (format nil "Integer must be at most ~d" max) errors))
    
    (if errors
        (apply #'validation-failure input (nreverse errors))
        (validation-success input))))

(defun validate-number (input options)
  "Validate a numeric input (integer or float)."
  (let ((min (getf options :min))
        (max (getf options :max))
        (errors nil))
    
    ;; Type check
    (unless (numberp input)
      (return-from validate-number
        (validation-failure input "Expected a number")))
    
    ;; Range checks
    (when (and min (< input min))
      (push (format nil "Number must be at least ~a" min) errors))
    
    (when (and max (> input max))
      (push (format nil "Number must be at most ~a" max) errors))
    
    (if errors
        (apply #'validation-failure input (nreverse errors))
        (validation-success input))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Boolean Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-boolean (input options)
  "Validate a boolean input."
  (declare (ignore options))
  ;; In Common Lisp, NIL is false and everything else is true
  ;; But for strict boolean validation, we only accept T or NIL
  (if (or (eq input t) (eq input nil))
      (validation-success input)
      (validation-failure input "Expected T or NIL")))

;;; ═══════════════════════════════════════════════════════════════════
;;; Symbol Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-keyword (input options)
  "Validate a keyword input."
  (let ((allowed-options (getf options :options)))
    
    ;; Type check
    (unless (keywordp input)
      (return-from validate-keyword
        (validation-failure input "Expected a keyword")))
    
    ;; Options check
    (when (and allowed-options (not (member input allowed-options)))
      (return-from validate-keyword
        (validation-failure input 
                           (format nil "Keyword must be one of: ~{~s~^, ~}" 
                                   allowed-options))))
    
    (validation-success input)))

(defun validate-symbol (input options)
  "Validate a symbol input."
  (let ((package-name (getf options :package)))
    
    ;; Type check
    (unless (symbolp input)
      (return-from validate-symbol
        (validation-failure input "Expected a symbol")))
    
    ;; Package check
    (when package-name
      (let ((pkg (symbol-package input)))
        (unless (and pkg (string-equal (package-name pkg) package-name))
          (return-from validate-symbol
            (validation-failure input 
                               (format nil "Symbol must be in package ~a" 
                                       package-name))))))
    
    (validation-success input)))

;;; ═══════════════════════════════════════════════════════════════════
;;; List Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-list (input options)
  "Validate a list input."
  (let ((element-spec (getf options :element-type))
        (min-length (getf options :min-length))
        (max-length (getf options :max-length))
        (errors nil))
    
    ;; Type check
    (unless (listp input)
      (return-from validate-list
        (validation-failure input "Expected a list")))
    
    ;; Length checks
    (when (and min-length (< (length input) min-length))
      (push (format nil "List must have at least ~d elements" min-length) errors))
    
    (when (and max-length (> (length input) max-length))
      (push (format nil "List must have at most ~d elements" max-length) errors))
    
    ;; Element validation
    (when element-spec
      (loop for element in input
            for i from 0
            do (let ((result (validate-input element element-spec)))
                 (unless (validation-result-valid-p result)
                   (push (format nil "Element ~d: ~{~a~^, ~}" 
                                 i (validation-result-errors result))
                         errors)))))
    
    (if errors
        (apply #'validation-failure input (nreverse errors))
        (validation-success input))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Property List Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-plist (input options)
  "Validate a property list input."
  (let ((required-keys (getf options :required-keys))
        (optional-keys (getf options :optional-keys))
        (key-specs (getf options :key-specs))
        (errors nil))
    
    ;; Type check - must be a list with even length
    (unless (and (listp input) (evenp (length input)))
      (return-from validate-plist
        (validation-failure input "Expected a property list (even-length list)")))
    
    ;; Check required keys
    (dolist (key required-keys)
      (unless (getf input key)
        (push (format nil "Missing required key: ~s" key) errors)))
    
    ;; Check for unknown keys if optional-keys is specified
    (when optional-keys
      (let ((all-allowed (append required-keys optional-keys)))
        (loop for (key value) on input by #'cddr
              unless (member key all-allowed)
              do (push (format nil "Unknown key: ~s" key) errors))))
    
    ;; Validate key values against specs
    (when key-specs
      (loop for (key spec) on key-specs by #'cddr
            do (let ((value (getf input key)))
                 (when value
                   (let ((result (validate-input value spec)))
                     (unless (validation-result-valid-p result)
                       (push (format nil "Key ~s: ~{~a~^, ~}" 
                                     key (validation-result-errors result))
                             errors)))))))
    
    (if errors
        (apply #'validation-failure input (nreverse errors))
        (validation-success input))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Association List Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-alist (input options)
  "Validate an association list input."
  (let ((required-keys (getf options :required-keys))
        (optional-keys (getf options :optional-keys))
        (key-specs (getf options :key-specs))
        (errors nil))
    
    ;; Type check - must be a list of conses
    (unless (and (listp input) (every #'consp input))
      (return-from validate-alist
        (validation-failure input "Expected an association list")))
    
    ;; Check required keys
    (dolist (key required-keys)
      (unless (assoc key input :test #'equal)
        (push (format nil "Missing required key: ~s" key) errors)))
    
    ;; Check for unknown keys if optional-keys is specified
    (when optional-keys
      (let ((all-allowed (append required-keys optional-keys)))
        (dolist (pair input)
          (unless (member (car pair) all-allowed :test #'equal)
            (push (format nil "Unknown key: ~s" (car pair)) errors)))))
    
    ;; Validate key values against specs
    (when key-specs
      (loop for (key . spec) in key-specs
            do (let ((pair (assoc key input :test #'equal)))
                 (when pair
                   (let ((result (validate-input (cdr pair) spec)))
                     (unless (validation-result-valid-p result)
                       (push (format nil "Key ~s: ~{~a~^, ~}" 
                                     key (validation-result-errors result))
                             errors)))))))
    
    (if errors
        (apply #'validation-failure input (nreverse errors))
        (validation-success input))))

;;; ═══════════════════════════════════════════════════════════════════
;;; One-Of Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-one-of (input options)
  "Validate that input is one of the allowed options."
  (let ((allowed (getf options :options)))
    (if (member input allowed :test #'equal)
        (validation-success input)
        (validation-failure input 
                           (format nil "Must be one of: ~{~s~^, ~}" allowed)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Combinator Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-and (input specs)
  "Validate that input passes all specs."
  (let ((all-errors nil))
    (dolist (spec specs)
      (let ((result (validate-input input spec)))
        (unless (validation-result-valid-p result)
          (setf all-errors (append all-errors (validation-result-errors result))))))
    (if all-errors
        (apply #'validation-failure input all-errors)
        (validation-success input))))

(defun validate-or (input specs)
  "Validate that input passes at least one spec."
  (dolist (spec specs)
    (let ((result (validate-input input spec)))
      (when (validation-result-valid-p result)
        (return-from validate-or (validation-success input)))))
  (validation-failure input "Did not match any of the allowed types"))

(defun validate-not (input options)
  "Validate that input does NOT pass the spec."
  (let* ((spec (first options))
         (result (validate-input input spec)))
    (if (validation-result-valid-p result)
        (validation-failure input "Value matched forbidden pattern")
        (validation-success input))))

(defun validate-nullable (input options)
  "Validate that input is either NIL or passes the spec."
  (if (null input)
      (validation-success input)
      (let* ((spec (first options))
             (result (validate-input input spec)))
        result)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Validation Macro
;;; ═══════════════════════════════════════════════════════════════════

(defmacro with-validated-input ((var input spec &key (on-error :signal)) &body body)
  "Execute body with validated input bound to VAR.
   
   Arguments:
     var      - Variable to bind the validated value to
     input    - The input to validate
     spec     - Validation specification
     on-error - What to do on validation failure:
                :signal - Signal a validation-error (default)
                :nil    - Return NIL
                :values - Return (values nil errors)
   
   Usage:
     (with-validated-input (name user-input '(:string :max-length 100))
       (process-name name))"
  (let ((result-var (gensym "RESULT")))
    `(let ((,result-var (validate-input ,input ',spec)))
       (if (validation-result-valid-p ,result-var)
           (let ((,var (validation-result-value ,result-var)))
             ,@body)
           ,(case on-error
              (:signal
               `(error 'validation-error
                       :input ,input
                       :spec ',spec
                       :errors (validation-result-errors ,result-var)))
              (:nil
               `nil)
              (:values
               `(values nil (validation-result-errors ,result-var)))
              (t
               `(error 'validation-error
                       :input ,input
                       :spec ',spec
                       :errors (validation-result-errors ,result-var))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Input Sanitization
;;; ═══════════════════════════════════════════════════════════════════

(defun sanitize-string (input &key (max-length 10000) 
                                   (trim t)
                                   (remove-control-chars t)
                                   (normalize-whitespace nil))
  "Sanitize a string input.
   
   Arguments:
     input                - String to sanitize
     max-length           - Truncate to this length
     trim                 - Remove leading/trailing whitespace
     remove-control-chars - Remove control characters (except newline, tab)
     normalize-whitespace - Replace multiple spaces with single space
   
   Returns: Sanitized string"
  (when (stringp input)
    (let ((result input))
      ;; Truncate
      (when (and max-length (> (length result) max-length))
        (setf result (subseq result 0 max-length)))
      
      ;; Trim whitespace
      (when trim
        (setf result (string-trim '(#\Space #\Tab #\Newline #\Return) result)))
      
      ;; Remove control characters
      (when remove-control-chars
        (setf result 
              (remove-if (lambda (c)
                           (and (< (char-code c) 32)
                                (not (member c '(#\Newline #\Tab)))))
                         result)))
      
      ;; Normalize whitespace
      (when normalize-whitespace
        (setf result (cl-ppcre:regex-replace-all "\\s+" result " ")))
      
      result)))

(defun sanitize-html (input)
  "Escape HTML special characters in a string.
   
   Arguments:
     input - String to escape
   
   Returns: HTML-safe string"
  (when (stringp input)
    (let ((result input))
      (setf result (cl-ppcre:regex-replace-all "&" result "&amp;"))
      (setf result (cl-ppcre:regex-replace-all "<" result "&lt;"))
      (setf result (cl-ppcre:regex-replace-all ">" result "&gt;"))
      (setf result (cl-ppcre:regex-replace-all "\"" result "&quot;"))
      (setf result (cl-ppcre:regex-replace-all "'" result "&#39;"))
      result)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Predefined Validation Specs
;;; ═══════════════════════════════════════════════════════════════════

(defparameter *validation-spec-agent-id*
  '(:string :min-length 1 :max-length 100 :pattern "^[a-zA-Z0-9_-]+$")
  "Validation spec for agent IDs.")

(defparameter *validation-spec-snapshot-id*
  '(:string :min-length 1 :max-length 100 :pattern "^[a-zA-Z0-9_-]+$")
  "Validation spec for snapshot IDs.")

(defparameter *validation-spec-branch-name*
  '(:string :min-length 1 :max-length 50 :pattern "^[a-zA-Z0-9_/-]+$")
  "Validation spec for branch names.")

(defparameter *validation-spec-capability-name*
  '(:keyword)
  "Validation spec for capability names.")

(defparameter *validation-spec-action*
  '(:keyword :options (:read :write :execute :delete :create :admin))
  "Validation spec for permission actions.")

(defparameter *validation-spec-resource-type*
  '(:keyword :options (:snapshot :agent :capability :extension :file :network :system))
  "Validation spec for resource types.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Batch Validation
;;; ═══════════════════════════════════════════════════════════════════

(defun validate-inputs (inputs-and-specs)
  "Validate multiple inputs against their specs.
   
   Arguments:
     inputs-and-specs - List of (name input spec) triples
   
   Returns: validation-result with combined errors"
  (let ((all-errors nil)
        (all-values nil))
    (dolist (triple inputs-and-specs)
      (destructuring-bind (name input spec) triple
        (let ((result (validate-input input spec)))
          (push (cons name (validation-result-value result)) all-values)
          (unless (validation-result-valid-p result)
            (dolist (err (validation-result-errors result))
              (push (format nil "~a: ~a" name err) all-errors))))))
    (if all-errors
        (apply #'validation-failure (nreverse all-values) (nreverse all-errors))
        (validation-success (nreverse all-values)))))
