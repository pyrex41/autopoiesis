;;;; sandbox-provider.lisp - Wraps squashd manager as an AP provider
;;;;
;;;; Follows the inference-provider pattern: overrides provider-invoke
;;;; directly to call the squashd manager in-process. Each invocation
;;;; creates a sandbox, executes the prompt as a shell command, captures
;;;; output, tracks state in substrate datoms, and destroys the sandbox.

(in-package #:autopoiesis.sandbox)

;;; ── Global sandbox manager ──────────────────────────────────────

(defvar *sandbox-manager* nil
  "The global squashd manager instance. Bound by start-sandbox-manager.")

(defvar *sandbox-config* nil
  "The global squashd config. Bound by start-sandbox-manager.")

(defun start-sandbox-manager (&key (data-dir "/data")
                                    (max-sandboxes 100)
                                    (upper-limit-mb 512)
                                    (backend :chroot))
  "Initialize the global sandbox manager.
   Must be called before any sandbox operations.
   DATA-DIR must exist and be writable."
  (setf *sandbox-config*
        (squashd:make-config :data-dir data-dir
                             :max-sandboxes max-sandboxes
                             :upper-limit-mb upper-limit-mb
                             :backend backend))
  (setf *sandbox-manager* (squashd:make-manager *sandbox-config*))
  ;; Ensure directories exist
  (ensure-directories-exist
   (format nil "~A/sandboxes/" data-dir))
  (ensure-directories-exist
   (format nil "~A/modules/" data-dir))
  ;; Recover any existing sandboxes from disk
  (squashd:init-recover *sandbox-config* *sandbox-manager*)
  *sandbox-manager*)

(defun stop-sandbox-manager ()
  "Destroy all sandboxes and clear the global manager."
  (when *sandbox-manager*
    (dolist (info (squashd:list-sandbox-infos *sandbox-manager*))
      (ignore-errors
        (squashd:manager-destroy-sandbox
         *sandbox-manager*
         (cdr (assoc :|id| info)))))
    (setf *sandbox-manager* nil)
    (setf *sandbox-config* nil)))

;;; ── Direct sandbox operations ───────────────────────────────────
;;;
;;; Thin wrappers around squashd manager that also track state in substrate.

(defun create-sandbox (sandbox-id &key (layers '("000-base-alpine"))
                                       (memory-mb 1024)
                                       (cpu 2.0)
                                       (max-lifetime-s 3600)
                                       owner task)
  "Create a sandbox and track it in the substrate.
   Returns the sandbox-id on success."
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized. Call start-sandbox-manager first."))
  (let ((sandbox-eid nil))
    ;; Track in substrate if store is active
    (when autopoiesis.substrate:*store*
      (setf sandbox-eid (autopoiesis.substrate:intern-id
                         (format nil "sandbox:~A" sandbox-id)))
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom
              sandbox-eid :sandbox-instance/sandbox-id sandbox-id)
             (autopoiesis.substrate:make-datom
              sandbox-eid :sandbox-instance/status :creating)
             (autopoiesis.substrate:make-datom
              sandbox-eid :sandbox-instance/created-at (get-universal-time))
             (autopoiesis.substrate:make-datom
              sandbox-eid :sandbox-instance/layers layers))))
    ;; Create via squashd
    (squashd:manager-create-sandbox
     *sandbox-manager* sandbox-id
     :layers layers
     :memory-mb memory-mb
     :cpu cpu
     :max-lifetime-s max-lifetime-s
     :owner owner
     :task task)
    ;; Update status
    (when sandbox-eid
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom
              sandbox-eid :sandbox-instance/status :ready))))
    sandbox-id))

(defun destroy-sandbox (sandbox-id)
  "Destroy a sandbox and update substrate tracking."
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized."))
  (let ((sandbox-eid (when autopoiesis.substrate:*store*
                       (autopoiesis.substrate:intern-id
                        (format nil "sandbox:~A" sandbox-id)))))
    (when sandbox-eid
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom
              sandbox-eid :sandbox-instance/status :destroying))))
    (squashd:manager-destroy-sandbox *sandbox-manager* sandbox-id)
    (when sandbox-eid
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom
              sandbox-eid :sandbox-instance/status :destroyed)
             (autopoiesis.substrate:make-datom
              sandbox-eid :sandbox-instance/destroyed-at
              (get-universal-time)))))
    sandbox-id))

(defun exec-in-sandbox (sandbox-id command &key (workdir "/") (timeout 300))
  "Execute a command in a sandbox. Returns an exec-result.
   Tracks the exec in substrate if store is active."
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized."))
  (let ((result (squashd:manager-exec
                 *sandbox-manager* sandbox-id command
                 :workdir workdir :timeout timeout)))
    ;; Track in substrate
    (when autopoiesis.substrate:*store*
      (let ((exec-eid (autopoiesis.substrate:intern-id
                       (format nil "exec:~A:~D"
                               sandbox-id
                               (squashd:exec-result-seq result)))))
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom
                exec-eid :sandbox-exec/sandbox-id sandbox-id)
               (autopoiesis.substrate:make-datom
                exec-eid :sandbox-exec/command command)
               (autopoiesis.substrate:make-datom
                exec-eid :sandbox-exec/exit-code
                (squashd:exec-result-exit-code result))
               (autopoiesis.substrate:make-datom
                exec-eid :sandbox-exec/started-at
                (squashd:exec-result-started result))
               (autopoiesis.substrate:make-datom
                exec-eid :sandbox-exec/finished-at
                (squashd:exec-result-finished result))
               (autopoiesis.substrate:make-datom
                exec-eid :sandbox-exec/duration-ms
                (squashd:exec-result-duration-ms result))
               (autopoiesis.substrate:make-datom
                exec-eid :sandbox-exec/stdout
                (squashd:exec-result-stdout result))
               (autopoiesis.substrate:make-datom
                exec-eid :sandbox-exec/stderr
                (squashd:exec-result-stderr result))
               (autopoiesis.substrate:make-datom
                exec-eid :sandbox-exec/seq
                (squashd:exec-result-seq result))))))
    result))

(defun snapshot-sandbox (sandbox-id label)
  "Snapshot a sandbox's writable layer as a new squashfs module."
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized."))
  (squashd:manager-snapshot *sandbox-manager* sandbox-id label))

(defun restore-sandbox (sandbox-id label)
  "Restore a sandbox from a previously saved snapshot."
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized."))
  (squashd:manager-restore *sandbox-manager* sandbox-id label))

(defun list-sandboxes ()
  "List all active sandboxes."
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized."))
  (squashd:list-sandbox-infos *sandbox-manager*))

;;; ── Sandbox provider class ──────────────────────────────────────

(defclass sandbox-provider (autopoiesis.integration:provider)
  ((default-layers :initarg :default-layers
                   :accessor sandbox-default-layers
                   :initform '("000-base-alpine")
                   :documentation "Default squashfs layers for new sandboxes")
   (default-memory-mb :initarg :default-memory-mb
                      :accessor sandbox-default-memory-mb
                      :initform 1024
                      :documentation "Default memory limit in MB")
   (default-cpu :initarg :default-cpu
                :accessor sandbox-default-cpu
                :initform 2.0
                :documentation "Default CPU quota")
   (default-max-lifetime-s :initarg :default-max-lifetime-s
                           :accessor sandbox-default-max-lifetime-s
                           :initform 3600
                           :documentation "Default max sandbox lifetime in seconds"))
  (:default-initargs :name "sandbox" :timeout 300)
  (:documentation "Provider that executes commands in squashd container sandboxes.
Overrides provider-invoke to use squashd manager directly (no CLI subprocess)."))

(defun make-sandbox-provider (&key (name "sandbox")
                                    (default-layers '("000-base-alpine"))
                                    (default-memory-mb 1024)
                                    (default-cpu 2.0)
                                    (default-max-lifetime-s 3600)
                                    (timeout 300))
  "Create a sandbox provider instance."
  (make-instance 'sandbox-provider
                 :name name
                 :timeout timeout
                 :default-layers default-layers
                 :default-memory-mb default-memory-mb
                 :default-cpu default-cpu
                 :default-max-lifetime-s default-max-lifetime-s))

;;; ── Provider protocol implementation ────────────────────────────

(defmethod autopoiesis.integration:provider-supported-modes
    ((provider sandbox-provider))
  '(:one-shot))

(defmethod autopoiesis.integration:provider-invoke
    ((provider sandbox-provider) prompt
     &key tools mode agent-id)
  "Execute PROMPT as a shell command inside a one-shot sandbox.
   Creates a sandbox, runs the command, captures output, destroys sandbox.
   Returns a provider-result."
  (declare (ignore tools mode))
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized. Call start-sandbox-manager first."))

  (let* ((sandbox-id (format nil "ap-~A" (autopoiesis.core:make-uuid)))
         (start-time (get-internal-real-time))
         (timeout (autopoiesis.integration:provider-timeout provider)))

    ;; Emit provider-request event
    (autopoiesis.integration:emit-integration-event
     :provider-request
     :source (autopoiesis.integration:provider-name provider)
     :agent-id agent-id
     :data (list :prompt (if (> (length prompt) 200)
                             (subseq prompt 0 200)
                             prompt)))

    (unwind-protect
         (handler-case
             (progn
               ;; Create sandbox
               (create-sandbox sandbox-id
                               :layers (sandbox-default-layers provider)
                               :memory-mb (sandbox-default-memory-mb provider)
                               :cpu (sandbox-default-cpu provider)
                               :max-lifetime-s (sandbox-default-max-lifetime-s provider))

               ;; Execute the command
               (let ((exec-result (exec-in-sandbox sandbox-id prompt
                                                    :timeout timeout)))
                 ;; Build provider-result
                 (let* ((end-time (get-internal-real-time))
                        (duration (/ (- end-time start-time)
                                     internal-time-units-per-second))
                        (result (autopoiesis.integration:make-provider-result
                                 :text (squashd:exec-result-stdout exec-result)
                                 :exit-code (squashd:exec-result-exit-code exec-result)
                                 :error-output (squashd:exec-result-stderr exec-result)
                                 :raw-output (squashd:exec-result-stdout exec-result)
                                 :duration duration
                                 :provider-name
                                 (autopoiesis.integration:provider-name provider)
                                 :metadata (list
                                            :sandbox-id sandbox-id
                                            :duration-ms
                                            (squashd:exec-result-duration-ms
                                             exec-result)))))

                   ;; Emit provider-response event
                   (autopoiesis.integration:emit-integration-event
                    :provider-response
                    :source (autopoiesis.integration:provider-name provider)
                    :agent-id agent-id
                    :data (list :exit-code (squashd:exec-result-exit-code exec-result)
                                :duration duration
                                :sandbox-id sandbox-id))

                   result)))

           ;; Handle errors
           (error (e)
             (autopoiesis.integration:make-provider-result
              :text (format nil "Sandbox error: ~A" e)
              :exit-code -1
              :error-output (format nil "~A" e)
              :provider-name
              (autopoiesis.integration:provider-name provider))))

      ;; Cleanup: always destroy sandbox
      (ignore-errors
        (destroy-sandbox sandbox-id)))))
