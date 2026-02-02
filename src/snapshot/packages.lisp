;;;; packages.lisp - Snapshot layer package definitions
;;;;
;;;; Defines packages for snapshot persistence, branching, and time-travel.

(in-package #:cl-user)

(defpackage #:autopoiesis.snapshot
  (:use #:cl #:alexandria #:autopoiesis.core)
  (:export
   ;; Snapshot class
   #:snapshot
   #:make-snapshot
   #:snapshot-id
   #:snapshot-timestamp
   #:snapshot-parent
   #:snapshot-agent-state
   #:snapshot-metadata
   #:snapshot-hash

   ;; Content-addressable store
   #:content-store
   #:make-content-store
   #:store-put
   #:store-get
   #:store-exists-p
   #:store-delete
   #:store-gc

   ;; Branch management
   #:branch
   #:make-branch
   #:branch-name
   #:branch-head
   #:branch-history
   #:create-branch
   #:switch-branch
   #:merge-branches
   #:list-branches
   #:current-branch

   ;; Time-travel
   #:checkout-snapshot
   #:snapshot-diff
   #:snapshot-patch
   #:find-snapshot
   #:snapshot-ancestors
   #:snapshot-descendants

   ;; Event log
   #:event
   #:make-event
   #:event-type
   #:event-timestamp
   #:event-data
   #:append-event
   #:replay-events
   #:compact-events))
