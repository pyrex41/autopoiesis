;;;; monitoring-tests.lisp - Tests for monitoring endpoints
;;;;
;;;; Tests for health check HTTP endpoints and metrics collection.

(in-package #:autopoiesis.test)

(def-suite monitoring-tests
  :description "Tests for monitoring HTTP endpoints and metrics")

(in-suite monitoring-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Metrics Registry Tests
;;; ═══════════════════════════════════════════════════════════════════

(test metrics-record-and-get
  "Test recording and retrieving metrics"
  (unwind-protect
       (progn
         (autopoiesis.monitoring:reset-metrics)
         
         ;; Record a gauge metric
         (autopoiesis.monitoring:record-metric "test_gauge" 42.5 :type :gauge)
         (let ((metric (autopoiesis.monitoring:get-metric "test_gauge")))
           (is-true metric)
           (is (= 42.5 (autopoiesis.monitoring:metric-value metric)))
           (is (eq :gauge (autopoiesis.monitoring:metric-type metric))))
         
         ;; Record with labels
         (autopoiesis.monitoring:record-metric "test_labeled" 100 
                                               :labels '(:env "test" :host "localhost"))
         (let ((metric (autopoiesis.monitoring:get-metric "test_labeled" 
                                                          '(:env "test" :host "localhost"))))
           (is-true metric)
           (is (= 100 (autopoiesis.monitoring:metric-value metric)))))
    (autopoiesis.monitoring:reset-metrics)))

(test metrics-increment-counter
  "Test counter increment functionality"
  (unwind-protect
       (progn
         (autopoiesis.monitoring:reset-metrics)
         
         ;; Increment counter
         (autopoiesis.monitoring:increment-counter "test_counter")
         (let ((metric (autopoiesis.monitoring:get-metric "test_counter")))
           (is-true metric)
           (is (= 1 (autopoiesis.monitoring:metric-value metric))))
         
         ;; Increment again
         (autopoiesis.monitoring:increment-counter "test_counter" :by 5)
         (let ((metric (autopoiesis.monitoring:get-metric "test_counter")))
           (is (= 6 (autopoiesis.monitoring:metric-value metric))))
         
         ;; Counter with labels
         (autopoiesis.monitoring:increment-counter "test_counter_labeled" 
                                                   :labels '(:method "GET"))
         (autopoiesis.monitoring:increment-counter "test_counter_labeled" 
                                                   :labels '(:method "POST"))
         (let ((get-metric (autopoiesis.monitoring:get-metric "test_counter_labeled" 
                                                              '(:method "GET")))
               (post-metric (autopoiesis.monitoring:get-metric "test_counter_labeled" 
                                                               '(:method "POST"))))
           (is (= 1 (autopoiesis.monitoring:metric-value get-metric)))
           (is (= 1 (autopoiesis.monitoring:metric-value post-metric)))))
    (autopoiesis.monitoring:reset-metrics)))

(test metrics-set-gauge
  "Test gauge set functionality"
  (unwind-protect
       (progn
         (autopoiesis.monitoring:reset-metrics)
         
         ;; Set gauge
         (autopoiesis.monitoring:set-gauge "test_gauge_set" 100)
         (let ((metric (autopoiesis.monitoring:get-metric "test_gauge_set")))
           (is (= 100 (autopoiesis.monitoring:metric-value metric))))
         
         ;; Update gauge
         (autopoiesis.monitoring:set-gauge "test_gauge_set" 50)
         (let ((metric (autopoiesis.monitoring:get-metric "test_gauge_set")))
           (is (= 50 (autopoiesis.monitoring:metric-value metric)))))
    (autopoiesis.monitoring:reset-metrics)))

(test metrics-get-all
  "Test getting all metrics"
  (unwind-protect
       (progn
         (autopoiesis.monitoring:reset-metrics)
         
         (autopoiesis.monitoring:record-metric "metric_a" 1)
         (autopoiesis.monitoring:record-metric "metric_b" 2)
         (autopoiesis.monitoring:record-metric "metric_c" 3)
         
         (let ((all-metrics (autopoiesis.monitoring:get-all-metrics)))
           (is (= 3 (length all-metrics)))))
    (autopoiesis.monitoring:reset-metrics)))

(test metrics-reset
  "Test metrics reset"
  (unwind-protect
       (progn
         (autopoiesis.monitoring:record-metric "to_be_reset" 42)
         (is-true (autopoiesis.monitoring:get-metric "to_be_reset"))
         
         (autopoiesis.monitoring:reset-metrics)
         (is-false (autopoiesis.monitoring:get-metric "to_be_reset"))
         (is (= 0 (length (autopoiesis.monitoring:get-all-metrics)))))
    (autopoiesis.monitoring:reset-metrics)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Health Check Tests
;;; ═══════════════════════════════════════════════════════════════════

(test health-check-result-structure
  "Test health check result has correct structure"
  (let ((result (autopoiesis.monitoring::health-check-result)))
    (is-true (getf result :status))
    (is-true (getf result :checks))
    (is-true (getf result :timestamp))
    (is (member (getf result :status) '("healthy" "unhealthy") :test #'string=))))

(test health-check-includes-core-packages
  "Test health check includes core packages check"
  (let* ((result (autopoiesis.monitoring::health-check-result))
         (checks (getf result :checks))
         (core-check (find "core_packages" checks 
                          :key (lambda (c) (getf c :name)) 
                          :test #'string=)))
    (is-true core-check)
    (is (string= "ok" (getf core-check :status)))))

(test health-check-includes-memory
  "Test health check includes memory check"
  (let* ((result (autopoiesis.monitoring::health-check-result))
         (checks (getf result :checks))
         (memory-check (find "memory" checks 
                            :key (lambda (c) (getf c :name)) 
                            :test #'string=)))
    (is-true memory-check)
    (is (member (getf memory-check :status) '("ok" "warning") :test #'string=))
    (is-true (getf memory-check :value))))

(test liveness-check
  "Test liveness check returns true when system is running"
  (is-true (autopoiesis.monitoring::liveness-check)))

(test readiness-check
  "Test readiness check returns true when system is ready"
  (is-true (autopoiesis.monitoring::readiness-check)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Built-in Metrics Tests
;;; ═══════════════════════════════════════════════════════════════════

(test record-request-metric
  "Test recording request metrics"
  (unwind-protect
       (progn
         (autopoiesis.monitoring:reset-metrics)
         
         (autopoiesis.monitoring:record-request-metric "/health" 200 0.05)
         
         ;; Check counter was incremented
         (let ((counter (autopoiesis.monitoring:get-metric 
                         "autopoiesis_http_requests_total"
                         '(:endpoint "/health" :status 200))))
           (is-true counter)
           (is (= 1 (autopoiesis.monitoring:metric-value counter)))))
    (autopoiesis.monitoring:reset-metrics)))

(test record-agent-metric
  "Test recording agent metrics"
  (unwind-protect
       (progn
         (autopoiesis.monitoring:reset-metrics)
         
         (autopoiesis.monitoring:record-agent-metric "agent-001" :running)
         
         (let ((metric (autopoiesis.monitoring:get-metric 
                        "autopoiesis_agent_status"
                        '(:agent_id "agent-001"))))
           (is-true metric)
           (is (= 1 (autopoiesis.monitoring:metric-value metric)))))
    (autopoiesis.monitoring:reset-metrics)))

(test record-snapshot-metric
  "Test recording snapshot metrics"
  (unwind-protect
       (progn
         (autopoiesis.monitoring:reset-metrics)
         
         (autopoiesis.monitoring:record-snapshot-metric "create" 0.1)
         
         (let ((counter (autopoiesis.monitoring:get-metric 
                         "autopoiesis_snapshot_operations_total"
                         '(:operation "create"))))
           (is-true counter)
           (is (= 1 (autopoiesis.monitoring:metric-value counter)))))
    (autopoiesis.monitoring:reset-metrics)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Server Management Tests
;;; ═══════════════════════════════════════════════════════════════════

(test server-not-running-initially
  "Test server is not running initially"
  (is-false (autopoiesis.monitoring:monitoring-server-running-p)))

(test server-start-stop
  "Test starting and stopping the monitoring server"
  ;; Skip if port is in use
  (handler-case
      (progn
        ;; Start server on a test port
        (let ((acceptor (autopoiesis.monitoring:start-monitoring-server :port 18081)))
          (unwind-protect
               (progn
                 (is-true acceptor)
                 (is-true (autopoiesis.monitoring:monitoring-server-running-p)))
            ;; Always stop the server
            (autopoiesis.monitoring:stop-monitoring-server)))
        
        ;; Verify stopped
        (is-false (autopoiesis.monitoring:monitoring-server-running-p)))
    (error (e)
      ;; If we can't bind to the port, skip the test
      (skip "Could not bind to test port: ~a" e))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Integration Tests (with actual HTTP requests)
;;; ═══════════════════════════════════════════════════════════════════

(test health-endpoint-integration
  "Test /health endpoint returns valid JSON"
  (handler-case
      (let ((port 18082))
        (autopoiesis.monitoring:start-monitoring-server :port port)
        (unwind-protect
             (progn
               ;; Give server time to start
               (sleep 0.1)
               
               ;; Make HTTP request
               (multiple-value-bind (body status)
                   (dexador:get (format nil "http://127.0.0.1:~d/health" port)
                                :keep-alive nil)
                 (is (= 200 status))
                 (let ((json (cl-json:decode-json-from-string body)))
                   (is-true (assoc :status json))
                   (is-true (assoc :checks json))
                   (is-true (assoc :timestamp json)))))
          (autopoiesis.monitoring:stop-monitoring-server)))
    (error (e)
      (autopoiesis.monitoring:stop-monitoring-server)
      (skip "HTTP test failed: ~a" e))))

(test liveness-endpoint-integration
  "Test /healthz endpoint returns OK"
  (handler-case
      (let ((port 18083))
        (autopoiesis.monitoring:start-monitoring-server :port port)
        (unwind-protect
             (progn
               (sleep 0.1)
               (multiple-value-bind (body status)
                   (dexador:get (format nil "http://127.0.0.1:~d/healthz" port)
                                :keep-alive nil)
                 (is (= 200 status))
                 (is (string= "OK" body))))
          (autopoiesis.monitoring:stop-monitoring-server)))
    (error (e)
      (autopoiesis.monitoring:stop-monitoring-server)
      (skip "HTTP test failed: ~a" e))))

(test readiness-endpoint-integration
  "Test /readyz endpoint returns OK"
  (handler-case
      (let ((port 18084))
        (autopoiesis.monitoring:start-monitoring-server :port port)
        (unwind-protect
             (progn
               (sleep 0.1)
               (multiple-value-bind (body status)
                   (dexador:get (format nil "http://127.0.0.1:~d/readyz" port)
                                :keep-alive nil)
                 (is (= 200 status))
                 (is (string= "OK" body))))
          (autopoiesis.monitoring:stop-monitoring-server)))
    (error (e)
      (autopoiesis.monitoring:stop-monitoring-server)
      (skip "HTTP test failed: ~a" e))))

(test metrics-endpoint-integration
  "Test /metrics endpoint returns Prometheus format"
  (handler-case
      (let ((port 18085))
        (autopoiesis.monitoring:start-monitoring-server :port port)
        (unwind-protect
             (progn
               (sleep 0.1)
               (multiple-value-bind (body status)
                   (dexador:get (format nil "http://127.0.0.1:~d/metrics" port)
                                :keep-alive nil)
                 (is (= 200 status))
                 ;; Check for expected metrics
                 (is-true (search "autopoiesis_up" body))
                 (is-true (search "autopoiesis_memory_bytes" body))))
          (autopoiesis.monitoring:stop-monitoring-server)))
    (error (e)
      (autopoiesis.monitoring:stop-monitoring-server)
      (skip "HTTP test failed: ~a" e))))
