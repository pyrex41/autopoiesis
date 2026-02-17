;;;; mcp-server.lisp - MCP Server (Streamable HTTP transport)
;;;;
;;;; Exposes Autopoiesis operations as MCP tools over the Streamable HTTP
;;;; transport. Any MCP-compatible client (Claude Desktop, Go SDK, etc.)
;;;; can connect to this endpoint.
;;;;
;;;; Protocol: JSON-RPC 2.0 over HTTP
;;;; Transport: Streamable HTTP (POST for client→server, GET/SSE for server→client)
;;;; Spec version: 2025-03-26

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; MCP Session Management
;;; ===================================================================

(defvar *mcp-sessions* (make-hash-table :test 'equal)
  "Active MCP sessions. Maps session-id to session plist.")

(defvar *mcp-sessions-lock* (bordeaux-threads:make-lock "mcp-sessions-lock"))

(defun make-mcp-session-id ()
  "Generate a new MCP session ID."
  (autopoiesis.core:make-uuid))

(defun register-mcp-session (session-id &key client-info)
  "Register a new MCP session."
  (bordeaux-threads:with-lock-held (*mcp-sessions-lock*)
    (setf (gethash session-id *mcp-sessions*)
          (list :id session-id
                :client-info client-info
                :initialized nil
                :created (get-universal-time)))))

(defun find-mcp-session (session-id)
  "Find an MCP session by ID."
  (bordeaux-threads:with-lock-held (*mcp-sessions-lock*)
    (gethash session-id *mcp-sessions*)))

(defun remove-mcp-session (session-id)
  "Remove an MCP session."
  (bordeaux-threads:with-lock-held (*mcp-sessions-lock*)
    (remhash session-id *mcp-sessions*)))

(defun mark-mcp-session-initialized (session-id)
  "Mark an MCP session as fully initialized."
  (bordeaux-threads:with-lock-held (*mcp-sessions-lock*)
    (let ((session (gethash session-id *mcp-sessions*)))
      (when session
        (setf (getf session :initialized) t)
        (setf (gethash session-id *mcp-sessions*) session)))))

;;; ===================================================================
;;; MCP Tool Definitions
;;; ===================================================================

(defun mcp-tool-definitions ()
  "Return the list of MCP tool definitions, generated from the operations registry."
  (operation-mcp-tool-definitions))

;;; ===================================================================
;;; Tool Definition Serialization
;;; ===================================================================

(defun tool-def-to-mcp-json (tool-def)
  "Convert an internal tool definition alist to MCP JSON format."
  (let ((name (cdr (assoc :name tool-def)))
        (description (cdr (assoc :description tool-def)))
        (input-schema (cdr (assoc :input-schema tool-def))))
    `(("name" . ,name)
      ("description" . ,description)
      ("inputSchema" . ,(schema-to-json-alist input-schema)))))

(defun schema-to-json-alist (schema)
  "Convert a schema alist to a JSON-ready alist with camelCase keys."
  (when schema
    (loop for (key . value) in schema
          collect (cons (schema-key-to-json key)
                        (cond
                          ;; Nested alist (properties, etc.)
                          ((and (consp value) (consp (car value))
                                (keywordp (caar value)))
                           (schema-to-json-alist value))
                          ;; Property definitions (each is an alist)
                          ((and (consp value) (consp (car value))
                                (not (keywordp (caar value))))
                           (mapcar (lambda (pair)
                                     (cons (car pair)
                                           (if (and (consp (cdr pair))
                                                    (consp (cadr pair)))
                                               (schema-to-json-alist (cdr pair))
                                               (cdr pair))))
                                   value))
                          (t value))))))

(defun schema-key-to-json (key)
  "Convert a schema keyword to JSON key string."
  (case key
    (:type "type")
    (:properties "properties")
    (:required "required")
    (:description "description")
    (:additional-properties "additionalProperties")
    (:input-schema "inputSchema")
    (t (string-downcase (substitute #\_ #\- (string key))))))

;;; ===================================================================
;;; MCP Tool Dispatch
;;; ===================================================================

(defun mcp-call-tool-dispatch (tool-name arguments)
  "Dispatch an MCP tools/call request via the unified operations registry.
   Returns a content list for the MCP response."
  (handler-case
      (let ((result (dispatch-operation-mcp tool-name arguments)))
        (list `(("type" . "text")
                ("text" . ,(cl-json:encode-json-to-string result)))))
    (error (e)
      (list `(("type" . "text")
              ("text" . ,(format nil "Error: ~a" e)))))))

;;; ===================================================================
;;; JSON-RPC Message Handling
;;; ===================================================================

(defun make-jsonrpc-result (id result)
  "Create a JSON-RPC 2.0 success response."
  `(("jsonrpc" . "2.0")
    ("id" . ,id)
    ("result" . ,result)))

(defun make-jsonrpc-error (id code message &optional data)
  "Create a JSON-RPC 2.0 error response."
  `(("jsonrpc" . "2.0")
    ("id" . ,id)
    ("error" . (("code" . ,code)
                ("message" . ,message)
                ,@(when data `(("data" . ,data)))))))

(defun handle-mcp-jsonrpc-message (message session-id)
  "Process a single JSON-RPC message and return the response (or nil for notifications)."
  (let ((method (cdr (assoc :method message)))
        (id (cdr (assoc :id message)))
        (params (cdr (assoc :params message))))
    (cond
      ;; --- initialize ---
      ((string= method "initialize")
       (let ((client-info (cdr (assoc :client-info params)))
             (new-session (or session-id (make-mcp-session-id))))
         (register-mcp-session new-session :client-info client-info)
         (values
          (make-jsonrpc-result id
            `(("protocolVersion" . "2025-03-26")
              ("capabilities" .
               (("tools" . (("listChanged" . t)))))
              ("serverInfo" .
               (("name" . "autopoiesis")
                ("version" . "0.1.0")))
              ("instructions" . "Autopoiesis cognitive backend. Use tools to manage agents, snapshots, branches, and human-in-the-loop requests.")))
          new-session)))

      ;; --- notifications/initialized ---
      ((string= method "notifications/initialized")
       (when session-id
         (mark-mcp-session-initialized session-id))
       (values nil session-id))

      ;; --- ping ---
      ((string= method "ping")
       (values (make-jsonrpc-result id (make-hash-table)) session-id))

      ;; --- tools/list ---
      ((string= method "tools/list")
       (values
        (make-jsonrpc-result id
          `(("tools" . ,(mapcar #'tool-def-to-mcp-json (mcp-tool-definitions)))))
        session-id))

      ;; --- tools/call ---
      ((string= method "tools/call")
       (let* ((tool-name (cdr (assoc :name params)))
              (arguments (cdr (assoc :arguments params))))
         (handler-case
             (let ((content (mcp-call-tool-dispatch tool-name arguments)))
               (values
                (make-jsonrpc-result id
                  `(("content" . ,content)
                    ("isError" . nil)))
                session-id))
           (error (e)
             (values
              (make-jsonrpc-result id
                `(("content" . ((("type" . "text")
                                 ("text" . ,(format nil "~a" e)))))
                  ("isError" . t)))
              session-id)))))

      ;; --- Unknown method ---
      (t
       (if id
           ;; Request - respond with error
           (values
            (make-jsonrpc-error id -32601
              (format nil "Method not found: ~a" method))
            session-id)
           ;; Notification - ignore
           (values nil session-id))))))

;;; ===================================================================
;;; HTTP Handler (Streamable HTTP Transport)
;;; ===================================================================

(defun handle-mcp-endpoint ()
  "Handle the /mcp endpoint for Streamable HTTP transport.
   POST: Receive JSON-RPC messages
   GET: Open SSE stream for server-initiated messages
   DELETE: Terminate session"
  (let* ((request hunchentoot:*request*)
         (method (hunchentoot:request-method request)))
    (cond
      ;; POST /mcp - Client sends JSON-RPC message(s)
      ((eq method :post)
       (handle-mcp-post request))

      ;; GET /mcp - Client opens SSE stream
      ((eq method :get)
       (handle-mcp-sse-stream request))

      ;; DELETE /mcp - Client terminates session
      ((eq method :delete)
       (handle-mcp-delete request))

      (t
       (setf (hunchentoot:return-code*) 405)
       (setf (hunchentoot:content-type*) "application/json")
       (cl-json:encode-json-to-string
        '(("error" . "Method not allowed")))))))

(defun handle-mcp-post (request)
  "Handle POST /mcp - process JSON-RPC message from client."
  (declare (ignore request))
  ;; Get or create session
  (let ((session-id (hunchentoot:header-in* :mcp-session-id)))
    (handler-case
        (let* ((body (hunchentoot:raw-post-data :force-text t))
               (message (cl-json:decode-json-from-string body))
               (method (cdr (assoc :method message))))
          ;; Validate session: if session-id header is provided, it must be valid
          ;; (exception: initialize doesn't need an existing session)
          (when (and session-id
                     (not (string= method "initialize"))
                     (not (find-mcp-session session-id)))
            (setf (hunchentoot:return-code*) 404)
            (setf (hunchentoot:content-type*) "application/json")
            (return-from handle-mcp-post
              (cl-json:encode-json-to-string
               '(("error" . "Session not found or expired")))))
          ;; Handle single message (not batching for now)
          (multiple-value-bind (response new-session-id)
              (handle-mcp-jsonrpc-message message session-id)
            ;; Set session header on initialize response
            (when (and new-session-id (not session-id))
              (setf (hunchentoot:header-out :mcp-session-id) new-session-id))
            (if response
                (progn
                  (setf (hunchentoot:content-type*) "application/json")
                  (cl-json:encode-json-to-string response))
                ;; Notification - no response body
                (progn
                  (setf (hunchentoot:return-code*) 202)
                  ""))))
      (error (e)
        (declare (ignore e))
        (setf (hunchentoot:content-type*) "application/json")
        (setf (hunchentoot:return-code*) 400)
        (cl-json:encode-json-to-string
         (make-jsonrpc-error nil -32700 "Parse error"))))))

(defun handle-mcp-sse-stream (request)
  "Handle GET /mcp - open SSE stream for server-initiated messages."
  (let ((session-id (hunchentoot:header-in* :mcp-session-id)))
    (unless (and session-id (find-mcp-session session-id))
      (setf (hunchentoot:return-code*) 400)
      (setf (hunchentoot:content-type*) "application/json")
      (return-from handle-mcp-sse-stream
        (cl-json:encode-json-to-string
         '(("error" . "No active session. Send initialize first via POST.")))))
    ;; Set SSE headers
    (setf (hunchentoot:content-type*) "text/event-stream")
    (setf (hunchentoot:header-out :cache-control) "no-cache")
    (setf (hunchentoot:header-out :connection) "keep-alive")
    (let ((stream (hunchentoot:send-headers)))
      (handler-case
          (progn
            ;; Send initial keepalive
            (write-string (format nil ": connected~%~%") stream)
            (force-output stream)
            ;; Register as SSE client for event forwarding
            (register-sse-client stream)
            (unwind-protect
                 (loop
                   (sleep 30)
                   (handler-case
                       (progn
                         (write-string (format nil ": heartbeat ~a~%~%"
                                              (get-universal-time))
                                      stream)
                         (force-output stream))
                     (error () (return))))
              (unregister-sse-client stream)
              (ignore-errors (close stream))))
        (error () nil)))))

(defun handle-mcp-delete (request)
  "Handle DELETE /mcp - terminate session."
  (let ((session-id (hunchentoot:header-in* :mcp-session-id)))
    (if (and session-id (find-mcp-session session-id))
        (progn
          (remove-mcp-session session-id)
          (setf (hunchentoot:return-code*) 200)
          (setf (hunchentoot:content-type*) "application/json")
          (cl-json:encode-json-to-string
           `(("terminated" . t) ("session" . ,session-id))))
        (progn
          (setf (hunchentoot:return-code*) 404)
          (setf (hunchentoot:content-type*) "application/json")
          (cl-json:encode-json-to-string
           '(("error" . "Session not found")))))))
