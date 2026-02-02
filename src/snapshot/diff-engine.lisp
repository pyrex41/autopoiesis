;;;; diff-engine.lisp - Snapshot diffing
;;;;
;;;; Compute differences between snapshots.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Diffing
;;; ═══════════════════════════════════════════════════════════════════

(defun snapshot-diff (old-snapshot new-snapshot)
  "Compute the diff between two snapshots.
   Returns a list of edit operations."
  (autopoiesis.core:sexpr-diff
   (snapshot-agent-state old-snapshot)
   (snapshot-agent-state new-snapshot)))

(defun snapshot-patch (snapshot edits)
  "Apply EDITS to SNAPSHOT, creating a new snapshot."
  (let ((new-state (autopoiesis.core:sexpr-patch
                    (snapshot-agent-state snapshot)
                    edits)))
    (make-snapshot new-state :parent (snapshot-id snapshot))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Navigation
;;; ═══════════════════════════════════════════════════════════════════

(defvar *snapshot-store* (make-hash-table :test 'equal)
  "Store of all snapshots by ID.")

(defun find-snapshot (id &key (store *snapshot-store*))
  "Find a snapshot by ID."
  (gethash id store))

(defun store-snapshot (snapshot &key (store *snapshot-store*))
  "Store a snapshot."
  (setf (gethash (snapshot-id snapshot) store) snapshot))

(defun snapshot-ancestors (snapshot &key (store *snapshot-store*))
  "Return list of ancestor snapshots."
  (let ((ancestors nil)
        (current (snapshot-parent snapshot)))
    (loop while current
          do (let ((parent (find-snapshot current :store store)))
               (when parent
                 (push parent ancestors)
                 (setf current (snapshot-parent parent)))))
    (nreverse ancestors)))

(defun snapshot-descendants (snapshot &key (store *snapshot-store*))
  "Return list of direct child snapshots."
  (let ((id (snapshot-id snapshot)))
    (loop for snap being the hash-values of store
          when (equal (snapshot-parent snap) id)
            collect snap)))
