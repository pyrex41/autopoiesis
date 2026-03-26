;;;; packages.lisp - Package definition for the orchestration layer
;;;;
;;;; The orchestration layer provides the CL conductor (tick loop,
;;;; timer heap, event processing) and Claude CLI worker. Events,
;;;; workers, and agents are stored as datoms in the substrate.

(in-package #:cl-user)

(defpackage #:autopoiesis.orchestration
  (:use #:cl #:alexandria #:autopoiesis.substrate #:autopoiesis.agent)
  (:export
   ;; Conductor lifecycle
   #:*conductor*
   #:conductor
   #:start-conductor
   #:stop-conductor
   #:conductor-running-p
   #:conductor-status
   ;; Timer heap
   #:conductor-timer-heap
   #:schedule-action
   #:cancel-action
   ;; Event queue (substrate-backed)
   #:queue-event
   #:process-events
   ;; Workers (substrate-backed)
   #:register-worker
   #:unregister-worker
   #:worker-running-p
   #:conductor-active-workers
   ;; Metrics
   #:increment-metric
   #:get-metric
   ;; Claude worker
   #:run-claude-cli
   #:build-claude-command
   #:extract-result
   #:shell-quote
   ;; System lifecycle
   #:start-system
   #:stop-system
   ;; Endpoints
   #:register-conductor-endpoints))
