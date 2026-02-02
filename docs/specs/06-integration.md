# Autopoiesis: External Integrations

## Specification Document 06: Integration Layer

**Version:** 0.1.0-draft
**Status:** Specification
**Last Updated:** 2026-02-02

---

## Overview

The Integration Layer connects Autopoiesis to external systems: Claude Code for AI capabilities, MCP servers for extensible tools, and various external services. This layer translates between Autopoiesis's homoiconic S-expression world and external APIs while maintaining the snapshot and introspection guarantees.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         INTEGRATION LAYER                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      CLAUDE BRIDGE                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │   │
│  │  │   Session   │  │  Message    │  │     Tool Call               │  │   │
│  │  │   Manager   │  │  Adapter    │  │     Handler                 │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      MCP INTEGRATION                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │   │
│  │  │   Server    │  │  Tool       │  │     Resource                │  │   │
│  │  │   Manager   │  │  Registry   │  │     Manager                 │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      EXTERNAL TOOLS                                  │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │   │
│  │  │ File System │  │    Web      │  │     Shell                   │  │   │
│  │  │   Access    │  │   Fetch     │  │     Commands                │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Claude Code Bridge

The Claude Bridge connects Autopoiesis agents to Claude's language model capabilities using the Claude Code paradigm.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; claude-bridge.lisp - Claude Code integration
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.integration)

;;; ─────────────────────────────────────────────────────────────────
;;; Bridge Configuration
;;; ─────────────────────────────────────────────────────────────────

(defclass claude-bridge ()
  ((api-key :initarg :api-key
            :accessor bridge-api-key)
   (model :initarg :model
          :accessor bridge-model
          :initform "claude-sonnet-4-20250514")
   (max-tokens :initarg :max-tokens
               :accessor bridge-max-tokens
               :initform 8192)
   (sessions :initarg :sessions
             :accessor bridge-sessions
             :initform (make-hash-table :test 'equal))
   (tool-handlers :initarg :tool-handlers
                  :accessor bridge-tool-handlers
                  :initform (make-hash-table :test 'equal)))
  (:documentation "Bridge between Autopoiesis and Claude API"))

(defvar *claude-bridge* nil
  "Global Claude bridge instance.")

(defun initialize-claude-bridge (&key api-key model)
  "Initialize the Claude bridge."
  (setf *claude-bridge*
        (make-instance 'claude-bridge
                       :api-key (or api-key (get-env "ANTHROPIC_API_KEY"))
                       :model (or model "claude-sonnet-4-20250514")))
  ;; Register default tool handlers
  (register-default-tool-handlers *claude-bridge*)
  *claude-bridge*)

;;; ─────────────────────────────────────────────────────────────────
;;; Session Management
;;; ─────────────────────────────────────────────────────────────────

(defclass claude-session ()
  ((id :initarg :id
       :accessor session-id
       :initform (make-uuid))
   (agent-id :initarg :agent-id
             :accessor session-agent-id)
   (messages :initarg :messages
             :accessor session-messages
             :initform nil)
   (system-prompt :initarg :system-prompt
                  :accessor session-system-prompt)
   (tools :initarg :tools
          :accessor session-tools
          :initform nil)
   (created-at :initarg :created-at
               :accessor session-created-at
               :initform (get-universal-time)))
  (:documentation "A conversation session with Claude"))

(defun create-claude-session (agent &key system-prompt tools)
  "Create a new Claude session for AGENT."
  (let ((session (make-instance 'claude-session
                                :agent-id (agent-id agent)
                                :system-prompt (or system-prompt
                                                   (generate-system-prompt agent))
                                :tools (or tools
                                           (agent-tools-as-claude-tools agent)))))
    (setf (gethash (session-id session) (bridge-sessions *claude-bridge*))
          session)
    session))

(defun generate-system-prompt (agent)
  "Generate Claude system prompt based on agent configuration."
  (format nil "You are an AI agent named ~a operating within the Autopoiesis platform.

Your capabilities include: ~{~a~^, ~}

Your current task context will be provided in the user messages.

You can use tools to interact with the environment. Each tool call will be recorded
and can be reviewed by human operators.

Be concise and focused. Explain your reasoning before taking actions.
If uncertain, you may request human input using the request_human_input tool."
          (agent-name agent)
          (mapcar #'capability-name
                  (hash-table-values (agent-capabilities agent)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Message Conversion
;;; ─────────────────────────────────────────────────────────────────

(defun context-to-claude-messages (context)
  "Convert Autopoiesis context to Claude message format."
  (let ((messages nil))
    (dolist (item context)
      (let ((role (context-item-role item))
            (content (context-item-content item)))
        (push `(:role ,(ecase role
                         (:user "user")
                         (:agent "assistant")
                         (:system "user")
                         (:tool-result "user"))
                :content ,(sexpr-to-claude-content content))
              messages)))
    (nreverse messages)))

(defun sexpr-to-claude-content (sexpr)
  "Convert S-expression content to Claude content format."
  (typecase sexpr
    (string sexpr)
    (list
     (cond
       ;; Tool result
       ((eq (first sexpr) 'tool-result)
        `((:type "tool_result"
           :tool_use_id ,(second sexpr)
           :content ,(format nil "~a" (third sexpr)))))
       ;; Default: format as string
       (t (format nil "~s" sexpr))))
    (t (format nil "~a" sexpr))))

(defun claude-response-to-thoughts (response)
  "Convert Claude response to Autopoiesis thoughts."
  (let ((thoughts nil))
    ;; Extract text blocks
    (dolist (block (getf response :content))
      (cond
        ((equal (getf block :type) "text")
         (push (make-thought (getf block :text)
                             :type :reasoning
                             :provenance :claude)
               thoughts))
        ((equal (getf block :type) "tool_use")
         (push (make-action (intern (string-upcase (getf block :name)) :keyword)
                            :id (getf block :id)
                            :arguments (getf block :input))
               thoughts))))
    (nreverse thoughts)))

;;; ─────────────────────────────────────────────────────────────────
;;; Tool Definitions
;;; ─────────────────────────────────────────────────────────────────

(defun agent-tools-as-claude-tools (agent)
  "Convert agent capabilities to Claude tool definitions."
  (let ((tools nil))
    (maphash (lambda (name capability)
               (push (capability-to-claude-tool capability) tools))
             (agent-capabilities agent))
    tools))

(defun capability-to-claude-tool (capability)
  "Convert a Autopoiesis capability to Claude tool format."
  `(:name ,(string-downcase (string (capability-name capability)))
    :description ,(capability-documentation capability)
    :input_schema ,(capability-params-to-json-schema
                    (capability-parameters capability))))

(defun capability-params-to-json-schema (params)
  "Convert capability parameters to JSON schema."
  (let ((properties (make-hash-table :test 'equal))
        (required nil))
    (dolist (param params)
      (destructuring-bind (name type &key required-p default doc) param
        (setf (gethash (string-downcase (string name)) properties)
              `(:type ,(lisp-type-to-json-type type)
                :description ,(or doc "")))
        (when required-p
          (push (string-downcase (string name)) required))))
    `(:type "object"
      :properties ,properties
      :required ,(nreverse required))))

(defun lisp-type-to-json-type (type)
  "Convert Lisp type to JSON schema type."
  (case type
    ((string) "string")
    ((integer fixnum) "integer")
    ((float single-float double-float) "number")
    ((boolean) "boolean")
    ((list) "array")
    (t "string")))

;;; ─────────────────────────────────────────────────────────────────
;;; API Communication
;;; ─────────────────────────────────────────────────────────────────

(defun send-to-claude (session messages &key tools)
  "Send messages to Claude API and get response."
  (let* ((request-body
           `(:model ,(bridge-model *claude-bridge*)
             :max_tokens ,(bridge-max-tokens *claude-bridge*)
             :system ,(session-system-prompt session)
             :messages ,messages
             ,@(when tools `(:tools ,tools))))
         (response (http-post "https://api.anthropic.com/v1/messages"
                              :headers `(("x-api-key" . ,(bridge-api-key *claude-bridge*))
                                         ("anthropic-version" . "2023-06-01")
                                         ("content-type" . "application/json"))
                              :body (json-encode request-body))))

    ;; Parse response
    (let ((parsed (json-decode (response-body response))))
      ;; Check for errors
      (when (getf parsed :error)
        (error 'autopoiesis-error
               :message (format nil "Claude API error: ~a"
                                (getf (getf parsed :error) :message))))
      parsed)))

;;; ─────────────────────────────────────────────────────────────────
;;; Tool Execution
;;; ─────────────────────────────────────────────────────────────────

(defun handle-tool-calls (agent response session)
  "Handle tool calls from Claude response."
  (let ((results nil)
        (content (getf response :content)))
    (dolist (block content)
      (when (equal (getf block :type) "tool_use")
        (let* ((tool-name (getf block :name))
               (tool-id (getf block :id))
               (arguments (getf block :input))
               (result (execute-tool agent tool-name arguments)))

          ;; Create snapshot for tool call
          (create-snapshot agent
                           :type :action
                           :trigger `(:tool-call ,tool-name))

          ;; Record result
          (push `(:type "tool_result"
                  :tool_use_id ,tool-id
                  :content ,(format nil "~a" result))
                results))))
    (nreverse results)))

(defun execute-tool (agent tool-name arguments)
  "Execute a tool and return result."
  (let* ((capability-name (intern (string-upcase tool-name) :keyword))
         (capability (gethash capability-name (agent-capabilities agent))))
    (if capability
        (handler-case
            (apply (capability-implementation capability)
                   (plist-to-keyword-args arguments))
          (error (e)
            (format nil "Error executing ~a: ~a" tool-name e)))
        (format nil "Unknown tool: ~a" tool-name))))

;;; ─────────────────────────────────────────────────────────────────
;;; Agent Thinking via Claude
;;; ─────────────────────────────────────────────────────────────────

(defun claude-think (agent context)
  "Use Claude to generate thoughts for AGENT given CONTEXT."
  (let* ((session (or (find-session-for-agent (agent-id agent))
                      (create-claude-session agent)))
         (messages (context-to-claude-messages context))
         (tools (session-tools session)))

    ;; Send to Claude
    (let ((response (send-to-claude session messages :tools tools)))

      ;; Check if Claude wants to use tools
      (when (equal (getf response :stop_reason) "tool_use")
        ;; Execute tools and continue
        (let ((tool-results (handle-tool-calls agent response session)))
          ;; Add assistant message and tool results
          (setf messages (append messages
                                 `((:role "assistant"
                                    :content ,(getf response :content)))
                                 (mapcar (lambda (r)
                                           `(:role "user" :content (,r)))
                                         tool-results)))
          ;; Continue conversation
          (setf response (send-to-claude session messages :tools tools))))

      ;; Convert response to thoughts
      (claude-response-to-thoughts response))))

;;; ─────────────────────────────────────────────────────────────────
;;; Bidirectional Sync
;;; ─────────────────────────────────────────────────────────────────

(defun sync-agent-with-claude-session (agent session)
  "Synchronize agent state with Claude session."
  ;; Push agent context to session
  (setf (session-messages session)
        (context-to-claude-messages
         (context-content (agent-context-window agent))))

  ;; Update tools based on current capabilities
  (setf (session-tools session)
        (agent-tools-as-claude-tools agent)))

(defun import-claude-session (session-data)
  "Import a Claude Code session into Autopoiesis."
  (let* ((agent (spawn-agent '(:class agent :name "imported-agent")))
         (session (create-claude-session agent)))
    ;; Import messages as context
    (dolist (msg (getf session-data :messages))
      (context-add (agent-context-window agent)
                   (claude-message-to-context-item msg)))
    ;; Create snapshot
    (create-snapshot agent :type :genesis :trigger :import)
    agent))
```

---

## MCP Server Integration

Model Context Protocol integration for extensible tools.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; mcp.lisp - MCP server integration
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.integration)

;;; ─────────────────────────────────────────────────────────────────
;;; MCP Server Management
;;; ─────────────────────────────────────────────────────────────────

(defclass mcp-server ()
  ((name :initarg :name
         :accessor server-name)
   (command :initarg :command
            :accessor server-command
            :documentation "Command to start the server")
   (args :initarg :args
         :accessor server-args
         :initform nil)
   (env :initarg :env
        :accessor server-env
        :initform nil)
   (process :initarg :process
            :accessor server-process
            :initform nil)
   (transport :initarg :transport
              :accessor server-transport
              :initform :stdio
              :documentation ":stdio or :sse")
   (tools :initarg :tools
          :accessor server-tools
          :initform nil
          :documentation "Tools provided by this server")
   (resources :initarg :resources
              :accessor server-resources
              :initform nil)
   (status :initarg :status
           :accessor server-status
           :initform :disconnected))
  (:documentation "An MCP server connection"))

(defvar *mcp-servers* (make-hash-table :test 'equal)
  "Connected MCP servers.")

;;; ─────────────────────────────────────────────────────────────────
;;; Connection Management
;;; ─────────────────────────────────────────────────────────────────

(defun connect-mcp-server (config)
  "Connect to an MCP server based on CONFIG."
  (let* ((name (getf config :name))
         (command (getf config :command))
         (args (getf config :args))
         (env (getf config :env))
         (server (make-instance 'mcp-server
                                :name name
                                :command command
                                :args args
                                :env env)))

    ;; Start server process
    (setf (server-process server)
          (run-program command args
                       :input :stream
                       :output :stream
                       :error :stream
                       :environment env
                       :wait nil))

    ;; Initialize protocol
    (mcp-initialize server)

    ;; Discover tools
    (mcp-list-tools server)

    ;; Register
    (setf (gethash name *mcp-servers*) server
          (server-status server) :connected)

    ;; Create capabilities from MCP tools
    (register-mcp-tools-as-capabilities server)

    server))

(defun disconnect-mcp-server (name)
  "Disconnect from MCP server NAME."
  (let ((server (gethash name *mcp-servers*)))
    (when server
      ;; Send shutdown
      (mcp-send server "notifications/cancelled" nil)

      ;; Kill process
      (when (server-process server)
        (process-kill (server-process server)))

      ;; Unregister tools
      (unregister-mcp-tools server)

      ;; Remove from registry
      (remhash name *mcp-servers*)
      (setf (server-status server) :disconnected))))

(defun disconnect-all-mcp-servers ()
  "Disconnect all MCP servers."
  (maphash (lambda (name server)
             (declare (ignore server))
             (disconnect-mcp-server name))
           *mcp-servers*))

;;; ─────────────────────────────────────────────────────────────────
;;; MCP Protocol
;;; ─────────────────────────────────────────────────────────────────

(defvar *mcp-request-id* 0)

(defun mcp-send (server method params)
  "Send an MCP request to SERVER."
  (let* ((id (incf *mcp-request-id*))
         (request `(:jsonrpc "2.0"
                    :id ,id
                    :method ,method
                    :params ,params))
         (json (json-encode request))
         (stream (process-input (server-process server))))

    ;; Write request
    (format stream "~a~%" json)
    (force-output stream)

    ;; Read response
    (let* ((response-line (read-line (process-output (server-process server))))
           (response (json-decode response-line)))

      ;; Check for error
      (when (getf response :error)
        (error 'autopoiesis-error
               :message (format nil "MCP error: ~a"
                                (getf (getf response :error) :message))))

      (getf response :result))))

(defun mcp-initialize (server)
  "Initialize MCP connection with SERVER."
  (let ((result (mcp-send server "initialize"
                          `(:protocolVersion "2024-11-05"
                            :capabilities (:tools t :resources t)
                            :clientInfo (:name "Autopoiesis" :version "0.1.0")))))
    (setf (server-tools server) (getf result :capabilities))
    result))

(defun mcp-list-tools (server)
  "List available tools from SERVER."
  (let ((result (mcp-send server "tools/list" nil)))
    (setf (server-tools server) (getf result :tools))
    (server-tools server)))

(defun mcp-call-tool (server tool-name arguments)
  "Call a tool on SERVER."
  (mcp-send server "tools/call"
            `(:name ,tool-name :arguments ,arguments)))

(defun mcp-list-resources (server)
  "List available resources from SERVER."
  (let ((result (mcp-send server "resources/list" nil)))
    (setf (server-resources server) (getf result :resources))
    (server-resources server)))

(defun mcp-read-resource (server uri)
  "Read a resource from SERVER."
  (mcp-send server "resources/read" `(:uri ,uri)))

;;; ─────────────────────────────────────────────────────────────────
;;; Tool Registration
;;; ─────────────────────────────────────────────────────────────────

(defun register-mcp-tools-as-capabilities (server)
  "Register MCP tools as Autopoiesis capabilities."
  (dolist (tool (server-tools server))
    (let* ((name (intern (string-upcase (getf tool :name)) :keyword))
           (description (getf tool :description))
           (schema (getf tool :inputSchema))
           (server-name (server-name server)))

      (register-capability
       (make-instance 'capability
         :name name
         :documentation description
         :parameters (json-schema-to-params schema)
         :source :mcp
         :author server-name
         :implementation (lambda (&rest args)
                           (mcp-call-tool
                            (gethash server-name *mcp-servers*)
                            (string-downcase (string name))
                            (apply #'make-plist args))))))))

(defun unregister-mcp-tools (server)
  "Unregister tools from SERVER."
  (dolist (tool (server-tools server))
    (let ((name (intern (string-upcase (getf tool :name)) :keyword)))
      (remhash name *capability-registry*))))

(defun json-schema-to-params (schema)
  "Convert JSON schema to capability parameters."
  (let ((params nil)
        (properties (getf schema :properties))
        (required (getf schema :required)))
    (maphash (lambda (name spec)
               (push `(,(intern (string-upcase name) :keyword)
                       ,(json-type-to-lisp-type (getf spec :type))
                       :required-p ,(member name required :test #'equal)
                       :doc ,(getf spec :description))
                     params))
             properties)
    (nreverse params)))

(defun json-type-to-lisp-type (json-type)
  "Convert JSON type to Lisp type."
  (cond
    ((equal json-type "string") 'string)
    ((equal json-type "integer") 'integer)
    ((equal json-type "number") 'float)
    ((equal json-type "boolean") 'boolean)
    ((equal json-type "array") 'list)
    ((equal json-type "object") 'hash-table)
    (t t)))
```

---

## External Tools

Built-in tools for file system, web, and shell access.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; tools.lisp - Built-in external tools
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.integration)

;;; ─────────────────────────────────────────────────────────────────
;;; File System Tools
;;; ─────────────────────────────────────────────────────────────────

(defcapability read-file (path &key start-line end-line)
  "Read contents of a file at PATH"
  :cost 0.001
  :latency :instant
  :side-effects nil
  :source :builtin
  :body
  (handler-case
      (with-open-file (in path)
        (let ((lines (loop for line = (read-line in nil nil)
                           for i from 1
                           while line
                           when (and (or (null start-line) (>= i start-line))
                                     (or (null end-line) (<= i end-line)))
                           collect line)))
          (format nil "~{~a~%~}" lines)))
    (error (e)
      (format nil "Error reading file: ~a" e))))

(defcapability write-file (path content)
  "Write CONTENT to file at PATH"
  :cost 0.001
  :latency :instant
  :side-effects (:file-system)
  :source :builtin
  :body
  (handler-case
      (progn
        (ensure-directories-exist path)
        (with-open-file (out path :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
          (write-string content out))
        (format nil "Successfully wrote ~a bytes to ~a"
                (length content) path))
    (error (e)
      (format nil "Error writing file: ~a" e))))

(defcapability list-directory (path &key pattern recursive)
  "List contents of directory at PATH"
  :cost 0.001
  :latency :instant
  :side-effects nil
  :source :builtin
  :body
  (handler-case
      (let ((entries (if recursive
                         (directory (merge-pathnames (or pattern "*.*") path))
                         (directory (merge-pathnames (or pattern "*") path)))))
        (format nil "~{~a~%~}" (mapcar #'namestring entries)))
    (error (e)
      (format nil "Error listing directory: ~a" e))))

(defcapability file-exists (path)
  "Check if file exists at PATH"
  :cost 0.0
  :latency :instant
  :side-effects nil
  :source :builtin
  :body
  (if (probe-file path) "true" "false"))

(defcapability glob-files (pattern &key base-directory)
  "Find files matching PATTERN"
  :cost 0.01
  :latency :fast
  :side-effects nil
  :source :builtin
  :body
  (let* ((base (or base-directory (uiop:getcwd)))
         (matches (directory (merge-pathnames pattern base))))
    (format nil "~{~a~%~}" (mapcar #'namestring matches))))

(defcapability grep-files (pattern &key path file-pattern)
  "Search for PATTERN in files"
  :cost 0.05
  :latency :medium
  :side-effects nil
  :source :builtin
  :body
  (let ((results nil)
        (search-path (or path (uiop:getcwd)))
        (file-glob (or file-pattern "**/*")))
    (dolist (file (directory (merge-pathnames file-glob search-path)))
      (when (probe-file file)
        (handler-case
            (with-open-file (in file)
              (loop for line = (read-line in nil nil)
                    for line-num from 1
                    while line
                    when (search pattern line)
                    do (push (format nil "~a:~a: ~a"
                                     (namestring file) line-num line)
                             results)))
          (error () nil))))  ; Skip unreadable files
    (format nil "~{~a~%~}" (nreverse results))))

;;; ─────────────────────────────────────────────────────────────────
;;; Web Tools
;;; ─────────────────────────────────────────────────────────────────

(defcapability web-fetch (url &key method headers body)
  "Fetch content from URL"
  :cost 0.01
  :latency :medium
  :side-effects nil
  :source :builtin
  :body
  (handler-case
      (let ((response (http-request url
                                    :method (or method :get)
                                    :additional-headers headers
                                    :content body)))
        (if (stringp response)
            response
            (flexi-streams:octets-to-string response)))
    (error (e)
      (format nil "Error fetching URL: ~a" e))))

(defcapability web-search (query &key num-results)
  "Search the web for QUERY"
  :cost 0.02
  :latency :medium
  :side-effects nil
  :source :builtin
  :body
  ;; This would integrate with a search API
  (format nil "Web search for: ~a (not implemented - requires search API)"
          query))

;;; ─────────────────────────────────────────────────────────────────
;;; Shell Tools
;;; ─────────────────────────────────────────────────────────────────

(defcapability run-command (command &key working-directory timeout)
  "Run a shell command"
  :cost 0.01
  :latency :medium
  :side-effects (:shell)
  :source :builtin
  :body
  (handler-case
      (let* ((dir (or working-directory (uiop:getcwd)))
             (result (uiop:run-program command
                                       :directory dir
                                       :output :string
                                       :error-output :string
                                       :ignore-error-status t)))
        result)
    (error (e)
      (format nil "Error running command: ~a" e))))

(defcapability git-status (&key directory)
  "Get git status"
  :cost 0.01
  :latency :fast
  :side-effects nil
  :source :builtin
  :body
  (run-command "git status --porcelain"
               :working-directory directory))

(defcapability git-diff (&key directory staged)
  "Get git diff"
  :cost 0.01
  :latency :fast
  :side-effects nil
  :source :builtin
  :body
  (run-command (if staged "git diff --staged" "git diff")
               :working-directory directory))

;;; ─────────────────────────────────────────────────────────────────
;;; Tool Registration
;;; ─────────────────────────────────────────────────────────────────

(defun register-builtin-tools ()
  "Register all built-in tools."
  ;; File tools
  (register-capability (find-capability 'read-file))
  (register-capability (find-capability 'write-file))
  (register-capability (find-capability 'list-directory))
  (register-capability (find-capability 'file-exists))
  (register-capability (find-capability 'glob-files))
  (register-capability (find-capability 'grep-files))

  ;; Web tools
  (register-capability (find-capability 'web-fetch))
  (register-capability (find-capability 'web-search))

  ;; Shell tools
  (register-capability (find-capability 'run-command))
  (register-capability (find-capability 'git-status))
  (register-capability (find-capability 'git-diff)))
```

---

## Event System

For coordination between integrations and core system.

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; events.lisp - Integration event system
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.integration)

;;; ─────────────────────────────────────────────────────────────────
;;; Event Types
;;; ─────────────────────────────────────────────────────────────────

(deftype integration-event-type ()
  '(member
    :tool-called
    :tool-result
    :claude-request
    :claude-response
    :mcp-connected
    :mcp-disconnected
    :mcp-error
    :external-error))

(defclass integration-event ()
  ((type :initarg :type
         :accessor event-type
         :type integration-event-type)
   (source :initarg :source
           :accessor event-source
           :documentation "What integration produced this event")
   (agent-id :initarg :agent-id
             :accessor event-agent-id)
   (data :initarg :data
         :accessor event-data)
   (timestamp :initarg :timestamp
              :accessor event-timestamp
              :initform (get-precise-time)))
  (:documentation "An event from the integration layer"))

;;; ─────────────────────────────────────────────────────────────────
;;; Event Bus
;;; ─────────────────────────────────────────────────────────────────

(defvar *event-handlers* (make-hash-table :test 'eq))
(defvar *event-history* nil)
(defvar *max-event-history* 1000)

(defun emit-integration-event (type source data &key agent-id)
  "Emit an integration event."
  (let ((event (make-instance 'integration-event
                              :type type
                              :source source
                              :agent-id agent-id
                              :data data)))
    ;; Add to history
    (push event *event-history*)
    (when (> (length *event-history*) *max-event-history*)
      (setf *event-history* (subseq *event-history* 0 *max-event-history*)))

    ;; Call handlers
    (dolist (handler (gethash type *event-handlers*))
      (funcall handler event))

    ;; Create snapshot if agent-related
    (when agent-id
      (let ((agent (find-agent agent-id)))
        (when agent
          (maybe-create-snapshot agent type))))

    event))

(defun subscribe-to-event (type handler)
  "Subscribe HANDLER to events of TYPE."
  (push handler (gethash type *event-handlers*)))

(defun unsubscribe-from-event (type handler)
  "Unsubscribe HANDLER from events of TYPE."
  (setf (gethash type *event-handlers*)
        (remove handler (gethash type *event-handlers*))))

;;; ─────────────────────────────────────────────────────────────────
;;; Default Event Handlers
;;; ─────────────────────────────────────────────────────────────────

(defun setup-default-event-handlers ()
  "Set up default event handling."

  ;; Log all tool calls
  (subscribe-to-event :tool-called
    (lambda (event)
      (log:info "Tool called: ~a by agent ~a"
                (getf (event-data event) :tool)
                (event-agent-id event))))

  ;; Notify on errors
  (subscribe-to-event :external-error
    (lambda (event)
      (log:error "External error from ~a: ~a"
                 (event-source event)
                 (getf (event-data event) :error))
      (notify-human (format nil "Error in ~a: ~a"
                            (event-source event)
                            (getf (event-data event) :error))
                    :type :error)))

  ;; Track MCP server status
  (subscribe-to-event :mcp-connected
    (lambda (event)
      (log:info "MCP server connected: ~a"
                (getf (event-data event) :server-name))))

  (subscribe-to-event :mcp-disconnected
    (lambda (event)
      (log:warn "MCP server disconnected: ~a"
                (getf (event-data event) :server-name)))))
```

---

## Next Document

Continue to [07-implementation-roadmap.md](./07-implementation-roadmap.md) for the phased implementation plan.
