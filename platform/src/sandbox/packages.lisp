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
   ;; Execution backend protocol
   #:execution-backend
   #:backend-name
   #:backend-config
   #:backend-create
   #:backend-destroy
   #:backend-exec
   #:backend-snapshot
   #:backend-restore
   #:backend-fork
   #:backend-sandbox-root
   #:backend-supports-native-fork-p
   ;; Exec result
   #:make-exec-result
   #:exec-result-exit-code
   #:exec-result-stdout
   #:exec-result-stderr
   #:exec-result-duration-ms
   ;; Backend registry
   #:*backend-registry*
   #:register-backend
   #:find-backend
   #:list-backends
   ;; Local backend
   #:local-backend
   #:make-local-backend
   #:local-backend-base-dir
   ;; Docker backend
   #:docker-backend
   #:make-docker-backend
   #:docker-backend-base-image
   ;; Changeset (incremental snapshot tracking)
   #:changeset
   #:make-changeset
   #:changeset-record
   #:changeset-record-write
   #:changeset-record-delete
   #:changeset-changed-paths
   #:changeset-change-count
   #:changeset-empty-p
   #:changeset-commit
   #:changeset-reset
   ;; Sandbox lifecycle manager (DAG-integrated)
   #:sandbox-manager
   #:make-sandbox-manager
   #:manager-create-sandbox
   #:manager-destroy-sandbox
   #:manager-exec
   #:manager-snapshot
   #:manager-restore
   #:manager-fork
   #:manager-diff
   #:manager-sandbox-info
   #:manager-list-sandboxes
   #:manager-content-store
   #:manager-backend
   ;; Squashd provider (legacy)
   #:sandbox-provider
   #:make-sandbox-provider
   ;; Entity types
   #:sandbox-instance-entity
   #:sandbox-exec-entity
   ;; Lifecycle (legacy squashd)
   #:start-sandbox-manager
   #:stop-sandbox-manager
   #:*sandbox-manager*
   #:*sandbox-config*
   ;; Direct sandbox operations (legacy squashd)
   #:create-sandbox
   #:destroy-sandbox
   #:exec-in-sandbox
   #:snapshot-sandbox
   #:restore-sandbox
   #:list-sandboxes
   ;; Conductor integration
   #:dispatch-sandbox-event))
