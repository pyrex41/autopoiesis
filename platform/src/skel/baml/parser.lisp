;;;; parser.lisp - BAML parser

(in-package #:autopoiesis.skel.baml)

;;; ============================================================================
;;; Parser Context
;;; ============================================================================

(defstruct (parser-context (:conc-name pc-))
  (tokens nil :type list)
  (definitions nil :type list))

(defun pc-peek (ctx)
  (first (pc-tokens ctx)))

(defun pc-advance (ctx)
  (let ((token (first (pc-tokens ctx))))
    (setf (pc-tokens ctx) (rest (pc-tokens ctx)))
    token))

(defun pc-expect (ctx type &optional value)
  (let ((token (pc-peek ctx)))
    (unless token
      (error 'baml-parse-error
             :message "Unexpected end of input"
             :expected (if value (format nil "~A ~S" type value) type)))
    (unless (eq (token-type token) type)
      (error 'baml-parse-error
             :message "Unexpected token type"
             :expected type
             :found (format nil "~A ~S" (token-type token) (token-value token))))
    (when (and value (not (equal (token-value token) value)))
      (error 'baml-parse-error
             :message "Unexpected token value"
             :expected value
             :found (token-value token)))
    (pc-advance ctx)))

(defun pc-match-p (ctx type &optional value)
  (let ((token (pc-peek ctx)))
    (and token
         (eq (token-type token) type)
         (or (null value)
             (equal (token-value token) value)))))

(defun pc-skip-if (ctx type &optional value)
  (when (pc-match-p ctx type value)
    (pc-advance ctx)
    t))

;;; ============================================================================
;;; Type Parsing
;;; ============================================================================

(defun parse-type (ctx)
  (let ((base-type (token-value (pc-expect ctx :identifier))))
    (when (pc-match-p ctx :lbracket)
      (pc-advance ctx)
      (pc-expect ctx :rbracket)
      (setf base-type (concatenate 'string base-type "[]")))
    (when (pc-match-p ctx :question)
      (pc-advance ctx)
      (setf base-type (concatenate 'string base-type "?")))
    (when (pc-match-p ctx :pipe)
      (pc-advance ctx)
      (let ((other-type (parse-type ctx)))
        (setf base-type (format nil "~A | ~A" base-type other-type))))
    base-type))

;;; ============================================================================
;;; Attribute Parsing
;;; ============================================================================

(defun parse-attributes (ctx)
  (let ((attrs nil))
    (loop while (pc-match-p ctx :at) do
      (pc-advance ctx)
      (let ((attr-name (token-value (pc-expect ctx :identifier))))
        (if (pc-match-p ctx :lparen)
            (progn
              (pc-advance ctx)
              (let ((value (cond
                            ((pc-match-p ctx :string)
                             (token-value (pc-advance ctx)))
                            ((pc-match-p ctx :number)
                             (token-value (pc-advance ctx)))
                            ((pc-match-p ctx :keyword)
                             (let ((kw (token-value (pc-advance ctx))))
                               (cond
                                 ((string= kw "true") t)
                                 ((string= kw "false") nil)
                                 ((string= kw "null") nil)
                                 (t kw))))
                            ((pc-match-p ctx :identifier)
                             (token-value (pc-advance ctx)))
                            (t nil))))
                (push (cons attr-name value) attrs)
                (pc-expect ctx :rparen)))
            (push (cons attr-name t) attrs))))
    (nreverse attrs)))

;;; ============================================================================
;;; Class Parsing
;;; ============================================================================

(defun parse-baml-class (ctx)
  (pc-expect ctx :keyword "class")
  (let ((class-name (token-value (pc-expect ctx :identifier)))
        (fields nil)
        (doc nil))
    (pc-expect ctx :lbrace)
    (loop until (pc-match-p ctx :rbrace) do
      (let ((field-name (token-value (pc-expect ctx :identifier)))
            (field-type (parse-type ctx))
            (attrs (parse-attributes ctx)))
        (push (make-baml-field
               :name field-name
               :type field-type
               :description (cdr (assoc "description" attrs :test #'string=))
               :required (not (cl-ppcre:scan "\\?$" field-type))
               :default (cdr (assoc "default" attrs :test #'string=))
               :alias (cdr (assoc "alias" attrs :test #'string=)))
              fields)
        (let ((field-doc (cdr (assoc "doc" attrs :test #'string=))))
          (when (and (null doc) field-doc)
            (setf doc field-doc)))))
    (pc-expect ctx :rbrace)
    (make-baml-class
     :name class-name
     :fields (nreverse fields)
     :documentation doc)))

;;; ============================================================================
;;; Function Parsing
;;; ============================================================================

(defun parse-function-params (ctx)
  (let ((params nil))
    (pc-expect ctx :lparen)
    (unless (pc-match-p ctx :rparen)
      (loop
        (let ((param-name (token-value (pc-expect ctx :identifier))))
          (pc-expect ctx :colon)
          (let ((param-type (parse-type ctx)))
            (push (make-baml-param :name param-name :type param-type) params)))
        (unless (pc-skip-if ctx :comma)
          (return))))
    (pc-expect ctx :rparen)
    (nreverse params)))

(defun parse-baml-function (ctx)
  (pc-expect ctx :keyword "function")
  (let ((func-name (token-value (pc-expect ctx :identifier)))
        (params (parse-function-params ctx))
        return-type
        client
        prompt
        (config nil))
    (pc-expect ctx :arrow)
    (setf return-type (parse-type ctx))
    (pc-expect ctx :lbrace)
    (loop until (pc-match-p ctx :rbrace) do
      (let ((prop-token (pc-peek ctx)))
        (cond
          ((and (eq (token-type prop-token) :keyword)
                (string= (token-value prop-token) "client"))
           (pc-advance ctx)
           (setf client (token-value (pc-expect ctx :string))))
          ((and (eq (token-type prop-token) :keyword)
                (string= (token-value prop-token) "prompt"))
           (pc-advance ctx)
           (setf prompt (token-value (pc-expect ctx :string))))
          ((eq (token-type prop-token) :identifier)
           (let ((key (intern (string-upcase (token-value (pc-advance ctx))) :keyword)))
             (let ((val (cond
                         ((pc-match-p ctx :string)
                          (token-value (pc-advance ctx)))
                         ((pc-match-p ctx :number)
                          (token-value (pc-advance ctx)))
                         ((pc-match-p ctx :keyword)
                          (let ((kw (token-value (pc-advance ctx))))
                            (cond
                              ((string= kw "true") t)
                              ((string= kw "false") nil)
                              (t kw))))
                         (t (token-value (pc-advance ctx))))))
               (setf config (append config (list key val))))))
          (t
           (pc-advance ctx)))))
    (pc-expect ctx :rbrace)
    (make-baml-function
     :name func-name
     :params params
     :return-type return-type
     :client client
     :prompt prompt
     :config config)))

;;; ============================================================================
;;; Enum Parsing
;;; ============================================================================

(defun parse-baml-enum (ctx)
  (pc-expect ctx :keyword "enum")
  (let ((enum-name (token-value (pc-expect ctx :identifier)))
        (values nil)
        (doc nil))
    (pc-expect ctx :lbrace)
    (loop until (pc-match-p ctx :rbrace) do
      (let ((value-name (token-value (pc-expect ctx :identifier)))
            (attrs (parse-attributes ctx)))
        (push (make-baml-enum-value
               :name value-name
               :description (cdr (assoc "description" attrs :test #'string=))
               :alias (cdr (assoc "alias" attrs :test #'string=)))
              values)))
    (pc-expect ctx :rbrace)
    (make-baml-enum
     :name enum-name
     :values (nreverse values)
     :documentation doc)))

;;; ============================================================================
;;; Client Parsing
;;; ============================================================================

(defun parse-baml-client (ctx)
  (pc-expect ctx :keyword "client")
  (when (pc-match-p ctx :langle)
    (pc-advance ctx)
    (pc-expect ctx :identifier)
    (pc-expect ctx :rangle))
  (let ((client-name (token-value (pc-expect ctx :identifier)))
        provider
        (options nil))
    (pc-expect ctx :lbrace)
    (loop until (pc-match-p ctx :rbrace) do
      (let ((prop-token (pc-peek ctx)))
        (cond
          ((and (eq (token-type prop-token) :identifier)
                (string= (token-value prop-token) "provider"))
           (pc-advance ctx)
           (setf provider (token-value (pc-expect ctx :string))))
          ((and (eq (token-type prop-token) :identifier)
                (string= (token-value prop-token) "options"))
           (pc-advance ctx)
           (pc-expect ctx :lbrace)
           (loop until (pc-match-p ctx :rbrace) do
             (let ((key (intern (string-upcase (token-value (pc-expect ctx :identifier))) :keyword)))
               (let ((val (cond
                           ((pc-match-p ctx :string)
                            (token-value (pc-advance ctx)))
                           ((pc-match-p ctx :number)
                            (token-value (pc-advance ctx)))
                           ((pc-match-p ctx :keyword)
                            (let ((kw (token-value (pc-advance ctx))))
                              (cond
                                ((string= kw "true") t)
                                ((string= kw "false") nil)
                                (t kw))))
                           (t (token-value (pc-advance ctx))))))
                 (setf options (append options (list key val))))))
           (pc-expect ctx :rbrace))
          (t
           (pc-advance ctx)))))
    (pc-expect ctx :rbrace)
    (make-baml-client-def
     :name client-name
     :provider provider
     :options options)))

;;; ============================================================================
;;; Main Parser
;;; ============================================================================

(defun parse-baml-content (content)
  "Parse BAML content string into definition structures."
  (let* ((tokens (tokenize-baml content))
         (ctx (make-parser-context :tokens tokens)))
    (loop until (null (pc-tokens ctx)) do
      (let ((token (pc-peek ctx)))
        (when token
          (cond
            ((and (eq (token-type token) :keyword)
                  (string= (token-value token) "class"))
             (push (parse-baml-class ctx) (pc-definitions ctx)))
            ((and (eq (token-type token) :keyword)
                  (string= (token-value token) "function"))
             (push (parse-baml-function ctx) (pc-definitions ctx)))
            ((and (eq (token-type token) :keyword)
                  (string= (token-value token) "enum"))
             (push (parse-baml-enum ctx) (pc-definitions ctx)))
            ((and (eq (token-type token) :keyword)
                  (string= (token-value token) "client"))
             (push (parse-baml-client ctx) (pc-definitions ctx)))
            (t
             (pc-advance ctx))))))
    (nreverse (pc-definitions ctx))))
