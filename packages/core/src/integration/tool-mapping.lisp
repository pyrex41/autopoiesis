;;;; tool-mapping.lisp - Bidirectional mapping between capabilities and Claude tools
;;;;
;;;; Converts Autopoiesis capabilities to Claude tool format and handles
;;;; tool call execution with result formatting.

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; Name Normalization (kebab-case <-> snake_case)
;;; ===================================================================

(defun lisp-name-to-tool-name (lisp-name)
  "Convert a Lisp symbol or string to Claude tool name format.

   Converts kebab-case to snake_case for Claude API compatibility.
   Example: :read-file -> \"read_file\""
  (substitute #\_ #\- (string-downcase (string lisp-name))))

(defun tool-name-to-lisp-name (tool-name)
  "Convert a Claude tool name to a Lisp keyword symbol.

   Converts snake_case to kebab-case for Lisp idiomatic naming.
   Example: \"read_file\" -> :READ-FILE"
  (intern (string-upcase (substitute #\- #\_ tool-name)) :keyword))

;;; ===================================================================
;;; Lisp Type to JSON Schema Type Conversion
;;; ===================================================================

(defun lisp-type-to-json-type (lisp-type)
  "Convert a Lisp type specifier to JSON Schema type string.

   LISP-TYPE - A Lisp type specifier symbol or form.

   Returns a string like \"string\", \"integer\", \"number\", \"boolean\",
   \"array\", or \"object\". Defaults to \"string\" for unknown types."
  (cond
    ((null lisp-type) "string")
    ((eq lisp-type t) "string")
    ((eq lisp-type 'string) "string")
    ((member lisp-type '(integer fixnum bignum)) "integer")
    ((member lisp-type '(float single-float double-float number real)) "number")
    ((member lisp-type '(boolean (member t nil))) "boolean")
    ((member lisp-type '(list cons sequence)) "array")
    ((member lisp-type '(hash-table plist alist)) "object")
    ((and (consp lisp-type)
          (eq (car lisp-type) 'or))
     ;; For union types, pick the first concrete type
     (lisp-type-to-json-type (second lisp-type)))
    (t "string")))

(defun json-type-to-lisp-type (json-type)
  "Convert a JSON Schema type string to a Lisp type specifier.

   JSON-TYPE - A string like \"string\", \"integer\", etc.

   Returns a Lisp type specifier symbol."
  (cond
    ((string= json-type "string") 'string)
    ((string= json-type "integer") 'integer)
    ((string= json-type "number") 'number)
    ((string= json-type "boolean") 'boolean)
    ((string= json-type "array") 'list)
    ((string= json-type "object") 'hash-table)
    ((string= json-type "null") 'null)
    (t t)))

;;; ===================================================================
;;; Capability Parameter to JSON Schema Conversion
;;; ===================================================================

(defun capability-param-to-json-property (param)
  "Convert a capability parameter spec to a JSON Schema property.

   PARAM - A list of (name type &key required default doc).

   Returns an alist entry (name . property-schema)."
  (destructuring-bind (name type &key required default doc &allow-other-keys)
      param
    (let ((prop `(("type" . ,(lisp-type-to-json-type type)))))
      (when doc
        (push (cons "description" doc) prop))
      (when default
        (push (cons "default" default) prop))
      (cons (string-downcase (string name)) prop))))

(defun capability-params-to-json-schema (params)
  "Convert capability parameters to a JSON Schema object.

   PARAMS - A list of parameter specs from a capability.

   Returns an alist representing a JSON Schema object type."
  (let ((properties nil)
        (required nil))
    (dolist (param params)
      (destructuring-bind (name type &key ((:required req)) &allow-other-keys)
          param
        (push (capability-param-to-json-property param) properties)
        (when req
          (push (string-downcase (string name)) required))))
    `(("type" . "object")
      ("properties" . ,(nreverse properties))
      ,@(when required
          `(("required" . ,(nreverse required)))))))

;;; ===================================================================
;;; JSON Schema to Capability Parameter Conversion
;;; ===================================================================

(defun json-property-to-capability-param (name prop required-list)
  "Convert a JSON Schema property to a capability parameter spec.

   NAME - The property name string.
   PROP - The property schema alist.
   REQUIRED-LIST - List of required property names.

   Returns a capability parameter spec list."
  (let ((type (cdr (assoc "type" prop :test #'string=)))
        (description (cdr (assoc "description" prop :test #'string=)))
        (default (cdr (assoc "default" prop :test #'string=)))
        (req (member name required-list :test #'string=)))
    `(,(intern (string-upcase name) :keyword)
      ,(json-type-to-lisp-type type)
      ,@(when req '(:required t))
      ,@(when default `(:default ,default))
      ,@(when description `(:doc ,description)))))

(defun json-schema-to-capability-params (schema)
  "Convert a JSON Schema object to capability parameters.

   SCHEMA - An alist representing a JSON Schema object type.

   Returns a list of capability parameter specs."
  (let ((properties (cdr (assoc "properties" schema :test #'string=)))
        (required (cdr (assoc "required" schema :test #'string=))))
    (loop for (name . prop) in properties
          collect (json-property-to-capability-param name prop required))))

;;; ===================================================================
;;; Capability to Claude Tool Conversion
;;; ===================================================================

(defun capability-to-claude-tool (capability)
  "Convert an Autopoiesis capability to Claude tool format.

   CAPABILITY - A capability instance from the agent system.

   Returns an alist suitable for the Claude API tools parameter.
   Note: Capability names like :read-file are converted to tool names
   like \"read_file\" (kebab-case to snake_case)."
  `(("name" . ,(lisp-name-to-tool-name (capability-name capability)))
    ("description" . ,(or (capability-description capability) ""))
    ("input_schema" . ,(capability-params-to-json-schema
                        (or (capability-parameters capability) nil)))))

(defun capabilities-to-claude-tools (capabilities)
  "Convert a list of capabilities to Claude tool format.

   CAPABILITIES - A list of capability instances.

   Returns a list of tool alists for Claude API."
  (mapcar #'capability-to-claude-tool capabilities))

(defun agent-capabilities-to-claude-tools (agent)
  "Convert all capabilities of an agent to Claude tool format.

   AGENT - An agent instance with capabilities.

   Returns a list of tool alists for Claude API."
  (capabilities-to-claude-tools (get-all-agent-capabilities agent)))

(defun get-all-agent-capabilities (agent)
  "Get all capabilities registered to an agent (for tool mapping).
   This returns ALL capabilities, not just agent-defined ones."
  (let ((caps (agent-capabilities agent)))
    (if (hash-table-p caps)
        (loop for cap being the hash-values of caps collect cap)
        caps)))

;;; ===================================================================
;;; Claude Tool to Capability Conversion
;;; ===================================================================

(defun claude-tool-to-capability (tool-def &key handler)
  "Convert a Claude tool definition to an Autopoiesis capability.

   TOOL-DEF - A tool definition alist from Claude API.
   HANDLER - Optional function to handle tool invocations.
             If not provided, creates a stub that errors.

   Returns a capability instance.
   Note: Tool names like \"write_file\" are converted to capability names
   like :WRITE-FILE (snake_case to kebab-case)."
  (let ((name (cdr (assoc "name" tool-def :test #'string=)))
        (description (cdr (assoc "description" tool-def :test #'string=)))
        (schema (cdr (assoc "input_schema" tool-def :test #'string=))))
    (make-capability
     (tool-name-to-lisp-name name)
     (or handler
         (lambda (&rest args)
           (error 'autopoiesis.core:autopoiesis-error
                  :message (format nil "No handler for tool ~a" name))))
     :description description)))

;;; ===================================================================
;;; Tool Call Execution
;;; ===================================================================

(defun execute-tool-call (tool-call capabilities)
  "Execute a tool call against available capabilities.

   TOOL-CALL - A plist with :id, :name, and :input keys.
   CAPABILITIES - Hash table or list of available capabilities.

   Returns a plist with :tool-use-id, :result, and :is-error keys.
   Note: Tool names are converted from snake_case to kebab-case for lookup."
  (let* ((tool-id (getf tool-call :id))
         (tool-name (getf tool-call :name))
         (input (getf tool-call :input))
         (cap-name (tool-name-to-lisp-name tool-name))
         (capability (if (hash-table-p capabilities)
                         (or (gethash cap-name capabilities)
                             ;; Fallback: search by string= for cross-package matches
                             ;; (defcapability registers package-qualified symbols,
                             ;; but tool dispatch converts to keywords)
                             (loop for k being the hash-keys of capabilities
                                     using (hash-value v)
                                   when (string= (string k) (string cap-name))
                                     return v))
                         (find cap-name capabilities
                               :key #'capability-name
                               :test (lambda (name cap-name)
                                       (string= (string name) (string cap-name)))))))
    (if capability
        (handler-case
            (let ((result (apply-capability-with-input capability input)))
              `(:tool-use-id ,tool-id
                :result ,(format nil "~a" result)
                :is-error nil))
          (error (e)
            `(:tool-use-id ,tool-id
              :result ,(format nil "Error: ~a" e)
              :is-error t)))
        `(:tool-use-id ,tool-id
          :result ,(format nil "Unknown tool: ~a" tool-name)
          :is-error t))))

(defun apply-capability-with-input (capability input)
  "Apply a capability function with JSON-style input.

   CAPABILITY - A capability instance.
   INPUT - An alist of input parameters.

   Returns the result of invoking the capability."
  (let ((func (capability-function capability))
        (args (json-input-to-keyword-args input)))
    (apply func args)))

(defun json-input-to-keyword-args (input)
  "Convert JSON-style input alist to keyword argument list.

   INPUT - An alist like ((\"path\" . \"/tmp/foo\") (\"content\" . \"bar\"))

   Returns a plist like (:path \"/tmp/foo\" :content \"bar\")"
  (loop for (key . value) in input
        append (list (intern (string-upcase key) :keyword) value)))

;;; ===================================================================
;;; Tool Result Formatting
;;; ===================================================================

(defun format-tool-results (results)
  "Format tool execution results for Claude API.

   RESULTS - A list of result plists from execute-tool-call.

   Returns a message alist suitable for Claude API."
  (let ((content-blocks
          (loop for result in results
                collect `(("type" . "tool_result")
                          ("tool_use_id" . ,(getf result :tool-use-id))
                          ("content" . ,(getf result :result))
                          ,@(when (getf result :is-error)
                              '(("is_error" . t)))))))
    `(("role" . "user")
      ("content" . ,content-blocks))))

;;; ===================================================================
;;; Batch Tool Execution
;;; ===================================================================

(defun execute-all-tool-calls (response capabilities)
  "Execute all tool calls from a Claude response.

   RESPONSE - A parsed Claude API response.
   CAPABILITIES - Available capabilities (hash table or list).

   Returns a list of result plists."
  (let ((tool-calls (response-tool-calls response)))
    (mapcar (lambda (call)
              (execute-tool-call call capabilities))
            tool-calls)))

(defun handle-tool-use-response (response capabilities)
  "Handle a Claude response that contains tool use.

   Executes all tool calls and returns a formatted message
   containing all results, suitable for continuing the conversation.

   RESPONSE - A parsed Claude API response.
   CAPABILITIES - Available capabilities.

   Returns a message alist or NIL if no tool calls."
  (let ((results (execute-all-tool-calls response capabilities)))
    (when results
      (format-tool-results results))))
