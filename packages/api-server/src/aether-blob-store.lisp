;;;; aether-blob-store.lisp - LMDB-backed durability for AETHER file blobs.
;;;;
;;;; The AETHER content-store (an autopoiesis.snapshot:content-store) keeps
;;;; file blob bytes in an in-process hash-table. When SBCL restarts, those
;;;; blobs disappear and any POST /api/aether/snapshots/:id/checkout against
;;;; a pre-restart snapshot fails — even though the snapshot metadata
;;;; (tree-entries with hashes) still lives on disk under /tmp/aether-seed/.
;;;;
;;;; This module adds an LMDB-backed "side" blob store: every blob captured
;;;; during scan-directory-flat is also written to LMDB, and every blob
;;;; needed during materialize-tree is hydrated back into the in-memory
;;;; content-store if it's missing. The in-memory store stays the fast path;
;;;; LMDB is the durability backstop.
;;;;
;;;; Why a dedicated LMDB env (not autopoiesis.substrate:open-lmdb-store)?
;;;;   open-lmdb-store stands up a full substrate (indexes, intern tables,
;;;;   datom storage) and clobbers *store* / *substrate*. We only need blob
;;;;   bytes keyed by SHA-256, and we don't want to interfere with any other
;;;;   code that might rely on the substrate globals. So we use the lmdb
;;;;   package directly with our own env handle.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Env + DB lifecycle
;;; ===================================================================

(defvar *aether-blob-env* nil
  "Dedicated LMDB env for AETHER's durable blob store, or NIL if not opened.")

(defvar *aether-blob-db* nil
  "LMDB DB handle inside *aether-blob-env* — blob hash (utf-8) → bytes.")

(defvar *aether-blob-store-lock*
  (bordeaux-threads:make-lock "aether-blob-store")
  "Serializes init and writes against the LMDB env.")

(defparameter *aether-blob-store-path* "/tmp/aether-seed/blobs/"
  "On-disk directory for the LMDB env. Parallel to the snapshot store
   already used by /tmp/aether-start-server.lisp.")

(defun ensure-aether-blob-store (&optional (path *aether-blob-store-path*))
  "Lazily open the LMDB env + blobs DB. Idempotent. Returns the DB handle.
   PATH defaults to *aether-blob-store-path*."
  (bordeaux-threads:with-lock-held (*aether-blob-store-lock*)
    (unless *aether-blob-db*
      (ensure-directories-exist (uiop:ensure-directory-pathname path))
      (handler-case
          (let ((env (lmdb:open-env path
                                    :if-does-not-exist :create
                                    :max-dbs 4
                                    ;; 1 GiB cap — plenty for source trees,
                                    ;; not so big it bloats sparse files.
                                    :map-size (* 1024 1024 1024))))
            (setf *aether-blob-env* env)
            (let ((lmdb:*env* env))
              (setf *aether-blob-db*
                    (lmdb:get-db "blobs"
                                 :if-does-not-exist :create
                                 :key-encoding :utf-8
                                 :value-encoding :octets))))
        (error (e)
          (log:warn "aether-blob-store: failed to open LMDB at ~A: ~A" path e)
          (setf *aether-blob-env* nil
                *aether-blob-db* nil))))
    *aether-blob-db*))

(defun close-aether-blob-store ()
  "Close the LMDB env. Tests use this between open/reopen cycles."
  (bordeaux-threads:with-lock-held (*aether-blob-store-lock*)
    (when *aether-blob-env*
      (handler-case (lmdb:close-env *aether-blob-env*)
        (error (e) (log:warn "aether-blob-store: close failed: ~A" e))))
    (setf *aether-blob-env* nil
          *aether-blob-db* nil)))

;;; ===================================================================
;;; Single-blob persistence
;;; ===================================================================

(defun persist-aether-blob (hash bytes)
  "Write a single blob to LMDB. HASH is the SHA-256 hex string; BYTES is an
   (unsigned-byte 8) vector. Idempotent: existing entries are left alone."
  (let ((db (ensure-aether-blob-store)))
    (when (and db hash bytes)
      (handler-case
          (bordeaux-threads:with-lock-held (*aether-blob-store-lock*)
            (let ((lmdb:*env* *aether-blob-env*))
              (lmdb:with-txn (:write t)
                (unless (lmdb:g3t db hash)
                  (lmdb:put db hash bytes
                            :overwrite t :key-exists-error-p nil)))))
        (error (e)
          (log:warn "aether-blob-store: persist failed for ~A: ~A" hash e)
          nil)))))

(defun load-aether-blob (hash)
  "Read a single blob from LMDB, or NIL if absent / store unopened."
  (let ((db (ensure-aether-blob-store)))
    (when (and db hash)
      (handler-case
          (let ((lmdb:*env* *aether-blob-env*))
            (lmdb:with-txn (:write nil)
              (lmdb:g3t db hash)))
        (error (e)
          (log:warn "aether-blob-store: load failed for ~A: ~A" hash e)
          nil)))))

(defun aether-blob-exists-p (hash)
  "Cheap existence check (avoids returning the full byte vector)."
  (let ((db (ensure-aether-blob-store)))
    (when (and db hash)
      (handler-case
          (let ((lmdb:*env* *aether-blob-env*))
            (lmdb:with-txn (:write nil)
              (not (null (lmdb:g3t db hash)))))
        (error () nil)))))

;;; ===================================================================
;;; Bulk persist / hydrate against an autopoiesis.snapshot:content-store
;;; ===================================================================

(defun persist-content-store-blobs (content-store)
  "Mirror every blob currently in CONTENT-STORE's in-memory blobs table out
   to LMDB. Cheap on re-call: already-present hashes are skipped. Returns
   the number of NEW blobs written."
  (let ((written 0))
    (when (and content-store (ensure-aether-blob-store))
      (let ((blobs (autopoiesis.snapshot::store-blobs content-store)))
        (maphash (lambda (hash bytes)
                   (unless (aether-blob-exists-p hash)
                     (when (persist-aether-blob hash bytes)
                       (incf written))))
                 blobs)))
    written))

(defun hydrate-content-store-blobs (content-store hashes)
  "For every hash in HASHES that's absent from CONTENT-STORE's in-memory
   blobs, try to load it from LMDB and stash it back. Returns the number of
   blobs hydrated. Caller-supplied HASHES is typically the set of file-entry
   hashes from a snapshot's tree-entries.

   This is the function that makes post-restart checkout work: blobs that
   were captured before the restart live only in LMDB, and we copy them
   back into the in-memory hash-table so materialize-tree finds them."
  (let ((hydrated 0)
        (blobs (and content-store
                    (autopoiesis.snapshot::store-blobs content-store))))
    (when (and blobs (ensure-aether-blob-store))
      (dolist (hash hashes)
        (when (and hash (not (gethash hash blobs)))
          (let ((bytes (load-aether-blob hash)))
            (when bytes
              (setf (gethash hash blobs) bytes)
              (incf hydrated))))))
    hydrated))

(defun tree-entry-hashes (entries)
  "Collect the content hashes of every :file entry in ENTRIES."
  (let ((result '()))
    (dolist (e (or entries '()))
      (when (eq (autopoiesis.snapshot:entry-type e) :file)
        (let ((h (autopoiesis.snapshot:entry-hash e)))
          (when h (push h result)))))
    (nreverse result)))
