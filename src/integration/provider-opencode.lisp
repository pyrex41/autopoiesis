;;;; provider-opencode.lisp - OpenCode CLI provider
;;;;
;;;; Wraps the `opencode` CLI tool as an inference provider.
;;;; Supports one-shot CLI mode and optional HTTP server mode.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; OpenCode Provider Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass opencode-provider (provider)
  ((use-server :initarg :use-server
               :accessor opencode-use-server
               :initform nil
               :documentation "Whether to use HTTP server mode")
   (server-port :initarg :server-port
                :accessor opencode-server-port
                :initform 4096
                :documentation "Port for HTTP server mode"))
  (:default-initargs :name "opencode" :command "opencode")
  (:documentation "Provider for the OpenCode CLI tool.

Invokes `opencode run` with --format json for structured output.
Optionally supports HTTP server mode for persistent sessions."))

(defun make-opencode-provider (&key (name "opencode") (command "opencode")
                                 working-directory default-model
                                 (max-turns 10) (timeout 300)
                                 env extra-args
                                 (use-server nil) (server-port 4096))
  "Create an OpenCode provider instance."
  (make-instance 'opencode-provider
                 :name name
                 :command command
                 :working-directory working-directory
                 :default-model default-model
                 :max-turns max-turns
                 :timeout timeout
                 :env env
                 :extra-args extra-args
                 :use-server use-server
                 :server-port server-port))

;;; ═══════════════════════════════════════════════════════════════════
;;; Protocol Implementation
;;; ═══════════════════════════════════════════════════════════════════

(defmethod provider-supported-modes ((provider opencode-provider))
  (if (opencode-use-server provider)
      '(:one-shot :streaming)
      '(:one-shot)))

(defmethod provider-build-command ((provider opencode-provider) prompt &key tools)
  "Build opencode CLI command."
  (declare (ignore tools))
  (let ((args (list "run" prompt "--format" "json")))
    (when (provider-extra-args provider)
      (setf args (append args (provider-extra-args provider))))
    (values (provider-command provider) args)))

(defmethod provider-parse-output ((provider opencode-provider) raw-output)
  "Parse OpenCode JSONL output.

   OpenCode --format json outputs newline-delimited JSON events:
   - type=text with part.text for text content
   - type=tool_call with part for tool invocations
   - type=step_finish with part.cost and part.tokens for metrics"
  (let ((text-parts nil)
        (tool-calls nil)
        (total-cost 0)
        (steps 0))
    (handler-case
        (with-input-from-string (s raw-output)
          (loop for line = (read-line s nil nil)
                while line
                when (and (> (length line) 0)
                          (char= (char line 0) #\{))
                  do (handler-case
                         (let* ((json (cl-json:decode-json-from-string line))
                                (event-type (or (cdr (assoc :type json)) "")))
                           (cond
                             ;; Text content
                             ((string= event-type "text")
                              (let* ((part (cdr (assoc :part json)))
                                     (text (cdr (assoc :text part))))
                                (when text (push text text-parts))))
                             ;; Tool call
                             ((string= event-type "tool_call")
                              (let ((part (cdr (assoc :part json))))
                                (when part
                                  (push (list :name (cdr (assoc :name part))
                                              :input (cdr (assoc :input part)))
                                        tool-calls))))
                             ;; Step finish — extract cost
                             ((string= event-type "step_finish")
                              (let ((part (cdr (assoc :part json))))
                                (when part
                                  (let ((cost (cdr (assoc :cost part))))
                                    (when cost (incf total-cost cost)))
                                  (incf steps))))))
                       (error () nil))))
      (error (e)
        (declare (ignore e))))
    (make-provider-result
     :text (format nil "~{~a~}" (nreverse text-parts))
     :tool-calls (nreverse tool-calls)
     :cost (when (> total-cost 0) total-cost)
     :turns (when (> steps 0) steps))))

(defmethod provider-to-sexpr ((provider opencode-provider))
  "Serialize OpenCode provider configuration."
  (let ((base (call-next-method)))
    (append base
            (list :use-server (opencode-use-server provider)
                  :server-port (opencode-server-port provider)))))
