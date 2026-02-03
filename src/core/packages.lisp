;;;; packages.lisp - Package definitions for Autopoiesis Core
;;;;
;;;; This file defines the package structure for the core layer.

(in-package #:cl-user)

;;; ═══════════════════════════════════════════════════════════════════
;;; Core Package - S-expression utilities and cognitive primitives
;;; ═══════════════════════════════════════════════════════════════════

(defpackage #:autopoiesis.core
  (:use #:cl #:alexandria)
  (:export
   ;; S-expression utilities
   #:sexpr-equal
   #:sexpr-hash
   #:sexpr-serialize
   #:sexpr-deserialize
   #:sexpr-diff
   #:sexpr-patch
   #:sexpr-edit
   #:make-edit

   ;; Cognitive primitives
   #:thought
   #:thought-id
   #:thought-timestamp
   #:thought-content
   #:thought-type
   #:thought-confidence
   #:thought-provenance
   #:make-thought
   #:thought-to-sexpr
   #:sexpr-to-thought

   ;; Decision
   #:decision
   #:decision-alternatives
   #:decision-chosen
   #:decision-rationale
   #:make-decision
   #:decision-unchosen

   ;; Action
   #:action
   #:action-capability
   #:action-arguments
   #:action-result
   #:action-side-effects
   #:make-action

   ;; Observation
   #:observation
   #:observation-source
   #:observation-raw
   #:observation-interpreted
   #:make-observation

   ;; Reflection
   #:reflection
   #:reflection-target
   #:reflection-insight
   #:reflection-modification
   #:make-reflection

   ;; Thought stream
   #:thought-stream
   #:make-thought-stream
   #:stream-thoughts
   #:stream-append
   #:stream-find
   #:stream-length
   #:stream-last
   #:stream-range
   #:stream-since
   #:stream-by-type
   #:stream-to-sexpr
   #:sexpr-to-stream
   ;; Thought stream compaction
   #:compact-thought-stream
   #:archive-thoughts
   #:load-archived-thoughts
   #:*thought-archive-path*

   ;; Conditions
   #:autopoiesis-condition
   #:autopoiesis-error
   #:autopoiesis-warning
   #:condition-message
   
   ;; Recovery conditions
   #:recoverable-error
   #:transient-error
   #:resource-error
   #:state-inconsistency-error
   #:error-operation
   #:error-recoverable-p
   #:error-recovery-hints
   #:error-retry-count
   #:error-max-retries
   #:error-resource
   #:error-resource-type
   #:error-expected-state
   #:error-actual-state
   
   ;; Recovery strategies
   #:recovery-strategy
   #:strategy-name
   #:strategy-description
   #:strategy-priority
   #:register-recovery-strategy
   #:find-recovery-strategies
   #:define-recovery-strategy
   #:*recovery-strategies*
   
   ;; Recovery restarts and macros
   #:establish-recovery-restarts
   #:with-recovery
   #:with-retry
   #:with-operation-recovery
   #:retry-with-backoff
   #:exponential-backoff-delay
   
   ;; Graceful degradation
   #:degradation-level
   #:degradation-name
   #:degradation-description
   #:degradation-capabilities
   #:degradation-restrictions
   #:define-degradation-level
   #:enter-degraded-mode
   #:exit-degraded-mode
   #:degraded-p
   #:capability-available-p
   #:with-graceful-degradation
   #:*current-degradation-level*
   #:*degradation-levels*
   
   ;; Recovery logging
   #:recovery-event
   #:recovery-event-timestamp
   #:recovery-event-operation
   #:recovery-event-error-type
   #:recovery-event-error-message
   #:recovery-event-strategy-used
   #:recovery-event-outcome
   #:log-recovery-event
   #:get-recovery-log
   #:clear-recovery-log
   #:*recovery-log*

   ;; Extension compiler
   #:extension
   #:extension-name
   #:extension-id
   #:extension-source
   #:extension-compiled
   #:extension-author
   #:extension-created
   #:extension-dependencies
   #:extension-provides
   #:extension-sandbox-level
   #:extension-invocations
   #:extension-errors
   #:extension-status
   #:compile-extension
   #:install-extension
   #:uninstall-extension
   #:find-extension
   #:list-extensions
   #:execute-extension
   #:register-extension
   #:invoke-extension
   #:clear-extension-registry
   #:*extension-registry*
   #:validate-extension-code
   #:validate-extension-source
   ;; Sandbox configuration
   #:*allowed-packages*
   #:*forbidden-symbols*
   #:*allowed-special-forms*
   #:*sandbox-allowed-symbols*
   #:*sandbox-forbidden-patterns*

   ;; Utilities
   #:make-uuid
   #:get-precise-time
   #:truncate-string
   #:sexpr-size

   ;; Profiling
   #:*profiling-enabled*
   #:profile-metric
   #:profile-metric-name
   #:profile-metric-call-count
   #:profile-metric-total-time-ns
   #:profile-metric-min-time-ns
   #:profile-metric-max-time-ns
   #:profile-metric-last-time-ns
   #:with-timing
   #:enable-profiling
   #:disable-profiling
   #:reset-profiling
   #:with-profiling
   #:get-profile-metrics
   #:get-profile-metric
   #:profile-report
   #:print-profile-report
   #:identify-hot-paths
   #:profile-summary
   ;; Optimized operations
   #:*sexpr-hash-cache*
   #:sexpr-hash-cached
   #:reset-hash-cache-stats
   #:hash-cache-stats
   #:batch-sexpr-hash
   #:batch-sexpr-serialize
   ;; Benchmarking
   #:benchmark
   #:print-benchmark
   ;; Memory profiling
   #:memory-usage
   #:with-memory-tracking))
