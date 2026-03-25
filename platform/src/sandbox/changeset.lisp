;;;; changeset.lisp - Track pending file changes between snapshots
;;;;
;;;; Instead of scanning the entire filesystem on every snapshot,
;;;; track which files have been modified/added/deleted since the last
;;;; snapshot. On commit, only hash/store the changed files.
;;;;
;;;; This turns snapshot creation from O(total_files) to O(changed_files).

(in-package #:autopoiesis.sandbox)

;;; ═══════════════════════════════════════════════════════════════════
;;; Changeset Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass changeset ()
  ((sandbox-id :initarg :sandbox-id
               :accessor changeset-sandbox-id
               :documentation "The sandbox this changeset tracks")
   (changes :initarg :changes
            :accessor changeset-changes
            :initform (make-hash-table :test 'equal)
            :documentation "path -> change-type (:added, :modified, :deleted)")
   (base-tree :initarg :base-tree
              :accessor changeset-base-tree
              :initform nil
              :documentation "Tree entries from the last snapshot (baseline)")
   (lock :initarg :lock
         :accessor changeset-lock
         :initform (bt:make-lock "changeset")))
  (:documentation "Tracks pending filesystem changes since last snapshot."))

(defun make-changeset (sandbox-id &key base-tree)
  "Create a new changeset for tracking changes."
  (make-instance 'changeset
                 :sandbox-id sandbox-id
                 :base-tree base-tree))

;;; ═══════════════════════════════════════════════════════════════════
;;; Recording Changes
;;; ═══════════════════════════════════════════════════════════════════

(defun changeset-record (changeset path change-type)
  "Record a file change. CHANGE-TYPE is :added, :modified, or :deleted.
   Thread-safe."
  (bt:with-lock-held ((changeset-lock changeset))
    (setf (gethash path (changeset-changes changeset)) change-type)))

(defun changeset-record-write (changeset path)
  "Record a file write (add or modify)."
  (let ((base (changeset-base-tree changeset)))
    (if (and base (autopoiesis.snapshot:tree-find-entry base path))
        (changeset-record changeset path :modified)
        (changeset-record changeset path :added))))

(defun changeset-record-delete (changeset path)
  "Record a file deletion."
  (changeset-record changeset path :deleted))

;;; ═══════════════════════════════════════════════════════════════════
;;; Querying
;;; ═══════════════════════════════════════════════════════════════════

(defun changeset-changed-paths (changeset)
  "Return a list of all changed paths."
  (bt:with-lock-held ((changeset-lock changeset))
    (let ((paths '()))
      (maphash (lambda (path type)
                 (declare (ignore type))
                 (push path paths))
               (changeset-changes changeset))
      paths)))

(defun changeset-change-count (changeset)
  "Return the number of pending changes."
  (hash-table-count (changeset-changes changeset)))

(defun changeset-empty-p (changeset)
  "True if no changes have been recorded."
  (zerop (changeset-change-count changeset)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Commit (incremental snapshot)
;;; ═══════════════════════════════════════════════════════════════════

(defun changeset-commit (changeset sandbox-root content-store)
  "Build a new tree from the base tree + pending changes.
   Only reads/hashes files that actually changed.
   Returns the new tree entries list.

   SANDBOX-ROOT is the filesystem root to read changed files from.
   CONTENT-STORE is where new blobs are stored."
  (bt:with-lock-held ((changeset-lock changeset))
    (let* ((base (or (changeset-base-tree changeset) '()))
           (base-map (make-hash-table :test 'equal))
           (new-entries '()))
      ;; Index base tree
      (dolist (entry base)
        (setf (gethash (autopoiesis.snapshot:entry-path entry) base-map) entry))
      ;; Apply changes
      (maphash (lambda (path change-type)
                 (ecase change-type
                   (:deleted
                    ;; Remove from base-map (won't appear in output)
                    (remhash path base-map))
                   ((:added :modified)
                    ;; Read the actual file, hash it, store blob
                    (let ((full-path (merge-pathnames path sandbox-root)))
                      (when (probe-file full-path)
                        (let* ((bytes (autopoiesis.snapshot:read-file-bytes
                                       (namestring full-path)))
                               (hash (autopoiesis.snapshot:store-put-blob
                                      content-store bytes))
                               (stat-mode
                                 (or (ignore-errors
                                       #+sbcl (sb-posix:stat-mode
                                               (sb-posix:stat (namestring full-path)))
                                       #-sbcl 33188)
                                     33188))
                               (stat-mtime
                                 (or (ignore-errors (file-write-date full-path))
                                     (get-universal-time)))
                               (entry (autopoiesis.snapshot:make-file-entry
                                       path hash stat-mode (length bytes) stat-mtime)))
                          ;; Replace in base-map
                          (setf (gethash path base-map) entry)))))))
               (changeset-changes changeset))
      ;; Collect all remaining entries
      (maphash (lambda (path entry)
                 (declare (ignore path))
                 (push entry new-entries))
               base-map)
      ;; Sort for deterministic Merkle root
      (sort new-entries #'string<
            :key #'autopoiesis.snapshot:entry-path))))

(defun changeset-reset (changeset &key new-base-tree)
  "Reset the changeset after a successful snapshot commit.
   Optionally set a new base tree."
  (bt:with-lock-held ((changeset-lock changeset))
    (clrhash (changeset-changes changeset))
    (when new-base-tree
      (setf (changeset-base-tree changeset) new-base-tree))))
