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

   ;; Snapshot persistence
   #:snapshot-store
   #:make-snapshot-store
   #:initialize-store
   #:*snapshot-store*
   #:save-snapshot
   #:load-snapshot
   #:delete-snapshot
   #:snapshot-exists-p
   #:snapshot-to-sexpr
   #:sexpr-to-snapshot
   #:list-snapshots
   #:find-snapshot-by-timestamp
   #:snapshot-children
   #:snapshot-ancestors
   #:snapshot-descendants
   #:save-store-index
   #:load-store-index
   #:rebuild-store-index
   #:clear-snapshot-cache
   #:snapshot-cache-stats
   #:close-store

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
   #:*current-snapshot*

   ;; DAG traversal
   #:collect-ancestor-ids
   #:find-common-ancestor
   #:find-path
   #:dag-distance
   #:is-ancestor-p
   #:is-descendant-p
   #:dag-depth
   #:find-root
   #:find-branch-point
   #:walk-ancestors
   #:walk-descendants
   #:find-snapshots-between

   ;; Event log
   #:event
   #:make-event
   #:event-id
   #:event-type
   #:event-timestamp
   #:event-data
   #:append-event
   #:replay-events
   #:compact-events
   #:event-log-count
   #:clear-event-log

   ;; Checkpoint
   #:checkpoint
   #:make-checkpoint
   #:checkpoint-id
   #:checkpoint-timestamp
   #:checkpoint-state
   #:checkpoint-event-count

   ;; LRU Cache
   #:lru-cache
   #:make-lru-cache
   #:cache-get
   #:cache-put
   #:cache-remove
   #:cache-contains-p
   #:cache-clear
   #:cache-size
   #:cache-capacity
   #:cache-hits
   #:cache-misses
   #:cache-evictions
   #:cache-hit-rate
   #:cache-stats
   #:reset-cache-stats
   #:cache-keys
   #:map-cache
   #:resize-cache

   ;; Lazy Loading
   #:lazy-snapshot
   #:make-lazy-snapshot
   #:lazy-snapshot-id
   #:lazy-snapshot-timestamp
   #:lazy-snapshot-parent-id
   #:lazy-snapshot-loaded-p
   #:lazy-snapshot-content
   #:ensure-snapshot-loaded
   #:make-lazy-snapshot-from-index

   ;; Lazy DAG Iterator
   #:lazy-dag-iterator
   #:make-lazy-dag-iterator
   #:iterator-next-batch
   #:iterator-exhausted-p

   ;; Paginated Queries
   #:list-snapshots-paginated
   #:list-children-paginated
   #:walk-descendants-paginated
   #:walk-ancestors-paginated

   ;; Lazy Loading Utilities
   #:prefetch-snapshots
   #:get-dag-statistics
   #:find-snapshots-by-time-range
   #:collect-snapshot-ids-lazy))
