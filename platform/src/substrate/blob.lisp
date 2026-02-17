;;;; blob.lisp - Content-addressed blob store
;;;;
;;;; Stores arbitrary content as SHA-256 addressed blobs.
;;;; When LMDB is available, uses LMDB; otherwise in-memory.

(in-package #:autopoiesis.substrate)

;;; In-memory blob store (fallback when no LMDB)
(defvar *memory-blobs* (make-hash-table :test 'equal)
  "In-memory blob storage for non-LMDB stores")

(defun reset-memory-blobs ()
  "Reset in-memory blob store. For testing."
  (clrhash *memory-blobs*))

(defun store-blob (content &key (store *store*))
  "Store content as a content-addressed blob. Returns hash string.
   CONTENT can be string or byte vector."
  (let* ((bytes (etypecase content
                  (string (babel:string-to-octets content :encoding :utf-8))
                  ((vector (unsigned-byte 8)) content)))
         (hash (ironclad:byte-array-to-hex-string
                (ironclad:digest-sequence :sha256 bytes))))
    (if (and store (store-blob-db store))
        ;; LMDB path
        (lmdb:with-txn (:write t)
          (lmdb:put (store-blob-db store) hash bytes
                    :overwrite t :key-exists-error-p nil))
        ;; In-memory fallback
        (setf (gethash hash *memory-blobs*) bytes))
    hash))

(defun load-blob (hash &key (store *store*) as-string)
  "Load blob by content hash. Returns bytes, or string if AS-STRING."
  (let ((bytes
          (if (and store (store-blob-db store))
              ;; LMDB path
              (lmdb:with-txn (:write nil)
                (lmdb:g3t (store-blob-db store) hash))
              ;; In-memory fallback
              (gethash hash *memory-blobs*))))
    (when bytes
      (if as-string
          (babel:octets-to-string bytes :encoding :utf-8)
          bytes))))

(defun blob-exists-p (hash &key (store *store*))
  "Check if blob exists without loading it."
  (if (and store (store-blob-db store))
      (lmdb:with-txn (:write nil)
        (not (null (lmdb:g3t (store-blob-db store) hash))))
      (not (null (gethash hash *memory-blobs*)))))
