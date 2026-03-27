;;;; conductor-dispatch.lisp - Sandbox action type for the conductor
;;;;
;;;; Extends the conductor to handle :sandbox action types.
;;;; Follows the same pattern as :claude actions in conductor.lisp.

(in-package #:autopoiesis.sandbox)

;;; ── Conductor sandbox dispatch ──────────────────────────────────

(defun dispatch-sandbox-event (conductor action-plist)
  "Handle a :sandbox action from the conductor timer heap.
   Creates a sandbox, executes the command, and reports results
   back via callbacks.

   ACTION-PLIST keys:
     :command     - Shell command to execute (required)
     :task-id     - Unique task identifier (auto-generated if missing)
     :layers      - List of squashfs layer names (optional)
     :memory-mb   - Memory limit (optional, default 1024)
     :cpu         - CPU quota (optional, default 2.0)
     :timeout     - Exec timeout in seconds (optional, default 300)
     :workdir     - Working directory inside sandbox (optional, default \"/\")
     :on-complete - Callback (lambda (result)) for success
     :on-error    - Callback (lambda (reason)) for failure"
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized"))

  (let* ((command (getf action-plist :command))
         (task-id (or (getf action-plist :task-id)
                      (format nil "sandbox-~A"
                              (autopoiesis.core:make-uuid))))
         (layers (getf action-plist :layers))
         (memory-mb (or (getf action-plist :memory-mb) 1024))
         (cpu (or (getf action-plist :cpu) 2.0))
         (timeout (or (getf action-plist :timeout) 300))
         (workdir (or (getf action-plist :workdir) "/"))
         (on-complete (getf action-plist :on-complete))
         (on-error (getf action-plist :on-error))
         (sandbox-id (format nil "cond-~A" task-id))
         ;; Capture substrate bindings for child thread
         (captured-substrate autopoiesis.substrate:*substrate*)
         (captured-store autopoiesis.substrate:*store*)
         (captured-intern autopoiesis.substrate::*intern-table*)
         (captured-resolve autopoiesis.substrate::*resolve-table*)
         (captured-index autopoiesis.substrate::*index*)
         (captured-hooks autopoiesis.substrate::*hooks*))

    ;; Register worker in substrate
    (autopoiesis.orchestration:register-worker conductor task-id
                                               (bt:current-thread))

    ;; Spawn worker thread
    (bt:make-thread
     (lambda ()
       ;; Rebind substrate specials
       (let ((autopoiesis.substrate:*substrate* captured-substrate)
             (autopoiesis.substrate:*store* captured-store)
             (autopoiesis.substrate::*intern-table* captured-intern)
             (autopoiesis.substrate::*resolve-table* captured-resolve)
             (autopoiesis.substrate::*index* captured-index)
             (autopoiesis.substrate::*hooks* captured-hooks))
         (handler-case
             (progn
               ;; Create sandbox
               (create-sandbox sandbox-id
                               :layers (or layers '("000-base-alpine"))
                               :memory-mb memory-mb
                               :cpu cpu
                               :max-lifetime-s (+ timeout 60))

               (unwind-protect
                    (let ((exec-result (exec-in-sandbox
                                        sandbox-id command
                                        :workdir workdir
                                        :timeout timeout)))
                      (if (zerop (squashd:exec-result-exit-code exec-result))
                          (when on-complete
                            (funcall on-complete
                                     (list :exit-code 0
                                           :stdout (squashd:exec-result-stdout
                                                    exec-result)
                                           :stderr (squashd:exec-result-stderr
                                                    exec-result)
                                           :duration-ms
                                           (squashd:exec-result-duration-ms
                                            exec-result)
                                           :sandbox-id sandbox-id)))
                          (when on-error
                            (funcall on-error
                                     (list :exit-code
                                           (squashd:exec-result-exit-code
                                            exec-result)
                                           :stderr (squashd:exec-result-stderr
                                                    exec-result))))))

                 ;; Always destroy sandbox
                 (ignore-errors
                   (destroy-sandbox sandbox-id))))

           (error (e)
             (when on-error
               (funcall on-error (list :error (format nil "~A" e))))))))
     :name (format nil "sandbox-worker-~A" task-id))))
