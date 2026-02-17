;;;; operations.lisp - Unified operation definition macro
;;;;
;;;; Provides `defoperation` which generates both a REST route handler
;;;; and an MCP tool definition from a single declaration.  Operations
;;;; are registered in *operations* and can be introspected at runtime.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Operation Registry
;;; ===================================================================

(defvar *operations* (make-hash-table :test 'equal)
  "Registry of defined operations. Maps operation name string to
   operation definition plist.")

(defvar *operations-lock* (bordeaux-threads:make-lock "operations-lock"))

(defun register-operation (name definition)
  "Register an operation definition."
  (bordeaux-threads:with-lock-held (*operations-lock*)
    (setf (gethash name *operations*) definition)))

(defun find-operation (name)
  "Find an operation by name."
  (bordeaux-threads:with-lock-held (*operations-lock*)
    (gethash name *operations*)))

(defun list-operations ()
  "List all registered operations."
  (bordeaux-threads:with-lock-held (*operations-lock*)
    (loop for name being the hash-keys of *operations*
          using (hash-value def)
          collect def)))

;;; ===================================================================
;;; Parameter Specification Helpers
;;; ===================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %param-name (param-spec)
    "Extract the parameter name from a param spec.
     Param spec is either a symbol or (name &key type description required)."
    (if (listp param-spec) (first param-spec) param-spec))

  (defun %param-type (param-spec)
    "Extract the parameter type string from a param spec."
    (if (listp param-spec)
        (or (getf (rest param-spec) :type) "string")
        "string"))

  (defun %param-description (param-spec)
    "Extract the parameter description from a param spec."
    (if (listp param-spec)
        (or (getf (rest param-spec) :description) "")
        ""))

  (defun %param-required-p (param-spec)
    "Check if a parameter is marked as required."
    (and (listp param-spec)
         (getf (rest param-spec) :required)))

  (defun %param-to-lisp-var (param-spec)
    "Convert a param spec to a Lisp variable name symbol."
    (let ((name (%param-name param-spec)))
      (if (symbolp name) name (intern (string-upcase (string name))))))

  (defun %param-to-json-key (param-spec)
    "Convert a param spec name to a keyword."
    (let* ((name (%param-name param-spec))
           (name-str (string-downcase (string name))))
      (intern (string-upcase name-str) :keyword)))

  (defun %param-to-mcp-key (param-spec)
    "Convert a param spec to the MCP arguments key (cl-json decoded).
     agent-id in MCP JSON is agent_id, which cl-json decodes as :AGENT--ID."
    (let* ((name (%param-name param-spec))
           (name-str (string-downcase (string name))))
      (intern (string-upcase
               (with-output-to-string (s)
                 (loop for c across name-str
                       do (if (char= c #\-)
                              (write-string "--" s)
                              (write-char c s)))))
              :keyword)))

  (defun %generate-mcp-schema (params)
    "Generate an MCP input-schema from parameter specs."
    (let ((properties
            (loop for p in params
                  for name-str = (substitute #\_ #\-
                                             (string-downcase (string (%param-name p))))
                  collect `(,name-str .
                            ((:type . ,(%param-type p))
                             (:description . ,(%param-description p))))))
          (required
            (loop for p in params
                  when (%param-required-p p)
                    collect (substitute #\_ #\-
                                        (string-downcase (string (%param-name p)))))))
      `((:type . "object")
        (:properties . ,properties)
        ,@(when required `((:required . ,required))))))

  (defun %generate-param-bindings (params)
    "Generate let bindings to extract parameters from ARGS alist.
     ARGS is the cl-json decoded arguments alist (available in handler body).
     Tries MCP key (double-hyphen) first, then simple key as fallback."
    (loop for p in params
          for var = (%param-to-lisp-var p)
          for key = (%param-to-mcp-key p)
          for simple-key = (%param-to-json-key p)
          collect (if (eq key simple-key)
                      `(,var (cdr (assoc ,key args)))
                      `(,var (or (cdr (assoc ,key args))
                                 (cdr (assoc ,simple-key args))))))))

;;; ===================================================================
;;; Main Macro
;;; ===================================================================

(defmacro defoperation (name &body clauses)
  "Define a unified REST + MCP operation.

   NAME is a keyword like :list-agents. The macro generates:
   - A handler function that implements the core logic
   - Registration in the *operations* registry for MCP + REST dispatch

   Supported clauses:
     (:description \"...\")     - Human-readable description
     (:parameters (spec ...))   - Parameter specifications
     (:permission :read|:write|:admin) - Required permission level
     (:handler body...)         - Core handler body
     (:event \"event_name\")    - SSE event to broadcast on success

   Parameter specifications:
     symbol                     - Simple string parameter
     (name :type \"string\" :description \"...\" :required t)
                                - Full parameter spec

   Handler body has access to:
     args     - Full decoded arguments alist
     <params> - Each parameter bound as a variable

   The handler body should return an alist result on success,
   or signal an error on failure."
  (let* ((name-str (string-downcase (substitute #\_ #\- (string name))))
         (handler-sym (intern (string-upcase (format nil "OP-~a" name))
                              :autopoiesis.api))
         ;; Extract clauses
         (description (or (second (find :description clauses :key #'first))
                          (format nil "~a operation" name-str)))
         (params (rest (find :parameters clauses :key #'first)))
         (permission (second (find :permission clauses :key #'first)))
         (handler-clause (find :handler clauses :key #'first))
         (handler-body (when handler-clause (rest handler-clause)))
         (event-name (second (find :event clauses :key #'first)))
         ;; Generated code pieces
         (param-bindings (%generate-param-bindings params))
         (mcp-schema (%generate-mcp-schema params)))

    `(progn
       ;; 1. Core handler function
       (defun ,handler-sym (args)
         ,(format nil "Execute the ~a operation.~%~a" name-str description)
         ,@(if param-bindings
               `((let (,@param-bindings)
                   ,@handler-body))
               `((declare (ignore args))
                 ,@handler-body)))

       ;; 2. Register in operations registry
       (register-operation
        ,name-str
        (list :name ,name-str
              :description ,description
              :permission ,(or permission :read)
              :handler #',handler-sym
              :mcp-schema ',mcp-schema
              ,@(when event-name `(:event ,event-name))))

       ',name)))

;;; ===================================================================
;;; Operation Dispatch
;;; ===================================================================

(defun dispatch-operation (op-name args)
  "Dispatch an operation by name. Returns the raw result.
   Handles permission checking and execution."
  (let ((op (find-operation op-name)))
    (unless op
      (error "Unknown operation: ~a" op-name))
    (let ((perm (getf op :permission)))
      (when perm (require-permission perm)))
    (funcall (getf op :handler) args)))

(defun dispatch-operation-rest (op-name args)
  "Dispatch an operation from a REST context.
   Handles permission checking, execution, SSE broadcast, and JSON response."
  (let ((op (find-operation op-name)))
    (unless op
      (return-from dispatch-operation-rest
        (json-not-found "Operation" op-name)))
    (let ((perm (getf op :permission)))
      (when perm (require-permission perm)))
    (handler-case
        (let* ((handler (getf op :handler))
               (result (funcall handler args))
               (event (getf op :event)))
          (when (and event result)
            (sse-broadcast event result))
          (json-ok result))
      (error (e)
        (json-error (format nil "~a" e) :status 500 :error-type "Internal Error")))))

(defun dispatch-operation-mcp (op-name args)
  "Dispatch an operation from an MCP context.
   Returns the result alist directly (MCP layer handles JSON-RPC wrapping)."
  (let ((op (find-operation op-name)))
    (unless op
      (error "Unknown operation: ~a" op-name))
    (funcall (getf op :handler) args)))

(defun operation-mcp-tool-definitions ()
  "Generate MCP tool definitions from all registered operations."
  (bordeaux-threads:with-lock-held (*operations-lock*)
    (loop for name being the hash-keys of *operations*
          using (hash-value op)
          collect `((:name . ,name)
                    (:description . ,(getf op :description))
                    (:input-schema . ,(getf op :mcp-schema))))))
