;;;; sandbox-lifecycle.lisp - DAG-integrated sandbox lifecycle manager
;;;;
;;;; The core of "AP IS the sandbox". Manages sandbox lifecycle through
;;;; the DAG: create, exec, snapshot, fork, restore, destroy — all
;;;; tracked as substrate datoms, all backed by the content-addressed
;;;; snapshot store.
;;;;
;;;; The DAG owns the truth. Backends are ephemeral materializations.

(in-package #:autopoiesis.sandbox)

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Manager (DAG-integrated)
;;; ═══════════════════════════════════════════════════════════════════

(defclass sandbox-manager ()
  ((backend :initarg :backend
            :accessor manager-backend
            :documentation "The execution backend instance")
   (content-store :initarg :content-store
                  :accessor manager-content-store
                  :documentation "Content-addressed store for file blobs")
   (sandboxes :initarg :sandboxes
              :accessor manager-sandboxes
              :initform (make-hash-table :test 'equal)
              :documentation "sandbox-id -> sandbox-info plist")
   (lock :initarg :lock
         :accessor manager-lock
         :initform (bt:make-lock "sandbox-manager")))
  (:documentation "DAG-integrated sandbox lifecycle manager.
Coordinates between execution backends and the content-addressed store."))

(defun make-sandbox-manager (backend &key content-store)
  "Create a new sandbox manager with the given execution BACKEND.
   If CONTENT-STORE is not provided, creates a new one."
  (make-instance 'sandbox-manager
                 :backend backend
                 :content-store (or content-store
                                    (autopoiesis.snapshot:make-content-store))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Sandbox Info
;;; ═══════════════════════════════════════════════════════════════════

(defun make-sandbox-info (sandbox-id &key branch-name status created-at)
  "Create a sandbox info plist."
  (list :sandbox-id sandbox-id
        :branch-name (or branch-name (format nil "sandbox/~A" sandbox-id))
        :status (or status :creating)
        :created-at (or created-at (get-universal-time))
        :snapshot-count 0
        :last-snapshot-id nil
        :last-tree-hash nil))

;;; ═══════════════════════════════════════════════════════════════════
;;; Lifecycle Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun manager-create-sandbox (manager sandbox-id &key tree config)
  "Create a new sandbox, optionally materializing TREE into it.
   Tracks creation in substrate if available.
   Returns sandbox-id."
  (bt:with-lock-held ((manager-lock manager))
    (let ((backend (manager-backend manager))
          (store (manager-content-store manager))
          (info (make-sandbox-info sandbox-id)))
      ;; Create via backend
      (backend-create backend sandbox-id
                      :tree tree
                      :content-store store
                      :config config)
      ;; Update info
      (setf (getf info :status) :ready)
      (setf (gethash sandbox-id (manager-sandboxes manager)) info)
      ;; Track in substrate if available
      (track-sandbox-event sandbox-id :created
                           (list :backend (backend-name backend)))
      sandbox-id)))

(defun manager-destroy-sandbox (manager sandbox-id)
  "Destroy a sandbox and clean up.
   Returns sandbox-id."
  (bt:with-lock-held ((manager-lock manager))
    (let ((backend (manager-backend manager))
          (info (gethash sandbox-id (manager-sandboxes manager))))
      (when info
        (setf (getf info :status) :destroyed))
      (backend-destroy backend sandbox-id)
      (remhash sandbox-id (manager-sandboxes manager))
      (track-sandbox-event sandbox-id :destroyed nil)
      sandbox-id)))

(defun manager-exec (manager sandbox-id command &key (timeout 300) env workdir)
  "Execute a command in a sandbox. Returns exec-result plist.
   Tracks execution in substrate."
  (let* ((backend (manager-backend manager))
         (result (backend-exec backend sandbox-id command
                               :timeout timeout :env env :workdir workdir)))
    ;; Track in substrate
    (track-sandbox-event sandbox-id :exec
                         (list :command command
                               :exit-code (exec-result-exit-code result)
                               :duration-ms (exec-result-duration-ms result)))
    result))

(defun manager-snapshot (manager sandbox-id &key label parent-id)
  "Snapshot the current state of a sandbox.
   Scans the filesystem, stores blobs, creates a DAG snapshot.
   Returns the snapshot object."
  (bt:with-lock-held ((manager-lock manager))
    (let* ((backend (manager-backend manager))
           (store (manager-content-store manager))
           (info (gethash sandbox-id (manager-sandboxes manager)))
           ;; Scan filesystem into content store
           (tree-entries (backend-snapshot backend sandbox-id store))
           ;; Create snapshot with tree
           (snapshot (autopoiesis.snapshot:make-snapshot
                      (list :sandbox-id sandbox-id
                            :label label
                            :timestamp (get-universal-time))
                      :parent (or parent-id
                                  (when info (getf info :last-snapshot-id)))
                      :metadata (list :label label
                                      :sandbox-id sandbox-id
                                      :backend (backend-name backend))
                      :tree-entries tree-entries)))
      ;; Update sandbox info
      (when info
        (incf (getf info :snapshot-count))
        (setf (getf info :last-snapshot-id) (autopoiesis.snapshot:snapshot-id snapshot))
        (setf (getf info :last-tree-hash) (autopoiesis.snapshot:snapshot-tree-root snapshot)))
      ;; Track event
      (track-sandbox-event sandbox-id :snapshot
                           (list :snapshot-id (autopoiesis.snapshot:snapshot-id snapshot)
                                 :tree-hash (autopoiesis.snapshot:snapshot-tree-root snapshot)
                                 :file-count (autopoiesis.snapshot:tree-file-count tree-entries)
                                 :label label))
      snapshot)))

(defun manager-restore (manager sandbox-id snapshot &key incremental)
  "Restore a sandbox to a snapshot's filesystem state.
   SNAPSHOT can be a snapshot object or its tree-entries.
   If INCREMENTAL is true, only applies changed files.
   Returns the number of operations performed."
  (bt:with-lock-held ((manager-lock manager))
    (let* ((backend (manager-backend manager))
           (store (manager-content-store manager))
           (tree (if (typep snapshot 'autopoiesis.snapshot:snapshot)
                     (autopoiesis.snapshot:snapshot-tree-entries snapshot)
                     snapshot))
           (ops (backend-restore backend sandbox-id tree store
                                  :incremental incremental)))
      ;; Track event
      (track-sandbox-event sandbox-id :restore
                           (list :incremental incremental
                                 :operations ops))
      ops)))

(defun manager-fork (manager source-id new-id &key label)
  "Fork a sandbox. Creates a DAG branch (O(1)) and materializes
   via the backend. If backend supports native COW, uses it.
   Returns new sandbox-id."
  (bt:with-lock-held ((manager-lock manager))
    (let* ((backend (manager-backend manager))
           (store (manager-content-store manager))
           (source-info (gethash source-id (manager-sandboxes manager)))
           (new-info (make-sandbox-info new-id)))
      ;; Copy DAG state from source
      (when source-info
        (setf (getf new-info :last-snapshot-id)
              (getf source-info :last-snapshot-id))
        (setf (getf new-info :last-tree-hash)
              (getf source-info :last-tree-hash)))
      ;; Try native fork first
      (let ((native-result (when (backend-supports-native-fork-p backend)
                             (ignore-errors
                               (backend-fork backend source-id new-id)))))
        (if native-result
            ;; Native fork succeeded
            (progn
              (setf (getf new-info :status) :ready)
              (setf (gethash new-id (manager-sandboxes manager)) new-info))
            ;; Fallback: create new sandbox, restore from source's last snapshot
            (let ((source-tree (when source-info
                                 (let ((snap-id (getf source-info :last-snapshot-id)))
                                   ;; If we have the tree entries cached, use them
                                   ;; Otherwise, scan the source
                                   (backend-snapshot backend source-id store)))))
              (backend-create backend new-id
                              :tree source-tree
                              :content-store store)
              (setf (getf new-info :status) :ready)
              (setf (gethash new-id (manager-sandboxes manager)) new-info))))
      ;; Track event
      (track-sandbox-event new-id :forked
                           (list :source source-id
                                 :label label))
      new-id)))

(defun manager-diff (manager sandbox-id-a sandbox-id-b)
  "Compute diff between two sandboxes' current filesystem state.
   Returns a list of change records from tree-diff."
  (let* ((backend (manager-backend manager))
         (store (manager-content-store manager))
         (tree-a (backend-snapshot backend sandbox-id-a store))
         (tree-b (backend-snapshot backend sandbox-id-b store)))
    (autopoiesis.snapshot:tree-diff tree-a tree-b)))

(defun manager-sandbox-info (manager sandbox-id)
  "Get info plist for a sandbox."
  (gethash sandbox-id (manager-sandboxes manager)))

(defun manager-list-sandboxes (manager)
  "List all active sandboxes as a list of info plists."
  (let ((result '()))
    (maphash (lambda (id info)
               (declare (ignore id))
               (push info result))
             (manager-sandboxes manager))
    result))

;;; ═══════════════════════════════════════════════════════════════════
;;; Substrate Event Tracking
;;; ═══════════════════════════════════════════════════════════════════

(defun track-sandbox-event (sandbox-id event-type data)
  "Track a sandbox lifecycle event in the substrate (if available)."
  (when (and (boundp 'autopoiesis.substrate:*store*)
             autopoiesis.substrate:*store*)
    (ignore-errors
      (let ((eid (autopoiesis.substrate:intern-id
                  (format nil "sandbox-event:~A:~A:~D"
                          sandbox-id event-type (get-universal-time)))))
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom
                eid :sandbox-event/sandbox-id (princ-to-string sandbox-id))
               (autopoiesis.substrate:make-datom
                eid :sandbox-event/type event-type)
               (autopoiesis.substrate:make-datom
                eid :sandbox-event/timestamp (get-universal-time))
               (autopoiesis.substrate:make-datom
                eid :sandbox-event/data data)))))))
