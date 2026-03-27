;;;; profiling.lisp - Performance profiling and optimization utilities
;;;;
;;;; Provides infrastructure for profiling critical paths:
;;;; - Timing utilities with nanosecond precision
;;;; - Metrics collection and aggregation
;;;; - Hot path identification
;;;; - Optimization hints and caching
;;;;
;;;; Critical paths identified for profiling:
;;;; - S-expression operations (hash, diff, serialize)
;;;; - Snapshot loading and persistence
;;;; - Thought stream operations
;;;; - Cognitive loop execution

(in-package #:autopoiesis.core)

;;; ═══════════════════════════════════════════════════════════════════
;;; Timing Utilities
;;; ═══════════════════════════════════════════════════════════════════

(defvar *profiling-enabled* nil
  "When T, profiling data is collected. When NIL, profiling is a no-op.")

(defvar *profile-metrics* (make-hash-table :test 'equal)
  "Hash table storing profiling metrics by operation name.")

(defvar *profile-metrics-lock* (bordeaux-threads:make-lock "profile-metrics-lock")
  "Lock for thread-safe metrics updates.")

(defstruct profile-metric
  "Aggregated metrics for a profiled operation."
  (name "" :type string)
  (call-count 0 :type fixnum)
  (total-time-ns 0 :type integer)
  (min-time-ns most-positive-fixnum :type integer)
  (max-time-ns 0 :type integer)
  (last-time-ns 0 :type integer))

(defun get-internal-time-ns ()
  "Get current time in nanoseconds using SBCL's high-resolution timer."
  #+sbcl
  (multiple-value-bind (sec nsec) (sb-ext:get-time-of-day)
    (+ (* sec 1000000000) (* nsec 1000)))
  #-sbcl
  (* (get-internal-real-time) 
     (floor 1000000000 internal-time-units-per-second)))

(defmacro with-timing ((name) &body body)
  "Execute BODY and record timing metrics under NAME.
   When *profiling-enabled* is NIL, just executes BODY with no overhead.
   
   Example:
     (with-timing (\"sexpr-hash\")
       (sexpr-hash some-data))"
  (let ((start-var (gensym "START"))
        (result-var (gensym "RESULT"))
        (elapsed-var (gensym "ELAPSED")))
    `(if *profiling-enabled*
         (let ((,start-var (get-internal-time-ns))
               (,result-var nil)
               (,elapsed-var 0))
           (unwind-protect
                (setf ,result-var (progn ,@body))
             (setf ,elapsed-var (- (get-internal-time-ns) ,start-var))
             (record-timing ,name ,elapsed-var))
           ,result-var)
         (progn ,@body))))

(defun record-timing (name elapsed-ns)
  "Record timing data for operation NAME."
  (bordeaux-threads:with-lock-held (*profile-metrics-lock*)
    (let ((metric (gethash name *profile-metrics*)))
      (unless metric
        (setf metric (make-profile-metric :name name))
        (setf (gethash name *profile-metrics*) metric))
      (incf (profile-metric-call-count metric))
      (incf (profile-metric-total-time-ns metric) elapsed-ns)
      (setf (profile-metric-min-time-ns metric)
            (min (profile-metric-min-time-ns metric) elapsed-ns))
      (setf (profile-metric-max-time-ns metric)
            (max (profile-metric-max-time-ns metric) elapsed-ns))
      (setf (profile-metric-last-time-ns metric) elapsed-ns))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Profiling Control
;;; ═══════════════════════════════════════════════════════════════════

(defun enable-profiling ()
  "Enable profiling data collection."
  (setf *profiling-enabled* t))

(defun disable-profiling ()
  "Disable profiling data collection."
  (setf *profiling-enabled* nil))

(defun reset-profiling ()
  "Clear all collected profiling data."
  (bordeaux-threads:with-lock-held (*profile-metrics-lock*)
    (clrhash *profile-metrics*)))

(defmacro with-profiling (&body body)
  "Execute BODY with profiling enabled, then disable.
   
   Example:
     (with-profiling
       (dotimes (i 1000)
         (sexpr-hash test-data))
       (print-profile-report))"
  `(progn
     (enable-profiling)
     (unwind-protect
          (progn ,@body)
       (disable-profiling))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Metrics Reporting
;;; ═══════════════════════════════════════════════════════════════════

(defun ns-to-ms (ns)
  "Convert nanoseconds to milliseconds."
  (/ ns 1000000.0d0))

(defun ns-to-us (ns)
  "Convert nanoseconds to microseconds."
  (/ ns 1000.0d0))

(defun get-profile-metrics ()
  "Return a list of all collected profile metrics."
  (bordeaux-threads:with-lock-held (*profile-metrics-lock*)
    (loop for metric being the hash-values of *profile-metrics*
          collect (copy-profile-metric metric))))

(defun get-profile-metric (name)
  "Return profile metric for NAME, or NIL if not found."
  (bordeaux-threads:with-lock-held (*profile-metrics-lock*)
    (let ((metric (gethash name *profile-metrics*)))
      (when metric
        (copy-profile-metric metric)))))

(defun profile-report ()
  "Generate a profile report as a plist.
   
   Returns:
     (:total-operations N
      :operations ((:name \"op1\" :calls N :total-ms F :avg-us F :min-us F :max-us F) ...))"
  (let ((metrics (get-profile-metrics)))
    (list :total-operations (reduce #'+ metrics :key #'profile-metric-call-count)
          :operations
          (sort
           (mapcar (lambda (m)
                     (let ((count (profile-metric-call-count m))
                           (total (profile-metric-total-time-ns m)))
                       (list :name (profile-metric-name m)
                             :calls count
                             :total-ms (ns-to-ms total)
                             :avg-us (if (zerop count) 0.0d0
                                         (ns-to-us (/ total count)))
                             :min-us (ns-to-us (profile-metric-min-time-ns m))
                             :max-us (ns-to-us (profile-metric-max-time-ns m)))))
                   metrics)
           #'> :key (lambda (op) (getf op :total-ms))))))

(defun print-profile-report (&optional (stream *standard-output*))
  "Print a formatted profile report to STREAM."
  (let ((report (profile-report)))
    (format stream "~&═══════════════════════════════════════════════════════════════~%")
    (format stream "PROFILE REPORT~%")
    (format stream "═══════════════════════════════════════════════════════════════~%")
    (format stream "Total operations: ~:d~%~%" (getf report :total-operations))
    (format stream "~30a ~10a ~12a ~12a ~12a ~12a~%"
            "Operation" "Calls" "Total (ms)" "Avg (μs)" "Min (μs)" "Max (μs)")
    (format stream "~30,,,'-a ~10,,,'-a ~12,,,'-a ~12,,,'-a ~12,,,'-a ~12,,,'-a~%"
            "" "" "" "" "" "")
    (dolist (op (getf report :operations))
      (format stream "~30a ~10:d ~12,3f ~12,3f ~12,3f ~12,3f~%"
              (getf op :name)
              (getf op :calls)
              (getf op :total-ms)
              (getf op :avg-us)
              (getf op :min-us)
              (getf op :max-us)))
    (format stream "═══════════════════════════════════════════════════════════════~%")))

;;; ═══════════════════════════════════════════════════════════════════
;;; Hot Path Identification
;;; ═══════════════════════════════════════════════════════════════════

(defun identify-hot-paths (&key (threshold-ms 100.0) (min-calls 10))
  "Identify operations that are candidates for optimization.
   
   Arguments:
     threshold-ms - Operations with total time > this are flagged (default 100ms)
     min-calls    - Minimum calls to be considered (default 10)
   
   Returns: List of operation names that exceed thresholds."
  (let ((metrics (get-profile-metrics)))
    (mapcar #'profile-metric-name
            (remove-if-not
             (lambda (m)
               (and (>= (profile-metric-call-count m) min-calls)
                    (>= (ns-to-ms (profile-metric-total-time-ns m)) threshold-ms)))
             metrics))))

(defun profile-summary ()
  "Return a brief summary of profiling data.
   
   Returns:
     (:enabled T/NIL
      :operations-tracked N
      :total-calls N
      :total-time-ms F
      :hot-paths (\"op1\" \"op2\" ...))"
  (let ((metrics (get-profile-metrics)))
    (list :enabled *profiling-enabled*
          :operations-tracked (length metrics)
          :total-calls (reduce #'+ metrics :key #'profile-metric-call-count
                               :initial-value 0)
          :total-time-ms (ns-to-ms
                          (reduce #'+ metrics :key #'profile-metric-total-time-ns
                                  :initial-value 0))
          :hot-paths (identify-hot-paths))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Optimized Operations
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; The following optimizations are applied to critical paths:
;;; 1. Memoization for expensive pure functions
;;; 2. Batch processing for repeated operations
;;; 3. Lazy evaluation where appropriate

(defvar *sexpr-hash-cache* nil
  "Optional cache for sexpr-hash results. Set to an LRU cache to enable.")

(defvar *sexpr-hash-cache-hits* 0
  "Counter for sexpr-hash cache hits.")

(defvar *sexpr-hash-cache-misses* 0
  "Counter for sexpr-hash cache misses.")

(defun sexpr-hash-cached (sexpr)
  "Cached version of sexpr-hash using object identity.
   
   When *sexpr-hash-cache* is set to an LRU cache, results are cached
   based on the sexpr's identity (EQ). This is useful when the same
   object is hashed multiple times.
   
   Note: Only effective for identical objects (EQ), not structurally
   equal objects. For structural caching, use content-addressable storage."
  (if *sexpr-hash-cache*
      (let ((identity (sb-kernel:get-lisp-obj-address sexpr)))
        (or (let ((cached (gethash identity *sexpr-hash-cache*)))
              (when cached
                (incf *sexpr-hash-cache-hits*)
                cached))
            (let ((hash (sexpr-hash sexpr)))
              (incf *sexpr-hash-cache-misses*)
              (setf (gethash identity *sexpr-hash-cache*) hash)
              hash)))
      (sexpr-hash sexpr)))

(defun reset-hash-cache-stats ()
  "Reset sexpr-hash cache statistics."
  (setf *sexpr-hash-cache-hits* 0
        *sexpr-hash-cache-misses* 0))

(defun hash-cache-stats ()
  "Return sexpr-hash cache statistics."
  (let ((total (+ *sexpr-hash-cache-hits* *sexpr-hash-cache-misses*)))
    (list :hits *sexpr-hash-cache-hits*
          :misses *sexpr-hash-cache-misses*
          :hit-rate (if (zerop total) 0.0
                        (/ (float *sexpr-hash-cache-hits*) total)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Batch Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun batch-sexpr-hash (sexprs)
  "Compute hashes for multiple S-expressions efficiently.
   
   This batches the hashing operation to reduce per-call overhead
   and allows for potential parallelization.
   
   Arguments:
     sexprs - List of S-expressions to hash
   
   Returns: List of hash strings in same order as input."
  (with-timing ("batch-sexpr-hash")
    (mapcar #'sexpr-hash sexprs)))

(defun batch-sexpr-serialize (sexprs &optional stream)
  "Serialize multiple S-expressions efficiently.
   
   Arguments:
     sexprs - List of S-expressions to serialize
     stream - Optional output stream (if NIL, returns list of strings)
   
   Returns: List of serialized strings, or NIL if stream provided."
  (with-timing ("batch-sexpr-serialize")
    (if stream
        (dolist (sexpr sexprs)
          (sexpr-serialize sexpr stream)
          (terpri stream))
        (mapcar #'sexpr-serialize sexprs))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Performance Benchmarking
;;; ═══════════════════════════════════════════════════════════════════

(defun benchmark (name iterations thunk)
  "Run a benchmark of THUNK for ITERATIONS, recording under NAME.
   
   Arguments:
     name       - Name for the benchmark
     iterations - Number of times to run thunk
     thunk      - Zero-argument function to benchmark
   
   Returns: Plist with benchmark results
     (:name NAME :iterations N :total-ms F :avg-us F :ops-per-sec F)"
  (reset-profiling)
  (enable-profiling)
  (dotimes (i iterations)
    (with-timing (name)
      (funcall thunk)))
  (disable-profiling)
  (let* ((metric (get-profile-metric name))
         (total-ns (profile-metric-total-time-ns metric))
         (total-ms (ns-to-ms total-ns))
         (avg-us (ns-to-us (/ total-ns iterations)))
         (ops-per-sec (if (zerop total-ms) 0.0d0
                          (/ iterations (/ total-ms 1000.0d0)))))
    (list :name name
          :iterations iterations
          :total-ms total-ms
          :avg-us avg-us
          :ops-per-sec ops-per-sec)))

(defun print-benchmark (result &optional (stream *standard-output*))
  "Print benchmark result in readable format."
  (format stream "~&Benchmark: ~a~%" (getf result :name))
  (format stream "  Iterations: ~:d~%" (getf result :iterations))
  (format stream "  Total time: ~,3f ms~%" (getf result :total-ms))
  (format stream "  Avg time:   ~,3f μs~%" (getf result :avg-us))
  (format stream "  Throughput: ~,2f ops/sec~%" (getf result :ops-per-sec)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Memory Profiling
;;; ═══════════════════════════════════════════════════════════════════

(defun memory-usage ()
  "Return current memory usage statistics.
   
   Returns:
     (:dynamic-usage N
      :gc-count N)"
  #+sbcl
  (list :dynamic-usage (sb-kernel:dynamic-usage)
        :gc-count sb-kernel::*gc-epoch*)
  #-sbcl
  (list :dynamic-usage 0 :gc-count 0))

(defmacro with-memory-tracking (&body body)
  "Execute BODY and report memory allocation.
   
   Returns: (values result bytes-consed)"
  #+sbcl
  (let ((before-var (gensym "BEFORE"))
        (result-var (gensym "RESULT"))
        (after-var (gensym "AFTER")))
    `(let ((,before-var (sb-kernel:dynamic-usage))
           (,result-var nil)
           (,after-var 0))
       (setf ,result-var (progn ,@body))
       (setf ,after-var (sb-kernel:dynamic-usage))
       (values ,result-var (- ,after-var ,before-var))))
  #-sbcl
  `(values (progn ,@body) 0))
