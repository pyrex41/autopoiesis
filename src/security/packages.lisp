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
   #:*sandbox-permissions*
   
   ;; Audit logging
   #:audit-entry
   #:audit-entry-timestamp
   #:audit-entry-agent-id
   #:audit-entry-action
   #:audit-entry-resource
   #:audit-entry-result
   #:audit-entry-details
   #:make-audit-entry
   #:audit-entry-p
   #:copy-audit-entry
   
   ;; Audit log management
   #:*audit-log*
   #:*audit-log-path*
   #:*audit-log-max-size*
   #:*audit-log-max-files*
   #:audit-log
   #:with-audit
   #:with-audit-logging
   #:start-audit-logging
   #:stop-audit-logging
   #:rotate-audit-log
   #:serialize-audit-entry
   #:deserialize-audit-entry
   #:read-audit-log
   #:audit-log-active-p
   
   ;; Input validation
   #:validation-result
   #:validation-result-valid-p
   #:validation-result-value
   #:validation-result-errors
   #:make-validation-result
   #:validation-success
   #:validation-failure
   
   ;; Validation condition
   #:validation-error
   #:validation-error-input
   #:validation-error-spec
   #:validation-error-errors
   
   ;; Core validation
   #:validate-input
   #:valid-p
   #:with-validated-input
   #:validate-inputs
   
   ;; Sanitization
   #:sanitize-string
   #:sanitize-html
   
   ;; Predefined specs
   #:*validation-spec-agent-id*
   #:*validation-spec-snapshot-id*
   #:*validation-spec-branch-name*
   #:*validation-spec-capability-name*
   #:*validation-spec-action*
   #:*validation-spec-resource-type*))
