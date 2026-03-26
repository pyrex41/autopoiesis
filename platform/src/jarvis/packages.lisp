;;;; packages.lisp - Jarvis conversational loop package definitions
;;;;
;;;; Defines the package for unified NL->tool dispatch via CLI providers
;;;; (rho, Pi, or any provider implementing provider-send).

(in-package #:cl-user)

(defpackage #:autopoiesis.jarvis
  (:use #:cl #:alexandria #:autopoiesis.core)
  (:export
   ;; Session class
   #:jarvis-session
   #:make-jarvis-session
   #:jarvis-session-id
   #:jarvis-agent
   #:jarvis-provider
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
   #:jarvis-prompt-streaming

   ;; Tool dispatch
   #:parse-tool-call
   #:dispatch-tool-call
   #:invoke-tool

   ;; Human-in-the-loop
   #:jarvis-request-human-input

   ;; Query tools (generative UI)
   #:make-block
   #:result-with-blocks
   #:query-snapshots
   #:diff-snapshots
   #:sandbox-file-tree
   #:list-sandboxes
   #:rollback-sandbox
   #:query-events))
