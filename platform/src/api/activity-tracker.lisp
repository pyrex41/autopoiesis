;;;; activity-tracker.lisp - Real-time agent activity and cost tracking
;;;;
;;;; Hooks into the integration event bus to track:
;;;;   - Agent activity state (current tool, timing, last active time)
;;;;   - Cost accumulation (tokens, API calls per agent)
;;;;
;;;; Broadcasts live updates to WebSocket clients subscribed to "activity".

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; State
;;; ═══════════════════════════════════════════════════════════════════

(defvar *activity-state* (make-hash-table :test 'equal)
  "Agent-id -> activity plist tracking current tool, timing, call count.
Keys: :current-tool, :tool-start, :last-active, :total-calls, :last-tool-duration.")

(defvar *cost-state* (make-hash-table :test 'equal)
  "Agent-id -> cost plist tracking tokens, cost, calls per agent.
Keys: :total-tokens, :total-cost, :total-calls, :last-duration.")

(defvar *activity-lock* (bt:make-lock "activity-tracker")
  "Lock protecting *activity-state* and *cost-state*.")

(defvar *activity-tracker-handler* nil
  "The global event handler for the activity tracker.
Stored so we can unsubscribe it on shutdown.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Handling
;;; ═══════════════════════════════════════════════════════════════════

(defun handle-activity-event (event)
  "Process an integration event for activity/cost tracking.
Dispatches on event kind to update the appropriate state tables."
  (let ((kind (integration-event-kind event))
        (agent-id (integration-event-agent-id event))
        (data (integration-event-data event))
        (timestamp (integration-event-timestamp event)))
    (when agent-id
      (case kind
        (:tool-called
         (handle-tool-called agent-id data timestamp))
        (:tool-result
         (handle-tool-result agent-id data timestamp))
        (:provider-response
         (handle-provider-response agent-id data timestamp))))))

(defun handle-tool-called (agent-id data timestamp)
  "Update activity state when a tool is called."
  (let ((tool-name (getf data :tool)))
    (bt:with-lock-held (*activity-lock*)
      (let ((state (or (gethash agent-id *activity-state*)
                       (list :current-tool nil
                             :tool-start nil
                             :last-active nil
                             :total-calls 0
                             :last-tool-duration nil))))
        (setf (getf state :current-tool) tool-name
              (getf state :tool-start) timestamp
              (getf state :last-active) timestamp)
        (setf (gethash agent-id *activity-state*) state)))
    ;; Broadcast update outside lock
    (broadcast-activity-update agent-id)))

(defun handle-tool-result (agent-id data timestamp)
  "Update activity state when a tool returns a result."
  (declare (ignore data))
  (bt:with-lock-held (*activity-lock*)
    (let ((state (gethash agent-id *activity-state*)))
      (when state
        (let ((start (getf state :tool-start)))
          (when start
            (setf (getf state :last-tool-duration)
                  (- timestamp start))))
        (setf (getf state :current-tool) nil
              (getf state :tool-start) nil
              (getf state :last-active) timestamp)
        (incf (getf state :total-calls))
        (setf (gethash agent-id *activity-state*) state))))
  ;; Broadcast update outside lock
  (broadcast-activity-update agent-id))

(defun handle-provider-response (agent-id data timestamp)
  "Update cost state when a provider response is received."
  (declare (ignore timestamp))
  (let ((usage (getf data :usage))
        (cost (getf data :cost))
        (duration (getf data :duration)))
    (bt:with-lock-held (*activity-lock*)
      (let ((state (or (gethash agent-id *cost-state*)
                       (list :total-tokens 0
                             :total-cost 0
                             :total-calls 0
                             :last-duration nil))))
        (when usage
          (let ((tokens (if (listp usage)
                            (or (getf usage :total-tokens)
                                (+ (or (getf usage :input-tokens) 0)
                                   (or (getf usage :output-tokens) 0)))
                            usage)))
            (when (numberp tokens)
              (incf (getf state :total-tokens) tokens))))
        (when (and cost (numberp cost))
          (incf (getf state :total-cost) cost))
        (when duration
          (setf (getf state :last-duration) duration))
        (incf (getf state :total-calls))
        (setf (gethash agent-id *cost-state*) state))))
  ;; Broadcast update outside lock
  (broadcast-activity-update agent-id))

;;; ═══════════════════════════════════════════════════════════════════
;;; Broadcasting
;;; ═══════════════════════════════════════════════════════════════════

(defun activity-to-json-alist (agent-id)
  "Return activity + cost data for AGENT-ID as a JSON-friendly alist."
  (bt:with-lock-held (*activity-lock*)
    (let ((activity (gethash agent-id *activity-state*))
          (cost (gethash agent-id *cost-state*)))
      (list (cons "currentTool" (when activity (getf activity :current-tool)))
            (cons "toolStartTime" (when activity (getf activity :tool-start)))
            (cons "lastActive" (when activity (getf activity :last-active)))
            (cons "callCount" (if activity (getf activity :total-calls) 0))
            (cons "duration" (when activity (getf activity :last-tool-duration)))
            (cons "totalCost" (if cost (getf cost :total-cost) 0))
            (cons "tokens" (if cost (getf cost :total-tokens) 0))))))

(defun broadcast-activity-update (agent-id)
  "Broadcast an activity update for AGENT-ID to subscribed WebSocket clients."
  (handler-case
      (broadcast-stream-data
       (ok-response "activity_update"
                    "agentId" agent-id
                    "activity" (activity-to-json-alist agent-id))
       :subscription-type "activity")
    (error (e)
      (log:warn "Activity broadcast error: ~a" e))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Public Query API
;;; ═══════════════════════════════════════════════════════════════════

(defun agent-activity (agent-id)
  "Return the activity plist for AGENT-ID, or NIL if not tracked.
Keys: :current-tool, :tool-start, :last-active, :total-calls, :last-tool-duration."
  (bt:with-lock-held (*activity-lock*)
    (let ((state (gethash agent-id *activity-state*)))
      (when state (copy-list state)))))

(defun all-activities ()
  "Return a list of (agent-id . activity-plist) for all tracked agents."
  (bt:with-lock-held (*activity-lock*)
    (let ((result nil))
      (maphash (lambda (id state)
                 (push (cons id (copy-list state)) result))
               *activity-state*)
      result)))

(defun agent-cost (agent-id)
  "Return the cost plist for AGENT-ID, or NIL if not tracked.
Keys: :total-tokens, :total-cost, :total-calls, :last-duration."
  (bt:with-lock-held (*activity-lock*)
    (let ((state (gethash agent-id *cost-state*)))
      (when state (copy-list state)))))

(defun cost-summary ()
  "Return an aggregate cost summary.
Returns a plist: (:total <total-cost> :per-agent ((id cost calls) ...))."
  (bt:with-lock-held (*activity-lock*)
    (let ((total 0)
          (per-agent nil))
      (maphash (lambda (id state)
                 (let ((cost (getf state :total-cost))
                       (calls (getf state :total-calls)))
                   (when (numberp cost)
                     (incf total cost))
                   (push (list id cost calls) per-agent)))
               *cost-state*)
      (list :total total :per-agent per-agent))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Lifecycle
;;; ═══════════════════════════════════════════════════════════════════

(defun start-activity-tracker ()
  "Install the global event handler for activity and cost tracking.
Subscribes to all integration events and dispatches relevant ones."
  (when *activity-tracker-handler*
    (stop-activity-tracker))
  (setf *activity-tracker-handler*
        (subscribe-to-all-events #'handle-activity-event))
  (log:info "Activity tracker started"))

(defun stop-activity-tracker ()
  "Remove the global event handler and clear tracked state."
  (when *activity-tracker-handler*
    (unsubscribe-from-all-events *activity-tracker-handler*)
    (setf *activity-tracker-handler* nil)
    (bt:with-lock-held (*activity-lock*)
      (clrhash *activity-state*)
      (clrhash *cost-state*))
    (log:info "Activity tracker stopped")))
