;;;; lazy-loading.lisp - Lazy loading for large DAGs
;;;;
;;;; Provides lazy loading capabilities for snapshot DAGs to handle
;;;; large datasets efficiently. Only metadata is loaded initially,
;;;; with full content loaded on demand.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Lazy Snapshot Proxy
;;; ═══════════════════════════════════════════════════════════════════

(defclass lazy-snapshot ()
  ((id :initarg :id
       :accessor lazy-snapshot-id
       :documentation "Snapshot ID")
   (timestamp :initarg :timestamp
              :accessor lazy-snapshot-timestamp
              :documentation "Snapshot timestamp from index")
   (parent-id :initarg :parent-id
              :accessor lazy-snapshot-parent-id
              :documentation "Parent snapshot ID from index")
   (loaded-p :initform nil
             :accessor lazy-snapshot-loaded-p
             :documentation "Whether full content has been loaded")
   (snapshot :initform nil
             :accessor lazy-snapshot-content
             :documentation "The actual snapshot when loaded")
   (store :initarg :store
          :accessor lazy-snapshot-store
          :documentation "Reference to the snapshot store"))
  (:documentation "A lazy proxy for a snapshot that loads on demand."))

(defun make-lazy-snapshot (id &key timestamp parent-id store)
  "Create a lazy snapshot proxy from index metadata."
  (make-instance 'lazy-snapshot
                 :id id
                 :timestamp timestamp
                 :parent-id parent-id
                 :store store))

(defun ensure-snapshot-loaded (lazy-snap)
  "Ensure the full snapshot content is loaded."
  (unless (lazy-snapshot-loaded-p lazy-snap)
    (let ((snapshot (load-snapshot (lazy-snapshot-id lazy-snap)
                                   (lazy-snapshot-store lazy-snap))))
      (when snapshot
        (setf (lazy-snapshot-content lazy-snap) snapshot)
        (setf (lazy-snapshot-loaded-p lazy-snap) t))))
  (lazy-snapshot-content lazy-snap))

(defmethod snapshot-id ((snap lazy-snapshot))
  "Get ID from lazy snapshot."
  (lazy-snapshot-id snap))

(defmethod snapshot-timestamp ((snap lazy-snapshot))
  "Get timestamp from lazy snapshot (available without loading)."
  (lazy-snapshot-timestamp snap))

(defmethod snapshot-parent ((snap lazy-snapshot))
  "Get parent ID from lazy snapshot (available without loading)."
  (lazy-snapshot-parent-id snap))

(defmethod snapshot-agent-state ((snap lazy-snapshot))
  "Get agent state from lazy snapshot (triggers load)."
  (let ((loaded (ensure-snapshot-loaded snap)))
    (when loaded
      (snapshot-agent-state loaded))))

(defmethod snapshot-metadata ((snap lazy-snapshot))
  "Get metadata from lazy snapshot (triggers load)."
  (let ((loaded (ensure-snapshot-loaded snap)))
    (when loaded
      (snapshot-metadata loaded))))

(defmethod snapshot-hash ((snap lazy-snapshot))
  "Get hash from lazy snapshot (triggers load)."
  (let ((loaded (ensure-snapshot-loaded snap)))
    (when loaded
      (snapshot-hash loaded))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Lazy DAG Iterator
;;; ═══════════════════════════════════════════════════════════════════

(defclass lazy-dag-iterator ()
  ((store :initarg :store
          :accessor iterator-store
          :documentation "The snapshot store")
   (current-ids :initarg :current-ids
                :accessor iterator-current-ids
                :initform nil
                :documentation "Current batch of snapshot IDs")
   (direction :initarg :direction
              :accessor iterator-direction
              :initform :forward
              :documentation ":forward (children) or :backward (ancestors)")
   (visited :initform (make-hash-table :test 'equal)
            :accessor iterator-visited
            :documentation "Set of visited snapshot IDs")
   (batch-size :initarg :batch-size
               :accessor iterator-batch-size
               :initform 100
               :documentation "Number of snapshots to load per batch")
   (exhausted-p :initform nil
                :accessor iterator-exhausted-p
                :documentation "Whether iteration is complete"))
  (:documentation "Iterator for lazy traversal of snapshot DAG."))

(defun make-lazy-dag-iterator (start-id store &key (direction :forward) (batch-size 100))
  "Create a lazy DAG iterator starting from START-ID.
   DIRECTION :forward traverses children, :backward traverses ancestors."
  (make-instance 'lazy-dag-iterator
                 :store store
                 :current-ids (list start-id)
                 :direction direction
                 :batch-size batch-size))

(defun iterator-next-batch (iterator)
  "Get the next batch of lazy snapshots from the iterator.
   Returns NIL when exhausted."
  (when (iterator-exhausted-p iterator)
    (return-from iterator-next-batch nil))
  
  (let ((store (iterator-store iterator))
        (batch nil)
        (next-ids nil)
        (count 0))
    
    ;; Process current IDs up to batch-size
    (loop for id in (iterator-current-ids iterator)
          while (< count (iterator-batch-size iterator))
          do (unless (gethash id (iterator-visited iterator))
               (setf (gethash id (iterator-visited iterator)) t)
               (let ((lazy-snap (make-lazy-snapshot-from-index id store)))
                 (when lazy-snap
                   (push lazy-snap batch)
                   (incf count)
                   ;; Queue next IDs based on direction
                   (case (iterator-direction iterator)
                     (:forward
                      (dolist (child-id (snapshot-children id store))
                        (unless (gethash child-id (iterator-visited iterator))
                          (push child-id next-ids))))
                     (:backward
                      (let ((parent-id (lazy-snapshot-parent-id lazy-snap)))
                        (when (and parent-id
                                   (not (gethash parent-id (iterator-visited iterator))))
                          (push parent-id next-ids)))))))))
    
    ;; Update iterator state
    (setf (iterator-current-ids iterator)
          (append (nthcdr count (iterator-current-ids iterator)) next-ids))
    
    (when (null (iterator-current-ids iterator))
      (setf (iterator-exhausted-p iterator) t))
    
    (nreverse batch)))

(defun make-lazy-snapshot-from-index (id store)
  "Create a lazy snapshot from index metadata."
  (when (and store (store-index store))
    (let ((meta (gethash id (index-by-id (store-index store)))))
      (when meta
        (make-lazy-snapshot id
                            :timestamp (getf meta :timestamp)
                            :parent-id (getf meta :parent)
                            :store store)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Paginated DAG Queries
;;; ═══════════════════════════════════════════════════════════════════

(defun list-snapshots-paginated (&key (offset 0) (limit 100) (store *snapshot-store*))
  "List snapshot IDs with pagination.
   Returns (values ids total-count has-more-p)."
  (unless (and store (store-index store))
    (return-from list-snapshots-paginated (values nil 0 nil)))
  
  (let* ((all-ids (loop for id being the hash-keys of (index-by-id (store-index store))
                        collect id))
         (total (length all-ids))
         (sorted (sort all-ids #'string<))
         (page (subseq sorted
                       (min offset total)
                       (min (+ offset limit) total)))
         (has-more (< (+ offset limit) total)))
    (values page total has-more)))

(defun list-children-paginated (parent-id &key (offset 0) (limit 100) (store *snapshot-store*))
  "List children of a snapshot with pagination.
   Returns (values child-ids total-count has-more-p)."
  (unless (and store (store-index store))
    (return-from list-children-paginated (values nil 0 nil)))
  
  (let* ((all-children (gethash parent-id (index-by-parent (store-index store))))
         (total (length all-children))
         (page (subseq all-children
                       (min offset total)
                       (min (+ offset limit) total)))
         (has-more (< (+ offset limit) total)))
    (values page total has-more)))

(defun walk-descendants-paginated (start-id function &key (batch-size 100) (max-depth nil) (store *snapshot-store*))
  "Walk descendants of START-ID, calling FUNCTION on each lazy snapshot.
   Processes in batches for memory efficiency.
   Returns the count of snapshots visited."
  (let ((iterator (make-lazy-dag-iterator start-id store
                                          :direction :forward
                                          :batch-size batch-size))
        (count 0)
        (depth 0))
    (loop for batch = (iterator-next-batch iterator)
          while batch
          do (dolist (lazy-snap batch)
               (funcall function lazy-snap)
               (incf count))
             (incf depth)
             (when (and max-depth (>= depth max-depth))
               (return)))
    count))

(defun walk-ancestors-paginated (start-id function &key (batch-size 100) (max-depth nil) (store *snapshot-store*))
  "Walk ancestors of START-ID, calling FUNCTION on each lazy snapshot.
   Processes in batches for memory efficiency.
   Returns the count of snapshots visited."
  (let ((iterator (make-lazy-dag-iterator start-id store
                                          :direction :backward
                                          :batch-size batch-size))
        (count 0)
        (depth 0))
    (loop for batch = (iterator-next-batch iterator)
          while batch
          do (dolist (lazy-snap batch)
               (funcall function lazy-snap)
               (incf count))
             (incf depth)
             (when (and max-depth (>= depth max-depth))
               (return)))
    count))

;;; ═══════════════════════════════════════════════════════════════════
;;; Lazy Loading Utilities
;;; ═══════════════════════════════════════════════════════════════════

(defun prefetch-snapshots (ids &optional (store *snapshot-store*))
  "Prefetch multiple snapshots into cache.
   Useful for batch operations where you know you'll need specific snapshots."
  (dolist (id ids)
    (load-snapshot id store)))

(defun get-dag-statistics (&optional (store *snapshot-store*))
  "Get statistics about the DAG without loading all snapshots.
   Returns a plist with :total-count, :root-count, :max-depth-estimate, :branch-count."
  (unless (and store (store-index store))
    (return-from get-dag-statistics nil))
  
  (let* ((index (store-index store))
         (total (hash-table-count (index-by-id index)))
         (roots (length (index-root-ids index)))
         (branch-points 0)
         (max-children 0))
    
    ;; Count branch points (snapshots with multiple children)
    (maphash (lambda (parent-id children)
               (declare (ignore parent-id))
               (when (> (length children) 1)
                 (incf branch-points))
               (setf max-children (max max-children (length children))))
             (index-by-parent index))
    
    (list :total-count total
          :root-count roots
          :branch-points branch-points
          :max-children max-children
          :estimated-depth (if (zerop roots)
                               0
                               (ceiling (log (max 1 total) 2))))))

(defun find-snapshots-by-time-range (start-time end-time &key (limit 100) (store *snapshot-store*))
  "Find snapshots within a time range without loading full content.
   Returns list of lazy snapshots."
  (unless (and store (store-index store))
    (return-from find-snapshots-by-time-range nil))
  
  (let ((results nil)
        (count 0))
    (dolist (pair (index-by-timestamp (store-index store)))
      (when (>= count limit)
        (return))
      (let ((timestamp (car pair))
            (id (cdr pair)))
        (when (and (>= timestamp start-time)
                   (<= timestamp end-time))
          (push (make-lazy-snapshot-from-index id store) results)
          (incf count))))
    (nreverse results)))

(defun collect-snapshot-ids-lazy (start-id direction &key (max-count 1000) (store *snapshot-store*))
  "Collect snapshot IDs lazily without loading full snapshots.
   DIRECTION is :ancestors or :descendants.
   Returns list of IDs up to MAX-COUNT."
  (let ((iterator (make-lazy-dag-iterator start-id store
                                          :direction (case direction
                                                       (:ancestors :backward)
                                                       (:descendants :forward)
                                                       (t direction))
                                          :batch-size (min 100 max-count)))
        (ids nil)
        (count 0))
    (loop for batch = (iterator-next-batch iterator)
          while (and batch (< count max-count))
          do (dolist (lazy-snap batch)
               (when (>= count max-count)
                 (return))
               (push (lazy-snapshot-id lazy-snap) ids)
               (incf count)))
    (nreverse ids)))
