;;;; endpoints.lisp - HTTP health check and metrics endpoints
;;;;
;;;; Provides HTTP endpoints for monitoring Autopoiesis:
;;;; - /health - Full health check with component status
;;;; - /healthz - Simple liveness probe (Kubernetes-style)
;;;; - /readyz - Readiness probe (Kubernetes-style)
;;;; - /metrics - Prometheus-compatible metrics

(in-package #:autopoiesis.monitoring)

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration
;;; ═══════════════════════════════════════════════════════════════════

(defvar *monitoring-port* 8081
  "Port for the monitoring HTTP server.
   Default is 8081 to avoid conflict with main application port.")

(defvar *monitoring-host* "0.0.0.0"
  "Host to bind the monitoring server to.")

(defvar *monitoring-server* nil
  "The running Hunchentoot acceptor for monitoring endpoints.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Metrics Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *metrics-registry* (make-hash-table :test 'equal)
  "Registry of all collected metrics.")

(defvar *metrics-lock* (bordeaux-threads:make-lock "metrics-lock")
  "Lock for thread-safe metrics updates.")

(defclass metric ()
  ((name :initarg :name
         :accessor metric-name
         :documentation "Metric name (e.g., 'autopoiesis_requests_total')")
   (type :initarg :type
         :accessor metric-type
         :initform :gauge
         :documentation "Metric type: :counter, :gauge, or :histogram")
   (value :initarg :value
          :accessor metric-value
          :initform 0
          :documentation "Current metric value")
   (labels :initarg :labels
           :accessor metric-labels
           :initform nil
           :documentation "Plist of label key-value pairs")
   (help :initarg :help
         :accessor metric-help
         :initform ""
         :documentation "Help text describing the metric")
   (timestamp :initarg :timestamp
              :accessor metric-timestamp
              :initform (get-universal-time)
              :documentation "Last update timestamp")
   ;; Histogram-specific fields
   (buckets :initarg :buckets
            :accessor metric-buckets
            :initform nil
            :documentation "Histogram bucket counts")
   (sum :initarg :sum
        :accessor metric-sum
        :initform 0
        :documentation "Sum of all observed values (histogram)")
   (count :initarg :count
          :accessor metric-count
          :initform 0
          :documentation "Count of observations (histogram)"))
  (:documentation "A single metric with optional labels."))

(defun make-metric-key (name labels)
  "Create a unique key for a metric with labels."
  (if labels
      (format nil "~a{~{~a=~s~^,~}}" name labels)
      name))

(defun record-metric (name value &key (type :gauge) (labels nil) (help ""))
  "Record a metric value.
   
   Arguments:
     name   - Metric name (string)
     value  - Metric value (number)
     type   - :counter, :gauge, or :histogram
     labels - Plist of label key-value pairs
     help   - Help text for the metric"
  (bordeaux-threads:with-lock-held (*metrics-lock*)
    (let* ((key (make-metric-key name labels))
           (metric (gethash key *metrics-registry*)))
      (if metric
          (progn
            (setf (metric-value metric) value)
            (setf (metric-timestamp metric) (get-universal-time)))
          (setf (gethash key *metrics-registry*)
                (make-instance 'metric
                               :name name
                               :type type
                               :value value
                               :labels labels
                               :help help)))
      value)))

(defun get-metric (name &optional labels)
  "Get a metric by name and optional labels."
  (bordeaux-threads:with-lock-held (*metrics-lock*)
    (gethash (make-metric-key name labels) *metrics-registry*)))

(defun get-all-metrics ()
  "Return a list of all metrics."
  (bordeaux-threads:with-lock-held (*metrics-lock*)
    (loop for metric being the hash-values of *metrics-registry*
          collect metric)))

(defun reset-metrics ()
  "Clear all metrics."
  (bordeaux-threads:with-lock-held (*metrics-lock*)
    (clrhash *metrics-registry*)))

(defun increment-counter (name &key (by 1) (labels nil) (help ""))
  "Increment a counter metric."
  (bordeaux-threads:with-lock-held (*metrics-lock*)
    (let* ((key (make-metric-key name labels))
           (metric (gethash key *metrics-registry*)))
      (if metric
          (progn
            (incf (metric-value metric) by)
            (setf (metric-timestamp metric) (get-universal-time)))
          (setf (gethash key *metrics-registry*)
                (make-instance 'metric
                               :name name
                               :type :counter
                               :value by
                               :labels labels
                               :help help)))
      (metric-value (gethash key *metrics-registry*)))))

(defun set-gauge (name value &key (labels nil) (help ""))
  "Set a gauge metric to a specific value."
  (record-metric name value :type :gauge :labels labels :help help))

(defun observe-histogram (name value &key (labels nil) (help "") 
                                       (buckets '(0.005 0.01 0.025 0.05 0.1 0.25 0.5 1 2.5 5 10)))
  "Observe a value for a histogram metric."
  (bordeaux-threads:with-lock-held (*metrics-lock*)
    (let* ((key (make-metric-key name labels))
           (metric (gethash key *metrics-registry*)))
      (if metric
          (progn
            ;; Update histogram
            (incf (metric-count metric))
            (incf (metric-sum metric) value)
            ;; Update buckets
            (let ((bucket-counts (or (metric-buckets metric)
                                     (make-list (length buckets) :initial-element 0))))
              (loop for bucket in buckets
                    for i from 0
                    when (<= value bucket)
                      do (incf (nth i bucket-counts)))
              (setf (metric-buckets metric) bucket-counts))
            (setf (metric-timestamp metric) (get-universal-time)))
          ;; Create new histogram metric
          (let ((bucket-counts (make-list (length buckets) :initial-element 0)))
            (loop for bucket in buckets
                  for i from 0
                  when (<= value bucket)
                    do (incf (nth i bucket-counts)))
            (setf (gethash key *metrics-registry*)
                  (make-instance 'metric
                                 :name name
                                 :type :histogram
                                 :value value
                                 :labels labels
                                 :help help
                                 :buckets bucket-counts
                                 :sum value
                                 :count 1))))
      value)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Built-in Metrics
;;; ═══════════════════════════════════════════════════════════════════

(defun record-request-metric (endpoint status duration)
  "Record metrics for an HTTP request."
  (increment-counter "autopoiesis_http_requests_total"
                     :labels (list :endpoint endpoint :status status)
                     :help "Total HTTP requests")
  (observe-histogram "autopoiesis_http_request_duration_seconds"
                     duration
                     :labels (list :endpoint endpoint)
                     :help "HTTP request duration in seconds"))

(defun record-agent-metric (agent-id status)
  "Record metrics for agent activity."
  (set-gauge "autopoiesis_agent_status"
             (case status
               (:running 1)
               (:paused 0.5)
               (:stopped 0)
               (t 0))
             :labels (list :agent_id agent-id)
             :help "Agent status (1=running, 0.5=paused, 0=stopped)"))

(defun record-snapshot-metric (operation duration)
  "Record metrics for snapshot operations."
  (increment-counter "autopoiesis_snapshot_operations_total"
                     :labels (list :operation operation)
                     :help "Total snapshot operations")
  (observe-histogram "autopoiesis_snapshot_operation_duration_seconds"
                     duration
                     :labels (list :operation operation)
                     :help "Snapshot operation duration in seconds"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Health Check Handlers
;;; ═══════════════════════════════════════════════════════════════════

(defun health-check-result ()
  "Get the full health check result.
   Returns a plist with status and component checks."
  (let ((checks nil)
        (all-ok t))
    
    ;; Check core packages
    (let ((core-ok (and (find-package :autopoiesis.core)
                        (find-package :autopoiesis.agent)
                        (find-package :autopoiesis.snapshot))))
      (push (list :name "core_packages" 
                  :status (if core-ok "ok" "error")
                  :message (if core-ok "All core packages loaded" "Missing core packages"))
            checks)
      (unless core-ok (setf all-ok nil)))
    
    ;; Check key functions
    (let ((fns-ok (and (fboundp 'autopoiesis.core:sexpr-equal)
                       (fboundp 'autopoiesis.agent:make-agent)
                       (fboundp 'autopoiesis.snapshot:make-snapshot))))
      (push (list :name "core_functions"
                  :status (if fns-ok "ok" "error")
                  :message (if fns-ok "Core functions available" "Missing core functions"))
            checks)
      (unless fns-ok (setf all-ok nil)))
    
    ;; Check memory usage
    (let* ((usage (sb-kernel:dynamic-usage))
           (usage-mb (/ usage 1024 1024))
           (memory-ok (< usage (* 1024 1024 1024))))  ; 1GB threshold
      (push (list :name "memory"
                  :status (if memory-ok "ok" "warning")
                  :message (format nil "~,2f MB used" usage-mb)
                  :value usage-mb)
            checks))
    
    ;; Check component health if available
    (when (and (find-package :autopoiesis.core)
               (fboundp 'autopoiesis.core:check-all-component-health))
      (let ((component-results (funcall 'autopoiesis.core:check-all-component-health)))
        (loop for (name status) on component-results by #'cddr
              do (let ((ok (eq status :healthy)))
                   (push (list :name (string-downcase (string name))
                               :status (if ok "ok" "error")
                               :message (string status))
                         checks)
                   (unless ok (setf all-ok nil))))))
    
    (list :status (if all-ok "healthy" "unhealthy")
          :checks (nreverse checks)
          :timestamp (get-universal-time))))

(defun liveness-check ()
  "Simple liveness check - just verifies the system is running.
   Returns T if alive, NIL otherwise."
  (and (find-package :autopoiesis.core)
       (fboundp 'autopoiesis.core:sexpr-equal)))

(defun readiness-check ()
  "Readiness check - verifies the system is ready to handle requests.
   Returns T if ready, NIL otherwise."
  (and (liveness-check)
       ;; Add additional readiness checks here
       ;; e.g., database connection, Claude API availability
       t))

;;; ═══════════════════════════════════════════════════════════════════
;;; HTTP Response Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun plist-to-alist (plist)
  "Convert a plist to an alist for JSON encoding."
  (loop for (key value) on plist by #'cddr
        collect (cons key 
                      (cond
                        ;; Recursively convert nested plists
                        ((and (listp value) 
                              (keywordp (first value))
                              (evenp (length value)))
                         (plist-to-alist value))
                        ;; Convert list of plists
                        ((and (listp value)
                              (listp (first value))
                              (keywordp (first (first value))))
                         (mapcar #'plist-to-alist value))
                        (t value)))))

(defun json-response (data &key (status 200))
  "Create a JSON HTTP response."
  (setf (hunchentoot:content-type*) "application/json")
  (setf (hunchentoot:return-code*) status)
  ;; Convert plist to alist for proper JSON object encoding
  (cl-json:encode-json-to-string (plist-to-alist data)))

(defun text-response (text &key (status 200))
  "Create a plain text HTTP response."
  (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
  (setf (hunchentoot:return-code*) status)
  text)

;;; ═══════════════════════════════════════════════════════════════════
;;; HTTP Endpoint Handlers
;;; ═══════════════════════════════════════════════════════════════════

(defun health-endpoint-handler ()
  "Handler for /health endpoint.
   Returns full health check as JSON."
  (let* ((result (health-check-result))
         (status (if (string= (getf result :status) "healthy") 200 503)))
    (json-response result :status status)))

(defun liveness-endpoint-handler ()
  "Handler for /healthz endpoint (Kubernetes liveness probe).
   Returns 200 OK if alive, 503 otherwise."
  (if (liveness-check)
      (text-response "OK" :status 200)
      (text-response "NOT OK" :status 503)))

(defun readiness-endpoint-handler ()
  "Handler for /readyz endpoint (Kubernetes readiness probe).
   Returns 200 OK if ready, 503 otherwise."
  (if (readiness-check)
      (text-response "OK" :status 200)
      (text-response "NOT OK" :status 503)))

(defun metrics-endpoint-handler ()
  "Handler for /metrics endpoint.
   Returns metrics in Prometheus exposition format."
  (setf (hunchentoot:content-type*) "text/plain; version=0.0.4; charset=utf-8")
  (with-output-to-string (out)
    ;; Add standard metrics
    (format out "# HELP autopoiesis_up Whether Autopoiesis is up~%")
    (format out "# TYPE autopoiesis_up gauge~%")
    (format out "autopoiesis_up 1~%~%")
    
    ;; Add memory metrics
    (let ((usage-bytes (sb-kernel:dynamic-usage)))
      (format out "# HELP autopoiesis_memory_bytes Memory usage in bytes~%")
      (format out "# TYPE autopoiesis_memory_bytes gauge~%")
      (format out "autopoiesis_memory_bytes ~d~%~%" usage-bytes))
    
    ;; Add custom metrics from registry
    (let ((metrics (get-all-metrics))
          (seen-names (make-hash-table :test 'equal)))
      (dolist (metric metrics)
        (let ((name (metric-name metric)))
          ;; Output HELP and TYPE only once per metric name
          (unless (gethash name seen-names)
            (setf (gethash name seen-names) t)
            (when (metric-help metric)
              (format out "# HELP ~a ~a~%" name (metric-help metric)))
            (format out "# TYPE ~a ~a~%" name 
                    (string-downcase (string (metric-type metric)))))
          
          ;; Output metric value with labels
          (if (metric-labels metric)
              (format out "~a{~{~a=\"~a\"~^,~}} ~a~%"
                      name
                      (loop for (k v) on (metric-labels metric) by #'cddr
                            collect (string-downcase (string k))
                            collect v)
                      (metric-value metric))
              (format out "~a ~a~%" name (metric-value metric))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Server Management
;;; ═══════════════════════════════════════════════════════════════════

(defun create-monitoring-dispatcher ()
  "Create the URL dispatcher for monitoring endpoints.
   Order matters - more specific paths must come first."
  (list
   ;; More specific paths first to avoid prefix matching issues
   (hunchentoot:create-prefix-dispatcher "/healthz" #'liveness-endpoint-handler)
   (hunchentoot:create-prefix-dispatcher "/readyz" #'readiness-endpoint-handler)
   (hunchentoot:create-prefix-dispatcher "/metrics" #'metrics-endpoint-handler)
   ;; /health last since it's a prefix of /healthz
   (hunchentoot:create-prefix-dispatcher "/health" #'health-endpoint-handler)))

(defvar *monitoring-dispatch-table* nil
  "Saved dispatch table for monitoring endpoints.")

(defvar *previous-dispatch-table* nil
  "Saved previous dispatch table to restore on stop.")

(defun start-monitoring-server (&key (port *monitoring-port*) (host *monitoring-host*))
  "Start the monitoring HTTP server.
   
   Arguments:
     port - Port to listen on (default *monitoring-port*)
     host - Host to bind to (default *monitoring-host*)
   
   Returns: The Hunchentoot acceptor"
  (when *monitoring-server*
    (warn "Monitoring server already running. Stopping existing server.")
    (stop-monitoring-server))
  
  (let ((acceptor (make-instance 'hunchentoot:easy-acceptor
                                 :port port
                                 :address host
                                 :name "autopoiesis-monitoring")))
    ;; Save current dispatch table and set up monitoring dispatchers
    (setf *previous-dispatch-table* hunchentoot:*dispatch-table*)
    (setf *monitoring-dispatch-table* (create-monitoring-dispatcher))
    (setf hunchentoot:*dispatch-table* 
          (append *monitoring-dispatch-table* *previous-dispatch-table*))
    
    ;; Start the server
    (hunchentoot:start acceptor)
    (setf *monitoring-server* acceptor)
    
    (format t "~&Monitoring server started on ~a:~d~%" host port)
    (format t "  /health  - Full health check (JSON)~%")
    (format t "  /healthz - Liveness probe~%")
    (format t "  /readyz  - Readiness probe~%")
    (format t "  /metrics - Prometheus metrics~%")
    
    acceptor))

(defun stop-monitoring-server ()
  "Stop the monitoring HTTP server."
  (when *monitoring-server*
    (hunchentoot:stop *monitoring-server*)
    (setf *monitoring-server* nil)
    ;; Restore previous dispatch table
    (when *previous-dispatch-table*
      (setf hunchentoot:*dispatch-table* *previous-dispatch-table*)
      (setf *previous-dispatch-table* nil))
    (setf *monitoring-dispatch-table* nil)
    (format t "~&Monitoring server stopped.~%")
    t))

(defun monitoring-server-running-p ()
  "Check if the monitoring server is running."
  (and *monitoring-server*
       (hunchentoot:started-p *monitoring-server*)))
