;;;; provider-macro.lisp - Data-driven CLI provider definition macro
;;;;
;;;; Provides `define-cli-provider` which generates a complete provider
;;;; implementation from a declarative specification: class, constructor,
;;;; command builder, output parser, and serializer.

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; Parser Form Generator (must precede macro that calls it)
;;; ===================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %generate-parser-forms (class-sym parse-clause)
    "Generate parser method forms from a :parse-output clause.
   Called at macro-expansion time."
    (when parse-clause
      (let ((parser-spec (rest parse-clause)))
        (cond
          ;; :json-object parser
          ((eq (first parser-spec) :json-object)
           (let ((field-mappings (rest parser-spec)))
             `((defmethod provider-parse-output ((provider ,class-sym) raw-output)
                 ,(format nil "Parse ~a JSON output."
                          (string-downcase (symbol-name class-sym)))
                 (handler-case
                     (let ((json (cl-json:decode-json-from-string raw-output)))
                       (make-provider-result
                        ,@(loop for mapping in field-mappings
                                for slot = (first mapping)
                                for json-field = (second mapping)
                                ;; cl-json:camel-case-to-lisp is what the
                                ;; decoder uses: cost_usd -> "COST--USD"
                                for primary-key = (intern
                                                   (cl-json:camel-case-to-lisp
                                                    json-field)
                                                   :keyword)
                                ;; Also try simple hyphen form (:COST-USD)
                                ;; for robustness
                                for alt-key = (let* ((hyphenated
                                                       (substitute #\- #\_ json-field))
                                                     (alt (intern
                                                           (string-upcase hyphenated)
                                                           :keyword)))
                                                (unless (eq alt primary-key) alt))
                                append (list slot
                                             (if alt-key
                                                 `(or (cdr (assoc ,primary-key json))
                                                      (cdr (assoc ,alt-key json)))
                                                 `(cdr (assoc ,primary-key json)))))))
                   (error (e)
                     (make-provider-result
                      :text raw-output
                      :metadata (list :parse-error (format nil "~a" e)))))))))

          ;; :jsonl-events parser
          ((eq (first parser-spec) :jsonl-events)
           (let ((event-handlers (rest parser-spec)))
             `((defmethod provider-parse-output ((provider ,class-sym) raw-output)
                 ,(format nil "Parse ~a JSONL output."
                          (string-downcase (symbol-name class-sym)))
                 (let ((text-parts nil)
                       (tool-calls nil)
                       (total-cost 0)
                       (turns 0))
                   (handler-case
                       (with-input-from-string (s raw-output)
                         (loop for line = (read-line s nil nil)
                               while line
                               when (and (> (length line) 0)
                                         (char= (char line 0) #\{))
                                 do (handler-case
                                        (let* ((json (cl-json:decode-json-from-string line))
                                               (event-type
                                                 (or (cdr (assoc :type json)) "")))
                                          (cond
                                            ,@(loop for handler in event-handlers
                                                    collect
                                                    `((string= event-type
                                                               ,(first handler))
                                                      ,@(rest handler)))))
                                      (error () nil))))
                     (error (e)
                       (declare (ignore e))))
                   (make-provider-result
                    :text (format nil "~{~a~}" (nreverse text-parts))
                    :tool-calls (nreverse tool-calls)
                    :cost (when (> total-cost 0) total-cost)
                    :turns (when (> turns 0) turns)))))))

          ;; Custom function parser
          ((symbolp (first parser-spec))
           `((defmethod provider-parse-output ((provider ,class-sym) raw-output)
               (,(first parser-spec) provider raw-output))))

          (t (error "Unknown parser type in define-cli-provider: ~a"
                    (first parser-spec))))))))

;;; ===================================================================
;;; Main Macro
;;; ===================================================================

(defmacro define-cli-provider (name &body clauses)
  "Define a CLI provider from a declarative specification.

   NAME is a keyword like :claude-code. The macro generates:
   - A defclass named <name>-provider inheriting from provider
   - A make-<name>-provider constructor function
   - provider-supported-modes method
   - provider-build-command method
   - provider-parse-output method
   - provider-to-sexpr method

   Supported clauses:
     (:command \"cmd\")             - CLI command name
     (:modes (:one-shot ...))      - Supported invocation modes
     (:default-timeout N)          - Default timeout (default 300)
     (:extra-slots (slot ...) ...) - Additional CLOS slot specifications
     (:build-command (provider prompt &key tools) body...)
                                   - Custom command builder body
     (:parse-output spec ...)      - Output parser specification
     (:documentation \"...\")      - Class documentation string

   Parser specifications for :parse-output:
     :json-object (result-kw \"json_field\") ...
       Parses single JSON object, maps fields to make-provider-result keywords.
       E.g. (:text \"result\") (:cost \"cost_usd\")
     :jsonl-events (\"event_type\" body...) ...
       Parses newline-delimited JSON, dispatches on type field.
       Body has access to bindings: json, text-parts, tool-calls, total-cost, turns.
     function-name
       Calls (function-name provider raw-output)"
  (let* ((name-str (string-downcase (symbol-name name)))
         (class-sym (intern (string-upcase (format nil "~a-PROVIDER" name-str))
                            :autopoiesis.integration))
         (constructor-sym (intern (string-upcase (format nil "MAKE-~a-PROVIDER" name-str))
                                  :autopoiesis.integration))
         ;; Extract clauses
         (command (second (find :command clauses :key #'first)))
         (modes (second (find :modes clauses :key #'first)))
         (default-timeout (or (second (find :default-timeout clauses :key #'first)) 300))
         (extra-slots-clause (find :extra-slots clauses :key #'first))
         (extra-slots (when extra-slots-clause (rest extra-slots-clause)))
         (build-cmd-clause (find :build-command clauses :key #'first))
         (parse-clause (find :parse-output clauses :key #'first))
         (doc-string (or (second (find :documentation clauses :key #'first))
                         (format nil "Provider for the ~a CLI tool." name-str)))
         ;; Collect slot metadata for constructor and serializer
         (slot-metas
           (loop for slot-spec in extra-slots
                 for slot-name = (first slot-spec)
                 for slot-props = (rest slot-spec)
                 for initarg = (getf slot-props :initarg
                                     (intern (string-upcase (symbol-name slot-name))
                                             :keyword))
                 for accessor = (getf slot-props :accessor slot-name)
                 for initform = (getf slot-props :initform)
                 for has-initform = (not (null (member :initform slot-props)))
                 collect (list :name slot-name
                               :initarg initarg
                               :accessor accessor
                               :initform initform
                               :has-initform has-initform))))

    `(progn
       ;; 1. Class definition
       (defclass ,class-sym (provider)
         (,@extra-slots)
         (:default-initargs :name ,name-str :command ,command
                            :timeout ,default-timeout)
         (:documentation ,doc-string))

       ;; 2. Constructor
       (defun ,constructor-sym (&key (name ,name-str) (command ,command)
                                  working-directory default-model
                                  (max-turns 10) (timeout ,default-timeout)
                                  env extra-args
                                  ,@(loop for meta in slot-metas
                                          for kw-name = (getf meta :name)
                                          for initform = (getf meta :initform)
                                          for has = (getf meta :has-initform)
                                          collect (if has
                                                      `(,kw-name ,initform)
                                                      kw-name)))
         ,(format nil "Create a ~a provider instance." name-str)
         (make-instance ',class-sym
                        :name name
                        :command command
                        :working-directory working-directory
                        :default-model default-model
                        :max-turns max-turns
                        :timeout timeout
                        :env env
                        :extra-args extra-args
                        ,@(loop for meta in slot-metas
                                append (list (getf meta :initarg)
                                             (getf meta :name)))))

       ;; 3. Supported modes
       ,@(when modes
           `((defmethod provider-supported-modes ((provider ,class-sym))
               ',modes)))

       ;; 4. Command builder
       ,@(when build-cmd-clause
           (destructuring-bind (_key params &body body) build-cmd-clause
             (declare (ignore _key))
             (let* ((provider-var (first params))
                    (prompt-var (second params))
                    (rest-params (cddr params))
                    (has-key (eq (first rest-params) '&key))
                    (tools-var (when has-key (second rest-params))))
               (if tools-var
                   `((defmethod provider-build-command ((,provider-var ,class-sym)
                                                        ,prompt-var &key ,tools-var)
                       ,@body))
                   (let ((ignored (gensym "TOOLS")))
                     `((defmethod provider-build-command ((,provider-var ,class-sym)
                                                          ,prompt-var
                                                          &key ((:tools ,ignored) nil))
                         (declare (ignore ,ignored))
                         ,@body)))))))

       ;; 5. Parser
       ,@(%generate-parser-forms class-sym parse-clause)

       ;; 6. Serializer (append extra slot values to base serialization)
       ,@(when slot-metas
           `((defmethod provider-to-sexpr ((provider ,class-sym))
               (let ((base (call-next-method)))
                 (append base
                         (list ,@(loop for meta in slot-metas
                                       append `(,(getf meta :initarg)
                                                (,(getf meta :accessor) provider)))))))))

       ',class-sym)))
