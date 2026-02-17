;;;; entity.lisp - Entity state reconstruction from datoms
;;;;
;;;; In-memory cache of current entity state, updated on every transact!.
;;;; Provides O(1) lookups for entity-attr and full state reconstruction.

(in-package #:autopoiesis.substrate)

(defvar *entity-cache* (make-hash-table :test 'equal)
  "In-memory cache of current entity state. Key: (entity-id . attribute-id) -> value")

(defun reset-entity-cache ()
  "Reset the entity cache. For testing only."
  (clrhash *entity-cache*))

(defun update-entity-cache (store datom)
  "Update the entity cache with a datom."
  (declare (ignore store))
  (let ((key (cons (d-entity datom) (d-attribute datom))))
    (if (d-added datom)
        (setf (gethash key *entity-cache*) (d-value datom))
        (remhash key *entity-cache*))))

(defun entity-attr (entity attribute &key (store *store*))
  "Get current value of ENTITY's ATTRIBUTE. O(1) from cache."
  (declare (ignore store))
  (let ((eid (if (integerp entity) entity
                 (gethash entity *intern-table*)))
        (aid (if (integerp attribute) attribute
                 (gethash attribute *intern-table*))))
    (when (and eid aid)
      (gethash (cons eid aid) *entity-cache*))))

(defun entity-attrs (entity &key (store *store*))
  "Get all attribute IDs that have values for ENTITY."
  (declare (ignore store))
  (let ((eid (if (integerp entity) entity
                 (gethash entity *intern-table*)))
        (attrs nil))
    (when eid
      (maphash (lambda (key value)
                 (declare (ignore value))
                 (when (= (car key) eid)
                   (push (cdr key) attrs)))
               *entity-cache*))
    attrs))

(defun entity-state (entity &key (store *store*))
  "Reconstruct full current state of ENTITY as a plist.
   Returns (:attr1 val1 :attr2 val2 ...) with resolved attribute names."
  (declare (ignore store))
  (let ((eid (if (integerp entity) entity
                 (gethash entity *intern-table*)))
        (attrs nil))
    (when eid
      (maphash (lambda (key value)
                 (when (= (car key) eid)
                   (let ((attr-name (resolve-id (cdr key))))
                     (push value attrs)
                     (push attr-name attrs))))
               *entity-cache*))
    attrs))

(defun entity-history (entity attribute &key (store *store*) (limit 100))
  "Get historical values of ENTITY's ATTRIBUTE, most recent first.
   Phase 1: returns current value only (no temporal index yet).
   Phase 2: will scan LMDB EAVT cursor."
  (declare (ignore store limit))
  (let ((current (entity-attr entity attribute)))
    (when current
      (list current))))
