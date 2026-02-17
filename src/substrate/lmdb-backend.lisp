;;;; lmdb-backend.lisp - LMDB persistent backend for the substrate
;;;;
;;;; Wires LMDB underneath the in-memory substrate store.
;;;; open-lmdb-store creates an LMDB-backed store; in-memory store
;;;; remains the default for testing.

(in-package #:autopoiesis.substrate)

;;; ===================================================================
;;; LMDB Store Lifecycle
;;; ===================================================================

(defun open-lmdb-store (path &key (map-size (* 256 1024 1024)))
  "Open substrate store backed by LMDB at PATH.
   MAP-SIZE is the maximum database size (default 256MB)."
  ;; Reset shared state
  (reset-intern-tables)
  (reset-entity-cache)
  (reset-value-index)
  (ensure-directories-exist (merge-pathnames "data/" path))
  (let ((store (make-instance 'substrate-store)))
    ;; Open LMDB environment
    (let ((env (lmdb:open-env path
                              :if-does-not-exist :create
                              :max-dbs 16
                              :map-size map-size)))
      (setf (store-lmdb-env store) env)
      ;; Register default indexes
      (register-default-indexes store)
      ;; Open named databases for each index
      (dolist (index-entry (store-indexes store))
        (let* ((name (car index-entry))
               (db (lmdb:get-db (string-downcase (symbol-name name))
                                :if-does-not-exist :create
                                :key-encoding :octets
                                :value-encoding :octets)))
          (setf (getf (cdr index-entry) :db) db)))
      ;; Open data database (for storing serialized datom values)
      (setf (store-data-db store)
            (lmdb:get-db "data"
                         :if-does-not-exist :create
                         :key-encoding :octets
                         :value-encoding :octets))
      ;; Open blob database
      (setf (store-blob-db store)
            (lmdb:get-db "blobs"
                         :if-does-not-exist :create
                         :key-encoding :utf-8
                         :value-encoding :octets))
      ;; Open intern databases and restore state
      (let ((intern-db (lmdb:get-db "intern"
                                     :if-does-not-exist :create
                                     :key-encoding :utf-8
                                     :value-encoding :uint64))
            (resolve-db (lmdb:get-db "resolve"
                                      :if-does-not-exist :create
                                      :key-encoding :uint64
                                      :value-encoding :utf-8))
            (meta-db (lmdb:get-db "meta"
                                   :if-does-not-exist :create
                                   :key-encoding :utf-8
                                   :value-encoding :uint64)))
        (restore-intern-tables intern-db resolve-db meta-db)
        ;; Store refs for later use
        (setf (slot-value store 'intern-db) intern-db)
        (setf (slot-value store 'resolve-db) resolve-db)
        (setf (slot-value store 'meta-db) meta-db))
      ;; Restore entity cache from EA-CURRENT database
      (restore-entity-cache store))
    (setf *store* store)
    store))

;; Add intern-db slots to the store class
(defmethod slot-unbound (class (store substrate-store) (slot-name (eql 'intern-db)))
  (declare (ignore class))
  nil)
(defmethod slot-unbound (class (store substrate-store) (slot-name (eql 'resolve-db)))
  (declare (ignore class))
  nil)
(defmethod slot-unbound (class (store substrate-store) (slot-name (eql 'meta-db)))
  (declare (ignore class))
  nil)

;;; ===================================================================
;;; Intern Table Persistence
;;; ===================================================================

(defun restore-intern-tables (intern-db resolve-db meta-db)
  "Restore intern tables from LMDB."
  ;; Restore counters
  (lmdb:with-txn (:write nil)
    (let ((eid-counter (lmdb:g3t meta-db "next-entity-id"))
          (aid-counter (lmdb:g3t meta-db "next-attribute-id"))
          (tx-counter (lmdb:g3t meta-db "tx-counter")))
      (when eid-counter
        (setf *next-entity-id* eid-counter))
      (when aid-counter
        (setf *next-attribute-id* aid-counter))
      (when tx-counter
        ;; Will be set on the store after it's fully initialized
        ))
    ;; Restore intern table
    (lmdb:do-db (key value intern-db)
      (setf (gethash key *intern-table*) value))
    ;; Restore resolve table
    (lmdb:do-db (key value resolve-db)
      (setf (gethash key *resolve-table*) value))))

(defun persist-intern-entry (store term id width)
  "Persist a single intern entry to LMDB."
  (when (store-lmdb-env store)
    (let ((intern-db (slot-value store 'intern-db))
          (resolve-db (slot-value store 'resolve-db))
          (meta-db (slot-value store 'meta-db)))
      (when (and intern-db resolve-db meta-db)
        (lmdb:with-txn (:write t)
          (lmdb:put intern-db (prin1-to-string term) id)
          (lmdb:put resolve-db id (prin1-to-string term))
          ;; Update counter
          (ecase width
            (:entity (lmdb:put meta-db "next-entity-id" *next-entity-id*))
            (:attribute (lmdb:put meta-db "next-attribute-id" *next-attribute-id*))))))))

(defun persist-tx-counter (store tx-id)
  "Persist the tx counter to LMDB."
  (when (and (store-lmdb-env store)
             (slot-boundp store 'meta-db)
             (slot-value store 'meta-db))
    (lmdb:with-txn (:write t)
      (lmdb:put (slot-value store 'meta-db) "tx-counter" tx-id))))

;;; ===================================================================
;;; Entity Cache Restoration
;;; ===================================================================

(defun restore-entity-cache (store)
  "Restore entity cache from EA-CURRENT LMDB database."
  (let ((ea-entry (assoc :ea-current (store-indexes store))))
    (when ea-entry
      (let ((db (getf (cdr ea-entry) :db)))
        (when db
          (lmdb:with-txn (:write nil)
            (lmdb:do-db (key value db)
              ;; key = EA key (12 bytes), value = serialized datom value
              (when (and key value (>= (length key) 12))
                (let ((eid (decode-u64-be key 0))
                      (aid (decode-u32-be key 8))
                      (val (deserialize-value value)))
                  (setf (gethash (cons eid aid) *entity-cache*) val)
                  ;; Also update value index
                  (let ((vi-key (cons aid val)))
                    (let ((set (or (gethash vi-key *value-index*)
                                   (setf (gethash vi-key *value-index*)
                                         (make-hash-table :test 'eql)))))
                      (setf (gethash eid set) t))))))))))))

;;; ===================================================================
;;; LMDB Write Path
;;; ===================================================================

(defun lmdb-write-to-index (store index-name key-fn datom)
  "Write a datom to an LMDB-backed index."
  (let* ((index-entry (assoc index-name (store-indexes store)))
         (db (getf (cdr index-entry) :db))
         (strategy (getf (cdr index-entry) :strategy))
         (key (funcall key-fn datom))
         (value (serialize-value (d-value datom))))
    (when db
      (ecase strategy
        (:append
         (lmdb:put db key value))
        (:replace
         (lmdb:put db key value))))))

(defun lmdb-transact! (datoms store)
  "LMDB-aware transaction: write datoms to LMDB in a single txn."
  (when (store-lmdb-env store)
    (lmdb:with-txn (:write t)
      (dolist (index-entry (store-indexes store))
        (let ((key-fn (getf (cdr index-entry) :key-fn))
              (scope (getf (cdr index-entry) :scope))
              (db (getf (cdr index-entry) :db)))
          (when db
            (dolist (datom datoms)
              (when (or (null scope) (funcall scope datom))
                (lmdb-write-to-index store (car index-entry) key-fn datom))))))
      ;; Also write to data db for full datom recovery
      (dolist (datom datoms)
        (let ((key (encode-eavt-key datom))
              (value (serialize-value (d-value datom))))
          (lmdb:put (store-data-db store) key value))))))

;;; ===================================================================
;;; Serialization helpers
;;; ===================================================================

(defun serialize-value (value)
  "Serialize a datom value to octets."
  (babel:string-to-octets (prin1-to-string value) :encoding :utf-8))

(defun deserialize-value (octets)
  "Deserialize octets back to a Lisp value."
  (let ((str (babel:octets-to-string octets :encoding :utf-8)))
    (read-from-string str)))

(defun decode-u64-be (buf offset)
  "Decode a big-endian u64 from BUF at OFFSET."
  (let ((result 0))
    (loop for i from 0 below 8
          do (setf result (logior (ash result 8)
                                  (aref buf (+ offset i)))))
    result))

(defun decode-u32-be (buf offset)
  "Decode a big-endian u32 from BUF at OFFSET."
  (let ((result 0))
    (loop for i from 0 below 4
          do (setf result (logior (ash result 8)
                                  (aref buf (+ offset i)))))
    result))

;;; ===================================================================
;;; Close LMDB Store
;;; ===================================================================

(defun close-lmdb-store (&key (store *store*))
  "Close an LMDB-backed store."
  (when (and store (store-lmdb-env store))
    ;; Persist final tx counter
    (persist-tx-counter store (store-tx-counter store))
    (lmdb:close-env (store-lmdb-env store))
    (setf (store-lmdb-env store) nil))
  (setf *store* nil))
