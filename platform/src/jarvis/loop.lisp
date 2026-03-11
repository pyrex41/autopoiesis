;;;; loop.lisp - Jarvis conversation loop
;;;;
;;;; Main entry points for starting, stopping, and prompting a Jarvis session.
;;;; Handles the NL->tool dispatch cycle: user prompt -> provider -> tool call
;;;; -> tool result -> provider follow-up -> text response.
;;;;
;;;; Supports any CLI provider that implements provider-start-session,
;;;; provider-send, and provider-stop-session (rho, Pi, etc.)

(in-package #:autopoiesis.jarvis)

;;; ===================================================================
;;; Session Lifecycle
;;; ===================================================================

(defun start-jarvis (&key agent provider provider-config tools)
  "Start a Jarvis session.

   AGENT - the backing agent (created if nil)
   PROVIDER - a provider instance to use (preferred). If nil, creates one
              from PROVIDER-CONFIG or auto-detects (rho > pi).
   PROVIDER-CONFIG - plist to configure auto-created provider:
     :type    - :rho or :pi (default: auto-detect)
     :model   - model ID (e.g. \"grok-4.20-reasoning\")
     :thinking - thinking level for provider
   TOOLS - list of capability names to make available (nil = all registered)

   Returns a jarvis-session ready for prompting."
  (let* ((the-agent (or agent
                        (autopoiesis.agent:make-agent :name "jarvis")))
         (the-provider (or provider
                           (create-default-provider provider-config)))
         (tool-ctx (or tools
                       (mapcar #'autopoiesis.agent:capability-name
                               (autopoiesis.agent:list-capabilities))))
         (session (make-jarvis-session :agent the-agent
                                       :provider the-provider
                                       :tool-context tool-ctx)))
    ;; Start provider session if available
    (when the-provider
      (let ((start-fn (find-symbol "PROVIDER-START-SESSION"
                                   :autopoiesis.integration)))
        (when start-fn
          (ignore-errors (funcall start-fn the-provider)))))
    session))

(defun create-default-provider (config)
  "Create a provider instance from CONFIG plist, or auto-detect.
   Tries rho first (if rho-cli is on PATH), then Pi."
  (let ((provider-type (or (getf config :type)
                           (auto-detect-provider)))
        (model (getf config :model))
        (thinking (getf config :thinking)))
    (when (and provider-type (find-package :autopoiesis.integration))
      (case provider-type
        (:rho
         (let ((rho-class (find-symbol "RHO-PROVIDER" :autopoiesis.integration)))
           (when rho-class
             (let ((p (make-instance rho-class
                                     :name "jarvis-rho"
                                     :command "rho-cli")))
               (when model
                 (setf (slot-value p
                         (find-symbol "DEFAULT-MODEL" :autopoiesis.integration))
                       model))
               (when thinking
                 (ignore-errors
                   (setf (slot-value p
                           (find-symbol "THINKING" :autopoiesis.integration))
                         thinking)))
               p))))
        (:pi
         (let ((pi-class (find-symbol "PI-PROVIDER" :autopoiesis.integration)))
           (when pi-class
             (let ((p (make-instance pi-class
                                     :name "jarvis-pi"
                                     :command "pi")))
               (when model
                 (setf (slot-value p
                         (find-symbol "DEFAULT-MODEL" :autopoiesis.integration))
                       model))
               (when thinking
                 (ignore-errors
                   (setf (slot-value p
                           (find-symbol "THINKING" :autopoiesis.integration))
                         thinking)))
               p))))
        (t nil)))))

(defun auto-detect-provider ()
  "Auto-detect which CLI provider is available. Prefers rho over pi."
  (cond
    ((probe-cli-command "rho-cli") :rho)
    ((probe-cli-command "pi") :pi)
    (t nil)))

(defun probe-cli-command (command)
  "Return T if COMMAND is on PATH."
  (ignore-errors
    (multiple-value-bind (output error-output exit-code)
        (uiop:run-program (list "which" command)
                          :output :string
                          :error-output :string
                          :ignore-error-status t)
      (declare (ignore output error-output))
      (eql exit-code 0))))

(defun start-jarvis-with-team (&key agent provider provider-config tools)
  "Start a Jarvis session with team coordination tools included.
   Same as START-JARVIS but appends team capabilities to the tool list."
  (let* ((team-tools '(autopoiesis.integration::create-team-tool
                       autopoiesis.integration::start-team-work
                       autopoiesis.integration::query-team-tool
                       autopoiesis.integration::await-team
                       autopoiesis.integration::disband-team-tool))
         (ws-team-tools '(autopoiesis.workspace::team-workspace-read
                          autopoiesis.workspace::team-workspace-write
                          autopoiesis.workspace::team-claim-task
                          autopoiesis.workspace::team-submit-result
                          autopoiesis.workspace::team-broadcast))
         (all-tools (append (or tools
                                (mapcar #'autopoiesis.agent:capability-name
                                        (autopoiesis.agent:list-capabilities)))
                            team-tools
                            ws-team-tools)))
    (start-jarvis :agent agent :provider provider
                  :provider-config provider-config :tools all-tools)))

(defun stop-jarvis (session)
  "Stop a Jarvis session and clean up the provider process.

   Returns T on success."
  (let ((provider (jarvis-provider session)))
    (when provider
      (let ((stop-fn (find-symbol "PROVIDER-STOP-SESSION"
                                  :autopoiesis.integration)))
        (when stop-fn
          (ignore-errors (funcall stop-fn provider))))))
  t)

;;; ===================================================================
;;; Conversation Loop
;;; ===================================================================

(defun jarvis-prompt (session user-input)
  "Send user input to Jarvis and get a response.

   Handles the full NL->tool dispatch cycle:
   1. Record user message in conversation history
   2. Send to provider (or echo if no provider)
   3. If provider returns a tool call, dispatch it and feed the result back
   4. Record and return the final text response

   Returns the final text response string."
  ;; Record user message
  (push (cons :user user-input) (jarvis-conversation-history session))

  (let ((provider (jarvis-provider session)))
    (if (null provider)
        ;; No provider - return echo for testing
        (let ((response (format nil "[no-provider] Received: ~a" user-input)))
          (push (cons :assistant response)
                (jarvis-conversation-history session))
          response)
        ;; Send to provider and handle response
        (handler-case
            (let ((send-fn (find-symbol "PROVIDER-SEND"
                                        :autopoiesis.integration)))
              (if (null send-fn)
                  (let ((err "[error] PROVIDER-SEND not found"))
                    (push (cons :error err)
                          (jarvis-conversation-history session))
                    err)
                  (let ((result (funcall send-fn provider user-input)))
                    ;; Check for tool calls in result
                    (multiple-value-bind (tool-name tool-args)
                        (parse-tool-call result)
                      (if tool-name
                          ;; Dispatch tool call and feed result back
                          (handle-tool-call session send-fn provider
                                            tool-name tool-args)
                          ;; No tool call - extract text response
                          (let ((text (extract-text result)))
                            (push (cons :assistant text)
                                  (jarvis-conversation-history session))
                            text))))))
          (error (e)
            (let ((err-msg (format nil "Jarvis error: ~a" e)))
              (push (cons :error err-msg)
                    (jarvis-conversation-history session))
              err-msg))))))

;;; ===================================================================
;;; Internal Helpers
;;; ===================================================================

(defun handle-tool-call (session send-fn provider tool-name tool-args)
  "Handle a tool call from the provider: dispatch, record, and send result back."
  (let ((tool-result (dispatch-tool-call session tool-name tool-args)))
    (push (cons :tool-result tool-result)
          (jarvis-conversation-history session))
    ;; Send tool result back to provider for follow-up
    (let ((follow-up (funcall send-fn provider
                              (format nil "Tool result: ~a" tool-result))))
      (let ((text (extract-text follow-up)))
        (push (cons :assistant text)
              (jarvis-conversation-history session))
        text))))

(defun extract-text (result)
  "Extract a text string from a provider result.

   Handles provider-result objects, alists with :TEXT or :RESULT keys,
   or converts to string."
  (cond
    ((stringp result) result)
    ;; Handle provider-result objects
    ((and (find-package :autopoiesis.integration)
          (let ((result-class (find-symbol "PROVIDER-RESULT"
                                           :autopoiesis.integration)))
            (and result-class (typep result (find-class result-class)))))
     (let ((text-fn (find-symbol "PROVIDER-RESULT-TEXT"
                                 :autopoiesis.integration)))
       (when text-fn (funcall text-fn result))))
    ((and (listp result) (assoc :text result))
     (cdr (assoc :text result)))
    ((and (listp result) (assoc :result result))
     (cdr (assoc :result result)))
    (t (format nil "~a" result))))
