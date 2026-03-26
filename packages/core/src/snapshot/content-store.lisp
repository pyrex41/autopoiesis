;;;; content-store.lisp - Content-addressable storage
;;;;
;;;; Stores data by content hash for deduplication.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; Content Store Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass content-store ()
  ((data :initarg :data
         :accessor store-data
         :initform (make-hash-table :test 'equal)
         :documentation "Hash -> content mapping")
   (refs :initarg :refs
         :accessor store-refs
         :initform (make-hash-table :test 'equal)
         :documentation "Hash -> reference count"))
  (:documentation "Content-addressable storage"))

(defun make-content-store ()
  "Create a new content store."
  (make-instance 'content-store))

;;; ═══════════════════════════════════════════════════════════════════
;;; Store Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun store-put (store content)
  "Store CONTENT, return its hash."
  (let ((hash (autopoiesis.core:sexpr-hash content)))
    (unless (gethash hash (store-data store))
      (setf (gethash hash (store-data store)) content))
    ;; Increment reference count
    (incf (gethash hash (store-refs store) 0))
    hash))

(defun store-get (store hash)
  "Retrieve content by HASH."
  (gethash hash (store-data store)))

(defun store-exists-p (store hash)
  "Check if HASH exists in store."
  (nth-value 1 (gethash hash (store-data store))))

(defun store-delete (store hash)
  "Delete content by HASH (decrements ref count)."
  (when (gethash hash (store-refs store))
    (decf (gethash hash (store-refs store)))
    (when (<= (gethash hash (store-refs store)) 0)
      (remhash hash (store-data store))
      (remhash hash (store-refs store)))))

(defun store-gc (store)
  "Garbage collect unreferenced content."
  (let ((removed 0))
    (maphash (lambda (hash refs)
               (when (<= refs 0)
                 (remhash hash (store-data store))
                 (remhash hash (store-refs store))
                 (incf removed)))
             (store-refs store))
    removed))
