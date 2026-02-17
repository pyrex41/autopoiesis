;;;; context.lisp - Substrate context object
;;;;
;;;; Replaces 7+ special variables with a single struct.
;;;; Thread capture becomes (let ((*substrate* ctx)) ...) instead of
;;;; rebinding 7 separate specials.

(in-package #:autopoiesis.substrate)

(defstruct substrate-context
  "All substrate state bundled into one object for thread-safe capture."
  (store nil :type (or null substrate-store))
  (entity-cache (make-hash-table :test 'equal) :type hash-table)
  (value-index (make-hash-table :test 'equal) :type hash-table)
  (intern-table (make-hash-table :test 'equal) :type hash-table)
  (resolve-table (make-hash-table :test 'eql) :type hash-table)
  (next-entity-id 1 :type (unsigned-byte 64))
  (next-attribute-id 1 :type (unsigned-byte 32))
  ;; Batch transaction support (Phase 4)
  (batch-queue nil :type list)
  (batch-depth 0 :type fixnum))

(defvar *substrate* nil
  "The active substrate context. Binds all substrate state for the current thread.")
