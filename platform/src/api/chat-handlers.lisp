;;;; chat-handlers.lisp - WebSocket chat handlers bridging to Jarvis sessions
;;;;
;;;; Provides three handlers for chat over WebSocket:
;;;;   start_chat  - Create a Jarvis session for an agent
;;;;   chat_prompt - Send user text to Jarvis (async, spawns worker thread)
;;;;   stop_chat   - Tear down a Jarvis session
;;;;
;;;; Sessions are tracked per-agent-id and cleaned up on connection close.

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *chat-sessions* (make-hash-table :test 'equal)
  "Map from agent-id string to jarvis-session.")

(defvar *chat-sessions-lock* (bordeaux-threads:make-lock "chat-sessions-lock")
  "Lock protecting *chat-sessions* and *chat-session-owners*.")

(defvar *chat-session-owners* (make-hash-table :test 'equal)
  "Map from agent-id string to connection-id that owns the session.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Utility
;;; ═══════════════════════════════════════════════════════════════════

(defun hash-table-to-plist (ht)
  "Convert a string-keyed hash-table to a keyword plist."
  (when ht
    (let ((result nil))
      (maphash (lambda (k v)
                 (push v result)
                 (push (intern (string-upcase k) :keyword) result))
               ht)
      result)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Jarvis bridge (runtime-resolved — jarvis is an optional extension)
;;; ═══════════════════════════════════════════════════════════════════

(defun call-jarvis (fn-name &rest args)
  "Call a function in autopoiesis.jarvis by name, resolving at runtime."
  (let ((fn (and (find-package :autopoiesis.jarvis)
                 (find-symbol (string fn-name) :autopoiesis.jarvis))))
    (unless fn
      (error "Jarvis extension not loaded. Load autopoiesis/jarvis first."))
    (apply fn args)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-start-chat "start_chat" (msg conn)
  (let* ((agent-id (gethash "agentId" msg))
         (config-ht (gethash "providerConfig" msg))
         (provider-config (hash-table-to-plist config-ht)))
    (unless agent-id
      (return-from handle-start-chat
        (error-response "missing_field" "start_chat requires agentId")))
    ;; Check for existing session — idempotent
    (bordeaux-threads:with-lock-held (*chat-sessions-lock*)
      (when (gethash agent-id *chat-sessions*)
        (return-from handle-start-chat
          (ok-response "chat_started"
                       "agentId" agent-id
                       "sessionId" (format nil "~a" agent-id)))))
    ;; Create session
    (let ((session (call-jarvis "START-JARVIS"
                                :provider-config provider-config)))
      (bordeaux-threads:with-lock-held (*chat-sessions-lock*)
        (setf (gethash agent-id *chat-sessions*) session)
        (setf (gethash agent-id *chat-session-owners*) (connection-id conn)))
      (ok-response "chat_started"
                   "agentId" agent-id
                   "sessionId" (format nil "~a" agent-id)))))

(define-handler handle-chat-prompt "chat_prompt" (msg conn)
  (let ((agent-id (gethash "agentId" msg))
        (text (gethash "text" msg))
        (request-id (gethash "requestId" msg)))
    (unless (and agent-id text)
      (return-from handle-chat-prompt
        (error-response "missing_field" "chat_prompt requires agentId and text")))
    ;; Check if this is a running agent with its own runtime
    ;; If so, route the message to the agent's mailbox instead of Jarvis
    (let ((runtime (get-agent-runtime agent-id)))
      (when (and runtime (not (equal agent-id "jarvis")))
        ;; Route to agent's cognitive loop via mailbox
        (handler-case
            (progn
              (send-message-to-agent agent-id text :from "user")
              ;; Subscribe this connection to agent thoughts so they get the response
              (subscribe-connection conn (format nil "agent:~a" agent-id))
              ;; Return acknowledgment — response comes async via broadcast
              (return-from handle-chat-prompt
                (ok-response "chat_prompt_accepted"
                             "agentId" agent-id
                             "routed" "agent")))
          (error (e)
            (return-from handle-chat-prompt
              (error-response "agent_message_error"
                              (format nil "~a" e)))))))
    ;; Fall through to Jarvis session for non-running agents or "jarvis" id
    (let ((session (bordeaux-threads:with-lock-held (*chat-sessions-lock*)
                     (gethash agent-id *chat-sessions*))))
      (unless session
        (return-from handle-chat-prompt
          (error-response "no_session"
                          "No chat session for this agent. Send start_chat first.")))
      ;; Spawn worker — jarvis-prompt-streaming or jarvis-prompt blocks
      (bordeaux-threads:make-thread
       (lambda ()
         (handler-case
             (let ((stream-fn (and (find-package :autopoiesis.jarvis)
                                   (find-symbol "JARVIS-PROMPT-STREAMING"
                                                :autopoiesis.jarvis))))
               (if stream-fn
                   ;; Streaming path
                   (progn
                     ;; Signal stream start
                     (send-to-connection
                      conn
                      (encode-message
                       (let ((r (ok-response "chat_stream_start" "agentId" agent-id)))
                         (when request-id (setf (gethash "requestId" r) request-id))
                         r)))
                     ;; Stream deltas
                     (let ((response-text
                             (funcall stream-fn session text
                                      (lambda (delta)
                                        (let ((msg (ok-response "chat_stream_delta"
                                                                "agentId" agent-id
                                                                "delta" delta)))
                                          (when request-id
                                            (setf (gethash "requestId" msg) request-id))
                                          (ignore-errors
                                            (send-to-connection
                                             conn (encode-message msg))))))))
                       ;; Signal stream end
                       (let ((end-msg (ok-response "chat_stream_end"
                                                   "agentId" agent-id)))
                         (when request-id
                           (setf (gethash "requestId" end-msg) request-id))
                         (send-to-connection conn (encode-message end-msg)))
                       ;; Send full response (or error if empty)
                       (let* ((final-text (if (and response-text
                                                   (not (string= "" response-text)))
                                              response-text
                                              "Provider returned empty response. Check API credentials (XAI_API_KEY) and rho-cli configuration."))
                              (result (ok-response "chat_response"
                                                   "agentId" agent-id
                                                   "text" final-text
                                                   "sessionId" (format nil "~a" agent-id))))
                         (when request-id
                           (setf (gethash "requestId" result) request-id))
                         (send-to-connection conn (encode-message result)))))
                   ;; Non-streaming fallback
                   (let* ((response-text (call-jarvis "JARVIS-PROMPT" session text))
                          (result (ok-response "chat_response"
                                               "agentId" agent-id
                                               "text" response-text
                                               "sessionId" (format nil "~a" agent-id))))
                     (when request-id
                       (setf (gethash "requestId" result) request-id))
                     (send-to-connection conn (encode-message result)))))
           (error (e)
             (let ((err-result (error-response "chat_error"
                                               (format nil "~a" e))))
               (setf (gethash "agentId" err-result) agent-id)
               (when request-id
                 (setf (gethash "requestId" err-result) request-id))
               (ignore-errors
                 (send-to-connection conn (encode-message err-result)))))))
       :name (format nil "chat-worker-~a" agent-id))
      ;; Return NIL — response will be sent async
      nil)))

(define-handler handle-stop-chat "stop_chat" (msg conn)
  (declare (ignore conn))
  (let ((agent-id (gethash "agentId" msg)))
    (unless agent-id
      (return-from handle-stop-chat
        (error-response "missing_field" "stop_chat requires agentId")))
    (let ((session (bordeaux-threads:with-lock-held (*chat-sessions-lock*)
                     (prog1 (gethash agent-id *chat-sessions*)
                       (remhash agent-id *chat-sessions*)
                       (remhash agent-id *chat-session-owners*)))))
      (when session
        (ignore-errors (call-jarvis "STOP-JARVIS" session)))
      (ok-response "chat_stopped" "agentId" agent-id))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Connection Cleanup
;;; ═══════════════════════════════════════════════════════════════════

(defun cleanup-chat-sessions-for-connection (conn)
  "Stop all chat sessions owned by CONN."
  (let ((conn-id (connection-id conn))
        (to-remove nil))
    (bordeaux-threads:with-lock-held (*chat-sessions-lock*)
      (maphash (lambda (agent-id owner-id)
                 (when (equal owner-id conn-id)
                   (push agent-id to-remove)))
               *chat-session-owners*)
      (dolist (agent-id to-remove)
        (let ((session (gethash agent-id *chat-sessions*)))
          (when session
            (ignore-errors (call-jarvis "STOP-JARVIS" session))))
        (remhash agent-id *chat-sessions*)
        (remhash agent-id *chat-session-owners*)))
    (when to-remove
      (log:info "Cleaned up ~d chat sessions for connection ~a"
                (length to-remove) conn-id))))
