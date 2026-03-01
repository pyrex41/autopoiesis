;;;; workspace-backend.lisp - Sandbox isolation backend for workspace manager
;;;;
;;;; Registers :sandbox as an isolation backend for the workspace system.
;;;; When autopoiesis/sandbox is loaded, sandbox-backed workspaces become
;;;; available via (with-workspace (agent :isolation :sandbox ...)).

(in-package #:autopoiesis.sandbox)

;;; ── Sandbox Workspace Backend ───────────────────────────────────

(defclass sandbox-workspace-backend (autopoiesis.workspace:isolation-backend)
  ()
  (:default-initargs :name :sandbox)
  (:documentation "Workspace isolation via squashd container sandboxes.
Full process, filesystem, and network isolation."))

(defmethod autopoiesis.workspace:backend-create-workspace
    ((backend sandbox-workspace-backend) workspace)
  "Create a squashd sandbox for the workspace."
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized. Call start-sandbox-manager first."))
  (let* ((ws-id (autopoiesis.workspace:workspace-id workspace))
         (sandbox-id (format nil "ws-~A" ws-id))
         (metadata (autopoiesis.workspace:workspace-metadata workspace))
         (layers (or (getf metadata :layers) '("000-base-alpine")))
         (memory-mb (or (getf metadata :memory-mb) 1024))
         (timeout (or (getf metadata :timeout) 3600)))
    ;; Store sandbox-id on workspace
    (setf (autopoiesis.workspace:workspace-sandbox-id workspace) sandbox-id)
    ;; Create the sandbox
    (create-sandbox sandbox-id
                    :layers layers
                    :memory-mb memory-mb
                    :cpu 2.0
                    :max-lifetime-s timeout)
    ;; Create workspace directory inside sandbox
    (exec-in-sandbox sandbox-id "mkdir -p /workspace" :timeout 5)
    ;; Override workspace root to point inside the sandbox
    (setf (autopoiesis.workspace:workspace-root workspace) "/workspace/")
    sandbox-id))

(defmethod autopoiesis.workspace:backend-destroy-workspace
    ((backend sandbox-workspace-backend) workspace)
  "Destroy the squashd sandbox backing this workspace."
  (let ((sandbox-id (autopoiesis.workspace:workspace-sandbox-id workspace)))
    (when (and sandbox-id *sandbox-manager*)
      (ignore-errors
        (destroy-sandbox sandbox-id))))
  (setf (autopoiesis.workspace:workspace-status workspace) :destroyed))

(defmethod autopoiesis.workspace:backend-exec
    ((backend sandbox-workspace-backend) workspace command
     &key (timeout 120) working-directory)
  "Execute a command inside the workspace's sandbox."
  (let ((sandbox-id (autopoiesis.workspace:workspace-sandbox-id workspace)))
    (unless sandbox-id
      (error "No sandbox associated with workspace ~A"
             (autopoiesis.workspace:workspace-id workspace)))
    (let ((result (exec-in-sandbox sandbox-id command
                                   :workdir (or working-directory "/workspace")
                                   :timeout timeout)))
      (values (squashd:exec-result-stdout result)
              (squashd:exec-result-stderr result)
              (squashd:exec-result-exit-code result)))))

(defmethod autopoiesis.workspace:backend-write-file
    ((backend sandbox-workspace-backend) workspace path content)
  "Write a file inside the workspace's sandbox via exec."
  (let* ((sandbox-id (autopoiesis.workspace:workspace-sandbox-id workspace))
         (full-path (if (and (> (length path) 0) (char= (char path 0) #\/))
                        path
                        (format nil "/workspace/~A" path)))
         ;; Use base64 encoding for safe transfer
         (b64 (cl-base64:string-to-base64-string content))
         (cmd (format nil "mkdir -p \"$(dirname '~A')\" && echo '~A' | base64 -d > '~A'"
                      full-path b64 full-path))
         (result (exec-in-sandbox sandbox-id cmd :timeout 10)))
    (if (zerop (squashd:exec-result-exit-code result))
        full-path
        (error "Failed to write ~A in sandbox: ~A"
               full-path (squashd:exec-result-stderr result)))))

(defmethod autopoiesis.workspace:backend-read-file
    ((backend sandbox-workspace-backend) workspace path)
  "Read a file from the workspace's sandbox via exec."
  (let* ((sandbox-id (autopoiesis.workspace:workspace-sandbox-id workspace))
         (full-path (if (and (> (length path) 0) (char= (char path 0) #\/))
                        path
                        (format nil "/workspace/~A" path)))
         (result (exec-in-sandbox sandbox-id
                                  (format nil "cat '~A'" full-path)
                                  :timeout 10)))
    (if (zerop (squashd:exec-result-exit-code result))
        (squashd:exec-result-stdout result)
        (error "Failed to read ~A in sandbox: ~A"
               full-path (squashd:exec-result-stderr result)))))

;;; ── Registration ────────────────────────────────────────────────
;;;
;;; Register the sandbox backend when this file loads.
;;; After this, (with-workspace (agent :isolation :sandbox ...) ...)
;;; will use squashd container isolation.

(autopoiesis.workspace:register-isolation-backend
 :sandbox (make-instance 'sandbox-workspace-backend))
