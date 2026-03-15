;;;; provider.lisp - Provider protocol and registry
;;;;
;;;; Defines the abstract provider interface for external CLI coding tools
;;;; (Claude Code, Codex, OpenCode, Cursor Agent). Providers wrap CLI tools
;;;; as inference engines for agent cognition.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider Base Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass provider ()
  ((name :initarg :name
         :accessor provider-name
         :initform "unnamed"
         :documentation "Unique name for this provider")
   (command :initarg :command
            :accessor provider-command
            :documentation "CLI command to invoke (e.g., \"claude\", \"codex\")")
   (working-directory :initarg :working-directory
                      :accessor provider-working-directory
                      :initform nil
                      :documentation "Working directory for subprocess")
   (default-model :initarg :default-model
                  :accessor provider-default-model
                  :initform nil
                  :documentation "Default model to use, if applicable")
   (max-turns :initarg :max-turns
              :accessor provider-max-turns
              :initform 10
              :documentation "Maximum agentic turns per invocation")
   (timeout :initarg :timeout
            :accessor provider-timeout
            :initform 300
            :documentation "Timeout in seconds for subprocess execution")
   (env :initarg :env
        :accessor provider-env
        :initform nil
        :documentation "Environment variables as alist of (name . value)")
   (extra-args :initarg :extra-args
               :accessor provider-extra-args
               :initform nil
               :documentation "Additional CLI arguments")
   (lock :initarg :lock
         :accessor provider-lock
         :documentation "Lock for thread-safe operations")
   (process :initarg :process
            :accessor provider-process
            :initform nil
            :documentation "Active subprocess (for streaming mode)")
   (input-stream :initarg :input-stream
                 :accessor provider-input-stream
                 :initform nil
                 :documentation "Input stream to subprocess")
   (output-stream :initarg :output-stream
                  :accessor provider-output-stream
                  :initform nil
                  :documentation "Output stream from subprocess")
   (session-id :initarg :session-id
               :accessor provider-session-id
               :initform nil
               :documentation "Session ID for streaming mode"))
  (:documentation "Abstract base class for CLI coding tool providers.

Providers wrap external CLI tools as inference engines. Each provider
knows how to build commands, parse output, and manage sessions for
its specific tool."))

(defmethod initialize-instance :after ((provider provider) &key)
  "Initialize the lock for the provider."
  (unless (slot-boundp provider 'lock)
    (setf (provider-lock provider)
          (bt:make-lock (format nil "provider-~a" (provider-name provider))))))

(defmethod print-object ((provider provider) stream)
  (print-unreadable-object (provider stream :type t)
    (format stream "~a (~a)" (provider-name provider) (provider-command provider))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider Protocol (Generic Functions)
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric provider-supported-modes (provider)
  (:documentation "Return list of supported invocation modes (e.g., '(:one-shot :streaming)).")
  (:method ((provider provider))
    '(:one-shot)))

(defgeneric provider-invoke (provider prompt &key tools mode agent-id)
  (:documentation "Invoke the provider with PROMPT. Returns a provider-result.

   TOOLS - List of tool specifications to make available
   MODE - :one-shot (default) or :streaming
   AGENT-ID - Optional agent ID for event tracking")
  (:method ((provider provider) prompt &key tools mode agent-id)
    (declare (ignore mode))
    ;; Default one-shot implementation
    (emit-integration-event :provider-request
                            (intern (string-upcase (provider-name provider)) :keyword)
                            (list :prompt (truncate-string (format nil "~a" prompt) 200)
                                  :tools (length (or tools nil)))
                            :agent-id agent-id)
    (multiple-value-bind (command args)
        (provider-build-command provider prompt :tools tools)
      (let ((start-time (get-internal-real-time)))
        (multiple-value-bind (stdout stderr exit-code)
            (run-provider-subprocess command args
                                     :working-directory (provider-working-directory provider)
                                     :env (provider-env provider)
                                     :timeout (provider-timeout provider))
          (let ((duration (/ (- (get-internal-real-time) start-time)
                             internal-time-units-per-second))
                (result (provider-parse-output provider stdout)))
            ;; Fill in fields the parser might not set
            (setf (provider-result-exit-code result) exit-code
                  (provider-result-error-output result) stderr
                  (provider-result-raw-output result) stdout
                  (provider-result-duration result) duration
                  (provider-result-provider-name result) (provider-name provider))
            (emit-integration-event :provider-response
                                    (intern (string-upcase (provider-name provider)) :keyword)
                                    (list :exit-code exit-code
                                          :duration duration
                                          :text-length (length (or (provider-result-text result) ""))
                                          :cost (provider-result-cost result))
                                    :agent-id agent-id)
            result))))))

(defgeneric provider-build-command (provider prompt &key tools)
  (:documentation "Build the CLI command and argument list for invoking this provider.
   Returns (values command args-list).")
  (:method ((provider provider) prompt &key tools)
    (declare (ignore prompt tools))
    (values (provider-command provider) (copy-list (provider-extra-args provider)))))

(defgeneric provider-parse-output (provider raw-output)
  (:documentation "Parse the raw output from the provider subprocess into a provider-result.")
  (:method ((provider provider) raw-output)
    (make-instance 'provider-result
                   :text raw-output
                   :provider-name (provider-name provider))))

(defgeneric provider-format-tools (provider tools)
  (:documentation "Format tool specifications for this provider's CLI format.
   Default extracts \"name\" from each tool alist.")
  (:method ((provider provider) tools)
    (loop for tool in tools
          when (and (listp tool) (assoc "name" tool :test #'string=))
            collect (cdr (assoc "name" tool :test #'string=))
          when (stringp tool)
            collect tool)))

(defgeneric provider-alive-p (provider)
  (:documentation "Return T if the provider's streaming session is alive.")
  (:method ((provider provider))
    (and (provider-process provider)
         (sb-ext:process-alive-p (provider-process provider)))))

(defgeneric provider-start-session (provider)
  (:documentation "Start a streaming session with this provider.")
  (:method ((provider provider))
    (error 'autopoiesis.core:autopoiesis-error
           :message (format nil "Provider ~a does not support streaming sessions"
                            (provider-name provider)))))

(defgeneric provider-send (provider message)
  (:documentation "Send a message to the provider's streaming session.")
  (:method ((provider provider) message)
    (declare (ignore message))
    (error 'autopoiesis.core:autopoiesis-error
           :message (format nil "Provider ~a does not support streaming sessions"
                            (provider-name provider)))))

(defgeneric provider-send-streaming (provider message on-text-delta)
  (:documentation "Send a message with streaming output. ON-TEXT-DELTA is called
   with each text fragment as it arrives. Returns the full provider-result.
   Default falls back to non-streaming provider-send.")
  (:method ((provider provider) message on-text-delta)
    (declare (ignore on-text-delta))
    (provider-send provider message)))

(defgeneric provider-stop-session (provider)
  (:documentation "Stop the provider's streaming session.")
  (:method ((provider provider))
    (when (provider-process provider)
      (ignore-errors
        (when (provider-input-stream provider)
          (close (provider-input-stream provider))))
      (ignore-errors
        (sb-ext:process-kill (provider-process provider) sb-unix:sigterm))
      (setf (provider-process provider) nil
            (provider-input-stream provider) nil
            (provider-output-stream provider) nil
            (provider-session-id provider) nil))))

(defgeneric provider-to-sexpr (provider)
  (:documentation "Serialize provider configuration to S-expression (not process state).")
  (:method ((provider provider))
    `(:provider
      :type ,(type-of provider)
      :name ,(provider-name provider)
      :command ,(provider-command provider)
      :working-directory ,(provider-working-directory provider)
      :default-model ,(provider-default-model provider)
      :max-turns ,(provider-max-turns provider)
      :timeout ,(provider-timeout provider)
      :extra-args ,(provider-extra-args provider))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *provider-registry* (make-hash-table :test 'equal)
  "Global registry of providers by name.")

(defun register-provider (provider)
  "Register PROVIDER in the global registry. Returns PROVIDER."
  (setf (gethash (provider-name provider) *provider-registry*) provider)
  provider)

(defun unregister-provider (name)
  "Unregister a provider by NAME. Returns T if found, NIL otherwise."
  (remhash name *provider-registry*))

(defun find-provider (name)
  "Find a provider by NAME in the registry. Returns NIL if not found."
  (gethash name *provider-registry*))

(defun list-providers ()
  "List all registered providers. Returns a list of provider instances."
  (loop for provider being the hash-values of *provider-registry*
        collect provider))

(defun provider-status (provider)
  "Return a plist describing the provider's current status."
  (list :name (provider-name provider)
        :command (provider-command provider)
        :modes (provider-supported-modes provider)
        :alive (provider-alive-p provider)
        :session-id (provider-session-id provider)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Subprocess Execution
;;; ═══════════════════════════════════════════════════════════════════

(defun run-provider-subprocess (command args &key working-directory env timeout input)
  "Run a provider subprocess and return its output.

   COMMAND - The program to run
   ARGS - List of string arguments
   WORKING-DIRECTORY - Working directory for the process
   ENV - Alist of (name . value) environment variables
   TIMEOUT - Timeout in seconds (default 300)
   INPUT - Optional string to send to stdin

   Returns (values stdout stderr exit-code).
   On timeout, sends SIGTERM then SIGKILL after 5s."
  (let* ((timeout (or timeout 300))
         (env-list (when env
                     (append (loop for (k . v) in env
                                   collect (format nil "~a=~a" k v))
                             (sb-ext:posix-environ))))
         (process (sb-ext:run-program command args
                                      :input (if input :stream nil)
                                      :output :stream
                                      :error :stream
                                      :wait nil
                                      :search t
                                      :directory working-directory
                                      :environment (or env-list
                                                       (sb-ext:posix-environ)))))
    (unless process
      (error 'autopoiesis.core:autopoiesis-error
             :message (format nil "Failed to start provider process: ~a" command)))

    ;; Send input if provided
    (when input
      (let ((stdin (sb-ext:process-input process)))
        (write-string input stdin)
        (close stdin)))

    ;; Read output with timeout
    (let ((stdout-result "")
          (stderr-result "")
          (stdout-stream (sb-ext:process-output process))
          (stderr-stream (sb-ext:process-error process))
          (deadline (+ (get-internal-real-time)
                       (* timeout internal-time-units-per-second))))
      ;; Read in threads to avoid deadlock
      (let ((stdout-thread
              (bt:make-thread
               (lambda ()
                 (with-output-to-string (s)
                   (loop for line = (read-line stdout-stream nil nil)
                         while line
                         do (write-line line s))))
               :name "provider-stdout"))
            (stderr-thread
              (bt:make-thread
               (lambda ()
                 (with-output-to-string (s)
                   (loop for line = (read-line stderr-stream nil nil)
                         while line
                         do (write-line line s))))
               :name "provider-stderr")))
        ;; Wait for completion or timeout
        (loop
          (when (not (sb-ext:process-alive-p process))
            (return))
          (when (> (get-internal-real-time) deadline)
            ;; Timeout - kill process
            (ignore-errors (sb-ext:process-kill process sb-unix:sigterm))
            (sleep 5)
            (when (sb-ext:process-alive-p process)
              (ignore-errors (sb-ext:process-kill process sb-unix:sigkill)))
            (return))
          (sleep 0.1))

        ;; Collect results
        (setf stdout-result (bt:join-thread stdout-thread))
        (setf stderr-result (bt:join-thread stderr-thread))

        ;; Get exit code
        (let ((exit-code (sb-ext:process-exit-code process)))
          (sb-ext:process-close process)
          (values stdout-result stderr-result (or exit-code -1)))))))

(defun run-provider-subprocess-streaming (command args &key working-directory env timeout
                                                          on-stdout-line on-complete)
  "Run a provider subprocess, calling ON-STDOUT-LINE for each output line as it arrives.

   COMMAND - The program to run
   ARGS - List of string arguments
   WORKING-DIRECTORY - Working directory for the process
   ENV - Alist of (name . value) environment variables
   TIMEOUT - Timeout in seconds (default 300)
   ON-STDOUT-LINE - (lambda (line)) called for each stdout line in real-time
   ON-COMPLETE - (lambda (exit-code)) called when process finishes

   Returns (values full-stdout stderr exit-code)."
  (let* ((timeout (or timeout 300))
         (env-list (when env
                     (append (loop for (k . v) in env
                                   collect (format nil "~a=~a" k v))
                             (sb-ext:posix-environ))))
         (process (sb-ext:run-program command args
                                      :input nil
                                      :output :stream
                                      :error :stream
                                      :wait nil
                                      :search t
                                      :directory working-directory
                                      :environment (or env-list
                                                       (sb-ext:posix-environ)))))
    (unless process
      (error 'autopoiesis.core:autopoiesis-error
             :message (format nil "Failed to start streaming provider process: ~a" command)))

    (let ((stdout-result "")
          (stderr-result "")
          (stdout-stream (sb-ext:process-output process))
          (stderr-stream (sb-ext:process-error process))
          (deadline (+ (get-internal-real-time)
                       (* timeout internal-time-units-per-second))))
      ;; Stdout reader: calls on-stdout-line per line AND accumulates
      (let ((stdout-thread
              (bt:make-thread
               (lambda ()
                 (with-output-to-string (s)
                   (loop for line = (read-line stdout-stream nil nil)
                         while line
                         do (write-line line s)
                            (when on-stdout-line
                              (ignore-errors (funcall on-stdout-line line))))))
               :name "provider-stdout-streaming"))
            (stderr-thread
              (bt:make-thread
               (lambda ()
                 (with-output-to-string (s)
                   (loop for line = (read-line stderr-stream nil nil)
                         while line
                         do (write-line line s))))
               :name "provider-stderr-streaming")))
        ;; Wait for completion or timeout
        (loop
          (when (not (sb-ext:process-alive-p process))
            (return))
          (when (> (get-internal-real-time) deadline)
            (ignore-errors (sb-ext:process-kill process sb-unix:sigterm))
            (sleep 5)
            (when (sb-ext:process-alive-p process)
              (ignore-errors (sb-ext:process-kill process sb-unix:sigkill)))
            (return))
          (sleep 0.1))

        (setf stdout-result (bt:join-thread stdout-thread))
        (setf stderr-result (bt:join-thread stderr-thread))

        (let ((exit-code (sb-ext:process-exit-code process)))
          (sb-ext:process-close process)
          (when on-complete
            (ignore-errors (funcall on-complete (or exit-code -1))))
          (values stdout-result stderr-result (or exit-code -1)))))))
