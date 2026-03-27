;;;; provider-pi.lisp - Pi coding agent CLI provider
;;;;
;;;; Wraps the `pi` CLI tool (Dicklesworthstone/pi_agent_rust) as an
;;;; inference provider. Supports one-shot print mode (-p) and streaming
;;;; RPC mode (--mode rpc) with line-delimited JSON.

(in-package #:autopoiesis.integration)

(define-cli-provider :pi
  (:command "pi")
  (:modes (:one-shot :streaming))
  (:documentation "Provider for the Pi coding agent CLI tool.

Invokes `pi -p` with --mode json for structured one-shot output.
Also supports --mode rpc for streaming line-delimited JSON sessions.")
  (:extra-slots
    (thinking :initarg :thinking
              :accessor pi-thinking
              :initform nil
              :documentation "Thinking level: off/minimal/low/medium/high/xhigh")
    (extension-policy :initarg :extension-policy
                      :accessor pi-extension-policy
                      :initform "safe"
                      :documentation "Extension policy: safe/balanced/permissive"))
  (:build-command (provider prompt &key tools)
    "Build pi CLI command for one-shot invocation."
    (let ((args (list "-p" prompt "--mode" "json")))
      ;; Add thinking level
      (when (pi-thinking provider)
        (setf args (append args (list "--thinking"
                                      (string-downcase
                                       (princ-to-string (pi-thinking provider)))))))
      ;; Add model if specified
      (when (provider-default-model provider)
        (setf args (append args (list "--model" (provider-default-model provider)))))
      ;; Add allowed tools
      (when tools
        (let ((tool-names (provider-format-tools provider tools)))
          (when tool-names
            (setf args (append args (list "--tools"
                                          (format nil "~{~a~^,~}" tool-names)))))))
      ;; Add any extra args
      (when (provider-extra-args provider)
        (setf args (append args (provider-extra-args provider))))
      (values (provider-command provider) args)))
  (:parse-output :json-object
    (:text "result")
    (:cost "cost")
    (:turns "turns")
    (:session-id "session_id")))

;;; ===================================================================
;;; RPC Streaming Session Support
;;; ===================================================================

(defmethod provider-start-session ((provider pi-provider))
  "Start a Pi RPC session by spawning `pi --mode rpc`."
  (let ((args (list "--mode" "rpc")))
    (when (pi-thinking provider)
      (setf args (append args (list "--thinking"
                                    (string-downcase
                                     (princ-to-string (pi-thinking provider)))))))
    (when (provider-default-model provider)
      (setf args (append args (list "--model" (provider-default-model provider)))))
    (let ((process (uiop:launch-program
                    (cons (provider-command provider) args)
                    :input :stream
                    :output :stream
                    :error-output :stream)))
      (setf (provider-process provider) process)
      (setf (provider-session-id provider)
            (format nil "pi-rpc-~a" (get-universal-time)))
      provider)))

(defmethod provider-send ((provider pi-provider) message)
  "Send a prompt message to the Pi RPC session."
  (let ((process (provider-process provider)))
    (when process
      (let ((input (uiop:process-info-input process))
            (json-msg (cl-json:encode-json-to-string
                       `((:type . "prompt") (:message . ,message)))))
        (write-line json-msg input)
        (force-output input)
        ;; Read response line
        (let ((output (uiop:process-info-output process)))
          (let ((line (read-line output nil nil)))
            (when line
              (provider-parse-output provider line))))))))

(defmethod provider-stop-session ((provider pi-provider))
  "Stop the Pi RPC session."
  (let ((process (provider-process provider)))
    (when process
      (ignore-errors
        (let ((input (uiop:process-info-input process)))
          (when input (close input))))
      (ignore-errors (uiop:terminate-process process))
      (ignore-errors (uiop:wait-process process))
      (setf (provider-process provider) nil)
      (setf (provider-session-id provider) nil)))
  provider)
