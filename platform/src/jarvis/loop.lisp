;;;; loop.lisp - Jarvis conversation loop
;;;;
;;;; Main entry points for starting, stopping, and prompting a Jarvis session.
;;;; Handles the NL->tool dispatch cycle: user prompt -> Pi RPC -> tool call
;;;; -> tool result -> Pi follow-up -> text response.

(in-package #:autopoiesis.jarvis)

;;; ===================================================================
;;; Session Lifecycle
;;; ===================================================================

(defun start-jarvis (&key agent pi-config tools)
  "Start a Jarvis session.

   AGENT - the backing agent (created if nil)
   PI-CONFIG - plist of Pi provider config (:model, :thinking, etc.)
   TOOLS - list of capability names to make available (nil = all registered)

   Returns a jarvis-session ready for prompting."
  (let* ((the-agent (or agent
                        (autopoiesis.agent:make-agent :name "jarvis")))
         (provider (when (find-package :autopoiesis.integration)
                     (let ((pi-class (find-symbol "PI-PROVIDER"
                                                  :autopoiesis.integration)))
                       (when pi-class
                         (let ((p (make-instance pi-class
                                                 :name "jarvis-pi"
                                                 :command "pi")))
                           ;; Configure model from pi-config
                           (when (getf pi-config :model)
                             (let ((model-slot (find-symbol "DEFAULT-MODEL"
                                                            :autopoiesis.integration)))
                               (when model-slot
                                 (setf (slot-value p model-slot)
                                       (getf pi-config :model)))))
                           ;; Configure thinking level
                           (when (getf pi-config :thinking)
                             (let ((thinking-slot (find-symbol "THINKING"
                                                               :autopoiesis.integration)))
                               (when thinking-slot
                                 (ignore-errors
                                   (setf (slot-value p thinking-slot)
                                         (getf pi-config :thinking))))))
                           p)))))
         (tool-ctx (or tools
                       (mapcar #'autopoiesis.agent:capability-name
                               (autopoiesis.agent:list-capabilities))))
         (session (make-jarvis-session :agent the-agent
                                       :pi-provider provider
                                       :tool-context tool-ctx)))
    ;; Start Pi RPC session if provider available
    (when provider
      (let ((start-fn (find-symbol "PROVIDER-START-SESSION"
                                   :autopoiesis.integration)))
        (when start-fn
          (ignore-errors (funcall start-fn provider)))))
    session))

(defun start-jarvis-with-team (&key agent pi-config tools)
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
    (start-jarvis :agent agent :pi-config pi-config :tools all-tools)))

(defun stop-jarvis (session)
  "Stop a Jarvis session and clean up the Pi process.

   Returns T on success."
  (let ((provider (jarvis-pi-provider session)))
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
   2. Send to Pi RPC (or echo if no provider)
   3. If Pi returns a tool call, dispatch it and feed the result back
   4. Record and return the final text response

   Returns the final text response string."
  ;; Record user message
  (push (cons :user user-input) (jarvis-conversation-history session))

  (let ((provider (jarvis-pi-provider session)))
    (if (null provider)
        ;; No provider - return echo for testing
        (let ((response (format nil "[no-provider] Received: ~a" user-input)))
          (push (cons :assistant response)
                (jarvis-conversation-history session))
          response)
        ;; Send to Pi and handle response
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
  "Handle a tool call from Pi: dispatch, record, and send result back."
  (let ((tool-result (dispatch-tool-call session tool-name tool-args)))
    (push (cons :tool-result tool-result)
          (jarvis-conversation-history session))
    ;; Send tool result back to Pi for follow-up
    (let ((follow-up (funcall send-fn provider
                              (format nil "Tool result: ~a" tool-result))))
      (let ((text (extract-text follow-up)))
        (push (cons :assistant text)
              (jarvis-conversation-history session))
        text))))

(defun extract-text (result)
  "Extract a text string from a provider result.

   Handles alists with :TEXT or :RESULT keys, or converts to string."
  (cond
    ((stringp result) result)
    ((and (listp result) (assoc :text result))
     (cdr (assoc :text result)))
    ((and (listp result) (assoc :result result))
     (cdr (assoc :result result)))
    (t (format nil "~a" result))))
