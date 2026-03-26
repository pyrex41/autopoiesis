;;;; branch.lisp - Branch management
;;;;
;;;; Named branches pointing to snapshot heads.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Branch Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass branch ()
  ((name :initarg :name
         :accessor branch-name
         :documentation "Branch name")
   (head :initarg :head
         :accessor branch-head
         :initform nil
         :documentation "Current head snapshot ID")
   (created :initarg :created
            :accessor branch-created
            :initform (autopoiesis.core:get-precise-time)
            :documentation "When branch was created"))
  (:documentation "A named branch in the snapshot DAG"))

(defun make-branch (name &key head)
  "Create a new branch."
  (make-instance 'branch :name name :head head))

;;; ═══════════════════════════════════════════════════════════════════
;;; Branch Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *branch-registry* (make-hash-table :test 'equal)
  "Registry of all branches.")

(defvar *current-branch* nil
  "Currently checked out branch.")

(defun create-branch (name &key from-snapshot (registry *branch-registry*))
  "Create a new branch."
  (let ((branch (make-branch name :head from-snapshot)))
    (setf (gethash name registry) branch)
    branch))

(defun switch-branch (name &key (registry *branch-registry*))
  "Switch to branch NAME."
  (let ((branch (gethash name registry)))
    (unless branch
      (error 'autopoiesis.core:autopoiesis-error
             :message (format nil "Branch not found: ~a" name)))
    (setf *current-branch* branch)
    branch))

(defun list-branches (&key (registry *branch-registry*))
  "List all branches."
  (loop for branch being the hash-values of registry
        collect branch))

(defun current-branch ()
  "Return the current branch."
  *current-branch*)

(defun merge-branches (source target &key (registry *branch-registry*))
  "Merge SOURCE branch into TARGET."
  (declare (ignore registry))
  ;; Placeholder - merge logic is complex
  (declare (ignore source target))
  (error 'autopoiesis.core:autopoiesis-error
         :message "Branch merging not yet implemented"))
