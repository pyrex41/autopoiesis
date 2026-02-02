;;;; persistence.lisp - Snapshot persistence to disk
;;;;
;;;; Provides disk-based storage for snapshots with filesystem backend.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Store Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass snapshot-store ()
  ((base-path :initarg :base-path
              :accessor store-base-path
              :documentation "Root directory for snapshot storage")
   (cache :initarg :cache
          :accessor store-cache
          :initform (make-hash-table :test 'equal)
          :documentation "In-memory cache of loaded snapshots")
   (index :initarg :index
          :accessor store-index
          :initform nil
          :documentation "Index of all snapshots for fast lookup"))
  (:documentation "Persistent storage for snapshots on filesystem"))

(defvar *snapshot-store* nil
  "Global snapshot store instance.")

(defun make-snapshot-store (base-path)
  "Create a new snapshot store at BASE-PATH."
  (let ((store (make-instance 'snapshot-store :base-path base-path)))
    (ensure-store-directories store)
    (load-store-index store)
    store))

(defun initialize-store (base-path)
  "Initialize the global snapshot store at BASE-PATH."
  (setf *snapshot-store* (make-snapshot-store base-path)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Directory Structure
;;; ═══════════════════════════════════════════════════════════════════

(defun ensure-store-directories (store)
  "Ensure all required directories exist for STORE."
  (let ((base (store-base-path store)))
    (ensure-directories-exist (merge-pathnames "snapshots/" base))
    (ensure-directories-exist (merge-pathnames "index/" base))
    (ensure-directories-exist (merge-pathnames "branches/" base))))

(defun snapshot-file-path (store snapshot-id)
  "Return the file path for SNAPSHOT-ID in STORE."
  ;; Use first 2 chars of ID as subdirectory for better filesystem performance
  (let ((prefix (subseq snapshot-id 0 (min 2 (length snapshot-id)))))
    (merge-pathnames
     (format nil "snapshots/~a/~a.sexpr" prefix snapshot-id)
     (store-base-path store))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun snapshot-to-sexpr (snapshot)
  "Convert SNAPSHOT to S-expression for storage."
  `(snapshot
    :version 1
    :id ,(snapshot-id snapshot)
    :timestamp ,(snapshot-timestamp snapshot)
    :parent ,(snapshot-parent snapshot)
    :agent-state ,(snapshot-agent-state snapshot)
    :metadata ,(snapshot-metadata snapshot)
    :hash ,(snapshot-hash snapshot)))

(defun sexpr-to-snapshot (sexpr)
  "Reconstruct SNAPSHOT from S-expression."
  (unless (and (listp sexpr) (eq (first sexpr) 'snapshot))
    (error 'autopoiesis.core:autopoiesis-error
           :message "Invalid snapshot S-expression"))
  (let ((plist (rest sexpr)))
    (make-instance 'snapshot
      :id (getf plist :id)
      :timestamp (getf plist :timestamp)
      :parent (getf plist :parent)
      :agent-state (getf plist :agent-state)
      :metadata (getf plist :metadata)
      :hash (getf plist :hash))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Core Persistence Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun save-snapshot (snapshot &optional (store *snapshot-store*))
  "Persist SNAPSHOT to disk in STORE."
  (unless store
    (error 'autopoiesis.core:autopoiesis-error
           :message "No snapshot store initialized"))
  (let* ((id (snapshot-id snapshot))
         (path (snapshot-file-path store id))
         (sexpr (snapshot-to-sexpr snapshot)))
    ;; Ensure parent directory exists
    (ensure-directories-exist path)
    ;; Write to disk
    (with-open-file (out path :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create
                              :external-format :utf-8)
      (let ((*print-readably* t)
            (*print-circle* t)
            (*print-array* t)
            (*print-length* nil)
            (*print-level* nil)
            (*package* (find-package :autopoiesis.core)))
        (prin1 sexpr out)))
    ;; Update cache
    (setf (gethash id (store-cache store)) snapshot)
    ;; Update index
    (index-snapshot store snapshot)
    snapshot))

(defun load-snapshot (id &optional (store *snapshot-store*))
  "Load snapshot with ID from STORE."
  (unless store
    (error 'autopoiesis.core:autopoiesis-error
           :message "No snapshot store initialized"))
  ;; Check cache first
  (let ((cached (gethash id (store-cache store))))
    (when cached
      (return-from load-snapshot cached)))
  ;; Load from disk
  (let ((path (snapshot-file-path store id)))
    (unless (probe-file path)
      (return-from load-snapshot nil))
    (let ((snapshot
            (handler-case
                (with-open-file (in path :direction :input
                                         :external-format :utf-8)
                  (let ((*package* (find-package :autopoiesis.core)))
                    (sexpr-to-snapshot (read in))))
              (error (e)
                (warn "Failed to load snapshot ~a: ~a" id e)
                nil))))
      (when snapshot
        ;; Update cache
        (setf (gethash id (store-cache store)) snapshot))
      snapshot)))

(defun delete-snapshot (id &optional (store *snapshot-store*))
  "Delete snapshot with ID from STORE."
  (unless store
    (error 'autopoiesis.core:autopoiesis-error
           :message "No snapshot store initialized"))
  (let ((path (snapshot-file-path store id)))
    (when (probe-file path)
      (delete-file path))
    ;; Remove from cache
    (remhash id (store-cache store))
    ;; Remove from index
    (unindex-snapshot store id)
    t))

(defun snapshot-exists-p (id &optional (store *snapshot-store*))
  "Check if snapshot with ID exists in STORE."
  (or (gethash id (store-cache store))
      (probe-file (snapshot-file-path store id))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Index
;;; ═══════════════════════════════════════════════════════════════════

(defclass snapshot-index ()
  ((by-id :initform (make-hash-table :test 'equal)
          :accessor index-by-id
          :documentation "ID -> snapshot metadata")
   (by-parent :initform (make-hash-table :test 'equal)
              :accessor index-by-parent
              :documentation "parent-id -> list of child IDs")
   (by-timestamp :initform nil
                 :accessor index-by-timestamp
                 :documentation "Sorted list of (timestamp . id) pairs")
   (root-ids :initform nil
             :accessor index-root-ids
             :documentation "IDs of root snapshots (no parent)"))
  (:documentation "Index for fast snapshot queries"))

(defun make-snapshot-index ()
  "Create a new snapshot index."
  (make-instance 'snapshot-index))

(defun index-snapshot (store snapshot)
  "Add SNAPSHOT to STORE's index."
  (unless (store-index store)
    (setf (store-index store) (make-snapshot-index)))
  (let* ((index (store-index store))
         (id (snapshot-id snapshot))
         (parent-id (snapshot-parent snapshot))
         (timestamp (snapshot-timestamp snapshot)))
    ;; Index by ID (store minimal metadata)
    (setf (gethash id (index-by-id index))
          (list :timestamp timestamp :parent parent-id))
    ;; Index by parent
    (when parent-id
      (pushnew id (gethash parent-id (index-by-parent index)) :test #'equal))
    ;; Track roots
    (unless parent-id
      (pushnew id (index-root-ids index) :test #'equal))
    ;; Add to timestamp index (keep sorted)
    (setf (index-by-timestamp index)
          (merge 'list
                 (list (cons timestamp id))
                 (index-by-timestamp index)
                 #'< :key #'car))))

(defun unindex-snapshot (store id)
  "Remove snapshot ID from STORE's index."
  (when (store-index store)
    (let ((index (store-index store)))
      ;; Get parent before removing
      (let ((meta (gethash id (index-by-id index))))
        (when meta
          (let ((parent-id (getf meta :parent)))
            (when parent-id
              (setf (gethash parent-id (index-by-parent index))
                    (remove id (gethash parent-id (index-by-parent index))
                            :test #'equal))))))
      ;; Remove from by-id
      (remhash id (index-by-id index))
      ;; Remove from roots
      (setf (index-root-ids index)
            (remove id (index-root-ids index) :test #'equal))
      ;; Remove from timestamp index
      (setf (index-by-timestamp index)
            (remove id (index-by-timestamp index) :test #'equal :key #'cdr)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Index Persistence
;;; ═══════════════════════════════════════════════════════════════════

(defun index-file-path (store)
  "Return the path to the index file for STORE."
  (merge-pathnames "index/snapshots.idx" (store-base-path store)))

(defun save-store-index (store)
  "Save STORE's index to disk."
  (when (store-index store)
    (let ((index (store-index store))
          (path (index-file-path store)))
      (ensure-directories-exist path)
      (with-open-file (out path :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create
                                :external-format :utf-8)
        (let ((*print-readably* t)
              (*print-circle* t)
              (*package* (find-package :autopoiesis.core)))
          (prin1
           `(snapshot-index
             :version 1
             :by-id ,(loop for k being the hash-keys of (index-by-id index)
                           using (hash-value v)
                           collect (cons k v))
             :by-parent ,(loop for k being the hash-keys of (index-by-parent index)
                               using (hash-value v)
                               when v collect (cons k v))
             :root-ids ,(index-root-ids index)
             :by-timestamp ,(index-by-timestamp index))
           out))))))

(defun load-store-index (store)
  "Load STORE's index from disk, or rebuild if missing."
  (let ((path (index-file-path store)))
    (if (probe-file path)
        ;; Load existing index
        (handler-case
            (with-open-file (in path :direction :input :external-format :utf-8)
              (let* ((*package* (find-package :autopoiesis.core))
                     (sexpr (read in))
                     (plist (rest sexpr))
                     (index (make-snapshot-index)))
                ;; Restore by-id
                (dolist (pair (getf plist :by-id))
                  (setf (gethash (car pair) (index-by-id index)) (cdr pair)))
                ;; Restore by-parent
                (dolist (pair (getf plist :by-parent))
                  (setf (gethash (car pair) (index-by-parent index)) (cdr pair)))
                ;; Restore roots and timestamps
                (setf (index-root-ids index) (getf plist :root-ids)
                      (index-by-timestamp index) (getf plist :by-timestamp))
                (setf (store-index store) index)))
          (error (e)
            (warn "Failed to load index, rebuilding: ~a" e)
            (rebuild-store-index store)))
        ;; No index file - rebuild
        (rebuild-store-index store))))

(defun rebuild-store-index (store)
  "Rebuild STORE's index by scanning all snapshot files."
  (setf (store-index store) (make-snapshot-index))
  (let ((snapshot-dir (merge-pathnames "snapshots/" (store-base-path store))))
    (when (probe-file snapshot-dir)
      ;; Walk all subdirectories
      (dolist (subdir (directory (merge-pathnames "*/" snapshot-dir)))
        (dolist (file (directory (merge-pathnames "*.sexpr" subdir)))
          (handler-case
              (with-open-file (in file :direction :input :external-format :utf-8)
                (let* ((*package* (find-package :autopoiesis.core))
                       (snapshot (sexpr-to-snapshot (read in))))
                  (index-snapshot store snapshot)))
            (error (e)
              (warn "Failed to index ~a: ~a" file e)))))))
  ;; Save the rebuilt index
  (save-store-index store))

;;; ═══════════════════════════════════════════════════════════════════
;;; Query Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun list-snapshots (&key parent-id root-only (store *snapshot-store*))
  "List snapshot IDs matching criteria.
   If PARENT-ID, return children of that snapshot.
   If ROOT-ONLY, return only root snapshots."
  (unless (and store (store-index store))
    (return-from list-snapshots nil))
  (let ((index (store-index store)))
    (cond
      (parent-id
       (gethash parent-id (index-by-parent index)))
      (root-only
       (index-root-ids index))
      (t
       ;; Return all IDs
       (loop for id being the hash-keys of (index-by-id index)
             collect id)))))

(defun find-snapshot-by-timestamp (timestamp &key (direction :nearest) (store *snapshot-store*))
  "Find snapshot near TIMESTAMP.
   DIRECTION: :nearest, :before, or :after."
  (unless (and store (store-index store))
    (return-from find-snapshot-by-timestamp nil))
  (let ((timestamps (index-by-timestamp (store-index store))))
    (case direction
      (:before
       (let ((before (remove-if (lambda (pair) (> (car pair) timestamp)) timestamps)))
         (when before
           (cdr (first (last before))))))
      (:after
       (let ((after (remove-if (lambda (pair) (< (car pair) timestamp)) timestamps)))
         (when after
           (cdr (first after)))))
      (:nearest
       (when timestamps
         (let ((closest nil)
               (min-diff most-positive-double-float))
           (dolist (pair timestamps)
             (let ((diff (abs (- (car pair) timestamp))))
               (when (< diff min-diff)
                 (setf min-diff diff
                       closest (cdr pair)))))
           closest))))))

(defun snapshot-children (snapshot-id &optional (store *snapshot-store*))
  "Return IDs of snapshots that have SNAPSHOT-ID as parent."
  (when (and store (store-index store))
    (gethash snapshot-id (index-by-parent (store-index store)))))

(defun snapshot-ancestors (snapshot-id &optional (store *snapshot-store*))
  "Return list of ancestor snapshot IDs, from parent to root."
  (unless store
    (return-from snapshot-ancestors nil))
  (loop for id = (let ((snap (load-snapshot snapshot-id store)))
                   (when snap (snapshot-parent snap)))
        then (let ((snap (load-snapshot id store)))
               (when snap (snapshot-parent snap)))
        while id
        collect id))

(defun snapshot-descendants (snapshot-id &optional (store *snapshot-store*))
  "Return list of all descendant snapshot IDs."
  (unless (and store (store-index store))
    (return-from snapshot-descendants nil))
  (let ((result nil)
        (queue (list snapshot-id)))
    (loop while queue
          do (let* ((current (pop queue))
                    (children (snapshot-children current store)))
               (dolist (child children)
                 (push child result)
                 (push child queue))))
    result))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cleanup and Maintenance
;;; ═══════════════════════════════════════════════════════════════════

(defun clear-snapshot-cache (&optional (store *snapshot-store*))
  "Clear the in-memory cache for STORE."
  (when store
    (clrhash (store-cache store))))

(defun close-store (&optional (store *snapshot-store*))
  "Close STORE, saving index and clearing cache."
  (when store
    (save-store-index store)
    (clear-snapshot-cache store)))
