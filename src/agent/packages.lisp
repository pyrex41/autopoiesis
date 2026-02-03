;;;; packages.lisp - Agent layer package definitions
;;;;
;;;; Defines packages for agent runtime, capabilities, and spawning.

(in-package #:cl-user)

(defpackage #:autopoiesis.agent
  (:use #:cl #:alexandria #:autopoiesis.core)
  (:export
   ;; Agent class
   #:agent
   #:make-agent
   #:agent-id
   #:agent-name
   #:agent-state
   #:agent-capabilities
   #:agent-thought-stream
   #:agent-parent
   #:agent-children

   ;; Agent lifecycle
   #:start-agent
   #:stop-agent
   #:pause-agent
   #:resume-agent
   #:agent-running-p

   ;; Cognitive loop
   #:cognitive-cycle
   #:perceive
   #:reason
   #:decide
   #:act
   #:reflect

   ;; Capability system
   #:capability
   #:make-capability
   #:capability-name
   #:capability-function
   #:capability-parameters
   #:capability-permissions
   #:capability-description
   #:register-capability
   #:unregister-capability
   #:find-capability
   #:invoke-capability
   #:list-capabilities
   #:defcapability
   #:parse-defcapability-body
   #:parse-capability-params
   #:*capability-registry*

   ;; Context window
   #:context-window
   #:make-context-window
   #:context-content
   #:context-max-size
   #:context-priority-queue
   #:context-add
   #:context-remove
   #:context-focus
   #:context-defocus
   #:context-size
   #:context-item-count
   #:context-total-items
   #:context-clear
   #:context-to-sexpr
   #:sexpr-to-context

   ;; Priority queue (internal but exported for testing)
   #:priority-queue
   #:make-priority-queue
   #:pqueue-push
   #:pqueue-pop
   #:pqueue-peek
   #:pqueue-remove
   #:pqueue-empty-p
   #:pqueue-size
   #:pqueue-map
   #:pqueue-do
   #:pqueue-items
   #:pqueue-clear

   ;; Agent spawning
   #:spawn-agent
   #:spawn-with-snapshot
   #:agent-lineage

   ;; Built-in capabilities
   #:*current-agent*
   #:with-current-agent
   #:capability-introspect
   #:capability-spawn
   #:capability-communicate
   #:capability-receive
   #:register-builtin-capabilities

   ;; Message system
   #:message
   #:make-message
   #:message-id
   #:message-from
   #:message-to
   #:message-content
   #:message-timestamp
   #:send-message
   #:receive-messages
   #:*agent-mailboxes*))
