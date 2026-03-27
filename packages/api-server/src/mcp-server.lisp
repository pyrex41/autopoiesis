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
  "Return the list of MCP tool definitions exposed by this server."
  (list
   ;; --- Agent Lifecycle ---
   `((:name . "list_agents")
     (:description . "List all registered agents")
     (:input-schema . ((:type . "object")
                       (:properties)
                       (:additional-properties . nil))))

   `((:name . "create_agent")
     (:description . "Create a new cognitive agent")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:name . ((:type . "string")
                                   (:description . "Agent name"))))))))

   `((:name . "get_agent")
     (:description . "Get details of a specific agent")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))))
                       (:required . ("agent_id")))))

   `((:name . "start_agent")
     (:description . "Start an agent's cognitive loop")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))))
                       (:required . ("agent_id")))))

   `((:name . "pause_agent")
     (:description . "Pause a running agent")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))))
                       (:required . ("agent_id")))))

   `((:name . "resume_agent")
     (:description . "Resume a paused agent")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))))
                       (:required . ("agent_id")))))

   `((:name . "stop_agent")
     (:description . "Stop an agent")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))))
                       (:required . ("agent_id")))))

   ;; --- Cognitive Operations ---
   `((:name . "cognitive_cycle")
     (:description . "Run one perceive-reason-decide-act-reflect cycle on an agent")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))
                         (:environment . ((:type . "object")
                                          (:description . "Environment data to feed the cycle")))))
                       (:required . ("agent_id")))))

   `((:name . "get_thoughts")
     (:description . "Get recent thoughts from an agent's thought stream")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))
                         (:limit . ((:type . "integer")
                                    (:description . "Max thoughts to return (default 20)")))))
                       (:required . ("agent_id")))))

   `((:name . "list_capabilities")
     (:description . "List an agent's capabilities")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))))
                       (:required . ("agent_id")))))

   `((:name . "invoke_capability")
     (:description . "Invoke a specific capability on behalf of an agent")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))
                         (:capability . ((:type . "string")
                                         (:description . "Capability name")))
                         (:arguments . ((:type . "object")
                                        (:description . "Arguments for the capability")))))
                       (:required . ("agent_id" "capability")))))

   ;; --- Snapshot Operations ---
   `((:name . "take_snapshot")
     (:description . "Capture a point-in-time snapshot of agent cognitive state")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent_id . ((:type . "string")
                                       (:description . "Agent ID")))
                         (:parent . ((:type . "string")
                                     (:description . "Parent snapshot ID")))
                         (:metadata . ((:type . "object")
                                       (:description . "Additional metadata")))))
                       (:required . ("agent_id")))))

   `((:name . "list_snapshots")
     (:description . "List snapshots, optionally filtered by parent")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:parent_id . ((:type . "string")
                                        (:description . "Filter by parent snapshot ID")))
                         (:root_only . ((:type . "boolean")
                                        (:description . "Return only root snapshots"))))))))

   `((:name . "get_snapshot")
     (:description . "Retrieve a specific snapshot by ID")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:snapshot_id . ((:type . "string")
                                          (:description . "Snapshot ID")))))
                       (:required . ("snapshot_id")))))

   `((:name . "diff_snapshots")
     (:description . "Compute the diff between two snapshots")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:from_id . ((:type . "string")
                                      (:description . "Source snapshot ID")))
                         (:to_id . ((:type . "string")
                                    (:description . "Target snapshot ID")))))
                       (:required . ("from_id" "to_id")))))

   ;; --- Branch Operations ---
   `((:name . "list_branches")
     (:description . "List all cognitive branches")
     (:input-schema . ((:type . "object")
                       (:properties)
                       (:additional-properties . nil))))

   `((:name . "create_branch")
     (:description . "Create a new branch for exploring alternative cognitive paths")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:name . ((:type . "string")
                                   (:description . "Branch name")))
                         (:from_snapshot . ((:type . "string")
                                            (:description . "Snapshot to branch from")))))
                       (:required . ("name")))))

   `((:name . "checkout_branch")
     (:description . "Switch to a different branch")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:name . ((:type . "string")
                                   (:description . "Branch name")))))
                       (:required . ("name")))))

   ;; --- Human-in-the-Loop ---
   `((:name . "list_pending_requests")
     (:description . "List pending human-in-the-loop input requests")
     (:input-schema . ((:type . "object")
                       (:properties)
                       (:additional-properties . nil))))

   `((:name . "respond_to_request")
     (:description . "Provide a human response to a pending blocking request")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:request_id . ((:type . "string")
                                         (:description . "Pending request ID")))
                         (:response . ((:type . "string")
                                       (:description . "The response to provide")))))
                       (:required . ("request_id" "response")))))

   ;; --- System ---
   `((:name . "system_info")
     (:description . "Get Autopoiesis system status: version, agent count, running state")
     (:input-schema . ((:type . "object")
                       (:properties)
                       (:additional-properties . nil))))))

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
  "Dispatch an MCP tools/call request to the appropriate handler.
   Returns a content list for the MCP response."
  (handler-case
      (let ((result (mcp-execute-tool tool-name arguments)))
        (list `(("type" . "text")
                ("text" . ,(cl-json:encode-json-to-string result)))))
    (error (e)
      (list `(("type" . "text")
              ("text" . ,(format nil "Error: ~a" e)))))))

(defun mcp-arg (key arguments)
  "Look up KEY in cl-json decoded ARGUMENTS alist.
   Handles cl-json's underscore-to-double-hyphen convention:
   'agent_id' becomes :AGENT--ID in the alist."
  (cdr (assoc key arguments)))

(defun mcp-execute-tool (tool-name arguments)
  "Execute an MCP tool and return the result as an alist."
  (let ((agent-id (mcp-arg :agent--id arguments))
        (snapshot-id (mcp-arg :snapshot--id arguments)))
    (cond
      ;; --- Agent Lifecycle ---
      ((string= tool-name "list_agents")
       (mapcar #'agent-to-json-alist (autopoiesis.agent:list-agents)))

      ((string= tool-name "create_agent")
       (let* ((name (or (cdr (assoc :name arguments)) "unnamed"))
              (agent (autopoiesis.agent:make-agent :name name)))
         (autopoiesis.agent:register-agent agent)
         (agent-to-json-alist agent)))

      ((string= tool-name "get_agent")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (agent-to-json-alist agent)))

      ((string= tool-name "start_agent")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (autopoiesis.agent:start-agent agent)
         (agent-to-json-alist agent)))

      ((string= tool-name "pause_agent")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (autopoiesis.agent:pause-agent agent)
         (agent-to-json-alist agent)))

      ((string= tool-name "resume_agent")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (autopoiesis.agent:resume-agent agent)
         (agent-to-json-alist agent)))

      ((string= tool-name "stop_agent")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (autopoiesis.agent:stop-agent agent)
         (agent-to-json-alist agent)))

      ;; --- Cognitive Operations ---
      ((string= tool-name "cognitive_cycle")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (let ((env (cdr (assoc :environment arguments)))
               (result (autopoiesis.agent:cognitive-cycle agent
                         (cdr (assoc :environment arguments)))))
           (declare (ignore env))
           `((:agent--id . ,agent-id)
             (:state . ,(string-downcase (string (autopoiesis.agent:agent-state agent))))
             (:result . ,(when result (prin1-to-string result)))))))

      ((string= tool-name "get_thoughts")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (let* ((limit (or (cdr (assoc :limit arguments)) 20))
                (stream (autopoiesis.agent:agent-thought-stream agent))
                (thoughts (autopoiesis.core:stream-last stream limit)))
           (mapcar #'thought-to-json-alist thoughts))))

      ((string= tool-name "list_capabilities")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (loop for name in (autopoiesis.agent:agent-capabilities agent)
               for cap = (autopoiesis.agent:find-capability name)
               when cap collect (capability-to-json-alist cap))))

      ((string= tool-name "invoke_capability")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (let* ((cap-name (cdr (assoc :capability arguments)))
                (cap-args (cdr (assoc :arguments arguments)))
                (cap-keyword (or (find-symbol (string-upcase cap-name) :keyword)
                                 (error "Unknown capability: ~a" cap-name)))
                (result (apply #'autopoiesis.agent:invoke-capability
                               cap-keyword
                               (when (listp cap-args)
                                 (loop for (k . v) in cap-args
                                       for kw = (or (find-symbol (string-upcase (string k)) :keyword)
                                                    (error "Unknown argument: ~a" k))
                                       collect kw
                                       collect v)))))
           `((:result . ,(prin1-to-string result))))))

      ;; --- Snapshot Operations ---
      ((string= tool-name "take_snapshot")
       (let ((agent (autopoiesis.agent:find-agent agent-id)))
         (unless agent (error "Agent not found: ~a" agent-id))
         (let* ((parent (cdr (assoc :parent arguments)))
                (metadata (cdr (assoc :metadata arguments)))
                (agent-state `(:agent
                               :id ,(autopoiesis.agent:agent-id agent)
                               :name ,(autopoiesis.agent:agent-name agent)
                               :state ,(autopoiesis.agent:agent-state agent)))
                (snapshot (autopoiesis.snapshot:make-snapshot
                           agent-state :parent parent :metadata metadata)))
           (when autopoiesis.snapshot:*snapshot-store*
             (autopoiesis.snapshot:save-snapshot snapshot))
           (snapshot-to-json-alist snapshot))))

      ((string= tool-name "list_snapshots")
       (let* ((parent-id (mcp-arg :parent--id arguments))
              (root-only (mcp-arg :root--only arguments))
              (ids (autopoiesis.snapshot:list-snapshots
                    :parent-id parent-id
                    :root-only root-only)))
         (loop for id in (if (> (length ids) 100) (subseq ids 0 100) ids)
               for snap = (autopoiesis.snapshot:load-snapshot id)
               when snap collect (snapshot-summary-alist snap))))

      ((string= tool-name "get_snapshot")
       (let ((sid (or snapshot-id (mcp-arg :snapshot--id arguments))))
         (let ((snapshot (autopoiesis.snapshot:load-snapshot sid)))
           (unless snapshot (error "Snapshot not found: ~a" sid))
           (snapshot-to-json-alist snapshot))))

      ((string= tool-name "diff_snapshots")
       (let* ((from-id (mcp-arg :from--id arguments))
              (to-id (mcp-arg :to--id arguments))
              (snap-a (autopoiesis.snapshot:load-snapshot from-id))
              (snap-b (autopoiesis.snapshot:load-snapshot to-id)))
         (unless snap-a (error "Snapshot not found: ~a" from-id))
         (unless snap-b (error "Snapshot not found: ~a" to-id))
         `((:from . ,from-id)
           (:to . ,to-id)
           (:diff . ,(prin1-to-string
                      (autopoiesis.snapshot:snapshot-diff snap-a snap-b))))))

      ;; --- Branch Operations ---
      ((string= tool-name "list_branches")
       (mapcar #'branch-to-json-alist (autopoiesis.snapshot:list-branches)))

      ((string= tool-name "create_branch")
       (let* ((name (cdr (assoc :name arguments)))
              (from-snap (mcp-arg :from--snapshot arguments))
              (branch (autopoiesis.snapshot:create-branch
                       name :from-snapshot from-snap)))
         (branch-to-json-alist branch)))

      ((string= tool-name "checkout_branch")
       (let ((name (cdr (assoc :name arguments))))
         (let ((branch (autopoiesis.snapshot:switch-branch name)))
           (branch-to-json-alist branch))))

      ;; --- Human-in-the-Loop ---
      ((string= tool-name "list_pending_requests")
       (mapcar #'blocking-request-to-json-alist
               (autopoiesis.interface:list-pending-blocking-requests)))

      ((string= tool-name "respond_to_request")
       (let* ((req-id (mcp-arg :request--id arguments))
              (response (cdr (assoc :response arguments))))
         (multiple-value-bind (success req)
             (autopoiesis.interface:respond-to-request req-id response)
           (declare (ignore req))
           (if success
               `((:responded . t) (:request--id . ,req-id))
               (error "Pending request not found: ~a" req-id)))))

      ;; --- System ---
      ((string= tool-name "system_info")
       `((:version . "0.1.0")
         (:platform . "autopoiesis")
         (:agent--count . ,(length (autopoiesis.agent:list-agents)))
         (:running--agents . ,(length (autopoiesis.agent:running-agents)))
         (:branch--count . ,(length (autopoiesis.snapshot:list-branches)))
         (:pending--requests . ,(length
                                 (autopoiesis.interface:list-pending-blocking-requests)))))

      (t (error "Unknown tool: ~a" tool-name)))))

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
