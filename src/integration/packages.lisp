;;;; packages.lisp - Integration layer package definitions
;;;;
;;;; Defines packages for external integrations (Claude API, MCP, tools).

(in-package #:cl-user)

(defpackage #:autopoiesis.integration
  (:use #:cl #:alexandria #:autopoiesis.core #:autopoiesis.agent)
  (:export
   ;; Claude bridge
   #:claude-client
   #:make-claude-client
   #:client-api-key
   #:client-model
   #:client-base-url
   #:client-max-tokens
   #:client-api-version
   #:claude-complete
   #:claude-stream
   #:claude-tool-use
   #:with-claude-session
   #:response-text
   #:response-tool-calls
   #:response-stop-reason
   #:response-usage

   ;; Message formatting
   #:format-message
   #:parse-response
   #:extract-tool-calls
   #:format-tool-result

   ;; MCP integration
   #:mcp-server
   #:make-mcp-server
   #:mcp-connect
   #:mcp-disconnect
   #:mcp-call-tool
   #:mcp-list-tools
   #:mcp-list-resources
   #:mcp-get-resource
   #:mcp-name
   #:mcp-command
   #:mcp-args
   #:mcp-connected-p
   #:mcp-tools
   #:mcp-resources
   #:mcp-server-info
   #:mcp-server-capabilities
   #:find-mcp-server
   #:list-mcp-servers
   #:register-mcp-server
   #:unregister-mcp-server
   #:disconnect-all-mcp-servers
   #:connect-mcp-server-config
   #:mcp-server-status
   #:mcp-tool-to-capability
   #:register-mcp-tools-as-capabilities
   #:unregister-mcp-tools
   #:*mcp-servers*

   ;; Tool registry
   #:external-tool
   #:make-external-tool
   #:register-external-tool
   #:unregister-external-tool
   #:find-external-tool
   #:invoke-external-tool
   #:list-external-tools

   ;; Tool mapping (capability <-> Claude tool)
   #:capability-to-claude-tool
   #:capabilities-to-claude-tools
   #:agent-capabilities-to-claude-tools
   #:claude-tool-to-capability
   #:execute-tool-call
   #:execute-all-tool-calls
   #:handle-tool-use-response
   #:format-tool-results
   #:lisp-type-to-json-type
   #:json-type-to-lisp-type
   #:capability-params-to-json-schema
   #:json-schema-to-capability-params
   #:lisp-name-to-tool-name
   #:tool-name-to-lisp-name

   ;; Claude session management
   #:claude-session
   #:make-claude-session
   #:claude-session-id
   #:claude-session-agent-id
   #:claude-session-messages
   #:claude-session-system-prompt
   #:claude-session-tools
   #:claude-session-created-at
   #:claude-session-updated-at
   #:claude-session-metadata
   #:create-claude-session-for-agent
   #:find-claude-session
   #:find-claude-session-for-agent
   #:list-claude-sessions
   #:delete-claude-session
   #:claude-session-add-message
   #:claude-session-add-assistant-response
   #:claude-session-add-tool-results
   #:claude-session-clear-messages
   #:claude-session-to-sexpr
   #:sexpr-to-claude-session
   #:sync-claude-session-tools
   #:generate-system-prompt
   #:*claude-session-registry*

   ;; Built-in tools
   #:read-file
   #:write-file
   #:list-directory
   #:file-exists-p
   #:delete-file-tool
   #:glob-files
   #:grep-files
   #:web-fetch
   #:web-head
   #:run-command
   #:git-status
   #:git-diff
   #:git-log
   #:register-builtin-tools
   #:unregister-builtin-tools
   #:list-builtin-tools
   #:*builtin-tools-registered*

   ;; Integration events
   #:integration-event-type
   #:integration-event
   #:make-integration-event
   #:integration-event-id
   #:integration-event-kind
   #:integration-event-source
   #:integration-event-agent-id
   #:integration-event-data
   #:integration-event-timestamp
   #:event-to-sexpr
   #:sexpr-to-event
   #:emit-integration-event
   #:subscribe-to-event
   #:unsubscribe-from-event
   #:subscribe-to-all-events
   #:unsubscribe-from-all-events
   #:clear-event-handlers
   #:clear-event-history
   #:get-event-history
   #:count-events
   #:with-events-disabled
   #:with-event-handler
   #:setup-default-event-handlers
   #:remove-default-event-handlers
   #:*event-handlers*
   #:*global-event-handlers*
   #:*event-history*
   #:*max-event-history*
   #:*events-enabled*
   #:*default-handlers-installed*))
