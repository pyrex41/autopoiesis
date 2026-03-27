;;;; sap.lisp - Schema-Aligned Parsing (SAP) for LLM output
;;;; Implements preprocessing and JSON normalization for robust LLM response handling

(in-package #:autopoiesis.skel)

;;; ============================================================================
;;; Conditions
;;; ============================================================================

(define-condition sap-error (skel-error)
  ((input :initarg :input :reader sap-error-input
          :documentation "The input that caused the error")
   (reason :initarg :reason :reader sap-error-reason
           :documentation "Detailed reason for the error"))
  (:report (lambda (condition stream)
             (format stream "SAP error: ~A~%Reason: ~A~%Input: ~S"
                     (skel-error-message condition)
                     (sap-error-reason condition)
                     (sap-error-input condition))))
  (:documentation "Base condition for SAP processing errors."))

(define-condition sap-preprocessing-error (sap-error)
  ()
  (:report (lambda (condition stream)
             (format stream "SAP preprocessing error: ~A~%Reason: ~A~%Input excerpt: ~S"
                     (skel-error-message condition)
                     (sap-error-reason condition)
                     (subseq (sap-error-input condition) 0
                             (min 200 (length (sap-error-input condition)))))))
  (:documentation "Signaled when preprocessing of LLM output fails."))

;;; ============================================================================
;;; SAP Preprocessor - Markdown Fence Stripping
;;; ============================================================================

(defun strip-markdown-fences (text)
  "Remove markdown code fences from TEXT."
  (when (null text)
    (return-from strip-markdown-fences ""))
  (when (zerop (length text))
    (return-from strip-markdown-fences ""))
  (let ((fence-pattern "```(?:\\w*)?\\s*([\\s\\S]*?)\\s*```"))
    (if (ppcre:scan fence-pattern text)
        (let ((result (ppcre:regex-replace-all fence-pattern text "\\1")))
          (string-trim '(#\Space #\Tab #\Newline #\Return) result))
        (string-trim '(#\Space #\Tab #\Newline #\Return) text))))

;;; ============================================================================
;;; SAP Preprocessor - Chain-of-Thought Extraction
;;; ============================================================================

(defun find-structural-start (text)
  "Find the position of the first structural character in TEXT."
  (let ((brace-pos (position #\{ text))
        (bracket-pos (position #\[ text))
        (paren-pos (position #\( text)))
    (let ((positions (remove nil (list brace-pos bracket-pos paren-pos))))
      (when positions
        (apply #'min positions)))))

(defun looks-like-preamble-p (text start end)
  "Check if TEXT from START to END looks like chain-of-thought preamble."
  (when (and start end (> end start))
    (let ((excerpt (subseq text start (min end (+ start 200)))))
      (or (ppcre:scan "(?i)let me" excerpt)
          (ppcre:scan "(?i)i will" excerpt)
          (ppcre:scan "(?i)i'll" excerpt)
          (ppcre:scan "(?i)here is" excerpt)
          (ppcre:scan "(?i)here's" excerpt)
          (ppcre:scan "(?i)the \\w+ is" excerpt)
          (ppcre:scan "(?i)based on" excerpt)
          (ppcre:scan "(?i)analyzing" excerpt)
          (ppcre:scan "(?i)looking at" excerpt)
          (ppcre:scan "\\.\\s+[A-Z]" excerpt)))))

(defun extract-structured-portion (text)
  "Extract the structured data portion from TEXT, skipping chain-of-thought preamble."
  (when (null text)
    (return-from extract-structured-portion ""))
  (when (zerop (length text))
    (return-from extract-structured-portion ""))
  (let* ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) text))
         (struct-start (find-structural-start trimmed)))
    (cond
      ((null struct-start)
       trimmed)
      ((zerop struct-start)
       trimmed)
      ((looks-like-preamble-p trimmed 0 struct-start)
       (subseq trimmed struct-start))
      (t trimmed))))

;;; ============================================================================
;;; JSON Normalizer - Fix Unquoted Keys
;;; ============================================================================

(defun fix-unquoted-keys (text)
  "Fix unquoted JSON object keys in TEXT."
  (when (null text)
    (return-from fix-unquoted-keys ""))
  (ppcre:regex-replace-all
   "([{,]\\s*)([a-zA-Z_][a-zA-Z0-9_]*)\\s*:"
   text
   "\\1\"\\2\":"))

;;; ============================================================================
;;; JSON Normalizer - Fix Single Quotes
;;; ============================================================================

(defun fix-single-quotes (text)
  "Convert single-quoted strings to double-quoted strings in TEXT."
  (when (null text)
    (return-from fix-single-quotes ""))
  (let* ((temp-escaped (ppcre:regex-replace-all "\\\\'" text "\x00ESCAPED_SINGLE\x00"))
         (replaced (ppcre:regex-replace-all "'" temp-escaped "\""))
         (final (ppcre:regex-replace-all "\x00ESCAPED_SINGLE\x00" replaced "\\\\\"" )))
    final))

;;; ============================================================================
;;; JSON Normalizer - Fix Trailing Commas
;;; ============================================================================

(defun fix-trailing-commas (text)
  "Remove trailing commas before closing brackets in TEXT."
  (when (null text)
    (return-from fix-trailing-commas ""))
  (ppcre:regex-replace-all ",\\s*([}\\]])" text "\\1"))

;;; ============================================================================
;;; JSON Normalizer - Combined Normalization
;;; ============================================================================

(defun normalize-json-ish (text)
  "Apply all JSON normalization fixes to TEXT."
  (when (null text)
    (return-from normalize-json-ish ""))
  (when (zerop (length text))
    (return-from normalize-json-ish ""))
  (let* ((step1 (fix-unquoted-keys text))
         (step2 (fix-single-quotes step1))
         (step3 (fix-trailing-commas step2)))
    step3))

;;; ============================================================================
;;; Main SAP Preprocessor
;;; ============================================================================

(defun sap-preprocess (raw)
  "Preprocess raw LLM output for parsing."
  (when (null raw)
    (return-from sap-preprocess ""))
  (when (not (stringp raw))
    (error 'sap-preprocessing-error
           :message "Input must be a string"
           :reason "Expected string input"
           :input (princ-to-string raw)))
  (when (zerop (length raw))
    (return-from sap-preprocess ""))
  (handler-case
      (let* ((step1 (strip-markdown-fences raw))
             (step2 (extract-structured-portion step1))
             (step3 (normalize-json-ish step2)))
        step3)
    (error (e)
      (error 'sap-preprocessing-error
             :message "Failed to preprocess LLM output"
             :reason (princ-to-string e)
             :input (subseq raw 0 (min 500 (length raw)))))))

;;; ============================================================================
;;; Utility Functions
;;; ============================================================================

(defun sap-parse-json (preprocessed)
  "Parse preprocessed text as JSON."
  (when (or (null preprocessed) (zerop (length preprocessed)))
    (return-from sap-parse-json nil))
  (handler-case
      (cl-json:decode-json-from-string preprocessed)
    (error ()
      (error 'skel-parse-error
             :message "Failed to parse JSON"
             :raw-response preprocessed))))

(defun sap-preprocess-and-parse (raw)
  "Preprocess raw LLM output and parse as JSON in one step."
  (sap-parse-json (sap-preprocess raw)))

;;; ============================================================================
;;; SAP Type Coercer
;;; ============================================================================

(define-condition sap-coercion-error (sap-error)
  ((expected-type :initarg :expected-type :reader sap-coercion-expected-type
                  :documentation "The expected type for coercion")
   (actual-value :initarg :actual-value :reader sap-coercion-actual-value
                 :documentation "The actual value that failed coercion"))
  (:report (lambda (condition stream)
             (format stream "SAP coercion error: ~A~%Expected type: ~S~%Actual value: ~S~%Reason: ~A"
                     (skel-error-message condition)
                     (sap-coercion-expected-type condition)
                     (sap-coercion-actual-value condition)
                     (sap-error-reason condition))))
  (:documentation "Signaled when type coercion fails."))

(defun parse-integer-lenient (value)
  "Parse VALUE as an integer leniently."
  (etypecase value
    (null nil)
    (integer value)
    (float (truncate value))
    (ratio (truncate value))
    (string
     (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
       (when (zerop (length trimmed))
         (return-from parse-integer-lenient nil))
       (handler-case
           (let ((num (read-from-string trimmed)))
             (etypecase num
               (integer num)
               (float (truncate num))
               (ratio (truncate num))))
         (error ()
           (error 'sap-coercion-error
                  :message "Cannot parse as integer"
                  :expected-type :integer
                  :actual-value value
                  :reason (format nil "Value '~A' is not a valid number" trimmed)
                  :input value)))))))

(defun parse-float-lenient (value)
  "Parse VALUE as a float leniently."
  (etypecase value
    (null nil)
    (integer (float value))
    (float value)
    (ratio (float value))
    (string
     (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
       (when (zerop (length trimmed))
         (return-from parse-float-lenient nil))
       (handler-case
           (let ((num (read-from-string trimmed)))
             (etypecase num
               (number (float num))))
         (error ()
           (error 'sap-coercion-error
                  :message "Cannot parse as float"
                  :expected-type :float
                  :actual-value value
                  :reason (format nil "Value '~A' is not a valid number" trimmed)
                  :input value)))))))

(defun parse-boolean-lenient (value)
  "Parse VALUE as a boolean leniently."
  (etypecase value
    (null nil)
    ((eql t) t)
    ((eql :true) t)
    ((eql :false) nil)
    (integer (not (zerop value)))
    (string
     (let ((trimmed (string-downcase
                     (string-trim '(#\Space #\Tab #\Newline #\Return) value))))
       (cond
         ((zerop (length trimmed)) nil)
         ((member trimmed '("true" "yes" "1" "t" "on") :test #'string=) t)
         ((member trimmed '("false" "no" "0" "nil" "f" "off" "null") :test #'string=) nil)
         (t (error 'sap-coercion-error
                   :message "Cannot parse as boolean"
                   :expected-type :boolean
                   :actual-value value
                   :reason (format nil "Value '~A' is not a recognized boolean" trimmed)
                   :input value)))))))

(defun ensure-string (value)
  "Ensure VALUE is a string, converting if necessary."
  (etypecase value
    (null "")
    (string value)
    (symbol (symbol-name value))
    (number (princ-to-string value))
    (t (princ-to-string value))))

(defun ensure-list (value)
  "Ensure VALUE is a list."
  (etypecase value
    (null '())
    (list value)
    (t (list value))))

(defun coerce-to-type (value expected-type &key (strict nil))
  "Coerce VALUE to EXPECTED-TYPE."
  (cond
    ((null value)
     (cond
       ((and (consp expected-type) (eq (car expected-type) 'optional))
        (if (cddr expected-type)
            (caddr expected-type)
            nil))
       ((and (consp expected-type) (eq (car expected-type) 'or))
        (if (member 'null (cdr expected-type))
            nil
            (if strict
                (error 'sap-coercion-error
                       :message "Nil not allowed for this type"
                       :expected-type expected-type
                       :actual-value nil
                       :reason "Type does not accept null"
                       :input nil)
                nil)))
       (t nil)))

    ((eq expected-type :string)
     (ensure-string value))

    ((eq expected-type :integer)
     (parse-integer-lenient value))

    ((eq expected-type :float)
     (parse-float-lenient value))

    ((eq expected-type :boolean)
     (parse-boolean-lenient value))

    ((eq expected-type :json)
     value)

    ((eq expected-type 'string)
     (ensure-string value))

    ((eq expected-type 'integer)
     (parse-integer-lenient value))

    ((eq expected-type 'float)
     (parse-float-lenient value))

    ((eq expected-type 'boolean)
     (parse-boolean-lenient value))

    ((consp expected-type)
     (case (car expected-type)
       ((list-of)
        (let ((element-type (cadr expected-type)))
          (mapcar (lambda (item)
                    (coerce-to-type item element-type :strict strict))
                  (ensure-list value))))

       ((one-of)
        (let* ((options (cdr expected-type))
               (str-value (ensure-string value)))
          (if (member str-value options :test #'string-equal)
              str-value
              (if strict
                  (error 'sap-coercion-error
                         :message "Value not in enumeration"
                         :expected-type expected-type
                         :actual-value value
                         :reason (format nil "Expected one of: ~{~A~^, ~}" options)
                         :input value)
                  str-value))))

       ((optional)
        (let ((base-type (cadr expected-type))
              (default (caddr expected-type)))
          (if (or (null value)
                  (and (stringp value)
                       (or (zerop (length (string-trim '(#\Space #\Tab) value)))
                           (string-equal value "null")
                           (string-equal value "nil"))))
              default
              (coerce-to-type value base-type :strict strict))))

       ((or)
        (let ((types (cdr expected-type)))
          (dolist (type types)
            (handler-case
                (return-from coerce-to-type
                  (coerce-to-type value type :strict t))
              (sap-coercion-error ())))
          (let ((non-null-types (remove 'null types)))
            (if non-null-types
                (coerce-to-type value (car non-null-types) :strict strict)
                nil))))

       (otherwise value)))

    ((and (symbolp expected-type) (skel-class-p expected-type))
     (if (listp value)
         (sap-extract-with-schema value expected-type :strict strict)
         value))

    (t value)))

;;; ============================================================================
;;; SAP Extractor
;;; ============================================================================

(define-condition sap-extraction-error (sap-error)
  ((schema :initarg :schema :reader sap-extraction-schema
           :documentation "The schema extraction was attempted against")
   (missing-fields :initarg :missing-fields :reader sap-extraction-missing-fields
                   :initform nil
                   :documentation "Required fields that were missing"))
  (:report (lambda (condition stream)
             (format stream "SAP extraction error: ~A~%Schema: ~S~%Missing fields: ~S~%Reason: ~A"
                     (skel-error-message condition)
                     (sap-extraction-schema condition)
                     (sap-extraction-missing-fields condition)
                     (sap-error-reason condition))))
  (:documentation "Signaled when extraction against a schema fails."))

(defun json-key-to-lisp-name (key)
  "Convert a JSON key (string or keyword) to a Lisp symbol name."
  (let ((str (etypecase key
               (keyword (symbol-name key))
               (symbol (symbol-name key))
               (string key))))
    (let ((result (ppcre:regex-replace-all
                   "([a-z])([A-Z])"
                   str
                   "\\1-\\2")))
      (setf result (ppcre:regex-replace-all "_" result "-"))
      (intern (string-upcase result)))))

(defun find-json-value (alist key)
  "Find value for KEY in ALIST, trying various key formats."
  (let ((lisp-key (if (symbolp key) key (json-key-to-lisp-name key))))
    (or
     (cdr (assoc lisp-key alist))
     (let ((camel-key (intern (lisp-name-to-json-key lisp-key) :keyword)))
       (cdr (assoc camel-key alist)))
     (cdr (assoc lisp-key alist :test #'string-equal)))))

(defun sap-extract-slot (alist slot-def &key (strict nil))
  "Extract and coerce a single slot value from ALIST using SLOT-DEF metadata."
  (let* ((slot-name (skel-slot-name slot-def))
         (slot-type (skel-slot-type slot-def))
         (json-key (skel-slot-effective-json-key slot-def))
         (default (skel-slot-default-value slot-def))
         (raw-value (or (find-json-value alist slot-name)
                        (find-json-value alist (intern json-key :keyword))
                        (cdr (assoc (intern (string-upcase json-key) :keyword) alist)))))
    (if raw-value
        (let ((coerced (coerce-to-type raw-value slot-type :strict strict)))
          (multiple-value-bind (val warnings)
              (validate-slot-constraints coerced slot-def)
            (dolist (w warnings)
              (warn "~A" w))
            (values val t)))
        (values default nil))))

(defun sap-extract-with-schema (parsed-data class-name &key (strict nil) (validate-required t))
  "Extract data from PARSED-DATA (an alist) according to SKEL class schema."
  (let ((metadata (get-skel-class class-name)))
    (unless metadata
      (error 'sap-extraction-error
             :message "Unknown SKEL class"
             :schema class-name
             :reason (format nil "Class ~A is not a registered SKEL class" class-name)
             :input (princ-to-string parsed-data)))

    (let ((result '())
          (missing-required '()))
      (dolist (slot-def (skel-class-slots metadata))
        (multiple-value-bind (value found-p)
            (sap-extract-slot parsed-data slot-def :strict strict)
          (let ((slot-name (skel-slot-name slot-def))
                (slot-key (intern (symbol-name (skel-slot-name slot-def)) :keyword)))
            (when (and validate-required
                       (skel-slot-required-p slot-def)
                       (not found-p)
                       (null value))
              (push slot-name missing-required))
            (setf (getf result slot-key) value))))

      (when (and validate-required missing-required)
        (error 'sap-extraction-error
               :message "Missing required fields"
               :schema class-name
               :missing-fields (nreverse missing-required)
               :reason (format nil "Required fields not found: ~{~A~^, ~}"
                               (nreverse missing-required))
               :input (princ-to-string parsed-data)))

      result)))

(defun sap-extract (raw class-name &key (strict nil) (validate-required t))
  "Full SAP extraction pipeline: preprocess, parse, and extract."
  (handler-case
      (let* ((preprocessed (sap-preprocess raw))
             (parsed (sap-parse-json preprocessed)))
        (sap-extract-with-schema parsed class-name
                                 :strict strict
                                 :validate-required validate-required))
    (cl-json:json-syntax-error (e)
      (error 'sap-extraction-error
             :message "JSON parsing failed after preprocessing"
             :schema class-name
             :reason (princ-to-string e)
             :input (subseq raw 0 (min 500 (length raw)))))))

(defun sap-extract-lenient (raw class-name)
  "Lenient extraction that tries to recover as much as possible."
  (sap-extract raw class-name :strict nil :validate-required nil))

(defun sap-try-extract (raw class-name)
  "Attempt extraction, returning (values result success-p error-message)."
  (handler-case
      (values (sap-extract raw class-name :strict nil :validate-required t) t nil)
    (error (e)
      (values nil nil (princ-to-string e)))))
