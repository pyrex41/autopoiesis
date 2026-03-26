;;;; packages.lisp - Sandbox integration package
;;;;
;;;; Wraps sq-sandbox's squashd runtime as an Autopoiesis provider,
;;;; tracks sandbox lifecycle in the substrate, and integrates with
;;;; the conductor for dispatching sandbox-backed work.

(in-package #:cl-user)

(defpackage #:autopoiesis.sandbox
  (:use #:cl #:alexandria)
  (:local-nicknames (#:bt #:bordeaux-threads))
  (:export
   ;; Provider
   #:sandbox-provider
   #:make-sandbox-provider
   ;; Entity types
   #:sandbox-instance-entity
   #:sandbox-exec-entity
   ;; Lifecycle
   #:start-sandbox-manager
   #:stop-sandbox-manager
   #:*sandbox-manager*
   #:*sandbox-config*
   ;; Direct sandbox operations
   #:create-sandbox
   #:destroy-sandbox
   #:exec-in-sandbox
   #:snapshot-sandbox
   #:restore-sandbox
   #:list-sandboxes
   ;; Conductor integration
   #:dispatch-sandbox-event))
