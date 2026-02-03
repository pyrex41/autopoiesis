;;;; packages.lisp - Package definitions for Autopoiesis Security
;;;;
;;;; This file defines the package structure for the security layer.
;;;; Phase 10.2: Security Hardening

(in-package #:cl-user)

;;; ═══════════════════════════════════════════════════════════════════
;;; Security Package - Permission system, audit logging, input validation
;;; ═══════════════════════════════════════════════════════════════════

(defpackage #:autopoiesis.security
  (:use #:cl #:alexandria)
  (:export
   ;; Permission classes
   #:permission
   #:permission-name
   #:permission-resource
   #:permission-actions
   #:make-permission
   
   ;; Resource types
   #:resource
   #:resource-type
   #:resource-id
   #:resource-owner
   #:make-resource
   
   ;; Permission checking
   #:check-permission
   #:grant-permission
   #:revoke-permission
   #:list-permissions
   #:has-permission-p
   #:with-permission-check
   
   ;; Permission denied condition
   #:permission-denied
   #:permission-denied-agent
   #:permission-denied-resource
   #:permission-denied-action
   
   ;; Agent permissions registry
   #:*agent-permissions*
   #:get-agent-permissions
   #:set-agent-permissions
   #:clear-agent-permissions
   
   ;; Resource actions
   #:+action-read+
   #:+action-write+
   #:+action-execute+
   #:+action-delete+
   #:+action-create+
   #:+action-admin+
   #:all-actions
   
   ;; Resource types
   #:+resource-snapshot+
   #:+resource-agent+
   #:+resource-capability+
   #:+resource-extension+
   #:+resource-file+
   #:+resource-network+
   #:+resource-system+
   
   ;; Permission templates
   #:make-read-only-permission
   #:make-full-access-permission
   #:make-execute-only-permission
   
   ;; Permission matrix
   #:permission-matrix
   #:make-permission-matrix
   #:matrix-check
   #:matrix-grant
   #:matrix-revoke
   #:matrix-to-list
   
   ;; Default permission sets
   #:*default-agent-permissions*
   #:*admin-permissions*
   #:*sandbox-permissions*))
