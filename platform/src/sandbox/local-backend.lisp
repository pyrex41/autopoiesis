;;;; local-backend.lisp - Local filesystem execution backend
;;;;
;;;; The simplest backend: sandboxes are directories on the local filesystem.
;;;; Process execution via UIOP:RUN-PROGRAM. No containerization.
;;;;
;;;; Snapshot = scan directory into content store.
;;;; Restore = materialize tree entries from content store.
;;;; Fork = copy directory (or native COW on btrfs/ZFS).

(in-package #:autopoiesis.sandbox)

;;; ═══════════════════════════════════════════════════════════════════
;;; Local Backend Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass local-backend (execution-backend)
  ((base-dir :initarg :base-dir
             :accessor local-backend-base-dir
             :initform "/tmp/ap-sandboxes/"
             :documentation "Base directory for all sandbox roots")
   (sandboxes :initarg :sandboxes
              :accessor local-backend-sandboxes
              :initform (make-hash-table :test 'equal)
              :documentation "sandbox-id -> sandbox root path"))
  (:default-initargs :name :local)
  (:documentation "Local filesystem execution backend.
Sandboxes are subdirectories under base-dir."))

(defun make-local-backend (&key (base-dir "/tmp/ap-sandboxes/"))
  "Create a local filesystem execution backend."
  (let ((backend (make-instance 'local-backend :base-dir base-dir)))
    (ensure-directories-exist (pathname base-dir))
    backend))

;;; ═══════════════════════════════════════════════════════════════════
;;; Protocol Implementation
;;; ═══════════════════════════════════════════════════════════════════

(defmethod backend-create ((backend local-backend) sandbox-id
                           &key tree content-store config)
  "Create a sandbox as a local directory. Materialize tree if provided."
  (declare (ignore config))
  (let ((root (sandbox-root-path backend sandbox-id)))
    ;; Create sandbox directory
    (ensure-directories-exist (pathname (format nil "~A/" root)))
    ;; Track it
    (setf (gethash sandbox-id (local-backend-sandboxes backend)) root)
    ;; Materialize initial tree if provided
    (when (and tree content-store)
      (autopoiesis.snapshot:materialize-tree tree root content-store))
    sandbox-id))

(defmethod backend-destroy ((backend local-backend) sandbox-id)
  "Destroy a sandbox by removing its directory."
  (let ((root (gethash sandbox-id (local-backend-sandboxes backend))))
    (when root
      (ignore-errors
        (uiop:delete-directory-tree (pathname (format nil "~A/" root))
                                    :validate t))
      (remhash sandbox-id (local-backend-sandboxes backend))))
  sandbox-id)

(defmethod backend-exec ((backend local-backend) sandbox-id command
                         &key (timeout 300) env workdir)
  "Execute a command in the sandbox directory via UIOP."
  (let* ((root (or (gethash sandbox-id (local-backend-sandboxes backend))
                   (error "Sandbox ~S not found" sandbox-id)))
         (effective-workdir (if workdir
                                (merge-pathnames workdir root)
                                root))
         (start-time (get-internal-real-time))
         (stdout-str "")
         (stderr-str "")
         (exit-code 1))
    ;; Build environment
    (let ((env-list (append (when env
                              (mapcar (lambda (pair)
                                        (format nil "~A=~A" (car pair) (cdr pair)))
                                      env))
                            (list (format nil "HOME=~A" root)
                                  (format nil "SANDBOX_ID=~A" sandbox-id)))))
      (handler-case
          (multiple-value-bind (output error-output code)
              (uiop:run-program
               (list "/bin/sh" "-c" command)
               :directory effective-workdir
               :output '(:string :stripped t)
               :error-output '(:string :stripped t)
               :ignore-error-status t)
            (setf stdout-str (or output ""))
            (setf stderr-str (or error-output ""))
            (setf exit-code (or code 0)))
        (error (e)
          (setf stderr-str (format nil "Exec error: ~A" e))
          (setf exit-code -1))))
    (let ((duration-ms (round (* 1000.0
                                 (/ (- (get-internal-real-time) start-time)
                                    internal-time-units-per-second)))))
      (make-exec-result :exit-code exit-code
                        :stdout stdout-str
                        :stderr stderr-str
                        :duration-ms duration-ms
                        :sandbox-id sandbox-id
                        :command command))))

(defmethod backend-snapshot ((backend local-backend) sandbox-id content-store)
  "Scan the sandbox filesystem and store blobs. Returns tree entries."
  (let ((root (or (gethash sandbox-id (local-backend-sandboxes backend))
                  (error "Sandbox ~S not found" sandbox-id))))
    (autopoiesis.snapshot:scan-directory-flat root content-store)))

(defmethod backend-restore ((backend local-backend) sandbox-id tree content-store
                            &key incremental)
  "Restore sandbox to match tree. Incremental diffing if requested."
  (let ((root (or (gethash sandbox-id (local-backend-sandboxes backend))
                  (error "Sandbox ~S not found" sandbox-id))))
    (if incremental
        ;; Scan current state, diff, apply only changes
        (let* ((current-tree (autopoiesis.snapshot:scan-directory-flat
                              root content-store))
               (diff (autopoiesis.snapshot:tree-diff current-tree tree)))
          (autopoiesis.snapshot:materialize-diff diff root content-store))
        ;; Full materialization: clear and rewrite
        (progn
          ;; Clear existing contents
          (dolist (item (uiop:directory-files root))
            (ignore-errors (delete-file item)))
          (dolist (item (uiop:subdirectories root))
            (ignore-errors (uiop:delete-directory-tree item :validate t)))
          (autopoiesis.snapshot:materialize-tree tree root content-store)))))

(defmethod backend-fork ((backend local-backend) source-id new-id)
  "Fork by copying the directory. Returns new sandbox-id."
  (let ((source-root (or (gethash source-id (local-backend-sandboxes backend))
                         (error "Source sandbox ~S not found" source-id)))
        (new-root (sandbox-root-path backend new-id)))
    ;; Copy directory tree
    (ensure-directories-exist (pathname (format nil "~A/" new-root)))
    (uiop:run-program
     (list "cp" "-a" (format nil "~A/." source-root) new-root)
     :ignore-error-status t)
    (setf (gethash new-id (local-backend-sandboxes backend)) new-root)
    new-id))

(defmethod backend-sandbox-root ((backend local-backend) sandbox-id)
  "Return the filesystem root path."
  (or (gethash sandbox-id (local-backend-sandboxes backend))
      (error "Sandbox ~S not found" sandbox-id)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun sandbox-root-path (backend sandbox-id)
  "Compute the root path for a sandbox."
  (let ((base (local-backend-base-dir backend)))
    (format nil "~A~A/" base sandbox-id)))
