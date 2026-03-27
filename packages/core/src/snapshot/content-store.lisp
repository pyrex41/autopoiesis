;;;; content-store.lisp - Content-addressable storage
;;;;
;;;; Stores data by content hash for deduplication.
;;;; Supports both S-expression content (via sexpr-hash) and raw byte
;;;; blobs (via SHA-256 of raw bytes) for filesystem snapshot storage.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Content Store Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass content-store ()
  ((data :initarg :data
         :accessor store-data
         :initform (make-hash-table :test 'equal)
         :documentation "Hash -> content mapping (S-expressions)")
   (blobs :initarg :blobs
          :accessor store-blobs
          :initform (make-hash-table :test 'equal)
          :documentation "Hash -> byte vector mapping (file blobs)")
   (refs :initarg :refs
         :accessor store-refs
         :initform (make-hash-table :test 'equal)
         :documentation "Hash -> reference count (shared across data and blobs)"))
  (:documentation "Content-addressable storage for S-expressions and file blobs"))

(defun make-content-store ()
  "Create a new content store."
  (make-instance 'content-store))

;;; ═══════════════════════════════════════════════════════════════════
;;; S-expression Store Operations (original API, unchanged)
;;; ═══════════════════════════════════════════════════════════════════

(defun store-put (store content)
  "Store S-expression CONTENT, return its hash."
  (let ((hash (autopoiesis.core:sexpr-hash content)))
    (unless (gethash hash (store-data store))
      (setf (gethash hash (store-data store)) content))
    ;; Increment reference count
    (incf (gethash hash (store-refs store) 0))
    hash))

(defun store-get (store hash)
  "Retrieve S-expression content by HASH."
  (gethash hash (store-data store)))

(defun store-exists-p (store hash)
  "Check if HASH exists in store (S-expression or blob)."
  (or (nth-value 1 (gethash hash (store-data store)))
      (nth-value 1 (gethash hash (store-blobs store)))))

(defun store-delete (store hash)
  "Delete content by HASH (decrements ref count)."
  (when (gethash hash (store-refs store))
    (decf (gethash hash (store-refs store)))
    (when (<= (gethash hash (store-refs store)) 0)
      (remhash hash (store-data store))
      (remhash hash (store-blobs store))
      (remhash hash (store-refs store)))))

(defun store-gc (store)
  "Garbage collect unreferenced content."
  (let ((removed 0))
    (maphash (lambda (hash refs)
               (when (<= refs 0)
                 (remhash hash (store-data store))
                 (remhash hash (store-blobs store))
                 (remhash hash (store-refs store))
                 (incf removed)))
             (store-refs store))
    removed))

;;; ═══════════════════════════════════════════════════════════════════
;;; Blob Store Operations (for filesystem content)
;;; ═══════════════════════════════════════════════════════════════════

(defun blob-hash (bytes)
  "Compute SHA-256 hash of a byte vector. Returns hex string."
  (let ((digester (ironclad:make-digest :sha256)))
    (ironclad:update-digest digester bytes)
    (ironclad:byte-array-to-hex-string
     (ironclad:produce-digest digester))))

(defun store-put-blob (store bytes)
  "Store raw BYTES (unsigned-byte 8 vector), return its SHA-256 hash.
   Deduplicates: if the same content already exists, just increments refcount."
  (let ((hash (blob-hash bytes)))
    (unless (gethash hash (store-blobs store))
      (setf (gethash hash (store-blobs store))
            (make-array (length bytes)
                        :element-type '(unsigned-byte 8)
                        :initial-contents bytes)))
    (incf (gethash hash (store-refs store) 0))
    hash))

(defun store-get-blob (store hash)
  "Retrieve raw bytes by HASH. Returns byte vector or NIL."
  (gethash hash (store-blobs store)))

(defun store-blob-exists-p (store hash)
  "Check if a blob with HASH exists in the store."
  (nth-value 1 (gethash hash (store-blobs store))))

(defun store-stats (store)
  "Return statistics about the content store as a plist."
  (let ((sexpr-count (hash-table-count (store-data store)))
        (blob-count (hash-table-count (store-blobs store)))
        (blob-bytes 0))
    (maphash (lambda (hash bytes)
               (declare (ignore hash))
               (incf blob-bytes (length bytes)))
             (store-blobs store))
    (list :sexpr-count sexpr-count
          :blob-count blob-count
          :blob-bytes blob-bytes
          :total-entries (+ sexpr-count blob-count)
          :ref-count (hash-table-count (store-refs store)))))
