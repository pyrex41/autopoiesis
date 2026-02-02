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
