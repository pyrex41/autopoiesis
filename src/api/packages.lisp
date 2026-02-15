;;;; packages.lisp - API layer package definitions
;;;;
;;;; Defines the package for the WebSocket API server built on
;;;; Clack/Lack/Woo that exposes autopoiesis functionality to
;;;; external frontends (3D holodeck, VR clients, terminals, etc.)

(in-package #:cl-user)

(defpackage #:autopoiesis.api
  (:use #:cl
        #:autopoiesis.core
        #:autopoiesis.agent
        #:autopoiesis.snapshot
        #:autopoiesis.interface
        #:autopoiesis.integration)
  (:export
   ;; Server lifecycle
   #:start-api-server
   #:stop-api-server
   #:api-server-running-p
   #:*api-server*
   #:*api-port*
   #:*api-host*

   ;; Connection management
   #:api-connection
   #:connection-id
   #:connection-ws
   #:connection-subscriptions
   #:list-connections
   #:find-connection
   #:broadcast-message
   #:send-to-connection

   ;; Message protocol
   #:handle-message
   #:encode-message
   #:decode-message

   ;; Serialization helpers
   #:agent-to-json-plist
   #:thought-to-json-plist
   #:snapshot-to-json-plist
   #:branch-to-json-plist
   #:event-to-json-plist
   #:blocking-request-to-json-plist))
