;;;; core.lisp - Core synchronous API for SKEL function calls
;;;; Provides function definition, registration, and synchronous invocation

(in-package #:autopoiesis.skel)

;;; ============================================================================
;;; Function Parameter Structure
;;; ============================================================================

(defstruct skel-parameter
  "A parameter definition for a SKEL function."
  (name nil :type symbol)
  (type :string :type (or keyword symbol skel-type list))
  (description nil :type (or null string))
  (required t :type boolean)
  (default nil))

;;; ============================================================================
;;; Function Definition Structure
;;; ============================================================================

(defstruct skel-function
  "A defined SKEL function with metadata."
  (name nil :type symbol)
  (prompt nil :type (or null string function))
  (return-type :string :type (or keyword symbol skel-type list))
  (parameters nil :type list)
  (config nil :type (or null skel-config))
  (documentation nil :type (or null string)))

;;; ============================================================================
;;; Result Structure
;;; ============================================================================

(defstruct skel-result
  "A typed result from a SKEL function invocation."
  (value nil)
  (success t :type boolean)
  (raw-response nil :type (or null string))
  (return-type nil)
  (attempts 1 :type integer)
  (duration 0.0 :type number)
  (input-tokens 0 :type integer)
  (output-tokens 0 :type integer)
  (error nil :type (or null condition)))

(defun skel-result-failed-p (result)
  "Return T if RESULT represents a failed call."
  (not (skel-result-success result)))

(defun skel-result-total-tokens (result)
  "Return total tokens used by this result."
  (+ (skel-result-input-tokens result)
     (skel-result-output-tokens result)))

;;; ============================================================================
;;; Function Registry
;;; ============================================================================

(defvar *skel-functions* (make-hash-table :test 'eq)
  "Registry of defined SKEL functions.")

(defun register-skel-function (func)
  "Register a SKEL function in the global registry."
  (setf (gethash (skel-function-name func) *skel-functions*) func))

(defun get-skel-function (name)
  "Retrieve a SKEL function by name. Returns NIL if not found."
  (gethash name *skel-functions*))

(defun list-skel-functions ()
  "Return a list of all registered SKEL function names."
  (loop for name being the hash-keys of *skel-functions*
        collect name))

(defun clear-skel-functions ()
  "Clear all registered SKEL functions."
  (clrhash *skel-functions*))

;;; ============================================================================
;;; Prompt Template Interpolation
;;; ============================================================================

(defun interpolate-prompt (template args)
  "Interpolate {{ variable }} placeholders in TEMPLATE with ARGS plist values."
  (if (functionp template)
      (apply template args)
      (let ((result template))
        (cl-ppcre:do-register-groups (var-name)
            ("\\{\\{\\s*(\\w+)\\s*\\}\\}" template)
          (let* ((key (intern (string-upcase var-name) :keyword))
                 (value (getf args key)))
            (when value
              (setf result
                    (cl-ppcre:regex-replace-all
                     (format nil "\\{\\{\\s*~A\\s*\\}\\}" var-name)
                     result
                     (princ-to-string value))))))
        result)))

;;; ============================================================================
;;; Argument Validation
;;; ============================================================================

;; Note: skel-validation-error is already defined in types.lisp

(defun validate-skel-arguments (func args)
  "Validate ARGS against the parameters of FUNC."
  (let ((params (skel-function-parameters func))
        (validated-args '()))
    (dolist (param params)
      (let* ((name (skel-parameter-name param))
             (key (intern (symbol-name name) :keyword))
             (value (getf args key :not-supplied)))
        (cond
          ((not (eq value :not-supplied))
           (setf (getf validated-args key) value))
          ((skel-parameter-required param)
           (error 'skel-validation-error
                  :message (format nil "Missing required parameter: ~A" name)
                  :value nil
                  :constraint (format nil "Parameter ~A is required" name)))
          (t
           (setf (getf validated-args key)
                 (skel-parameter-default param))))))
    validated-args))

;;; ============================================================================
;;; Response Parsing
;;; ============================================================================

(defun parse-llm-response (raw-response return-type)
  "Parse RAW-RESPONSE from LLM according to RETURN-TYPE."
  (handler-case
      (let* ((preprocessed (sap-preprocess raw-response)))
        (cond
          ((keywordp return-type)
           (let ((skel-type (get-skel-type return-type)))
             (if skel-type
                 (funcall (type-parser skel-type) preprocessed)
                 (error 'skel-type-error
                        :type-name return-type
                        :value nil
                        :message "Unknown return type"))))
          ;; Handle SKEL class return types via SAP extraction
          ((and (symbolp return-type) (get-skel-class return-type))
           (let ((parsed (sap-parse-json preprocessed)))
             (sap-extract-with-schema parsed return-type :strict nil)))
          (t (parse-typed-value return-type preprocessed))))
    (skel-type-error (e)
      (error e))
    (sap-error (e)
      (error 'skel-parse-error
             :message (format nil "SAP preprocessing failed: ~A" (skel-error-message e))
             :raw-response raw-response))
    (error (e)
      (error 'skel-parse-error
             :message (format nil "Failed to parse response: ~A" e)
             :raw-response raw-response))))

;;; ============================================================================
;;; Synchronous Invocation API
;;; ============================================================================

(defvar *current-llm-client* nil
  "The LLM client to use for SKEL function calls.")

(defun ensure-llm-client (client-arg)
  "Ensure we have an LLM client. Resolves named clients from registry."
  (let ((resolved (etypecase client-arg
                    (null nil)
                    (keyword (find-skel-client client-arg))
                    (string (find-skel-client client-arg))
                    (t client-arg))))  ; already a client instance
    (or resolved
        *current-llm-client*
        (error 'skel-error
               :message "No LLM client available. Set *current-llm-client* or pass :client."))))

(defun build-skel-prompt (func validated-args)
  "Build the complete prompt for a SKEL function call."
  (let* ((template (skel-function-prompt func))
         (user-prompt (interpolate-prompt template validated-args))
         (return-type (skel-function-return-type func))
         (type-hint (format-type-hint return-type)))
    (if type-hint
        (format nil "~A~%~%~A" user-prompt type-hint)
        user-prompt)))

(defun format-type-hint (return-type)
  "Format a type hint to append to the prompt."
  (cond
    ((eq return-type :string)
     "Respond with plain text.")
    ((eq return-type :integer)
     "Respond with only an integer number.")
    ((eq return-type :float)
     "Respond with only a number.")
    ((eq return-type :boolean)
     "Respond with only 'true' or 'false'.")
    ((eq return-type :json)
     "Respond with valid JSON.")
    ((and (listp return-type) (eq (car return-type) 'list-of))
     (format nil "Respond with a JSON array of ~A values."
             (string-downcase (symbol-name (cadr return-type)))))
    ((and (symbolp return-type) (get-skel-class return-type))
     (format nil "Respond with a JSON object matching this schema:~%~A"
             (format-class-schema return-type :style :json)))
    (t nil)))

(defun invoke-skel-function (name &rest args
                             &key client config &allow-other-keys)
  "Invoke a SKEL function synchronously by NAME."
  (let ((func-args (remove-from-plist args :client :config)))
    (let ((func (get-skel-function name)))
      (unless func
        (error 'skel-error
               :message (format nil "Unknown SKEL function: ~A" name)))
      (let ((validated-args (validate-skel-arguments func func-args)))
        (let ((llm-client (ensure-llm-client client)))
          (let* ((func-config (or (skel-function-config func) *default-skel-config*))
                 (merged-config (if config
                                    (merge-configs func-config config)
                                    func-config))
                 (configured-client (apply-config-to-client llm-client merged-config))
                 (prompt (build-skel-prompt func validated-args))
                 (system-prompt (config-system-prompt merged-config)))
            (call-with-retries
             (lambda ()
               (multiple-value-bind (text input-tokens output-tokens)
                   (skel-send-message configured-client prompt
                                      :system system-prompt)
                 (declare (ignore input-tokens output-tokens))
                 (parse-llm-response text
                                     (skel-function-return-type func))))
             :count (config-retry-count merged-config)
             :delay (config-retry-delay merged-config))))))))

;;; ============================================================================
;;; Retry Logic
;;; ============================================================================

(defun call-with-retries (thunk &key (count 0) (delay 1.0))
  "Call THUNK, retrying on skel-parse-error up to COUNT times with DELAY seconds between."
  (let ((attempts 0)
        (last-error nil))
    (loop
      (handler-case
          (return-from call-with-retries (funcall thunk))
        (skel-parse-error (e)
          (setf last-error e)
          (incf attempts)
          (when (>= attempts (1+ count))
            (error e))
          (when (> delay 0)
            (sleep delay)))))))

;;; ============================================================================
;;; Function Definition Macro
;;; ============================================================================

(defmacro define-skel-function (name (&rest params) &body options)
  "Define a SKEL function for typed LLM interactions."
  (let ((prompt (getf options :prompt))
        (return-type (getf options :return-type :string))
        (config (getf options :config))
        (doc (getf options :documentation)))
    `(register-skel-function
      (make-skel-function
       :name ',name
       :prompt ,prompt
       :return-type ',return-type
       :config ,config
       :documentation ,doc
       :parameters (list
                    ,@(mapcar
                       (lambda (param-spec)
                         (destructuring-bind (pname ptype &key description
                                                    (required t) default)
                             param-spec
                           `(make-skel-parameter
                             :name ',pname
                             :type ',ptype
                             :description ,description
                             :required ,required
                             :default ,default)))
                       params))))))

;;; ============================================================================
;;; Convenience Wrapper
;;; ============================================================================

(defun skel-call (name &rest args)
  "Convenience wrapper for invoke-skel-function."
  (apply #'invoke-skel-function name args))
