;;;; api-server.asd - WebSocket API server for Autopoiesis frontends
;;;;
;;;; Separate system so core doesn't require web server dependencies.
;;;; Provides real-time WebSocket connectivity (Clack/Lack/Woo),
;;;; JSON/MessagePack wire format, and frontend event broadcasting.

(asdf:defsystem #:autopoiesis/api
  :description "WebSocket API server for Autopoiesis frontends"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:autopoiesis
               #:clack                ; Web application environment
               #:lack                 ; Middleware composition
               #:woo                  ; Async HTTP server (event-driven)
               #:websocket-driver     ; WebSocket protocol
               #:com.inuoe.jzon      ; Fast, safe JSON (control messages)
               #:cl-messagepack)     ; Binary encoding (data streams)
   :components
   ((:module "src"
     :serial t
     :components
     ((:file "wire-format")
      (:file "serializers")
      (:file "connections")
      (:file "handlers")
      (:file "team-handlers")
      (:file "chat-handlers")
      (:file "agent-runtime")
      (:file "holodeck-sync")
      (:file "events")
      (:file "activity-tracker")
      (:file "holodeck-bridge")
      (:file "web-console")
      (:file "server")))))

;;; API server tests
(asdf:defsystem #:autopoiesis/api-test
  :description "Tests for Autopoiesis WebSocket API"
  :depends-on (#:autopoiesis/api #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "api-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.api.test :run-api-tests)))
