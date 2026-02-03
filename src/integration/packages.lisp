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
   #:mcp-get-resource

   ;; Tool registry
   #:external-tool
   #:make-external-tool
   #:register-external-tool
   #:unregister-external-tool
   #:find-external-tool
   #:invoke-external-tool
   #:list-external-tools))
