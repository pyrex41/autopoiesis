;;;; snapshot.lisp - Snapshot class
;;;;
;;;; Snapshots capture agent state at a point in time.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass snapshot ()
  ((id :initarg :id
       :accessor snapshot-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique identifier")
   (timestamp :initarg :timestamp
              :accessor snapshot-timestamp
              :initform (autopoiesis.core:get-precise-time)
              :documentation "When this snapshot was created")
   (parent :initarg :parent
           :accessor snapshot-parent
           :initform nil
           :documentation "Parent snapshot ID (nil for root)")
   (agent-state :initarg :agent-state
                :accessor snapshot-agent-state
                :initform nil
                :documentation "Serialized agent state")
   (tree-root :initarg :tree-root
              :accessor snapshot-tree-root
              :initform nil
              :documentation "Merkle root hash of filesystem tree (nil if no filesystem state)")
   (tree-entries :initarg :tree-entries
                 :accessor snapshot-tree-entries
                 :initform nil
                 :documentation "List of filesystem tree entries (path/hash/mode/size)")
   (metadata :initarg :metadata
             :accessor snapshot-metadata
             :initform nil
             :documentation "Additional metadata plist")
   (hash :initarg :hash
         :accessor snapshot-hash
         :initform nil
         :documentation "Content hash for deduplication"))
  (:documentation "A point-in-time capture of agent state and optional filesystem state"))

(defun make-snapshot (agent-state &key parent metadata tree-entries)
  "Create a new snapshot of AGENT-STATE and optional TREE-ENTRIES (filesystem state).
   If TREE-ENTRIES is provided, computes the Merkle root hash."
  (let ((snap (make-instance 'snapshot
                             :agent-state agent-state
                             :parent parent
                             :metadata metadata
                             :tree-entries tree-entries)))
    ;; Compute content hash (covers agent state)
    (setf (snapshot-hash snap)
          (autopoiesis.core:sexpr-hash agent-state))
    ;; Compute tree root hash if filesystem entries provided
    (when tree-entries
      (setf (snapshot-tree-root snap)
            (tree-hash tree-entries)))
    snap))

(defmethod print-object ((snap snapshot) stream)
  (print-unreadable-object (snap stream :type t)
    (format stream "~a" (snapshot-id snap))))
