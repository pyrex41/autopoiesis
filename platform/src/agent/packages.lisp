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

   ;; Agent serialization
   #:agent-to-sexpr
   #:sexpr-to-agent

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
   #:deliver-message
   #:receive-messages
   #:ensure-mailbox
   #:*agent-mailboxes*
   #:*mailboxes-lock*

   ;; Agent registry
   #:*agent-registry*
   #:register-agent
   #:unregister-agent
   #:find-agent
   #:list-agents
   #:running-agents

   ;; Agent-defined capabilities
   #:agent-capability
   #:make-agent-capability
   #:cap-source-agent
   #:cap-source-code
   #:cap-extension-id
   #:cap-test-results
   #:cap-promotion-status
   #:agent-define-capability
   #:test-agent-capability
   #:promote-capability
   #:reject-capability
   #:agent-capability-p
   #:list-agent-capabilities
   #:find-agent-capability

   ;; Learning system - Experience
   #:experience
   #:make-experience
   #:experience-id
   #:experience-task-type
   #:experience-context
   #:experience-actions
   #:experience-outcome
   #:experience-timestamp
   #:experience-agent-id
   #:experience-metadata
   #:experience-to-sexpr
   #:sexpr-to-experience

   ;; Learning system - Heuristic
   #:heuristic
   #:make-heuristic
   #:heuristic-id
   #:heuristic-name
   #:heuristic-condition
   #:heuristic-recommendation
   #:heuristic-confidence
   #:heuristic-applications
   #:heuristic-successes
   #:heuristic-source-pattern
   #:heuristic-created
   #:heuristic-last-applied
   #:heuristic-to-sexpr
   #:sexpr-to-heuristic

   ;; Learning system - Storage
   #:*experience-store*
   #:*heuristic-store*
   #:store-experience
   #:find-experience
   #:list-experiences
   #:clear-experiences
   #:store-heuristic
   #:find-heuristic
   #:list-heuristics
   #:clear-heuristics

   ;; Learning system - Application
   #:record-heuristic-application
   #:decay-heuristic-confidence
   #:condition-matches-p
   #:find-applicable-heuristics

   ;; Learning system - Pattern Extraction
   #:extract-patterns
   #:extract-action-sequences
   #:extract-context-patterns
   #:extract-context-keys
   #:pattern-to-condition
   #:actions-contain-sequence-p

   ;; Learning system - Heuristic Generation
   #:generate-heuristic
   #:generate-recommendation
   #:calculate-pattern-confidence
   #:generate-heuristic-name
   #:generate-heuristics-from-patterns

   ;; Learning system - Heuristic Application
   #:apply-heuristics
   #:decision-context
   #:adjust-decision-weights
   #:alternative-matches-pattern-p
   #:context-key-matches-p
   #:update-heuristic-confidence))
