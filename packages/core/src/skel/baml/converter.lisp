;;;; converter.lisp - BAML to SKEL conversion

(in-package #:autopoiesis.skel.baml)

;;; ============================================================================
;;; Utility Functions
;;; ============================================================================

(defun kebab-case (string)
  "Convert a camelCase or PascalCase string to kebab-case."
  (with-output-to-string (out)
    (loop for i from 0 below (length string)
          for ch = (char string i)
          do (cond
               ((and (upper-case-p ch)
                     (> i 0)
                     (or (lower-case-p (char string (1- i)))
                         (and (< (1+ i) (length string))
                              (lower-case-p (char string (1+ i))))))
                (write-char #\- out)
                (write-char (char-downcase ch) out))
               (t
                (write-char (char-downcase ch) out))))))

(defun lisp-symbol-name (string)
  "Convert a BAML identifier to a Lisp symbol name."
  (string-upcase (kebab-case string)))

;;; ============================================================================
;;; Type Conversion
;;; ============================================================================

(defun baml-type->skel-type (baml-type)
  "Convert BAML type syntax to SKEL type specification."
  (cond
    ((string= baml-type "string") 'string)
    ((string= baml-type "int") 'integer)
    ((string= baml-type "float") 'number)
    ((string= baml-type "bool") 'boolean)
    ((string= baml-type "boolean") 'boolean)

    ;; Array types: string[] -> (autopoiesis.skel:list-of string)
    ((cl-ppcre:scan "\\[\\]$" baml-type)
     (let ((element-type (subseq baml-type 0 (- (length baml-type) 2))))
       `(autopoiesis.skel:list-of ,(baml-type->skel-type element-type))))

    ;; Optional types: string? -> (or string null)
    ((cl-ppcre:scan "\\?$" baml-type)
     (let ((base-type (subseq baml-type 0 (1- (length baml-type)))))
       `(or ,(baml-type->skel-type base-type) null)))

    ;; Union types: string | int -> (or string integer)
    ((cl-ppcre:scan "\\|" baml-type)
     (let ((parts (cl-ppcre:split "\\s*\\|\\s*" baml-type)))
       `(or ,@(mapcar #'baml-type->skel-type parts))))

    ;; Map types
    ((cl-ppcre:scan "^map<" baml-type)
     'hash-table)

    ;; Custom class reference
    (t
     (intern (lisp-symbol-name baml-type)))))

;;; ============================================================================
;;; Field/Slot Conversion
;;; ============================================================================

(defun baml-field->skel-slot (field)
  "Convert a BAML field to a SKEL slot specification."
  (let ((name (intern (lisp-symbol-name (baml-field-name field))))
        (type (baml-type->skel-type (baml-field-type field))))
    `(,name :type ,type
            ,@(when (baml-field-description field)
                `(:description ,(baml-field-description field)))
            ,@(when (baml-field-required field)
                `(:required t))
            ,@(when (baml-field-default field)
                `(:default ,(baml-field-default field)))
            ,@(when (baml-field-alias field)
                `(:json-key ,(baml-field-alias field))))))

(defun baml-param->skel-param (param)
  "Convert a BAML function parameter to SKEL parameter spec."
  (let ((name (intern (lisp-symbol-name (baml-param-name param))))
        (type (baml-type->skel-type (baml-param-type param))))
    `(,name ,type)))

;;; ============================================================================
;;; Prompt Conversion
;;; ============================================================================

(defun convert-baml-prompt (baml-prompt)
  "Convert BAML prompt template to SKEL format."
  (when (null baml-prompt)
    (return-from convert-baml-prompt nil))
  (let* ((step1 (cl-ppcre:regex-replace-all
                 "\\{\\{\\s*ctx\\.output_format\\s*\\}\\}"
                 baml-prompt
                 "{{ autopoiesis.skel:output-schema }}"))
         (step2 (cl-ppcre:regex-replace-all
                 "\\{\\{\\s*_\\.role\\(['\"]?(\\w+)['\"]?\\)\\s*\\}\\}"
                 step1
                 "{{ autopoiesis.skel:role '\\1' }}"))
         (step3 (cl-ppcre:regex-replace-all
                 "\\{\\{\\s*ctx\\.input\\s*\\}\\}"
                 step2
                 "{{ input }}")))
    step3))

;;; ============================================================================
;;; Class Conversion
;;; ============================================================================

(defun baml-class->skel-class (baml-class)
  "Convert BAML class to SKEL define-skel-class form."
  (let ((name (intern (lisp-symbol-name (baml-class-name baml-class))))
        (slots (mapcar #'baml-field->skel-slot (baml-class-fields baml-class))))
    `(skel:define-skel-class ,name ()
       ,slots
       ,@(when (baml-class-documentation baml-class)
           `((:documentation ,(baml-class-documentation baml-class)))))))

;;; ============================================================================
;;; Function Conversion
;;; ============================================================================

(defun baml-function->skel-function (baml-func)
  "Convert BAML function to SKEL define-skel-function form."
  (let ((name (intern (lisp-symbol-name (baml-function-name baml-func))))
        (params (mapcar #'baml-param->skel-param (baml-function-params baml-func)))
        (return-type (baml-type->skel-type (baml-function-return-type baml-func)))
        (prompt (convert-baml-prompt (baml-function-prompt baml-func))))
    `(skel:define-skel-function ,name ,params ,return-type
       ,@(when (baml-function-client baml-func)
           `((:client ,(baml-function-client baml-func))))
       ,@(loop for (key val) on (baml-function-config baml-func) by #'cddr
               collect `(,key ,val))
       ,@(when prompt
           `((:prompt ,prompt))))))

;;; ============================================================================
;;; Enum Conversion
;;; ============================================================================

(defun baml-enum->skel-enum (baml-enum)
  "Convert BAML enum to SKEL define-skel-enum form."
  (let ((name (intern (lisp-symbol-name (baml-enum-name baml-enum))))
        (values (mapcar (lambda (v)
                          (let ((val-name (intern (lisp-symbol-name (baml-enum-value-name v)))))
                            (if (baml-enum-value-description v)
                                `(,val-name :description ,(baml-enum-value-description v))
                                val-name)))
                        (baml-enum-values baml-enum))))
    `(skel:define-skel-enum ,name ()
       ,@values
       ,@(when (baml-enum-documentation baml-enum)
           `((:documentation ,(baml-enum-documentation baml-enum)))))))

;;; ============================================================================
;;; Top-Level Conversion
;;; ============================================================================

(defun baml->skel (definition)
  "Convert any BAML definition to its SKEL form."
  (etypecase definition
    (baml-class (baml-class->skel-class definition))
    (baml-function (baml-function->skel-function definition))
    (baml-enum (baml-enum->skel-enum definition))))
