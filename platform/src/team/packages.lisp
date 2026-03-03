;;;; packages.lisp - Package definition for team coordination layer
;;;;
;;;; Teams coordinate multiple agents working together on complex tasks
;;;; using configurable strategies (leader-worker, parallel, pipeline,
;;;; debate, consensus).

(in-package #:cl-user)

(defpackage #:autopoiesis.team
  (:use #:cl #:alexandria)
  (:local-nicknames (#:bt #:bordeaux-threads))
  (:export
   ;; Team class
   #:team
   #:team-id
   #:team-strategy
   #:team-leader
   #:team-members
   #:team-status
   #:team-workspace-id
   #:team-task
   #:team-config
   #:team-created-at

   ;; Lifecycle
   #:create-team
   #:start-team
   #:pause-team
   #:resume-team
   #:disband-team
   #:query-team-status

   ;; Registry
   #:*team-registry*
   #:*team-registry-lock*
   #:register-team
   #:find-team
   #:list-teams
   #:active-teams

   ;; Strategy protocol
   #:strategy-initialize
   #:strategy-assign-work
   #:strategy-collect-results
   #:strategy-handle-failure
   #:strategy-complete-p

   ;; Strategy classes
   #:make-strategy
   #:leader-worker-strategy
   #:parallel-strategy
   #:pipeline-strategy
   #:debate-strategy
   #:consensus-strategy

   ;; Serialization
   #:team-to-plist
   #:plist-to-team))
