;;;; packages.lisp - Package definitions for the substrate kernel
;;;;
;;;; The substrate is a datom store with transact!, hooks, indexes,
;;;; and Linda coordination primitives. Everything else in the system
;;;; (snapshots, conversations, conductor events, blob storage) is
;;;; stored as datoms in the substrate.

(in-package #:cl-user)

(defpackage #:autopoiesis.substrate
  (:use #:cl #:alexandria)
  (:export
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
   ;; Query
   #:entity-attr
   #:entity-attrs
   #:entity-state
   #:find-entities
   #:find-entities-by-type
   #:scan-index
   #:query-first
   ;; Entity cache
   #:*entity-cache*
   #:reset-entity-cache
   ;; Hooks
   #:register-hook
   #:unregister-hook
   ;; Indexes (with :scope and :strategy)
   #:define-index
   ;; Linda operations
   #:take!
   ;; Value index
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
   ;; Blob store (Phase 2)
   #:store-blob
   #:load-blob
   #:blob-exists-p))
