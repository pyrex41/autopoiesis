;;;; navigator.lisp - Snapshot navigation
;;;;
;;;; Tools for humans to navigate the snapshot DAG.

(in-package #:autopoiesis.interface)

;;; ═══════════════════════════════════════════════════════════════════
;;; Navigator Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass navigator ()
  ((position :initarg :position
             :accessor navigator-position
             :initform nil
             :documentation "Current snapshot ID")
   (history :initarg :history
            :accessor navigator-history
            :initform nil
            :documentation "Navigation history (list of snapshot IDs)"))
  (:documentation "Navigates through the snapshot DAG"))

(defun make-navigator (&key initial-position)
  "Create a new navigator."
  (make-instance 'navigator :position initial-position))

;;; ═══════════════════════════════════════════════════════════════════
;;; Navigation Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun navigate-to (navigator snapshot-id)
  "Navigate to a specific snapshot."
  (when (navigator-position navigator)
    (push (navigator-position navigator) (navigator-history navigator)))
  (setf (navigator-position navigator) snapshot-id))

(defun navigate-back (navigator)
  "Go back to previous position."
  (when (navigator-history navigator)
    (setf (navigator-position navigator) (pop (navigator-history navigator)))))

(defun navigate-forward (navigator)
  "Navigate forward (to child snapshot if unambiguous)."
  ;; Placeholder - needs snapshot store access
  (declare (ignore navigator))
  nil)

(defun navigate-to-branch (navigator branch-name)
  "Navigate to the head of a branch."
  (let ((branch (autopoiesis.snapshot:switch-branch branch-name)))
    (navigate-to navigator (autopoiesis.snapshot:branch-head branch))))
