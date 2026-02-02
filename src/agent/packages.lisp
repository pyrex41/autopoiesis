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

   ;; Agent spawning
   #:spawn-agent
   #:spawn-with-snapshot
   #:agent-lineage))
