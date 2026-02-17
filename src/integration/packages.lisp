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
   ;; Self-extension tools
   #:define-capability-tool
   #:test-capability-tool
   #:promote-capability-tool
   ;; Introspection tools
   #:list-capabilities-tool
   #:inspect-thoughts
   ;; Orchestration tools (Phase 5)
   #:spawn-agent
   #:query-agent
   #:await-agent
   #:update-sub-agent
   #:funcall-agent-task
   ;; Cognitive branching tools (Phase 5)
   #:fork-branch
   #:compare-branches
   ;; Session management tools (Phase 5)
   #:save-session
   #:resume-session

   ;; Provider macro
   #:define-cli-provider

   ;; Provider protocol
   #:provider
   #:provider-name
   #:provider-command
   #:provider-working-directory
   #:provider-default-model
   #:provider-max-turns
   #:provider-timeout
   #:provider-env
   #:provider-extra-args
   #:provider-lock
   #:provider-process
   #:provider-session-id
   #:provider-supported-modes
   #:provider-invoke
   #:provider-build-command
   #:provider-parse-output
   #:provider-format-tools
   #:provider-alive-p
   #:provider-start-session
   #:provider-send
   #:provider-stop-session
   #:provider-to-sexpr
   #:provider-status

   ;; Provider registry
   #:*provider-registry*
   #:register-provider
   #:unregister-provider
   #:find-provider
   #:list-providers

   ;; Provider subprocess
   #:run-provider-subprocess

   ;; Provider result
   #:provider-result
   #:make-provider-result
   #:provider-result-provider-name
   #:provider-result-text
   #:provider-result-tool-calls
   #:provider-result-turns
   #:provider-result-cost
   #:provider-result-duration
   #:provider-result-raw-output
   #:provider-result-exit-code
   #:provider-result-error-output
   #:provider-result-session-id
   #:provider-result-metadata
   #:result-success-p
   #:provider-result-to-sexpr
   #:sexpr-to-provider-result
   #:record-provider-exchange

   ;; Claude Code provider
   #:claude-code-provider
   #:make-claude-code-provider
   #:claude-code-skip-permissions
   #:claude-code-max-budget-usd

   ;; Codex provider
   #:codex-provider
   #:make-codex-provider
   #:codex-full-auto

   ;; OpenCode provider
   #:opencode-provider
   #:make-opencode-provider
   #:opencode-use-server
   #:opencode-server-port

   ;; Cursor provider
   #:cursor-provider
   #:make-cursor-provider
   #:cursor-mode
   #:cursor-force

   ;; Provider-backed agent
   #:provider-backed-agent
   #:make-provider-backed-agent
   #:provider-agent-prompt
   #:provider-backed-agent-to-sexpr
   #:agent-provider
   #:agent-system-prompt
   #:agent-invocation-mode

   ;; Agentic loop
   #:agentic-loop
   #:agentic-complete
   #:*claude-complete-function*

   ;; Agentic agent
   #:agentic-agent
   #:make-agentic-agent
   #:agent-client
   #:agent-inference-provider
   #:agent-max-turns
   #:agent-conversation-history
   #:agent-conversation-context
   #:agent-tool-capabilities
   #:agentic-agent-prompt
   #:agentic-agent-to-sexpr
   #:init-conversation-context
   #:fork-agent-context
   #:record-turn-if-context

   ;; OpenAI bridge
   #:openai-client
   #:make-openai-client
   #:openai-client-api-key
   #:openai-client-model
   #:openai-client-base-url
   #:openai-client-max-tokens
   #:openai-complete
   #:claude-messages-to-openai
   #:claude-tools-to-openai
   #:openai-response-to-claude-format

   ;; Inference provider
   #:inference-provider
   #:make-inference-provider
   #:make-anthropic-provider
   #:make-openai-provider
   #:make-ollama-provider
   #:provider-api-client
   #:provider-api-format
   #:provider-complete-function
   #:provider-capabilities
   #:provider-system-prompt
   #:sexpr-to-inference-provider

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
