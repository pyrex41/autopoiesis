;;;; packages.lisp - Package definitions for the substrate kernel
;;;;
;;;; The substrate is a datom store with transact!, hooks, indexes,
;;;; and Linda coordination primitives. Everything else in the system
;;;; (snapshots, conversations, conductor events, blob storage) is
;;;; stored as datoms in the substrate.

(in-package #:cl-user)

(defpackage #:autopoiesis.substrate
  (:nicknames #:substrate)
  (:use #:cl #:alexandria)
  (:export
   ;; Context object (replaces individual specials)
   #:*substrate*
   #:substrate-context
   #:make-substrate-context
   #:substrate-context-store
   #:substrate-context-entity-cache
   #:substrate-context-value-index
   #:substrate-context-intern-table
   #:substrate-context-resolve-table
   #:substrate-context-next-entity-id
   #:substrate-context-next-attribute-id
   ;; Store lifecycle
   #:*store*
   #:open-store
   #:close-store
   #:with-store
   ;; Datom
   #:datom
   #:make-datom
   #:d-entity
   #:d-attribute
   #:d-value
   #:d-tx
   #:d-added
   ;; Interning (monotonic counter)
   #:intern-id
   #:resolve-id
   #:reset-intern-tables
   ;; Transactions
   #:transact!
   #:next-tx-id
   #:with-batch-transaction
   ;; Query
   #:entity-attr
   #:entity-attrs
   #:entity-state
   #:entity-history
   #:entity-as-of
   #:find-entities
   #:find-entities-by-type
   #:scan-index
   #:query-first
   ;; Entity cache (backward compat accessors)
   #:*entity-cache*
   #:reset-entity-cache
   ;; Hooks
   #:register-hook
   #:unregister-hook
   ;; Indexes (with :scope and :strategy)
   #:define-index
   ;; Linda operations
   #:take!
   ;; Datalog queries
   #:query
   #:compile-query
   ;; Pull API
   #:pull
   #:pull-many
   ;; Datomic-style query
   #:q
   ;; Value index (backward compat accessor)
   #:*value-index*
   ;; Programming model (Phase 1.5)
   #:define-entity-type
   #:make-typed-entity
   #:entity-id
   #:*entity-type-registry*
   #:defsystem
   #:*system-registry*
   ;; Conditions
   #:substrate-condition
   #:substrate-error
   #:substrate-validation-error
   #:unknown-entity-type
   #:circular-system-dependency
   ;; Blob store (Phase 2)
   #:store-blob
   #:load-blob
   #:blob-exists-p))
