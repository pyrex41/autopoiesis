;;;; entity.lisp - Entity state reconstruction from datoms
;;;;
;;;; In-memory cache of current entity state, updated on every transact!.
;;;; Provides O(1) lookups for entity-attr and full state reconstruction.
;;;; Also provides temporal queries: entity-history, entity-as-of.
;;;;
;;;; All state accessed through *substrate* context object.

(in-package #:autopoiesis.substrate)

(defvar *entity-cache* (make-hash-table :test 'equal)
  "DEPRECATED: Use (substrate-context-entity-cache *substrate*).
   In-memory cache of current entity state. Key: (entity-id . attribute-id) -> value")

(defun reset-entity-cache ()
  "Reset the entity cache. For testing only."
  (let ((ctx *substrate*))
    (if ctx
        (clrhash (substrate-context-entity-cache ctx))
        (clrhash *entity-cache*))))

(defun get-entity-cache ()
  "Return the active entity cache hash table."
  (let ((ctx *substrate*))
    (if ctx (substrate-context-entity-cache ctx) *entity-cache*)))

(defun get-intern-table ()
  "Return the active intern table hash table."
  (let ((ctx *substrate*))
    (if ctx (substrate-context-intern-table ctx) *intern-table*)))

(defun update-entity-cache (store datom)
  "Update the entity cache with a datom."
  (declare (ignore store))
  (let* ((cache (get-entity-cache))
         (key (cons (d-entity datom) (d-attribute datom))))
    (if (d-added datom)
        (setf (gethash key cache) (d-value datom))
        (remhash key cache))))

(defun entity-attr (entity attribute &key (store *store*))
  "Get current value of ENTITY's ATTRIBUTE. O(1) from cache."
  (declare (ignore store))
  (let* ((cache (get-entity-cache))
         (intern-tbl (get-intern-table))
         (eid (if (integerp entity) entity
                  (gethash entity intern-tbl)))
         (aid (if (integerp attribute) attribute
                  (gethash attribute intern-tbl))))
    (when (and eid aid)
      (gethash (cons eid aid) cache))))

(defun entity-attrs (entity &key (store *store*))
  "Get all attribute IDs that have values for ENTITY."
  (declare (ignore store))
  (let* ((cache (get-entity-cache))
         (intern-tbl (get-intern-table))
         (eid (if (integerp entity) entity
                  (gethash entity intern-tbl)))
         (attrs nil))
    (when eid
      (maphash (lambda (key value)
                 (declare (ignore value))
                 (when (= (car key) eid)
                   (push (cdr key) attrs)))
               cache))
    attrs))

(defun entity-state (entity &key (store *store*))
  "Reconstruct full current state of ENTITY as a plist.
   Returns (:attr1 val1 :attr2 val2 ...) with resolved attribute names."
  (declare (ignore store))
  (let* ((cache (get-entity-cache))
         (intern-tbl (get-intern-table))
         (eid (if (integerp entity) entity
                  (gethash entity intern-tbl)))
         (attrs nil))
    (when eid
      (maphash (lambda (key value)
                 (when (= (car key) eid)
                   (let ((attr-name (resolve-id (cdr key))))
                     (push value attrs)
                     (push attr-name attrs))))
               cache))
    attrs))

;;; ===================================================================
;;; Temporal queries
;;; ===================================================================

(defun %decode-eavt-key (key-bytes)
  "Decode an EAVT key into (entity-id attribute-id tx-id)."
  (when (and key-bytes (>= (length key-bytes) 20))
    (values (decode-u64-be key-bytes 0)
            (decode-u32-be key-bytes 8)
            (decode-u64-be key-bytes 12))))

(defun %scan-eavt-in-memory (store eid aid)
  "Scan in-memory EAVT index for all entries matching ENTITY-ID and optionally ATTRIBUTE-ID.
   Returns list of (tx-id . value) sorted by tx-id descending."
  (let ((mem-table (gethash :eavt (store-memory-indexes store)))
        (results nil))
    (when mem-table
      (maphash (lambda (key value-list)
                 (when (and (typep key '(simple-array (unsigned-byte 8) (*)))
                            (>= (length key) 20))
                   (let ((k-eid (decode-u64-be key 0))
                         (k-aid (decode-u32-be key 8))
                         (k-tx (decode-u64-be key 12)))
                     (when (and (= k-eid eid)
                                (or (null aid) (= k-aid aid)))
                       (dolist (val value-list)
                         (push (cons k-tx (cons k-aid val)) results))))))
               mem-table))
    ;; Sort by tx-id descending (most recent first)
    (sort results #'> :key #'car)))

(defun entity-history (entity attribute &key (store *store*) (last-n 10))
  "Get historical values of ENTITY's ATTRIBUTE, most recent first.
   Returns list of (:tx tx-id :value value) plists.
   Scans EAVT index (in-memory or LMDB)."
  (let* ((intern-tbl (get-intern-table))
         (eid (if (integerp entity) entity
                  (gethash entity intern-tbl)))
         (aid (when attribute
                (if (integerp attribute) attribute
                    (gethash attribute intern-tbl)))))
    (unless eid
      (return-from entity-history nil))
    ;; In-memory path
    (let* ((entries (%scan-eavt-in-memory store eid aid))
           (limited (if last-n
                        (subseq entries 0 (min last-n (length entries)))
                        entries)))
      (mapcar (lambda (entry)
                (list :tx (car entry) :value (cddr entry)))
              limited))))

(defun entity-as-of (entity tx-id &key (store *store*))
  "Reconstruct entity state as of TX-ID.
   Scans EAVT for all attributes up to that tx, returns plist like entity-state."
  (let* ((intern-tbl (get-intern-table))
         (eid (if (integerp entity) entity
                  (gethash entity intern-tbl))))
    (unless eid
      (return-from entity-as-of nil))
    ;; Scan all entries for this entity up to tx-id
    (let ((entries (%scan-eavt-in-memory store eid nil))
          (state (make-hash-table :test 'eql))) ; aid -> latest value at or before tx-id
      ;; entries are sorted descending by tx; we want latest value per attribute <= tx-id
      (dolist (entry entries)
        (let ((e-tx (car entry))
              (e-aid (cadr entry))
              (e-val (cddr entry)))
          (when (<= e-tx tx-id)
            ;; Only take the first (most recent) value per attribute
            (unless (gethash e-aid state)
              (setf (gethash e-aid state) e-val)))))
      ;; Convert to plist with resolved attribute names
      (let ((result nil))
        (maphash (lambda (aid val)
                   (let ((attr-name (resolve-id aid)))
                     (push val result)
                     (push attr-name result)))
                 state)
        result))))
