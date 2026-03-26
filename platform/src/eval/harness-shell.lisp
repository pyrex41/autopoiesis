;;;; harness-shell.lisp - Shell command harness
;;;;
;;;; Wraps an arbitrary shell command as an eval harness.
;;;; The command template supports {{prompt}} interpolation.

(in-package #:autopoiesis.eval)

;;; ===================================================================
;;; Shell Harness Class
;;; ===================================================================

(defclass shell-harness (eval-harness)
  ((command-template :initarg :command-template
                     :accessor sh-command-template
                     :type string
                     :documentation "Shell command with {{prompt}} placeholder.
E.g., \"echo '{{prompt}}' | my-tool --eval\"")
   (env :initarg :env
        :accessor sh-env
        :initform nil
        :documentation "Additional environment variables as alist of (name . value)")
   (working-directory :initarg :working-directory
                      :accessor sh-working-directory
                      :initform nil
                      :documentation "Working directory for command execution"))
  (:documentation "Harness wrapping an arbitrary shell command for eval."))

(defun make-shell-harness (name command-template &key env working-directory
                                                    (description ""))
  "Create a shell harness."
  (make-instance 'shell-harness
                 :name name
                 :description (if (string= description "")
                                  (format nil "Shell harness: ~a" command-template)
                                  description)
                 :command-template command-template
                 :env env
                 :working-directory working-directory))

;;; ===================================================================
;;; Prompt Interpolation
;;; ===================================================================

(defun interpolate-template (template prompt)
  "Replace {{prompt}} in TEMPLATE with PROMPT (shell-escaped)."
  (let ((escaped (shell-escape prompt)))
    (cl-ppcre:regex-replace-all "\\{\\{prompt\\}\\}" template escaped)))

(defun shell-escape (str)
  "Escape a string for safe inclusion in a shell command.
   Wraps in single quotes, escaping any internal single quotes."
  (if (null str)
      "''"
      (format nil "'~a'" (cl-ppcre:regex-replace-all "'" str "'\\''"))))

;;; ===================================================================
;;; Harness Protocol
;;; ===================================================================

(defmethod harness-run-scenario ((harness shell-harness) scenario-plist &key timeout)
  "Run scenario by interpolating prompt into command template and executing."
  (let* ((prompt (getf scenario-plist :eval-scenario/prompt))
         (verifier (getf scenario-plist :eval-scenario/verifier))
         (expected (getf scenario-plist :eval-scenario/expected))
         (command (interpolate-template (sh-command-template harness) prompt))
         (effective-timeout (or timeout
                                (getf scenario-plist :eval-scenario/timeout)
                                300))
         (start-time (get-precise-time))
         stdout stderr exit-code duration)
    (handler-case
        (let* ((process (sb-ext:run-program
                         "/bin/sh" (list "-c" command)
                         :output :stream
                         :error :stream
                         :wait nil
                         :directory (sh-working-directory harness)
                         :environment (when (sh-env harness)
                                        (append (mapcar (lambda (pair)
                                                          (format nil "~a=~a" (car pair) (cdr pair)))
                                                        (sh-env harness))
                                                (sb-ext:posix-environ)))))
               ;; Read output with timeout
               (out-thread (bordeaux-threads:make-thread
                            (lambda ()
                              (with-output-to-string (s)
                                (loop for line = (read-line (sb-ext:process-output process) nil nil)
                                      while line do (write-line line s))))
                            :name "shell-harness-stdout"))
               (err-thread (bordeaux-threads:make-thread
                            (lambda ()
                              (with-output-to-string (s)
                                (loop for line = (read-line (sb-ext:process-error process) nil nil)
                                      while line do (write-line line s))))
                            :name "shell-harness-stderr"))
               (deadline (+ (get-internal-real-time)
                            (* effective-timeout internal-time-units-per-second))))
          ;; Wait for completion or timeout
          (loop while (eq (sb-ext:process-status process) :running)
                when (> (get-internal-real-time) deadline)
                  do (sb-ext:process-kill process 15) ; SIGTERM
                     (sleep 2)
                     (when (eq (sb-ext:process-status process) :running)
                       (sb-ext:process-kill process 9)) ; SIGKILL
                     (loop-finish)
                do (sleep 0.1))
          (setf exit-code (sb-ext:process-exit-code process))
          (bordeaux-threads:join-thread out-thread)
          (bordeaux-threads:join-thread err-thread)
          (setf stdout (bordeaux-threads:join-thread out-thread))
          (setf stderr (bordeaux-threads:join-thread err-thread))
          (setf duration (/ (- (get-precise-time) start-time) 1000000.0)))
      (error (e)
        (setf duration (/ (- (get-precise-time) start-time) 1000000.0))
        (return-from harness-run-scenario
          (list :output (format nil "Error: ~a" e)
                :duration duration
                :exit-code -1
                :passed :error
                :metadata (list :error (format nil "~a" e))))))
    ;; Run verifier if present
    (let ((passed (if verifier
                      (run-verifier verifier stdout
                                    :expected expected
                                    :exit-code exit-code)
                      nil)))
      (list :output stdout
            :tool-calls nil
            :duration duration
            :cost nil
            :turns nil
            :exit-code exit-code
            :passed passed
            :metadata (list :command command
                            :stderr stderr
                            :working-directory (sh-working-directory harness))))))

(defmethod harness-to-config-plist ((harness shell-harness))
  (list :type "shell"
        :name (harness-name harness)
        :command-template (sh-command-template harness)))
