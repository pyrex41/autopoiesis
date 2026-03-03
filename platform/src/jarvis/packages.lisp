;;;; packages.lisp - Jarvis conversational loop package definitions
;;;;
;;;; Defines the package for unified NL->tool dispatch using Pi RPC streaming.

(in-package #:cl-user)

(defpackage #:autopoiesis.jarvis
  (:use #:cl #:alexandria #:autopoiesis.core)
  (:export
   ;; Session class
   #:jarvis-session
   #:make-jarvis-session
   #:jarvis-session-id
   #:jarvis-agent
   #:jarvis-pi-provider
   #:jarvis-tool-context
   #:jarvis-conversation-history
   #:jarvis-supervisor-enabled-p

   ;; Lifecycle
   #:start-jarvis
   #:start-jarvis-with-team
   #:stop-jarvis

   ;; Conversation
   #:jarvis-prompt

   ;; Tool dispatch
   #:parse-tool-call
   #:dispatch-tool-call
   #:invoke-tool

   ;; Human-in-the-loop
   #:jarvis-request-human-input))
