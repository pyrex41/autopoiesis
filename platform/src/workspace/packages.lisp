;;;; packages.lisp - Workspace management package
;;;;
;;;; Provides per-agent persistent homes and per-task ephemeral workspaces.
;;;; Three isolation levels:
;;;;   :none      - No isolation, paths used as-is
;;;;   :directory - Workspace directory on host filesystem
;;;;   :sandbox   - Full container isolation via sq-sandbox (when loaded)
;;;;
;;;; For :sandbox isolation, the sandbox is hermetic. Host files are
;;;; made available via :references — directories snapshotted into
;;;; read-only squashfs layers, mounted at /ref/<name>/ in the sandbox.
;;;;
;;;; The workspace protocol is backend-agnostic. Sandbox support is
;;;; registered by autopoiesis/sandbox when that system is loaded.

(in-package #:cl-user)

(defpackage #:autopoiesis.workspace
  (:use #:cl #:alexandria)
  (:local-nicknames (#:bt #:bordeaux-threads))
  (:export
   ;; Configuration
   #:*agent-data-root*
   #:*current-workspace*

   ;; Agent home
   #:agent-home
   #:agent-home-id
   #:agent-home-root
   #:ensure-agent-home
   #:agent-home-config-path
   #:agent-home-history-path
   #:agent-home-learning-path
   #:agent-home-workspaces-path

   ;; Workspace
   #:workspace
   #:workspace-id
   #:workspace-agent-id
   #:workspace-task
   #:workspace-isolation
   #:workspace-root
   #:workspace-sandbox-id
   #:workspace-references
   #:workspace-status
   #:workspace-created-at

   ;; Lifecycle
   #:create-workspace
   #:destroy-workspace
   #:with-workspace

   ;; Path resolution
   #:resolve-path
   #:workspace-relative

   ;; File operations (workspace-aware, sandbox-confined)
   #:ws-read-file
   #:ws-write-file
   #:ws-exec
   #:ws-list-directory
   #:ws-file-exists-p

   ;; Isolation backend protocol
   #:isolation-backend
   #:register-isolation-backend
   #:find-isolation-backend
   #:backend-create-workspace
   #:backend-destroy-workspace
   #:backend-exec
   #:backend-write-file
   #:backend-read-file

   ;; Reference snapshotting (for sandbox isolation)
   #:snapshot-directory-to-module

   ;; Registry
   #:*workspace-registry*
   #:find-workspace
   #:list-workspaces
   #:list-agent-workspaces))
