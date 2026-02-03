;;;; lru-cache.lisp - LRU cache for hot snapshots
;;;;
;;;; Provides a Least Recently Used cache with configurable capacity
;;;; for efficient in-memory caching of frequently accessed snapshots.

(in-package #:autopoiesis.snapshot)

;;; ═══════════════════════════════════════════════════════════════════
;;; LRU Cache Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass lru-cache ()
  ((capacity :initarg :capacity
             :accessor cache-capacity
             :initform 1000
             :documentation "Maximum number of entries in the cache")
   (table :initform (make-hash-table :test 'equal)
          :accessor cache-table
          :documentation "Hash table for O(1) key lookup")
   (order :initform nil
          :accessor cache-order
          :documentation "List of keys in LRU order (most recent first)")
   (hits :initform 0
         :accessor cache-hits
         :documentation "Number of cache hits")
   (misses :initform 0
           :accessor cache-misses
           :documentation "Number of cache misses")
   (evictions :initform 0
              :accessor cache-evictions
              :documentation "Number of entries evicted"))
  (:documentation "Least Recently Used cache with configurable capacity."))

(defun make-lru-cache (&key (capacity 1000))
  "Create a new LRU cache with given CAPACITY."
  (make-instance 'lru-cache :capacity capacity))

;;; ═══════════════════════════════════════════════════════════════════
;;; Core Cache Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun cache-get (cache key)
  "Get value from CACHE by KEY, updating LRU order.
   Returns the value if found, NIL otherwise.
   Updates cache hit/miss statistics."
  (let ((value (gethash key (cache-table cache))))
    (if value
        (progn
          (incf (cache-hits cache))
          ;; Move key to front of order (most recently used)
          (setf (cache-order cache)
                (cons key (remove key (cache-order cache) :test #'equal)))
          value)
        (progn
          (incf (cache-misses cache))
          nil))))

(defun cache-put (cache key value)
  "Put VALUE in CACHE under KEY, evicting LRU entry if at capacity.
   Returns the evicted key if eviction occurred, NIL otherwise."
  (let ((evicted-key nil))
    ;; Check if key already exists
    (if (gethash key (cache-table cache))
        ;; Update existing entry, move to front
        (progn
          (setf (gethash key (cache-table cache)) value)
          (setf (cache-order cache)
                (cons key (remove key (cache-order cache) :test #'equal))))
        ;; New entry
        (progn
          ;; Evict if at capacity
          (when (>= (hash-table-count (cache-table cache)) (cache-capacity cache))
            (let ((lru-key (car (last (cache-order cache)))))
              (when lru-key
                (remhash lru-key (cache-table cache))
                (setf (cache-order cache) (butlast (cache-order cache)))
                (incf (cache-evictions cache))
                (setf evicted-key lru-key))))
          ;; Insert new entry
          (setf (gethash key (cache-table cache)) value)
          (push key (cache-order cache))))
    evicted-key))

(defun cache-remove (cache key)
  "Remove KEY from CACHE. Returns T if key was present, NIL otherwise."
  (when (gethash key (cache-table cache))
    (remhash key (cache-table cache))
    (setf (cache-order cache)
          (remove key (cache-order cache) :test #'equal))
    t))

(defun cache-contains-p (cache key)
  "Check if KEY exists in CACHE without updating LRU order."
  (nth-value 1 (gethash key (cache-table cache))))

(defun cache-clear (cache)
  "Clear all entries from CACHE."
  (clrhash (cache-table cache))
  (setf (cache-order cache) nil))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cache Statistics
;;; ═══════════════════════════════════════════════════════════════════

(defun cache-size (cache)
  "Return the current number of entries in CACHE."
  (hash-table-count (cache-table cache)))

(defun cache-hit-rate (cache)
  "Return the cache hit rate as a float between 0.0 and 1.0.
   Returns 0.0 if no accesses have been made."
  (let ((total (+ (cache-hits cache) (cache-misses cache))))
    (if (zerop total)
        0.0
        (/ (float (cache-hits cache)) total))))

(defun cache-stats (cache)
  "Return a plist of cache statistics."
  (list :capacity (cache-capacity cache)
        :size (cache-size cache)
        :hits (cache-hits cache)
        :misses (cache-misses cache)
        :evictions (cache-evictions cache)
        :hit-rate (cache-hit-rate cache)))

(defun reset-cache-stats (cache)
  "Reset cache hit/miss/eviction statistics."
  (setf (cache-hits cache) 0
        (cache-misses cache) 0
        (cache-evictions cache) 0))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cache Iteration
;;; ═══════════════════════════════════════════════════════════════════

(defun cache-keys (cache)
  "Return list of all keys in CACHE in LRU order (most recent first)."
  (copy-list (cache-order cache)))

(defun map-cache (function cache)
  "Apply FUNCTION to each (key value) pair in CACHE.
   Iteration order is most recently used to least recently used."
  (dolist (key (cache-order cache))
    (funcall function key (gethash key (cache-table cache)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cache Resizing
;;; ═══════════════════════════════════════════════════════════════════

(defun resize-cache (cache new-capacity)
  "Resize CACHE to NEW-CAPACITY, evicting LRU entries if necessary.
   Returns the number of entries evicted."
  (let ((evicted 0))
    (setf (cache-capacity cache) new-capacity)
    ;; Evict entries if over new capacity
    (loop while (> (cache-size cache) new-capacity)
          do (let ((lru-key (car (last (cache-order cache)))))
               (when lru-key
                 (remhash lru-key (cache-table cache))
                 (setf (cache-order cache) (butlast (cache-order cache)))
                 (incf evicted))))
    evicted))
