;;;; packages.lisp - API layer package definitions
;;;;
;;;; Defines the package for the autopoiesis API layer, including:
;;;; - WebSocket server (Clack/Lack/Woo) for real-time frontend connectivity
;;;; - REST server (Hunchentoot) for external agent system integration
;;;; - MCP server for Model Context Protocol support
;;;;
;;;; Wire format: JSON text frames for control, MessagePack binary
;;;; frames for data streams (WebSocket), JSON over HTTP (REST).

(in-package #:cl-user)

(defpackage #:autopoiesis.api
  (:use #:cl #:alexandria
        #:autopoiesis.core
        #:autopoiesis.agent
        #:autopoiesis.snapshot
        #:autopoiesis.interface
        #:autopoiesis.integration)
  (:export
   ;; === WebSocket Server (Clack/Woo) ===
   ;; Server lifecycle
   #:start-api-server
   #:stop-api-server
   #:api-server-running-p
   #:*api-server*
   #:*api-port*
   #:*api-host*

   ;; Wire format
   #:wire-format
   #:*stream-format*
   #:encode-control
   #:encode-stream
   #:encode-auto
   #:decode-json
   #:decode-msgpack
   #:encode-json
   #:encode-msgpack

   ;; Connection management
   #:api-connection
   #:connection-id
   #:connection-ws
   #:connection-subscriptions
   #:connection-stream-format
   #:list-connections
   #:find-connection
   #:broadcast-message
   #:broadcast-stream-data
   #:send-to-connection
   #:send-stream-to-connection

   ;; Message protocol
   #:handle-message
   #:encode-message
   #:decode-message

   ;; Serialization helpers (WebSocket - hash-table JSON objects)
   #:json-object
   #:agent-to-json-plist
   #:thought-to-json-plist
   #:snapshot-to-json-plist
   #:branch-to-json-plist
   #:event-to-json-plist
   #:blocking-request-to-json-plist

   ;; === REST Server (Hunchentoot) ===
   ;; Server lifecycle
   #:*rest-server*
   #:*rest-port*
   #:start-rest-server
   #:stop-rest-server
   #:rest-server-running-p

   ;; Authentication
   #:*api-keys*
   #:*api-require-auth*
   #:register-api-key
   #:revoke-api-key
   #:validate-api-key

   ;; SSE event streaming
   #:*sse-clients*
   #:sse-broadcast

   ;; Serialization helpers (REST - alists for cl-json)
   #:agent-to-json-alist
   #:snapshot-to-json-alist
   #:branch-to-json-alist
   #:capability-to-json-alist
   #:blocking-request-to-json-alist
   #:thought-to-json-alist
   #:event-to-json-alist

    ;; MCP server
    #:mcp-tool-definitions
    #:handle-mcp-endpoint
    #:*mcp-sessions*

    ;; Activity + Cost tracking
    #:agent-activity
    #:all-activities
    #:agent-cost
    #:cost-summary
    #:start-activity-tracker
    #:stop-activity-tracker
    #:*activity-state*
    #:*cost-state*

    ;; Holodeck bridge (frame serialization)
    #:serialize-holodeck-frame
    #:serialize-entity-desc
    #:serialize-connection-desc
    #:holodeck-single-frame

    ;; Chat handlers (Jarvis bridge)
    #:*chat-sessions*
    #:*chat-sessions-lock*
    #:*chat-session-owners*
    #:cleanup-chat-sessions-for-connection
    #:hash-table-to-plist

    ;; Web console
    #:init-web-console
    #:require-web-auth
    #:require-web-auth-with-permission
    #:*session-cookie-name*
    #:*session-cookie-secure*
    #:*session-cookie-http-only*
    #:*session-cookie-path*
    #:*session-cookie-max-age*))
