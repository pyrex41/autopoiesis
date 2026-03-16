;;;; events.lisp - Integration event system
;;;;
;;;; Provides an event bus for coordination between integrations and the
;;;; core system. Events are emitted when significant actions occur
;;;; (tool calls, API requests, MCP connections) and can be subscribed to
;;;; for logging, monitoring, and triggering side effects like snapshots.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Types
;;; ═══════════════════════════════════════════════════════════════════

(deftype integration-event-type ()
  "Types of events that can be emitted by the integration layer."
  '(member
    :tool-called          ; A tool/capability was invoked
    :tool-result          ; A tool returned a result
    :claude-request       ; Request sent to Claude API
    :claude-response      ; Response received from Claude API
    :mcp-connected        ; MCP server connected
    :mcp-disconnected     ; MCP server disconnected
    :mcp-tool-call        ; MCP tool was called
    :mcp-error            ; Error from MCP server
    :external-error       ; Error from external service
    :session-created      ; Claude session created
    :session-ended        ; Claude session ended
    :provider-request     ; Request sent to CLI provider
    :provider-response    ; Response received from CLI provider
    :provider-session-started  ; Provider streaming session started
    :provider-session-ended    ; Provider streaming session ended
    :provider-error       ; Error from CLI provider
    :thought-recorded     ; A thought was recorded in an agent's stream
    ;; Team coordination events
    :team-created         ; A new team was created
    :team-started         ; Team began active work
    :team-completed       ; Team completed its task
    :team-failed          ; Team failed its task
    :team-member-joined   ; Agent joined a team
    :team-member-left     ; Agent left a team
    :team-task-assigned   ; Task assigned to team member
    :team-task-completed  ; Team member completed a task
    ;; Paperclip adapter events
    :paperclip-heartbeat-received   ; Paperclip heartbeat received
    :paperclip-heartbeat-responded)) ; Paperclip heartbeat response sent

;;; ═══════════════════════════════════════════════════════════════════
;;; Integration Event Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass integration-event ()
  ((id :initarg :id
       :accessor integration-event-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique identifier for this event")
   (type :initarg :type
         :accessor integration-event-kind
         :type integration-event-type
         :documentation "Type of event")
   (source :initarg :source
           :accessor integration-event-source
           :documentation "What integration/component produced this event (e.g., :claude, :mcp, :builtin)")
   (agent-id :initarg :agent-id
             :accessor integration-event-agent-id
             :initform nil
             :documentation "ID of the agent this event relates to, if any")
   (data :initarg :data
         :accessor integration-event-data
         :initform nil
         :documentation "Event-specific data as a plist")
   (timestamp :initarg :timestamp
              :accessor integration-event-timestamp
              :initform (autopoiesis.core:get-precise-time)
              :documentation "When the event occurred"))
  (:documentation "An event from the integration layer.

Events are emitted when significant actions occur and can be subscribed to
for logging, monitoring, snapshot creation, and other side effects."))

(defun make-integration-event (type source &key agent-id data)
  "Create a new integration event.

   TYPE - Event type (see integration-event-type)
   SOURCE - What produced this event (e.g., :claude, :mcp-servername, :builtin)
   AGENT-ID - Optional agent ID this event relates to
   DATA - Event-specific data as a plist"
  (make-instance 'integration-event
                 :type type
                 :source source
                 :agent-id agent-id
                 :data data))

(defmethod print-object ((event integration-event) stream)
  "Print an integration event in a readable format."
  (print-unreadable-object (event stream :type t)
    (format stream "~a from ~a~@[ agent:~a~]"
            (integration-event-kind event)
            (integration-event-source event)
            (integration-event-agent-id event))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun event-to-sexpr (event)
  "Serialize an integration event to an S-expression."
  `(:integration-event
    :id ,(integration-event-id event)
    :type ,(integration-event-kind event)
    :source ,(integration-event-source event)
    :agent-id ,(integration-event-agent-id event)
    :data ,(integration-event-data event)
    :timestamp ,(integration-event-timestamp event)))

(defun sexpr-to-event (sexpr)
  "Deserialize an integration event from an S-expression."
  (unless (and (listp sexpr) (eq (first sexpr) :integration-event))
    (error 'autopoiesis.core:autopoiesis-error
           :message "Invalid event S-expression"))
  (let ((plist (rest sexpr)))
    (make-instance 'integration-event
                   :id (getf plist :id)
                   :type (getf plist :type)
                   :source (getf plist :source)
                   :agent-id (getf plist :agent-id)
                   :data (getf plist :data)
                   :timestamp (getf plist :timestamp))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Bus
;;; ═══════════════════════════════════════════════════════════════════

(defvar *event-handlers* (make-hash-table :test 'eq)
  "Map from event type to list of handler functions.
Each handler is called with the event as its sole argument.")

(defvar *global-event-handlers* nil
  "List of handlers that receive all events regardless of type.")

(defvar *event-history* nil
  "Recent events for debugging and introspection.")

(defvar *max-event-history* 1000
  "Maximum number of events to keep in history.")

(defvar *events-enabled* t
  "When nil, no events are emitted. Useful for batch operations.")

(defun emit-integration-event (type source data &key agent-id)
  "Emit an integration event.

   TYPE - Event type keyword (see integration-event-type)
   SOURCE - What produced this event
   DATA - Event-specific data as a plist
   AGENT-ID - Optional agent ID this event relates to

   Returns the emitted event, or nil if events are disabled."
  (when *events-enabled*
    (let ((event (make-integration-event type source
                                         :agent-id agent-id
                                         :data data)))
      ;; Add to history
      (push event *event-history*)
      (when (> (length *event-history*) *max-event-history*)
        (setf *event-history* (subseq *event-history* 0 *max-event-history*)))

      ;; Call type-specific handlers
      (dolist (handler (gethash type *event-handlers*))
        (handler-case
            (funcall handler event)
          (error (e)
            (warn "Event handler error for ~a: ~a" type e))))

      ;; Call global handlers
      (dolist (handler *global-event-handlers*)
        (handler-case
            (funcall handler event)
          (error (e)
            (warn "Global event handler error: ~a" e))))

      event)))

(defun subscribe-to-event (type handler)
  "Subscribe HANDLER to events of TYPE.

   HANDLER is a function taking one argument (the event).
   TYPE should be an integration-event-type keyword.

   Returns HANDLER for convenience (can be used to unsubscribe later)."
  (push handler (gethash type *event-handlers*))
  handler)

(defun unsubscribe-from-event (type handler)
  "Unsubscribe HANDLER from events of TYPE.

   Returns T if the handler was found and removed, NIL otherwise."
  (let ((handlers (gethash type *event-handlers*)))
    (when (member handler handlers)
      (setf (gethash type *event-handlers*)
            (remove handler handlers))
      t)))

(defun subscribe-to-all-events (handler)
  "Subscribe HANDLER to receive all events regardless of type.

   Returns HANDLER for convenience."
  (push handler *global-event-handlers*)
  handler)

(defun unsubscribe-from-all-events (handler)
  "Unsubscribe HANDLER from global event handling.

   Returns T if the handler was found and removed, NIL otherwise."
  (when (member handler *global-event-handlers*)
    (setf *global-event-handlers*
          (remove handler *global-event-handlers*))
    t))

(defun clear-event-handlers ()
  "Remove all event handlers. Useful for testing."
  (clrhash *event-handlers*)
  (setf *global-event-handlers* nil))

(defun clear-event-history ()
  "Clear the event history."
  (setf *event-history* nil))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event History Queries
;;; ═══════════════════════════════════════════════════════════════════

(defun get-event-history (&key (limit 100) type source agent-id)
  "Get recent events from history.

   LIMIT - Maximum number of events to return (default 100)
   TYPE - Filter by event type
   SOURCE - Filter by source
   AGENT-ID - Filter by agent ID

   Returns events in reverse chronological order (most recent first)."
  (let ((events *event-history*))
    ;; Apply filters
    (when type
      (setf events (remove-if-not (lambda (e) (eq (integration-event-kind e) type)) events)))
    (when source
      (setf events (remove-if-not (lambda (e) (equal (integration-event-source e) source)) events)))
    (when agent-id
      (setf events (remove-if-not (lambda (e) (equal (integration-event-agent-id e) agent-id)) events)))
    ;; Limit results
    (if (> (length events) limit)
        (subseq events 0 limit)
        events)))

(defun count-events (&key type source since)
  "Count events matching criteria.

   TYPE - Filter by event type
   SOURCE - Filter by source
   SINCE - Only count events after this timestamp

   Returns the count of matching events."
  (let ((events *event-history*))
    (when type
      (setf events (remove-if-not (lambda (e) (eq (integration-event-kind e) type)) events)))
    (when source
      (setf events (remove-if-not (lambda (e) (equal (integration-event-source e) source)) events)))
    (when since
      (setf events (remove-if-not (lambda (e) (> (integration-event-timestamp e) since)) events)))
    (length events)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Convenience Macros
;;; ═══════════════════════════════════════════════════════════════════

(defmacro with-events-disabled (&body body)
  "Execute BODY with event emission disabled.

   Useful for batch operations where generating many events would be
   noisy or cause performance issues."
  `(let ((*events-enabled* nil))
     ,@body))

(defmacro with-event-handler ((type handler) &body body)
  "Execute BODY with a temporary event handler installed.

   TYPE - Event type to subscribe to
   HANDLER - Handler function or form

   The handler is automatically unsubscribed when BODY completes."
  (let ((handler-var (gensym "HANDLER"))
        (type-var (gensym "TYPE")))
    `(let* ((,type-var ,type)
            (,handler-var ,handler))
       (subscribe-to-event ,type-var ,handler-var)
       (unwind-protect
            (progn ,@body)
         (unsubscribe-from-event ,type-var ,handler-var)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Default Event Handlers
;;; ═══════════════════════════════════════════════════════════════════

(defvar *default-handlers-installed* nil
  "Flag indicating whether default handlers have been installed.")

(defun log-tool-called (event)
  "Default handler for tool-called events - logs the call."
  (log:debug "Tool called: ~a by agent ~a, args: ~a"
             (getf (integration-event-data event) :tool)
             (integration-event-agent-id event)
             (getf (integration-event-data event) :arguments)))

(defun log-tool-result (event)
  "Default handler for tool-result events - logs the result."
  (log:debug "Tool result: ~a returned: ~a"
             (getf (integration-event-data event) :tool)
             (autopoiesis.core:truncate-string
              (format nil "~a" (getf (integration-event-data event) :result)) 200)))

(defun log-claude-request (event)
  "Default handler for claude-request events - logs the request."
  (log:debug "Claude request: ~a messages, model: ~a"
             (getf (integration-event-data event) :message-count)
             (getf (integration-event-data event) :model)))

(defun log-claude-response (event)
  "Default handler for claude-response events - logs the response."
  (log:debug "Claude response: ~a, usage: ~a"
             (getf (integration-event-data event) :stop-reason)
             (getf (integration-event-data event) :usage)))

(defun log-mcp-connected (event)
  "Default handler for mcp-connected events - logs the connection."
  (log:info "MCP server connected: ~a"
            (getf (integration-event-data event) :server-name)))

(defun log-mcp-disconnected (event)
  "Default handler for mcp-disconnected events - logs the disconnection."
  (log:info "MCP server disconnected: ~a"
            (getf (integration-event-data event) :server-name)))

(defun log-external-error (event)
  "Default handler for external-error events - logs the error."
  (log:error "External error from ~a: ~a"
             (integration-event-source event)
             (getf (integration-event-data event) :error)))

(defun log-provider-request (event)
  "Default handler for provider-request events - logs the request."
  (log:debug "Provider request to ~a: ~a"
             (integration-event-source event)
             (autopoiesis.core:truncate-string
              (format nil "~a" (getf (integration-event-data event) :prompt)) 100)))

(defun log-provider-response (event)
  "Default handler for provider-response events - logs the response."
  (log:debug "Provider response from ~a: exit ~a, ~,1fs"
             (integration-event-source event)
             (getf (integration-event-data event) :exit-code)
             (getf (integration-event-data event) :duration)))

(defun setup-default-event-handlers ()
  "Set up default event handling.

   Installs handlers for logging and monitoring. Can be called multiple
   times safely - subsequent calls are no-ops."
  (unless *default-handlers-installed*
    ;; Tool events
    (subscribe-to-event :tool-called #'log-tool-called)
    (subscribe-to-event :tool-result #'log-tool-result)

    ;; Claude events
    (subscribe-to-event :claude-request #'log-claude-request)
    (subscribe-to-event :claude-response #'log-claude-response)

    ;; MCP events
    (subscribe-to-event :mcp-connected #'log-mcp-connected)
    (subscribe-to-event :mcp-disconnected #'log-mcp-disconnected)

    ;; Error events
    (subscribe-to-event :external-error #'log-external-error)

    ;; Provider events
    (subscribe-to-event :provider-request #'log-provider-request)
    (subscribe-to-event :provider-response #'log-provider-response)

    (setf *default-handlers-installed* t)))

(defun remove-default-event-handlers ()
  "Remove the default event handlers.

   Useful for testing or when custom handling is desired."
  (when *default-handlers-installed*
    (unsubscribe-from-event :tool-called #'log-tool-called)
    (unsubscribe-from-event :tool-result #'log-tool-result)
    (unsubscribe-from-event :claude-request #'log-claude-request)
    (unsubscribe-from-event :claude-response #'log-claude-response)
    (unsubscribe-from-event :mcp-connected #'log-mcp-connected)
    (unsubscribe-from-event :mcp-disconnected #'log-mcp-disconnected)
    (unsubscribe-from-event :external-error #'log-external-error)
    (unsubscribe-from-event :provider-request #'log-provider-request)
    (unsubscribe-from-event :provider-response #'log-provider-response)
    (setf *default-handlers-installed* nil)))
