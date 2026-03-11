;;;; provider-rho.lisp - Rho AI coding agent CLI provider
;;;;
;;;; Wraps the `rho-cli` tool as an inference provider.
;;;; Supports one-shot mode with --output-format stream-json for structured
;;;; output, and multi-turn sessions via --resume <session-id>.
;;;;
;;;; Unlike the Pi provider which uses a long-lived RPC process,
;;;; rho uses per-turn subprocess invocations with SQLite-backed session
;;;; persistence for continuity.

(in-package #:autopoiesis.integration)

(define-cli-provider :rho
  (:command "rho-cli")
  (:modes (:one-shot :streaming))
  (:default-timeout 600)
  (:documentation "Provider for the rho AI coding agent.

Invokes `rho-cli` with --output-format stream-json for structured output.
Supports Grok, Claude, and any OpenAI-compatible model via rho's model registry.
Multi-turn sessions use --resume with rho's SQLite session persistence.")
  (:extra-slots
    (thinking :initarg :thinking
              :accessor rho-thinking
              :initform nil
              :documentation "Thinking level: off/minimal/low/medium/high")
    (skip-tools :initarg :skip-tools
                :accessor rho-skip-tools
                :initform nil
                :documentation "When T, don't pass --tools (let rho use its own tools)")
    (system-append :initarg :system-append
                   :accessor rho-system-append
                   :initform nil
                   :documentation "Text appended to rho's system prompt"))
  (:build-command (provider prompt &key tools)
    "Build rho-cli command for one-shot invocation."
    (let ((args (list prompt
                      "--output-format" "stream-json")))
      ;; Add model
      (when (provider-default-model provider)
        (setf args (append (list "--model" (provider-default-model provider))
                           args)))
      ;; Add thinking level
      (when (rho-thinking provider)
        (setf args (append (list "--thinking"
                                 (string-downcase
                                  (princ-to-string (rho-thinking provider))))
                           args)))
      ;; Add system-append
      (when (rho-system-append provider)
        (setf args (append (list "--system-append" (rho-system-append provider))
                           args)))
      ;; Add tools restriction (unless skip-tools)
      (when (and tools (not (rho-skip-tools provider)))
        (let ((tool-names (provider-format-tools provider tools)))
          (when tool-names
            (setf args (append (list "--tools"
                                     (format nil "~{~a~^,~}" tool-names))
                               args)))))
      ;; Add working directory
      (when (provider-working-directory provider)
        (setf args (append (list "--directory"
                                 (namestring (provider-working-directory provider)))
                           args)))
      ;; Add any extra args
      (when (provider-extra-args provider)
        (setf args (append args (provider-extra-args provider))))
      (values (provider-command provider) args)))
  (:parse-output :jsonl-events
    ;; Each line is a JSON object with a "type" field.
    ;; Accumulate text_delta into text-parts, track tool calls and completion.
    ("text_delta"
     (let ((text (cdr (assoc :text json))))
       (when text (push text text-parts))))
    ("tool_start"
     (incf turns)
     (push (list :name (cdr (assoc :tool--name json))
                 :id (cdr (assoc :tool--id json))
                 :input (cdr (assoc :input--summary json)))
           tool-calls))
    ("tool_result"
     ;; Update the last tool call with success status
     nil)
    ("session"
     (let ((sid (cdr (assoc :session--id json))))
       (when sid
         (setf (provider-session-id provider) sid))))
    ("complete"
     (let ((sid (cdr (assoc :session--id json))))
       (when sid
         (setf (provider-session-id provider) sid))))))

;;; ===================================================================
;;; Multi-Turn Session Support (via --resume)
;;; ===================================================================

(defmethod provider-start-session ((provider rho-provider))
  "Start a rho session. Unlike Pi, rho doesn't keep a process alive.
   We just mark the session as active; actual process spawning happens per-turn."
  (setf (provider-session-id provider)
        (format nil "rho-~a" (get-universal-time)))
  provider)

(defmethod provider-send ((provider rho-provider) message)
  "Send a message to rho by spawning a new process.
   Uses --resume if we have a session ID from a previous turn."
  (let* ((session-id (provider-session-id provider))
         (args (list message "--output-format" "stream-json")))
    ;; Add model
    (when (provider-default-model provider)
      (setf args (append (list "--model" (provider-default-model provider))
                         args)))
    ;; Add thinking level
    (when (rho-thinking provider)
      (setf args (append (list "--thinking"
                               (string-downcase
                                (princ-to-string (rho-thinking provider))))
                         args)))
    ;; Add system-append
    (when (rho-system-append provider)
      (setf args (append (list "--system-append" (rho-system-append provider))
                         args)))
    ;; Add working directory
    (when (provider-working-directory provider)
      (setf args (append (list "--directory"
                               (namestring (provider-working-directory provider)))
                         args)))
    ;; Resume previous session if we have a real session ID from rho
    ;; (not our synthetic "rho-NNNN" placeholder)
    (when (and session-id (not (search "rho-" session-id)))
      (setf args (append (list "--resume" session-id) args)))
    ;; Add any extra args
    (when (provider-extra-args provider)
      (setf args (append args (provider-extra-args provider))))
    ;; Run subprocess and parse output
    (multiple-value-bind (stdout stderr exit-code)
        (run-provider-subprocess (provider-command provider) args
                                 :timeout (provider-timeout provider)
                                 :working-directory (provider-working-directory provider)
                                 :env (provider-env provider))
      (declare (ignore stderr))
      (let ((result (provider-parse-output provider stdout)))
        ;; Stash exit-code and raw output on the result
        (setf (provider-result-exit-code result) exit-code)
        (setf (provider-result-raw-output result) stdout)
        (setf (provider-result-provider-name result) (provider-name provider))
        result))))

(defmethod provider-stop-session ((provider rho-provider))
  "Stop the rho session. Since rho uses per-turn processes,
   we just clear the session state."
  (setf (provider-session-id provider) nil)
  (setf (provider-process provider) nil)
  provider)
