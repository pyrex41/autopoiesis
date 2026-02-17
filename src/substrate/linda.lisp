;;;; linda.lisp - Linda tuple-space coordination primitives
;;;;
;;;; Inverted value index for O(1) take! lookups.
;;;; The value index maps (attribute-id . value) -> set of entity-ids,
;;;; updated alongside entity-cache on every transact!.

(in-package #:autopoiesis.substrate)

(defvar *value-index* (make-hash-table :test 'equal)
  "Inverted index: (attribute-id . value) -> hash-set of entity-ids")

(defun reset-value-index ()
  "Reset the value index. For testing only."
  (clrhash *value-index*))

(defun update-value-index (datom)
  "Update the inverted value index for take! lookups."
  (let ((key (cons (d-attribute datom) (d-value datom))))
    (if (d-added datom)
        ;; Assert: add entity to the value index
        (let ((set (or (gethash key *value-index*)
                       (setf (gethash key *value-index*)
                             (make-hash-table :test 'eql)))))
          (setf (gethash (d-entity datom) set) t))
        ;; Retract: remove entity from the value index
        (let ((set (gethash key *value-index*)))
          (when set
            (remhash (d-entity datom) set)
            (when (zerop (hash-table-count set))
              (remhash key *value-index*)))))))

(defun take! (attribute match-value &key (store *store*) (new-value nil new-value-p))
  "Linda in() -- atomically find an entity where ATTRIBUTE equals MATCH-VALUE,
   and either retract it or update it to NEW-VALUE.
   Returns the entity ID, or nil if no match.

   Uses inverted value index for O(1) lookup instead of scanning
   the entire entity cache. This is the coordination primitive:
   - Workers call (take! :task/status :pending :new-value :in-progress)
   - Only one worker succeeds per entity (lock serializes)
   - Others see the updated value and move on."
  (bt:with-lock-held ((store-lock store))
    (let* ((aid (if (integerp attribute) attribute
                    (or (gethash attribute *intern-table*)
                        (return-from take! nil))))
           (key (cons aid match-value))
           (set (gethash key *value-index*))
           (match-eid nil))
      ;; O(1) lookup via inverted index
      (when set
        (block found
          (maphash (lambda (eid _)
                     (declare (ignore _))
                     (setf match-eid eid)
                     (return-from found))
                   set)))
      (when match-eid
        ;; Atomically update: retract old, assert new
        (let ((datoms (if new-value-p
                          (list (%make-datom :entity match-eid :attribute aid
                                            :value match-value :added nil)
                                (%make-datom :entity match-eid :attribute aid
                                            :value new-value :added t))
                          (list (%make-datom :entity match-eid :attribute aid
                                            :value match-value :added nil)))))
          ;; Internal transact (already holding lock)
          (let ((tx-id (incf (store-tx-counter store))))
            (dolist (datom datoms)
              (setf (d-tx datom) tx-id)
              (update-entity-cache store datom)
              (update-value-index datom)))
          match-eid)))))
