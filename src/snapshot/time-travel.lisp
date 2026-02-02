;;;; time-travel.lisp - Time travel navigation
;;;;
;;;; Moving through the snapshot DAG.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Time Travel Operations
;;; ═══════════════════════════════════════════════════════════════════

(defvar *current-snapshot* nil
  "Currently checked out snapshot.")

(defun checkout-snapshot (snapshot-id &key (store *snapshot-store*))
  "Check out a snapshot, making it current.
   Returns the snapshot's agent state."
  (let ((snapshot (find-snapshot snapshot-id :store store)))
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
        (let ((head-snap (find-snapshot head :store store)))
          (when head-snap
            (cons head-snap (snapshot-ancestors head-snap :store store))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun snapshot-to-sexpr (snapshot)
  "Convert SNAPSHOT to S-expression for persistence."
  `(:snapshot
    :id ,(snapshot-id snapshot)
    :timestamp ,(snapshot-timestamp snapshot)
    :parent ,(snapshot-parent snapshot)
    :hash ,(snapshot-hash snapshot)
    :metadata ,(snapshot-metadata snapshot)
    :agent-state ,(snapshot-agent-state snapshot)))

(defun sexpr-to-snapshot (sexpr)
  "Reconstruct a snapshot from S-expression."
  (destructuring-bind (&key id timestamp parent hash metadata agent-state)
      (rest sexpr)
    (let ((snap (make-instance 'snapshot
                               :id id
                               :timestamp timestamp
                               :parent parent
                               :hash hash
                               :metadata metadata
                               :agent-state agent-state)))
      snap)))
