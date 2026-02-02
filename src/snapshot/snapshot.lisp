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
   (metadata :initarg :metadata
             :accessor snapshot-metadata
             :initform nil
             :documentation "Additional metadata plist")
   (hash :initarg :hash
         :accessor snapshot-hash
         :initform nil
         :documentation "Content hash for deduplication"))
  (:documentation "A point-in-time capture of agent state"))

(defun make-snapshot (agent-state &key parent metadata)
  "Create a new snapshot of AGENT-STATE."
  (let ((snap (make-instance 'snapshot
                             :agent-state agent-state
                             :parent parent
                             :metadata metadata)))
    ;; Compute content hash
    (setf (snapshot-hash snap)
          (autopoiesis.core:sexpr-hash agent-state))
    snap))

(defmethod print-object ((snap snapshot) stream)
  (print-unreadable-object (snap stream :type t)
    (format stream "~a" (snapshot-id snap))))
