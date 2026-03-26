;;;; migration.lisp - Migrate filesystem snapshots to substrate
;;;;
;;;; Migrates snapshot data from the existing filesystem-based
;;;; content store to substrate datoms + blobs.

(in-package #:autopoiesis.substrate)

(defun migrate-filesystem-to-substrate (old-store-path &key (store *store*))
  "Migrate all snapshots from filesystem to substrate datoms + blobs.
   Each snapshot becomes:
   - A blob (the full S-expression content)
   - Datoms for metadata: :snapshot/content-hash, :snapshot/timestamp, etc."
  (declare (ignore store))
  (let ((migrated 0)
        (errors 0))
    (when (and old-store-path (probe-file old-store-path))
      (dolist (file (uiop:directory-files old-store-path))
        (handler-case
            (when (string= "lisp" (pathname-type file))
              (let* ((content (uiop:read-file-string file))
                     (blob-hash (store-blob content))
                     (snap-name (pathname-name file))
                     (snap-eid (intern-id (format nil "migrated-~A" snap-name))))
                (transact!
                 (list (make-datom snap-eid :entity/type :snapshot)
                       (make-datom snap-eid :snapshot/content-hash blob-hash)
                       (make-datom snap-eid :snapshot/timestamp (get-universal-time))))
                (incf migrated)))
          (error (e)
            (warn "Migration error for ~A: ~A" file e)
            (incf errors)))))
    (values migrated errors)))
