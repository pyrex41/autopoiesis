;;;; docker-backend.lisp - Docker container execution backend
;;;;
;;;; Sandboxes are Docker containers. Provides full process isolation,
;;;; network control, and resource limits via Docker.
;;;;
;;;; Snapshot = docker cp + scan into content store.
;;;; Restore = materialize to temp dir + docker cp into container.
;;;; Fork = docker commit + docker run from committed image.

(in-package #:autopoiesis.sandbox)

;;; ═══════════════════════════════════════════════════════════════════
;;; Docker Backend Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass docker-backend (execution-backend)
  ((base-image :initarg :base-image
               :accessor docker-backend-base-image
               :initform "alpine:latest"
               :documentation "Default Docker image for new containers")
   (network :initarg :network
            :accessor docker-backend-network
            :initform "none"
            :documentation "Docker network mode (:none, :bridge, :host, or network name)")
   (containers :initarg :containers
               :accessor docker-backend-containers
               :initform (make-hash-table :test 'equal)
               :documentation "sandbox-id -> container-id")
   (temp-dir :initarg :temp-dir
             :accessor docker-backend-temp-dir
             :initform "/tmp/ap-docker-staging/"
             :documentation "Temp directory for staging file transfers"))
  (:default-initargs :name :docker)
  (:documentation "Docker container execution backend.
Provides full process isolation via Docker."))

(defun make-docker-backend (&key (base-image "alpine:latest")
                                  (network "none")
                                  (temp-dir "/tmp/ap-docker-staging/"))
  "Create a Docker execution backend."
  (let ((backend (make-instance 'docker-backend
                                :base-image base-image
                                :network network
                                :temp-dir temp-dir)))
    (ensure-directories-exist (pathname temp-dir))
    backend))

;;; ═══════════════════════════════════════════════════════════════════
;;; Protocol Implementation
;;; ═══════════════════════════════════════════════════════════════════

(defmethod backend-create ((backend docker-backend) sandbox-id
                           &key tree content-store config)
  "Create a Docker container. Materialize tree into it if provided."
  (let* ((image (or (getf config :image) (docker-backend-base-image backend)))
         (memory (or (getf config :memory-mb) 1024))
         (cpus (or (getf config :cpus) "2.0"))
         (network (or (getf config :network) (docker-backend-network backend)))
         (container-name (format nil "ap-~A" sandbox-id))
         ;; Create container
         (cmd (format nil "docker create --name ~A ~
                           --memory ~Dm --cpus ~A ~
                           --network ~A ~
                           --workdir /workspace ~
                           ~A sleep infinity"
                      container-name memory cpus network image)))
    ;; Create and start container
    (let ((result (uiop:run-program
                   (list "/bin/sh" "-c" cmd)
                   :output '(:string :stripped t)
                   :error-output '(:string :stripped t)
                   :ignore-error-status t)))
      (declare (ignore result)))
    (uiop:run-program
     (list "docker" "start" container-name)
     :ignore-error-status t)
    ;; Track container
    (setf (gethash sandbox-id (docker-backend-containers backend))
          container-name)
    ;; Materialize tree into container if provided
    (when (and tree content-store)
      (let ((staging (format nil "~A~A/" (docker-backend-temp-dir backend)
                             sandbox-id)))
        (ensure-directories-exist (pathname staging))
        (autopoiesis.snapshot:materialize-tree tree staging content-store)
        ;; Copy into container
        (uiop:run-program
         (list "docker" "cp" (format nil "~A." staging)
               (format nil "~A:/workspace/" container-name))
         :ignore-error-status t)
        ;; Clean up staging
        (ignore-errors
          (uiop:delete-directory-tree (pathname staging) :validate t))))
    sandbox-id))

(defmethod backend-destroy ((backend docker-backend) sandbox-id)
  "Stop and remove the Docker container."
  (let ((container (gethash sandbox-id (docker-backend-containers backend))))
    (when container
      (ignore-errors
        (uiop:run-program (list "docker" "rm" "-f" container)
                          :ignore-error-status t))
      (remhash sandbox-id (docker-backend-containers backend))))
  sandbox-id)

(defmethod backend-exec ((backend docker-backend) sandbox-id command
                         &key (timeout 300) env workdir)
  "Execute a command in the Docker container."
  (let* ((container (or (gethash sandbox-id (docker-backend-containers backend))
                        (error "Sandbox ~S not found" sandbox-id)))
         (start-time (get-internal-real-time))
         (env-args (when env
                     (mapcan (lambda (pair)
                               (list "-e" (format nil "~A=~A" (car pair) (cdr pair))))
                             env)))
         (workdir-args (when workdir
                         (list "-w" workdir)))
         (docker-cmd (append (list "docker" "exec")
                             env-args
                             workdir-args
                             (list container "/bin/sh" "-c" command)))
         (stdout-str "")
         (stderr-str "")
         (exit-code 1))
    (handler-case
        (multiple-value-bind (output error-output code)
            (uiop:run-program docker-cmd
                              :output '(:string :stripped t)
                              :error-output '(:string :stripped t)
                              :ignore-error-status t)
          (setf stdout-str (or output ""))
          (setf stderr-str (or error-output ""))
          (setf exit-code (or code 0)))
      (error (e)
        (setf stderr-str (format nil "Docker exec error: ~A" e))
        (setf exit-code -1)))
    (let ((duration-ms (round (* 1000.0
                                 (/ (- (get-internal-real-time) start-time)
                                    internal-time-units-per-second)))))
      (make-exec-result :exit-code exit-code
                        :stdout stdout-str
                        :stderr stderr-str
                        :duration-ms duration-ms
                        :sandbox-id sandbox-id
                        :command command))))

(defmethod backend-snapshot ((backend docker-backend) sandbox-id content-store)
  "Copy container filesystem to staging dir, scan into content store."
  (let* ((container (or (gethash sandbox-id (docker-backend-containers backend))
                        (error "Sandbox ~S not found" sandbox-id)))
         (staging (format nil "~A~A-snap/" (docker-backend-temp-dir backend)
                          sandbox-id)))
    ;; Copy from container
    (ensure-directories-exist (pathname staging))
    (uiop:run-program
     (list "docker" "cp" (format nil "~A:/workspace/." container) staging)
     :ignore-error-status t)
    ;; Scan staged files
    (let ((entries (autopoiesis.snapshot:scan-directory-flat staging content-store)))
      ;; Clean up staging
      (ignore-errors
        (uiop:delete-directory-tree (pathname staging) :validate t))
      entries)))

(defmethod backend-restore ((backend docker-backend) sandbox-id tree content-store
                            &key incremental)
  "Restore container filesystem from tree entries."
  (declare (ignore incremental)) ; Docker doesn't support incremental easily
  (let* ((container (or (gethash sandbox-id (docker-backend-containers backend))
                        (error "Sandbox ~S not found" sandbox-id)))
         (staging (format nil "~A~A-restore/" (docker-backend-temp-dir backend)
                          sandbox-id)))
    ;; Materialize to staging
    (ensure-directories-exist (pathname staging))
    (autopoiesis.snapshot:materialize-tree tree staging content-store)
    ;; Clear container workspace and copy in
    (uiop:run-program
     (list "docker" "exec" container "sh" "-c" "rm -rf /workspace/*")
     :ignore-error-status t)
    (uiop:run-program
     (list "docker" "cp" (format nil "~A." staging)
           (format nil "~A:/workspace/" container))
     :ignore-error-status t)
    ;; Clean up staging
    (ignore-errors
      (uiop:delete-directory-tree (pathname staging) :validate t))
    (length tree)))

(defmethod backend-fork ((backend docker-backend) source-id new-id)
  "Fork by committing container to image, then running new container."
  (let* ((source-container (or (gethash source-id (docker-backend-containers backend))
                               (error "Source sandbox ~S not found" source-id)))
         (image-tag (format nil "ap-fork-~A:latest" new-id))
         (new-container (format nil "ap-~A" new-id)))
    ;; Commit current container as image
    (uiop:run-program
     (list "docker" "commit" source-container image-tag)
     :ignore-error-status t)
    ;; Run new container from committed image
    (uiop:run-program
     (list "docker" "run" "-d" "--name" new-container
           "--network" (docker-backend-network backend)
           "--workdir" "/workspace"
           image-tag "sleep" "infinity")
     :ignore-error-status t)
    ;; Track it
    (setf (gethash new-id (docker-backend-containers backend)) new-container)
    new-id))

(defmethod backend-sandbox-root ((backend docker-backend) sandbox-id)
  "Docker containers don't expose a host filesystem path.
   Returns the container workspace path (useful for docker cp)."
  (let ((container (or (gethash sandbox-id (docker-backend-containers backend))
                       (error "Sandbox ~S not found" sandbox-id))))
    (format nil "~A:/workspace" container)))

(defmethod backend-supports-native-fork-p ((backend docker-backend))
  "Docker supports native fork via commit + run."
  t)
