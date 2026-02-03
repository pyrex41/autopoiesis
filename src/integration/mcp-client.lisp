;;;; mcp-client.lisp - Model Context Protocol client
;;;;
;;;; Connect to MCP servers for extended capabilities via stdio transport.
;;;; Implements JSON-RPC 2.0 protocol as specified by MCP.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; MCP Server Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass mcp-server ()
  ((name :initarg :name
         :accessor mcp-name
         :documentation "Unique server name")
   (command :initarg :command
            :accessor mcp-command
            :documentation "Command to start the server (e.g., 'npx')")
   (args :initarg :args
         :accessor mcp-args
         :initform nil
         :documentation "Command arguments")
   (env :initarg :env
        :accessor mcp-env
        :initform nil
        :documentation "Environment variables as alist")
   (working-directory :initarg :working-directory
                      :accessor mcp-working-directory
                      :initform nil
                      :documentation "Working directory for server process")
   (process :initarg :process
            :accessor mcp-process
            :initform nil
            :documentation "SBCL process object when connected")
   (input-stream :initarg :input-stream
                 :accessor mcp-input-stream
                 :initform nil
                 :documentation "Stream to write to server")
   (output-stream :initarg :output-stream
                  :accessor mcp-output-stream
                  :initform nil
                  :documentation "Stream to read from server")
   (error-stream :initarg :error-stream
                 :accessor mcp-error-stream
                 :initform nil
                 :documentation "Error output stream")
   (connected :initarg :connected
              :accessor mcp-connected-p
              :initform nil
              :documentation "Connection state")
   (server-info :initarg :server-info
                :accessor mcp-server-info
                :initform nil
                :documentation "Server info from initialize response")
   (server-capabilities :initarg :server-capabilities
                        :accessor mcp-server-capabilities
                        :initform nil
                        :documentation "Server capabilities from initialize")
   (tools :initarg :tools
          :accessor mcp-tools
          :initform nil
          :documentation "Available tools from server")
   (resources :initarg :resources
              :accessor mcp-resources
              :initform nil
              :documentation "Available resources from server")
   (request-id :initarg :request-id
               :accessor mcp-request-id
               :initform 0
               :documentation "Counter for JSON-RPC request IDs")
   (lock :initarg :lock
         :accessor mcp-lock
         :documentation "Lock for thread-safe operations"))
  (:documentation "An MCP server connection using stdio transport"))

(defmethod initialize-instance :after ((server mcp-server) &key)
  "Initialize the lock for the MCP server."
  (setf (mcp-lock server) (bt:make-lock (format nil "mcp-~a" (mcp-name server)))))

(defun make-mcp-server (name command &key args env working-directory)
  "Create an MCP server configuration.

   NAME - Unique identifier for this server
   COMMAND - Command to run (e.g., 'npx', 'node', 'python')
   ARGS - List of command arguments
   ENV - Alist of environment variables
   WORKING-DIRECTORY - Working directory for the process"
  (make-instance 'mcp-server
                 :name name
                 :command command
                 :args args
                 :env env
                 :working-directory working-directory))

;;; ═══════════════════════════════════════════════════════════════════
;;; MCP Server Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *mcp-servers* (make-hash-table :test 'equal)
  "Registry of connected MCP servers by name.")

(defun find-mcp-server (name)
  "Find an MCP server by name."
  (gethash name *mcp-servers*))

(defun list-mcp-servers ()
  "List all registered MCP servers."
  (loop for server being the hash-values of *mcp-servers*
        collect server))

(defun register-mcp-server (server)
  "Register an MCP server in the global registry."
  (setf (gethash (mcp-name server) *mcp-servers*) server))

(defun unregister-mcp-server (name)
  "Unregister an MCP server from the global registry."
  (remhash name *mcp-servers*))

;;; ═══════════════════════════════════════════════════════════════════
;;; JSON-RPC Protocol
;;; ═══════════════════════════════════════════════════════════════════

(defun next-request-id (server)
  "Get the next request ID for SERVER."
  (bt:with-lock-held ((mcp-lock server))
    (incf (mcp-request-id server))))

(defun make-jsonrpc-request (id method &optional params)
  "Create a JSON-RPC 2.0 request.

   ID - Request identifier
   METHOD - Method name (string)
   PARAMS - Method parameters (optional)"
  `(("jsonrpc" . "2.0")
    ("id" . ,id)
    ("method" . ,method)
    ,@(when params `(("params" . ,params)))))

(defun make-jsonrpc-notification (method &optional params)
  "Create a JSON-RPC 2.0 notification (no id, no response expected).

   METHOD - Method name (string)
   PARAMS - Method parameters (optional)"
  `(("jsonrpc" . "2.0")
    ("method" . ,method)
    ,@(when params `(("params" . ,params)))))

(defun send-jsonrpc (server request)
  "Send a JSON-RPC request to SERVER and return the response.

   Handles newline-delimited JSON protocol."
  (unless (mcp-connected-p server)
    (error 'autopoiesis.core:autopoiesis-error
           :message (format nil "MCP server ~a not connected" (mcp-name server))))
  (bt:with-lock-held ((mcp-lock server))
    (let ((json-str (cl-json:encode-json-to-string request))
          (input (mcp-input-stream server))
          (output (mcp-output-stream server)))
      ;; Send request (newline-delimited JSON)
      (write-string json-str input)
      (write-char #\Newline input)
      (force-output input)
      ;; Read response
      (let ((response-line (read-line output nil nil)))
        (unless response-line
          (error 'autopoiesis.core:autopoiesis-error
                 :message (format nil "No response from MCP server ~a" (mcp-name server))))
        (let ((response (cl-json:decode-json-from-string response-line)))
          ;; Check for error
          (let ((err (cdr (assoc :error response))))
            (when err
              (error 'autopoiesis.core:autopoiesis-error
                     :message (format nil "MCP error from ~a: ~a (code: ~a)"
                                      (mcp-name server)
                                      (cdr (assoc :message err))
                                      (cdr (assoc :code err))))))
          ;; Return result
          (cdr (assoc :result response)))))))

(defun send-jsonrpc-notification (server notification)
  "Send a JSON-RPC notification to SERVER (no response expected)."
  (unless (mcp-connected-p server)
    (error 'autopoiesis.core:autopoiesis-error
           :message (format nil "MCP server ~a not connected" (mcp-name server))))
  (bt:with-lock-held ((mcp-lock server))
    (let ((json-str (cl-json:encode-json-to-string notification))
          (input (mcp-input-stream server)))
      (write-string json-str input)
      (write-char #\Newline input)
      (force-output input))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Connection Management
;;; ═══════════════════════════════════════════════════════════════════

(defun mcp-connect (server)
  "Connect to an MCP server by starting its process.

   Starts the server process, performs MCP initialization handshake,
   and discovers available tools."
  (when (mcp-connected-p server)
    (error 'autopoiesis.core:autopoiesis-error
           :message (format nil "MCP server ~a already connected" (mcp-name server))))

  ;; Build command line
  (let* ((cmd (mcp-command server))
         (args (mcp-args server))
         (full-command (format nil "~a~{ ~a~}" cmd args)))

    ;; Start process with bidirectional streams
    (multiple-value-bind (process)
        (sb-ext:run-program cmd args
                            :input :stream
                            :output :stream
                            :error :stream
                            :wait nil
                            :search t
                            :directory (mcp-working-directory server)
                            :environment (mcp-env server))
      (unless process
        (error 'autopoiesis.core:autopoiesis-error
               :message (format nil "Failed to start MCP server: ~a" full-command)))

      ;; Store process and streams
      (setf (mcp-process server) process
            (mcp-input-stream server) (sb-ext:process-input process)
            (mcp-output-stream server) (sb-ext:process-output process)
            (mcp-error-stream server) (sb-ext:process-error process)
            (mcp-connected-p server) t)

      ;; Perform MCP initialization
      (handler-case
          (progn
            (mcp-initialize server)
            (mcp-discover-tools server)
            ;; Register in global registry
            (register-mcp-server server))
        (error (e)
          ;; Clean up on initialization failure
          (mcp-disconnect server)
          (error e)))

      server)))

(defun mcp-disconnect (server)
  "Disconnect from an MCP server by terminating its process."
  (when (mcp-connected-p server)
    ;; Try to send shutdown notification
    (ignore-errors
      (send-jsonrpc-notification server
                                  (make-jsonrpc-notification "notifications/cancelled")))
    ;; Close streams
    (ignore-errors
      (when (mcp-input-stream server)
        (close (mcp-input-stream server))))
    (ignore-errors
      (when (mcp-output-stream server)
        (close (mcp-output-stream server))))
    (ignore-errors
      (when (mcp-error-stream server)
        (close (mcp-error-stream server))))
    ;; Terminate process
    (when (mcp-process server)
      (ignore-errors
        (sb-ext:process-kill (mcp-process server) sb-unix:sigterm))
      ;; Give it a moment to terminate gracefully
      (sleep 0.1)
      ;; Force kill if still alive
      (ignore-errors
        (when (sb-ext:process-alive-p (mcp-process server))
          (sb-ext:process-kill (mcp-process server) sb-unix:sigkill))))
    ;; Clear state
    (setf (mcp-process server) nil
          (mcp-input-stream server) nil
          (mcp-output-stream server) nil
          (mcp-error-stream server) nil
          (mcp-connected-p server) nil
          (mcp-tools server) nil
          (mcp-resources server) nil
          (mcp-server-info server) nil
          (mcp-server-capabilities server) nil)
    ;; Unregister from global registry
    (unregister-mcp-server (mcp-name server)))
  server)

(defun disconnect-all-mcp-servers ()
  "Disconnect all connected MCP servers."
  (maphash (lambda (name server)
             (declare (ignore name))
             (ignore-errors (mcp-disconnect server)))
           *mcp-servers*)
  (clrhash *mcp-servers*))

;;; ═══════════════════════════════════════════════════════════════════
;;; MCP Protocol Methods
;;; ═══════════════════════════════════════════════════════════════════

(defun mcp-initialize (server)
  "Perform MCP initialization handshake with SERVER.

   Sends initialize request and initialized notification."
  (let* ((request-id (next-request-id server))
         (request (make-jsonrpc-request
                   request-id
                   "initialize"
                   `(("protocolVersion" . "2024-11-05")
                     ("capabilities" . (("tools" . t)
                                        ("resources" . t)))
                     ("clientInfo" . (("name" . "Autopoiesis")
                                      ("version" . "0.1.0"))))))
         (result (send-jsonrpc server request)))
    ;; Store server info
    (setf (mcp-server-info server) (cdr (assoc :server-info result))
          (mcp-server-capabilities server) (cdr (assoc :capabilities result)))
    ;; Send initialized notification
    (send-jsonrpc-notification server
                                (make-jsonrpc-notification "notifications/initialized"))
    result))

(defun mcp-discover-tools (server)
  "Discover available tools from SERVER."
  (when (and (mcp-server-capabilities server)
             (cdr (assoc :tools (mcp-server-capabilities server))))
    (let* ((request-id (next-request-id server))
           (request (make-jsonrpc-request request-id "tools/list"))
           (result (send-jsonrpc server request)))
      (setf (mcp-tools server) (cdr (assoc :tools result)))
      (mcp-tools server))))

(defun mcp-discover-resources (server)
  "Discover available resources from SERVER."
  (when (and (mcp-server-capabilities server)
             (cdr (assoc :resources (mcp-server-capabilities server))))
    (let* ((request-id (next-request-id server))
           (request (make-jsonrpc-request request-id "resources/list"))
           (result (send-jsonrpc server request)))
      (setf (mcp-resources server) (cdr (assoc :resources result)))
      (mcp-resources server))))

(defun mcp-list-tools (server)
  "List tools available on SERVER.

   Returns cached tools if available, otherwise discovers them."
  (unless (mcp-connected-p server)
    (error 'autopoiesis.core:autopoiesis-error
           :message (format nil "MCP server ~a not connected" (mcp-name server))))
  (or (mcp-tools server)
      (mcp-discover-tools server)))

(defun mcp-call-tool (server tool-name arguments)
  "Call a tool on SERVER.

   TOOL-NAME - Name of the tool to call (string)
   ARGUMENTS - Alist of tool arguments"
  (unless (mcp-connected-p server)
    (error 'autopoiesis.core:autopoiesis-error
           :message (format nil "MCP server ~a not connected" (mcp-name server))))
  (let* ((request-id (next-request-id server))
         (request (make-jsonrpc-request
                   request-id
                   "tools/call"
                   `(("name" . ,tool-name)
                     ("arguments" . ,arguments))))
         (result (send-jsonrpc server request)))
    ;; Result should contain content array
    (cdr (assoc :content result))))

(defun mcp-list-resources (server)
  "List resources available on SERVER.

   Returns cached resources if available, otherwise discovers them."
  (unless (mcp-connected-p server)
    (error 'autopoiesis.core:autopoiesis-error
           :message (format nil "MCP server ~a not connected" (mcp-name server))))
  (or (mcp-resources server)
      (mcp-discover-resources server)))

(defun mcp-get-resource (server resource-uri)
  "Get a resource from SERVER.

   RESOURCE-URI - URI of the resource to fetch"
  (unless (mcp-connected-p server)
    (error 'autopoiesis.core:autopoiesis-error
           :message (format nil "MCP server ~a not connected" (mcp-name server))))
  (let* ((request-id (next-request-id server))
         (request (make-jsonrpc-request
                   request-id
                   "resources/read"
                   `(("uri" . ,resource-uri))))
         (result (send-jsonrpc server request)))
    (cdr (assoc :contents result))))

;;; ═══════════════════════════════════════════════════════════════════
;;; MCP Tool to Capability Bridge
;;; ═══════════════════════════════════════════════════════════════════

(defun mcp-tool-to-capability (tool server-name)
  "Convert an MCP tool definition to an Autopoiesis capability.

   TOOL - MCP tool definition alist
   SERVER-NAME - Name of the MCP server providing this tool"
  (let* ((tool-name (cdr (assoc :name tool)))
         (description (or (cdr (assoc :description tool)) ""))
         (input-schema (cdr (assoc :input-schema tool)))
         (cap-name (tool-name-to-lisp-name tool-name))
         ;; Include MCP source info in description
         (full-description (format nil "~a [MCP: ~a]" description server-name)))
    (autopoiesis.agent:make-capability
     cap-name
     ;; Handler that calls the MCP server
     (lambda (&rest args)
       (let ((server (find-mcp-server server-name)))
         (unless server
           (error 'autopoiesis.core:autopoiesis-error
                  :message (format nil "MCP server ~a not found" server-name)))
         ;; Convert keyword args to alist
         (let ((arguments (loop for (key value) on args by #'cddr
                                collect (cons (string-downcase (string key)) value))))
           (mcp-call-tool server tool-name arguments))))
     :description full-description
     :parameters (when input-schema (json-schema-to-capability-params input-schema)))))

(defun register-mcp-tools-as-capabilities (server &key registry)
  "Register all tools from SERVER as Autopoiesis capabilities.

   REGISTRY - Optional capability registry (uses global registry if not specified)

   Returns the list of registered capabilities."
  (let ((server-name (mcp-name server))
        (capabilities nil))
    (dolist (tool (mcp-tools server))
      (let ((cap (mcp-tool-to-capability tool server-name)))
        (if registry
            (autopoiesis.agent:register-capability cap :registry registry)
            (autopoiesis.agent:register-capability cap))
        (push cap capabilities)))
    (nreverse capabilities)))

(defun unregister-mcp-tools (server &key registry)
  "Unregister all tools from SERVER from the capability registry.

   REGISTRY - Optional capability registry (uses global registry if not specified)"
  (dolist (tool (mcp-tools server))
    (let* ((tool-name (cdr (assoc :name tool)))
           (cap-name (tool-name-to-lisp-name tool-name)))
      (if registry
          (autopoiesis.agent:unregister-capability cap-name :registry registry)
          (autopoiesis.agent:unregister-capability cap-name)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Convenience Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun connect-mcp-server-config (config)
  "Connect to an MCP server from a configuration plist.

   CONFIG should contain:
     :name - Server name
     :command - Command to run
     :args - (optional) List of arguments
     :env - (optional) Environment variables
     :working-directory - (optional) Working directory"
  (let ((server (make-mcp-server
                 (getf config :name)
                 (getf config :command)
                 :args (getf config :args)
                 :env (getf config :env)
                 :working-directory (getf config :working-directory))))
    (mcp-connect server)))

(defun mcp-server-status (server)
  "Get the status of an MCP server as a plist."
  `(:name ,(mcp-name server)
    :connected ,(mcp-connected-p server)
    :command ,(mcp-command server)
    :args ,(mcp-args server)
    :tools-count ,(length (mcp-tools server))
    :resources-count ,(length (mcp-resources server))
    :server-info ,(mcp-server-info server)))
