;;;; query.lisp - Query functions for the substrate
;;;;
;;;; find-entities and find-entities-by-type use the inverted
;;;; value index for O(1) lookups.

(in-package #:autopoiesis.substrate)

(defun find-entities (attribute value &key (store *store*))
  "Find all entity IDs where ATTRIBUTE equals VALUE.
   Uses the inverted value index for O(1) lookup."
  (declare (ignore store))
  (let* ((aid (if (integerp attribute) attribute
                  (gethash attribute *intern-table*)))
         (results nil))
    (when aid
      (let* ((key (cons aid value))
             (set (gethash key *value-index*)))
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

(defun scan-index (index-name &key (store *store*) (limit 100))
  "Scan entries from a named index. Phase 1: returns nil (no index storage yet).
   Phase 2: cursor scan over LMDB."
  (declare (ignore index-name store limit))
  nil)
