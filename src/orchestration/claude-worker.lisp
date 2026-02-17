;;;; claude-worker.lisp - Claude CLI subprocess driver
;;;;
;;;; Builds command strings, spawns Claude CLI as a subprocess,
;;;; parses stream-json output, extracts results.
;;;; Ported from claude-worker.lfe.

(in-package #:autopoiesis.orchestration)

;;; ===================================================================
;;; Shell quoting
;;; ===================================================================

(defun shell-quote (str)
  "Single-quote a string for shell safety.
   Escapes embedded single quotes: each ' becomes '\\''."
  (format nil "'~A'"
          (with-output-to-string (out)
            (loop for ch across str
                  do (if (char= ch #\')
                         (write-string "'\\''" out)
                         (write-char ch out))))))

;;; ===================================================================
;;; Find Claude executable
;;; ===================================================================

(defun find-claude-executable ()
  "Find the claude binary in PATH. Returns the path or \"claude\" as fallback."
  (let ((path (handler-case
                  (uiop:run-program "which claude"
                                    :output '(:string :stripped t)
                                    :ignore-error-status t)
                (error () nil))))
    (if (and path (not (string= "" path))) path "claude")))

;;; ===================================================================
;;; Build command
;;; ===================================================================

(defun build-claude-command (config)
  "Build a claude CLI command string.
   CONFIG is a plist with keys:
     :prompt :mcp-config :allowed-tools :max-turns :claude-path
   Returns a shell command string."
  (let* ((claude (or (getf config :claude-path) (find-claude-executable)))
         (prompt (or (getf config :prompt) ""))
         (max-turns (or (getf config :max-turns) 50))
         (parts (list claude
                      "-p" (shell-quote prompt)
                      "--output-format" "stream-json"
                      "--verbose"
                      "--max-turns" (write-to-string max-turns)
                      "--dangerously-skip-permissions")))
    (when (getf config :mcp-config)
      (appendf parts (list "--mcp-config" (getf config :mcp-config))))
    (when (getf config :allowed-tools)
      (appendf parts (list "--allowedTools" (getf config :allowed-tools))))
    (format nil "~{~A~^ ~} </dev/null" parts)))

;;; ===================================================================
;;; Run Claude CLI
;;; ===================================================================

(defun run-claude-cli (config &key (timeout 300) on-complete on-error)
  "Run Claude CLI as a subprocess, parse stream-json output.
   Calls ON-COMPLETE with the result plist, or ON-ERROR with the reason.
   Runs in a new thread -- returns the thread."
  (bt:make-thread
   (lambda ()
     (handler-case
         (let* ((command (build-claude-command config))
                (messages nil))
           (let ((process (sb-ext:run-program
                           "/bin/sh" (list "-c" command)
                           :output :stream
                           :error :output
                           :wait nil)))
             (unwind-protect
                  (let ((stdout (sb-ext:process-output process))
                        (deadline (+ (get-internal-real-time)
                                     (* timeout internal-time-units-per-second))))
                    ;; Read stream-json lines
                    (loop for line = (read-line stdout nil nil)
                          while line
                          do (handler-case
                                 (let ((json (cl-json:decode-json-from-string line)))
                                   (push json messages))
                               (error () nil))
                          when (> (get-internal-real-time) deadline)
                            do (sb-ext:process-kill process sb-unix:sigterm)
                               (sleep 2)
                               (when (sb-ext:process-alive-p process)
                                 (sb-ext:process-kill process sb-unix:sigkill))
                               (when on-error
                                 (funcall on-error :timeout))
                               (return))
                    ;; Wait for exit
                    (sb-ext:process-wait process)
                    (let ((exit-code (sb-ext:process-exit-code process)))
                      (if (zerop exit-code)
                          (let ((result (extract-result (nreverse messages))))
                            (when on-complete (funcall on-complete result)))
                          (when on-error
                            (funcall on-error (list :exit-code exit-code))))))
               (ignore-errors (sb-ext:process-close process)))))
       (error (e)
         (when on-error (funcall on-error (format nil "~A" e))))))
   :name "claude-worker"))

;;; ===================================================================
;;; Extract result
;;; ===================================================================

(defun extract-result (messages)
  "Extract the result message from stream-json output.
   MESSAGES is a list of decoded JSON alists.
   Returns the last message with type \"result\", or the last message overall."
  (let ((result-msgs (remove-if-not
                      (lambda (msg)
                        (when (consp msg)
                          (let ((type-entry (assoc :type msg)))
                            (and type-entry
                                 (string= "result" (cdr type-entry))))))
                      messages)))
    (if result-msgs
        (car (last result-msgs))
        (car (last messages)))))

;;; ===================================================================
;;; Prompt file reader
;;; ===================================================================

(defun read-prompt-file (path)
  "Read a prompt file, return default string on failure."
  (handler-case
      (uiop:read-file-string path)
    (error ()
      "Analyze infrastructure and report findings.")))

;;; ===================================================================
;;; Schedule infrastructure watcher
;;; ===================================================================

(defun schedule-infra-watcher (&key (conductor *conductor*)
                                 (interval 300)
                                 (mcp-config "config/cortex-mcp.json"))
  "Schedule the infrastructure watcher to run periodically."
  (let ((prompt (read-prompt-file "config/infra-watcher-prompt.md")))
    (schedule-action conductor interval
                     (list :action-type :claude
                           :id :infra-watcher
                           :prompt prompt
                           :mcp-config (when (probe-file mcp-config)
                                         (namestring (truename mcp-config)))
                           :timeout 120
                           :max-turns 20
                           :allowed-tools (format nil "~{~A~^,~}"
                                                  '("mcp__cortex__cortex_status"
                                                    "mcp__cortex__cortex_schema"
                                                    "mcp__cortex__cortex_query"
                                                    "mcp__cortex__cortex_entity_detail"))))))
