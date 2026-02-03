;;;; packages.lisp - Package definitions for Autopoiesis Monitoring
;;;;
;;;; This file defines the package for HTTP health check endpoints
;;;; and metrics collection.

(in-package #:cl-user)

;;; ═══════════════════════════════════════════════════════════════════
;;; Monitoring Package - HTTP endpoints for health checks and metrics
;;; ═══════════════════════════════════════════════════════════════════

(defpackage #:autopoiesis.monitoring
  (:use #:cl #:alexandria)
  (:export
   ;; Server management
   #:*monitoring-server*
   #:start-monitoring-server
   #:stop-monitoring-server
   #:monitoring-server-running-p

   ;; Health check endpoint
   #:health-endpoint
   #:health-endpoint-handler

   ;; Readiness and liveness probes (Kubernetes-style)
   #:readiness-endpoint
   #:liveness-endpoint

   ;; Metrics endpoint
   #:metrics-endpoint
   #:metrics-endpoint-handler

   ;; Configuration
   #:*monitoring-port*
   #:*monitoring-host*

   ;; Metrics collection
   #:*metrics-registry*
   #:metric
   #:metric-name
   #:metric-type
   #:metric-value
   #:metric-labels
   #:metric-timestamp
   #:record-metric
   #:get-metric
   #:get-all-metrics
   #:reset-metrics
   #:increment-counter
   #:set-gauge
   #:observe-histogram

   ;; Built-in metrics
   #:record-request-metric
   #:record-agent-metric
   #:record-snapshot-metric))
