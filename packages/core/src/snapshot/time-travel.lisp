;;;; time-travel.lisp - Time travel navigation
;;;;
;;;; Moving through the snapshot DAG.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Time Travel Operations
;;; ═══════════════════════════════════════════════════════════════════

(defvar *current-snapshot* nil
  "Currently checked out snapshot.")

(defun checkout-snapshot (snapshot-id &optional (store *snapshot-store*))
  "Check out a snapshot, making it current.
   Returns the snapshot's agent state."
  (let ((snapshot (load-snapshot snapshot-id store)))
    (unless snapshot
      (error 'autopoiesis.core:autopoiesis-error
             :message (format nil "Snapshot not found: ~a" snapshot-id)))
    (setf *current-snapshot* snapshot)
    (snapshot-agent-state snapshot)))

(defun branch-history (&key (branch *current-branch*) (store *snapshot-store*))
  "Return the history of snapshots on BRANCH."
  (when branch
    (let ((head (branch-head branch)))
      (when head
        (let ((head-snap (load-snapshot head store)))
          (when head-snap
            (cons head-snap (snapshot-ancestors head store))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; DAG Traversal
;;; ═══════════════════════════════════════════════════════════════════

(defun collect-ancestor-ids (snapshot-id &optional (store *snapshot-store*))
  "Collect all ancestor IDs of SNAPSHOT-ID (not including itself).
   Returns a list of IDs from parent to root."
  (unless store
    (return-from collect-ancestor-ids nil))
  (loop with current-id = snapshot-id
        for snap = (load-snapshot current-id store)
        while snap
        for parent-id = (snapshot-parent snap)
        while parent-id
        collect parent-id
        do (setf current-id parent-id)))

(defun find-common-ancestor (snapshot-id-a snapshot-id-b &optional (store *snapshot-store*))
  "Find the most recent common ancestor of two snapshots.
   Returns the common ancestor snapshot, or NIL if none exists."
  (unless store
    (return-from find-common-ancestor nil))
  ;; Build set of ancestors for A (including A itself)
  (let ((ancestors-a (make-hash-table :test 'equal)))
    (setf (gethash snapshot-id-a ancestors-a) t)
    (dolist (id (collect-ancestor-ids snapshot-id-a store))
      (setf (gethash id ancestors-a) t))
    ;; Walk B's lineage until we find a common ancestor
    (loop for current-id = snapshot-id-b
          then (let ((snap (load-snapshot current-id store)))
                 (when snap (snapshot-parent snap)))
          while current-id
          when (gethash current-id ancestors-a)
          return (load-snapshot current-id store))))

(defun find-path (from-id to-id &optional (store *snapshot-store*))
  "Find the path of snapshot IDs from FROM-ID to TO-ID.
   Returns a list of IDs representing the path, or NIL if no path exists.
   Works by finding common ancestor and constructing path through it."
  (unless store
    (return-from find-path nil))
  ;; Handle same snapshot case
  (when (equal from-id to-id)
    (return-from find-path (list from-id)))
  ;; Check if TO-ID is an ancestor of FROM-ID (going backward in lineage)
  (let ((ancestors-from (collect-ancestor-ids from-id store)))
    (when (member to-id ancestors-from :test #'equal)
      ;; Path goes: from-id -> parent -> ... -> to-id
      ;; Collect in traversal order (from -> to)
      (return-from find-path
        (loop for id = from-id then (snapshot-parent (load-snapshot id store))
              collect id
              until (equal id to-id)))))
  ;; Check if FROM-ID is an ancestor of TO-ID (going forward)
  (let ((ancestors-to (collect-ancestor-ids to-id store)))
    (when (member from-id ancestors-to :test #'equal)
      ;; Path goes forward: from-id -> ... -> to-id
      (return-from find-path
        (loop for id = to-id then (snapshot-parent (load-snapshot id store))
              collect id into path
              until (equal id from-id)
              finally (return (nreverse path))))))
  ;; Find common ancestor and construct path through it
  (let ((ancestor (find-common-ancestor from-id to-id store)))
    (when ancestor
      (let* ((ancestor-id (snapshot-id ancestor))
             ;; Path from FROM-ID to ancestor (going backward)
             (path-to-ancestor
               (loop for id = from-id then (snapshot-parent (load-snapshot id store))
                     collect id
                     until (equal id ancestor-id)))
             ;; Path from TO-ID to ancestor (going backward, will be reversed)
             (path-from-ancestor
               (loop for id = to-id then (snapshot-parent (load-snapshot id store))
                     until (equal id ancestor-id)
                     collect id)))
        ;; Combine: from-id -> ancestor -> to-id
        (append path-to-ancestor (nreverse path-from-ancestor))))))

(defun dag-distance (snapshot-id-a snapshot-id-b &optional (store *snapshot-store*))
  "Calculate the distance (number of edges) between two snapshots in the DAG.
   Returns NIL if no path exists."
  (let ((path (find-path snapshot-id-a snapshot-id-b store)))
    (when path
      (1- (length path)))))

(defun is-ancestor-p (potential-ancestor-id descendant-id &optional (store *snapshot-store*))
  "Check if POTENTIAL-ANCESTOR-ID is an ancestor of DESCENDANT-ID."
  (unless store
    (return-from is-ancestor-p nil))
  (member potential-ancestor-id
          (collect-ancestor-ids descendant-id store)
          :test #'equal))

(defun is-descendant-p (potential-descendant-id ancestor-id &optional (store *snapshot-store*))
  "Check if POTENTIAL-DESCENDANT-ID is a descendant of ANCESTOR-ID."
  (is-ancestor-p ancestor-id potential-descendant-id store))

(defun dag-depth (snapshot-id &optional (store *snapshot-store*))
  "Calculate the depth of SNAPSHOT-ID in the DAG (distance from root).
   Root snapshots have depth 0."
  (length (collect-ancestor-ids snapshot-id store)))

(defun find-root (snapshot-id &optional (store *snapshot-store*))
  "Find the root snapshot (genesis) of the lineage containing SNAPSHOT-ID."
  (unless store
    (return-from find-root nil))
  (let ((ancestors (collect-ancestor-ids snapshot-id store)))
    (if ancestors
        (load-snapshot (car (last ancestors)) store)
        ;; snapshot-id itself is the root
        (load-snapshot snapshot-id store))))

(defun find-branch-point (snapshot-id &optional (store *snapshot-store*))
  "Find the most recent snapshot where SNAPSHOT-ID's lineage has multiple children.
   This represents where a branch diverged."
  (unless store
    (return-from find-branch-point nil))
  (loop for current-id = snapshot-id then (snapshot-parent snap)
        for snap = (load-snapshot current-id store)
        while snap
        when (> (length (snapshot-children current-id store)) 1)
        return snap))

(defun walk-ancestors (snapshot-id function &optional (store *snapshot-store*))
  "Walk up the DAG from SNAPSHOT-ID, calling FUNCTION on each snapshot.
   FUNCTION receives the snapshot object. Stops if FUNCTION returns :stop."
  (unless store
    (return-from walk-ancestors nil))
  (loop for current-id = snapshot-id then (snapshot-parent snap)
        for snap = (load-snapshot current-id store)
        while snap
        do (when (eq :stop (funcall function snap))
             (return snap))))

(defun walk-descendants (snapshot-id function &optional (store *snapshot-store*))
  "Walk down the DAG from SNAPSHOT-ID in breadth-first order, calling FUNCTION on each snapshot.
   FUNCTION receives the snapshot object. Stops if FUNCTION returns :stop."
  (unless (and store (store-index store))
    (return-from walk-descendants nil))
  (let ((queue (list snapshot-id))
        (visited (make-hash-table :test 'equal)))
    (loop while queue
          do (let* ((current-id (pop queue))
                    (snap (load-snapshot current-id store)))
               (unless (or (null snap) (gethash current-id visited))
                 (setf (gethash current-id visited) t)
                 (when (eq :stop (funcall function snap))
                   (return snap))
                 ;; Add children to queue
                 (dolist (child-id (snapshot-children current-id store))
                   (unless (gethash child-id visited)
                     (setf queue (nconc queue (list child-id))))))))))

(defun find-snapshots-between (start-id end-id &optional (store *snapshot-store*))
  "Find all snapshots on the path between START-ID and END-ID (exclusive).
    Returns a list of snapshot objects."
  (let ((path (find-path start-id end-id store)))
    (when (and path (> (length path) 2))
      ;; Remove first and last, load the rest
      (mapcar (lambda (id) (load-snapshot id store))
              (butlast (rest path))))))

(defun find-snapshots-since (since-timestamp &optional (store *snapshot-store*))
  "Find all snapshots with timestamp >= SINCE-TIMESTAMP.
    Returns a list of snapshot objects."
  (unless store
    (return-from find-snapshots-since nil))
  (let ((result nil)
        (snapshot-eids (autopoiesis.substrate:find-entities :type :snapshot)))
    (dolist (eid snapshot-eids)
      (let ((state (autopoiesis.substrate:entity-state eid store)))
        (when state
          (let ((timestamp (getf state :timestamp)))
            (when (and timestamp (>= timestamp since-timestamp))
              ;; Construct snapshot from state
              (let ((snapshot (make-instance 'snapshot
                                             :id (getf state :id)
                                             :timestamp timestamp
                                             :parent (getf state :parent)
                                             :agent-state (getf state :agent-state)
                                             :metadata (getf state :metadata))))
                (push snapshot result)))))))
    (nreverse result)))
