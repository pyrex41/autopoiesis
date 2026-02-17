;;;; store.lisp - The substrate store: datoms, indexes, hooks
;;;;
;;;; Central class that ties together indexes, hooks, and transact!.
;;;; Phase 1 uses in-memory hash tables. Phase 2 wires LMDB underneath.
;;;;
;;;; All mutable state is accessed through the *substrate* context object.

(in-package #:autopoiesis.substrate)

;;; ===================================================================
;;; Store class
;;; ===================================================================

(defclass substrate-store ()
  ((indexes :initform nil :accessor store-indexes
            :documentation "List of (name . plist) -- each index has :key-fn, :scope, :strategy, :db")
   (memory-indexes :initform (make-hash-table :test 'eq) :accessor store-memory-indexes
                   :documentation "In-memory index storage: index-name -> hash-table")
   (hooks :initform nil :accessor store-hooks
          :documentation "List of (name . hook-fn) called after each transaction")
   (tx-counter :initform 0 :accessor store-tx-counter)
   (lock :initform (bt:make-lock "substrate") :accessor store-lock)
   ;; LMDB fields (nil until Phase 2 wires them)
   (lmdb-env :initform nil :accessor store-lmdb-env)
   (data-db :initform nil :accessor store-data-db
            :documentation "Datom value storage: encoded-key -> serialized value")
   (blob-db :initform nil :accessor store-blob-db
            :documentation "Blob storage: hash -> bytes"))
  (:documentation "The substrate store -- datoms, indexes, hooks."))

(defvar *store* nil "The active substrate store.")

;;; ===================================================================
;;; Index registration
;;; ===================================================================

(defun define-index (store name key-fn &key description scope strategy)
  "Register a named index. TRANSACT! auto-writes to all registered indexes.
   SCOPE: optional predicate (lambda (datom) ...) -- when non-nil, only datoms
   matching the scope are written to this index.
   STRATEGY: :append (default, add new entry) or :replace (overwrite existing key)."
  (let ((entry (cons name (list :key-fn key-fn
                                :description description
                                :scope scope
                                :strategy (or strategy :append)
                                :db nil))))
    ;; Remove existing index with same name
    (setf (store-indexes store)
          (remove name (store-indexes store) :key #'car))
    (push entry (store-indexes store))
    ;; Create in-memory storage for this index
    (setf (gethash name (store-memory-indexes store))
          (make-hash-table :test 'equalp))
    name))

;;; ===================================================================
;;; Default indexes
;;; ===================================================================

(defun register-default-indexes (store)
  "Register EAVT, AEVT, and EA-CURRENT as the default indexes."
  (define-index store :eavt #'encode-eavt-key
    :description "Entity-Attribute-Tx"
    :strategy :append)
  (define-index store :aevt #'encode-aevt-key
    :description "Attribute-Entity-Tx"
    :strategy :append)
  ;; EA-CURRENT: latest value per (entity, attribute) -- write-through cache
  (define-index store :ea-current #'encode-ea-key
    :description "Entity-Attribute current value"
    :strategy :replace))

;;; ===================================================================
;;; Hooks
;;; ===================================================================

(defun register-hook (store name hook-fn)
  "Register a hook that fires after every TRANSACT! with (datoms tx-id).
   Hooks fire AFTER the transaction commits."
  ;; Remove existing hook with same name
  (setf (store-hooks store)
        (remove name (store-hooks store) :key #'car))
  (push (cons name hook-fn) (store-hooks store))
  name)

(defun unregister-hook (store name)
  "Remove a named hook."
  (setf (store-hooks store) (remove name (store-hooks store) :key #'car))
  name)

;;; ===================================================================
;;; Write to index (in-memory for Phase 1)
;;; ===================================================================

(defun write-to-index (store index-name key-fn datom)
  "Write a datom to a named index. Uses LMDB when available, in-memory otherwise."
  (let* ((index-entry (assoc index-name (store-indexes store)))
         (strategy (getf (cdr index-entry) :strategy))
         (db (getf (cdr index-entry) :db))
         (key (funcall key-fn datom)))
    (if db
        ;; LMDB path (handled in lmdb-transact!)
        nil
        ;; In-memory fallback
        (let ((mem-table (gethash index-name (store-memory-indexes store))))
          (when mem-table
            (ecase strategy
              (:append
               (push (d-value datom) (gethash key mem-table)))
              (:replace
               (setf (gethash key mem-table) (d-value datom)))))))))

;;; ===================================================================
;;; The one function that matters: transact!
;;; ===================================================================

(defun transact! (datoms &key (store *store*))
  "Atomically write DATOMS to all registered indexes. Fire hooks after commit.
   This is the substrate's core contract:
   1. Assign tx-id (under lock)
   2. Write to ALL registered indexes (under lock, respecting :scope)
   3. Release lock
   4. Fire ALL registered hooks with (datoms tx-id) (OUTSIDE lock)
   Returns tx-id.

   CRITICAL: Hooks fire OUTSIDE the lock. This prevents deadlock when hooks
   call transact! (common for defsystem callbacks, materialized views, etc.)."
  ;; Filter out nils (convenience for callers using conditional datoms)
  (let ((datoms (remove nil datoms)))
    (when (null datoms)
      (return-from transact! nil))
    (let ((tx-id nil)
          (committed-datoms nil)
          (hooks-snapshot nil)
          (cache (get-entity-cache)))
      ;; Phase 1: Write under lock
      (bt:with-lock-held ((store-lock store))
        (setf tx-id (incf (store-tx-counter store)))
        ;; Stamp all datoms with tx-id
        (dolist (datom datoms)
          (setf (d-tx datom) tx-id))
        ;; Write to all indexes (respecting scope)
        (dolist (index-entry (store-indexes store))
          (let ((key-fn (getf (cdr index-entry) :key-fn))
                (scope (getf (cdr index-entry) :scope)))
            (dolist (datom datoms)
              (when (or (null scope) (funcall scope datom))
                (write-to-index store (car index-entry) key-fn datom)))))
        ;; Update entity cache (write-through over EA-CURRENT) + value index
        (dolist (datom datoms)
          ;; When asserting a value that overwrites an existing one,
          ;; retract the OLD value from the value index first.
          (when (d-added datom)
            (multiple-value-bind (old-value found-p)
                (gethash (cons (d-entity datom) (d-attribute datom)) cache)
              (when (and found-p (not (equal old-value (d-value datom))))
                (update-value-index (%make-datom :entity (d-entity datom)
                                                 :attribute (d-attribute datom)
                                                 :value old-value
                                                 :added nil)))))
          (update-entity-cache store datom)
          (update-value-index datom))
        ;; Write to LMDB if available (inside lock for atomicity)
        (when (store-lmdb-env store)
          (lmdb-transact! datoms store)
          (persist-tx-counter store tx-id))
        ;; Snapshot datoms and hooks for firing outside lock
        (setf committed-datoms (copy-list datoms))
        (setf hooks-snapshot (copy-list (store-hooks store))))
      ;; Phase 2: Fire hooks OUTSIDE the lock
      (dolist (hook-entry hooks-snapshot)
        (handler-case
            (funcall (cdr hook-entry) committed-datoms tx-id)
          (error (e)
            (warn "Hook ~A error: ~A" (car hook-entry) e))))
      tx-id)))

(defun next-tx-id (&key (store *store*))
  "Return the next transaction ID that would be assigned."
  (1+ (store-tx-counter store)))

;;; ===================================================================
;;; Store lifecycle
;;; ===================================================================

(defun open-store (&key path)
  "Open a substrate store. PATH is for LMDB (Phase 2).
   Without PATH, uses in-memory storage."
  (declare (ignore path))
  (let* ((ctx (or *substrate* (make-substrate-context)))
         (store (make-instance 'substrate-store)))
    (register-default-indexes store)
    (setf (substrate-context-store ctx) store)
    ;; Reset context tables for a clean store
    (clrhash (substrate-context-intern-table ctx))
    (clrhash (substrate-context-resolve-table ctx))
    (clrhash (substrate-context-entity-cache ctx))
    (clrhash (substrate-context-value-index ctx))
    (setf (substrate-context-next-entity-id ctx) 1)
    (setf (substrate-context-next-attribute-id ctx) 1)
    (setf *substrate* ctx)
    (setf *store* store)
    store))

(defun close-store (&key (store *store*))
  "Close the substrate store."
  (when store
    (when (store-lmdb-env store)
      (close-lmdb-store :store store)
      (return-from close-store))
    (setf *store* nil)))

(defmacro with-store ((&key path) &body body)
  "Execute BODY with a fresh substrate store. Cleans up on exit.
   Binds *substrate* context with fresh tables and *store* for backward compat."
  `(let* ((*substrate* (make-substrate-context))
          (*store* nil)
          ;; Keep old specials bound for any code still referencing them directly
          (*entity-cache* (substrate-context-entity-cache *substrate*))
          (*value-index* (substrate-context-value-index *substrate*))
          (*intern-table* (substrate-context-intern-table *substrate*))
          (*resolve-table* (substrate-context-resolve-table *substrate*))
          (*next-entity-id* (substrate-context-next-entity-id *substrate*))
          (*next-attribute-id* (substrate-context-next-attribute-id *substrate*)))
     (declare (ignorable *entity-cache* *value-index* *intern-table*
                         *resolve-table* *next-entity-id* *next-attribute-id*))
     (let ((store (make-instance 'substrate-store)))
       (register-default-indexes store)
       (setf (substrate-context-store *substrate*) store)
       (setf *store* store)
       (unwind-protect (progn ,@body)
         (close-store :store store)))))
