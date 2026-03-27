;;;; packages.lisp - Crystallization engine package definitions
;;;;
;;;; Defines package for emitting live runtime changes as .lisp source,
;;;; stored in the snapshot DAG with Git export on demand.

(in-package #:cl-user)

(defpackage #:autopoiesis.crystallize
  (:use #:cl #:alexandria #:autopoiesis.core)
  (:export
    ;; Core emitter
    #:emit-to-file

    ;; Crystallizers
    #:crystallize-capabilities
    #:crystallize-heuristics
    #:crystallize-genome
    #:crystallize-genomes

    ;; Snapshot integration
    #:store-crystallized-snapshot
    #:crystallize-all

    ;; ASDF fragment
    #:emit-asdf-fragment

    ;; Git export
    #:export-to-git

    ;; Trigger conditions
    #:trigger-condition
    #:trigger-condition-id
    #:trigger-condition-enabled
    #:trigger-condition-name
    #:trigger-condition-description
    #:trigger-condition-last-triggered
    #:performance-threshold-trigger
    #:performance-threshold-trigger-metric-type
    #:performance-threshold-trigger-threshold
    #:performance-threshold-trigger-comparison
    #:performance-threshold-trigger-agent-id
    #:performance-threshold-trigger-cooldown-seconds
    #:scheduled-interval-trigger
    #:scheduled-interval-trigger-interval-seconds
    #:scheduled-interval-trigger-next-trigger-time
    #:register-trigger
    #:unregister-trigger
    #:get-trigger
    #:list-triggers
    #:clear-triggers
    #:check-all-triggers
    #:create-performance-trigger
    #:create-scheduled-trigger
    #:save-triggers-to-store
    #:load-triggers-from-store
    #:auto-crystallize-if-triggered))
