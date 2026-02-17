;;;; endpoints.lisp - Conductor HTTP endpoints and system lifecycle
;;;;
;;;; Adds /conductor/status and /conductor/webhook endpoints to the
;;;; existing Hunchentoot monitoring server. Provides unified
;;;; start-system and stop-system for the full Autopoiesis runtime.

(in-package #:autopoiesis.orchestration)

;;; ===================================================================
;;; Conductor HTTP endpoints
;;; ===================================================================

(defun conductor-status-handler ()
  "GET /conductor/status -- return conductor metrics as JSON."
  (if *conductor*
      (autopoiesis.monitoring::json-response (conductor-status))
      (autopoiesis.monitoring::json-response
       '(:status "stopped") :status 503)))

(defun conductor-webhook-handler ()
  "POST /conductor/webhook -- accept events."
  (let ((body (hunchentoot:raw-post-data :force-text t)))
    (handler-case
        (let ((json (cl-json:decode-json-from-string body)))
          (queue-event (or (cdr (assoc :type json)) :unknown) json)
          (autopoiesis.monitoring::json-response '(:status "accepted")))
      (error ()
        (autopoiesis.monitoring::json-response
         '(:error "invalid_json") :status 400)))))

(defun register-conductor-endpoints ()
  "Add conductor endpoints to the running Hunchentoot dispatch table."
  (push (hunchentoot:create-prefix-dispatcher
         "/conductor/webhook" #'conductor-webhook-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-prefix-dispatcher
         "/conductor/status" #'conductor-status-handler)
        hunchentoot:*dispatch-table*)
  t)

;;; ===================================================================
;;; System lifecycle
;;; ===================================================================

(defun start-system (&key (monitoring-port 8081) (start-conductor t))
  "Start the full Autopoiesis system: substrate + monitoring + conductor.
   Returns T on success."
  ;; Open substrate store if not already open
  (unless autopoiesis.substrate:*store*
    (autopoiesis.substrate:open-store))
  ;; Start monitoring server
  (handler-case
      (autopoiesis.monitoring:start-monitoring-server :port monitoring-port)
    (error (e)
      (format *error-output* "~&Warning: monitoring server: ~A~%" e)))
  ;; Register conductor endpoints
  (register-conductor-endpoints)
  ;; Start conductor
  (when start-conductor
    (start-conductor))
  (format t "~&Autopoiesis system started.~%")
  (format t "  Monitoring: http://localhost:~D~%" monitoring-port)
  (format t "  Conductor: ~A~%" (if start-conductor "running" "stopped"))
  t)

(defun stop-system ()
  "Stop the full Autopoiesis system: conductor + monitoring + substrate."
  ;; Stop conductor
  (when *conductor*
    (stop-conductor))
  ;; Stop monitoring server
  (handler-case
      (autopoiesis.monitoring:stop-monitoring-server)
    (error (e)
      (format *error-output* "~&Warning: monitoring server: ~A~%" e)))
  ;; Close substrate store
  (when autopoiesis.substrate:*store*
    (autopoiesis.substrate:close-store))
  (format t "~&Autopoiesis system stopped.~%")
  t)
