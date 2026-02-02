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
;;; Snapshot Navigation (wrappers for persistence layer)
;;; ═══════════════════════════════════════════════════════════════════

;; Note: find-snapshot is a compatibility wrapper that uses load-snapshot
;; from the persistence layer.

(defun find-snapshot (id &optional (store *snapshot-store*))
  "Find a snapshot by ID. Wrapper around load-snapshot."
  (load-snapshot id store))
