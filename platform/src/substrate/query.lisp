;;;; query.lisp - Query functions for the substrate
;;;;
;;;; find-entities and find-entities-by-type use the inverted
;;;; value index for O(1) lookups.
;;;; scan-index scans in-memory or LMDB indexes.
;;;;
;;;; All state accessed through *substrate* context object.

(in-package #:autopoiesis.substrate)

(defun get-value-index ()
  "Return the active value index hash table."
  (let ((ctx *substrate*))
    (if ctx (substrate-context-value-index ctx) *value-index*)))

(defun find-entities (attribute value &key (store *store*))
  "Find all entity IDs where ATTRIBUTE equals VALUE.
   Uses the inverted value index for O(1) lookup."
  (declare (ignore store))
  (let* ((intern-tbl (get-intern-table))
         (vi (get-value-index))
         (aid (if (integerp attribute) attribute
                  (gethash attribute intern-tbl)))
         (results nil))
    (when aid
      (let* ((key (cons aid value))
             (set (gethash key vi)))
        (when set
          (maphash (lambda (eid _)
                     (declare (ignore _))
                     (push eid results))
                   set))))
    results))

(defun find-entities-by-type (type-keyword &key (store *store*))
  "Find all entity IDs of a given type.
   Sugar for (find-entities :entity/type type-keyword)."
  (find-entities :entity/type type-keyword :store store))

(defun query-first (attribute value &key (store *store*))
  "Find the first entity ID where ATTRIBUTE equals VALUE, or nil."
  (car (find-entities attribute value :store store)))

(defun scan-index (index-name &key (store *store*) prefix (limit 100))
  "Scan entries from a named index. Returns list of (key . value) pairs.
   PREFIX: optional byte array prefix to filter by.
   In-memory path: scans hash table with optional prefix matching.
   LMDB path: cursor scan with prefix."
  (let ((mem-table (gethash index-name (store-memory-indexes store)))
        (results nil)
        (count 0))
    (when mem-table
      (maphash (lambda (key value)
                 (when (< count limit)
                   (if prefix
                       ;; Prefix match: key must start with prefix bytes
                       (when (and (typep key '(simple-array (unsigned-byte 8) (*)))
                                  (>= (length key) (length prefix))
                                  (%byte-prefix-match-p key prefix))
                         (push (cons key value) results)
                         (incf count))
                       ;; No prefix: return all
                       (progn
                         (push (cons key value) results)
                         (incf count)))))
               mem-table))
    ;; LMDB path
    (let ((index-entry (assoc index-name (store-indexes store))))
      (when index-entry
        (let ((db (getf (cdr index-entry) :db)))
          (when (and db (store-lmdb-env store) (zerop (length results)))
            (lmdb:with-txn (:write nil)
              (lmdb:do-db (key value db)
                (when (< count limit)
                  (if prefix
                      (when (and (>= (length key) (length prefix))
                                 (%byte-prefix-match-p key prefix))
                        (push (cons key (deserialize-value value)) results)
                        (incf count))
                      (progn
                        (push (cons key (deserialize-value value)) results)
                        (incf count))))))))))
    (nreverse results)))

(defun %byte-prefix-match-p (key prefix)
  "Check if KEY starts with PREFIX (both byte arrays)."
  (loop for i below (length prefix)
        always (= (aref key i) (aref prefix i))))
