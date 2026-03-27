;;;; adapter.lisp - Paperclip AI BYOA adapter core logic
;;;;
;;;; Handles Paperclip heartbeats by mapping them to Autopoiesis agent
;;;; cognitive cycles, with agent registry and budget tracking.

(in-package #:autopoiesis.paperclip)

;;; ===================================================================
;;; Adapter State
;;; ===================================================================

(defvar *paperclip-adapter-loaded* nil
  "Flag indicating the Paperclip adapter is loaded. Checked by REST routes.")

(defvar *paperclip-agents* (make-hash-table :test 'equal)
  "Map from Paperclip role-id (string) to Autopoiesis agent-id (string).")

(defvar *paperclip-agents-lock* (bt:make-lock "paperclip-agents")
  "Lock protecting *paperclip-agents*.")

(defvar *paperclip-budgets* (make-hash-table :test 'equal)
  "Map from role-id (string) to budget plist (:spent :limit :currency).")

(defvar *paperclip-budgets-lock* (bt:make-lock "paperclip-budgets")
  "Lock protecting *paperclip-budgets*.")

(defvar *paperclip-config* '(:default-currency "USD")
  "Adapter configuration plist.")

;;; ===================================================================
;;; Agent Registry
;;; ===================================================================

(defun paperclip-get-or-create-agent (role-id &key capabilities)
  "Look up or create an Autopoiesis agent for a Paperclip role.
   Thread-safe. Returns the agent object."
  (bt:with-lock-held (*paperclip-agents-lock*)
    (let ((existing-id (gethash role-id *paperclip-agents*)))
      (when existing-id
        (let ((agent (autopoiesis.agent:find-agent existing-id)))
          (when agent (return-from paperclip-get-or-create-agent agent)))))
    ;; Create new agent
    (let* ((name (format nil "paperclip:~a" role-id))
           (agent (autopoiesis.agent:make-agent
                   :name name
                   :capabilities capabilities)))
      (autopoiesis.agent:register-agent agent)
      (setf (gethash role-id *paperclip-agents*)
            (autopoiesis.agent:agent-id agent))
      agent)))

(defun paperclip-retire-agent (role-id)
  "Remove a Paperclip-managed agent from the registry.
   Returns T if found and removed, NIL otherwise."
  (bt:with-lock-held (*paperclip-agents-lock*)
    (let ((agent-id (gethash role-id *paperclip-agents*)))
      (when agent-id
        (let ((agent (autopoiesis.agent:find-agent agent-id)))
          (when agent
            (autopoiesis.agent:stop-agent agent)
            (autopoiesis.agent:unregister-agent agent)))
        (remhash role-id *paperclip-agents*)
        t))))

(defun paperclip-list-agents ()
  "Return an alist of (role-id . agent-id) for all Paperclip-managed agents."
  (bt:with-lock-held (*paperclip-agents-lock*)
    (loop for role-id being the hash-keys of *paperclip-agents*
          using (hash-value agent-id)
          collect (cons role-id agent-id))))

;;; ===================================================================
;;; Budget Tracking
;;; ===================================================================

(defun check-paperclip-budget (role-id cost)
  "Check budget status for a role given an additional COST.
   Returns :OK, :WARNING (>=80%), or :EXCEEDED (>=100%)."
  (bt:with-lock-held (*paperclip-budgets-lock*)
    (let ((budget (gethash role-id *paperclip-budgets*)))
      (unless budget
        (return-from check-paperclip-budget :ok))
      (let ((spent (or (getf budget :spent) 0))
            (limit (getf budget :limit)))
        (unless limit
          (return-from check-paperclip-budget :ok))
        (let ((projected (+ spent cost)))
          (cond
            ((>= projected limit) :exceeded)
            ((>= projected (* limit 0.8)) :warning)
            (t :ok)))))))

(defun record-paperclip-cost (role-id cost)
  "Add COST to the accumulated spend for ROLE-ID."
  (bt:with-lock-held (*paperclip-budgets-lock*)
    (let ((budget (or (gethash role-id *paperclip-budgets*)
                      (list :spent 0 :limit nil
                            :currency (getf *paperclip-config* :default-currency)))))
      (setf (getf budget :spent) (+ (or (getf budget :spent) 0) cost))
      (setf (gethash role-id *paperclip-budgets*) budget))))

(defun update-paperclip-budget (role-id &key limit currency)
  "Set budget limit and/or currency for ROLE-ID. Returns the updated budget plist."
  (bt:with-lock-held (*paperclip-budgets-lock*)
    (let ((budget (or (gethash role-id *paperclip-budgets*)
                      (list :spent 0 :limit nil
                            :currency (getf *paperclip-config* :default-currency)))))
      (when limit (setf (getf budget :limit) limit))
      (when currency (setf (getf budget :currency) currency))
      (setf (gethash role-id *paperclip-budgets*) budget)
      budget)))

(defun get-paperclip-budget (role-id)
  "Get current budget plist for ROLE-ID, or NIL if none set."
  (bt:with-lock-held (*paperclip-budgets-lock*)
    (gethash role-id *paperclip-budgets*)))

;;; ===================================================================
;;; Payload Normalization
;;; ===================================================================

(defun normalize-heartbeat-payload (alist)
  "Normalize a heartbeat payload from either Paperclip-native or custom format.
   Paperclip-native sends camelCase keys (agentId, runId, context) which cl-json
   converts to :AGENT-ID, :RUN-ID, :CONTEXT.  Custom format uses underscore keys
   (agent_role, heartbeat_id) which become :AGENT--ROLE, :HEARTBEAT--ID.
   Returns plist (:heartbeat-id :role-id :task :context :estimated-cost)."
  (if (assoc :agent-id alist)
      ;; Paperclip-native: {agentId, runId, context}
      (let* ((agent-id (cdr (assoc :agent-id alist)))
             (run-id (cdr (assoc :run-id alist)))
             (context (cdr (assoc :context alist)))
             (task (when context
                     (or (cdr (assoc :task-key context))
                         (cdr (assoc :task context))))))
        (list :heartbeat-id (or run-id (autopoiesis.core:make-uuid))
              :role-id (or agent-id "default")
              :task task
              :context context
              :estimated-cost 0))
      ;; Custom format: {agent_role, heartbeat_id, task, ...}
      (list :heartbeat-id (or (cdr (assoc :heartbeat--id alist))
                              (autopoiesis.core:make-uuid))
            :role-id (or (cdr (assoc :agent--role alist)) "default")
            :task (cdr (assoc :task alist))
            :context (cdr (assoc :context alist))
            :estimated-cost (or (cdr (assoc :estimated--cost alist)) 0))))

;;; ===================================================================
;;; Heartbeat Handler
;;; ===================================================================

(defun handle-paperclip-heartbeat (heartbeat-alist)
  "Handle a Paperclip heartbeat request.
   Accepts both Paperclip-native format (agentId/runId/context) and
   custom format (agent_role/heartbeat_id/task/estimated_cost/context).
   Returns a response alist suitable for JSON encoding."
  (let* ((normalized (normalize-heartbeat-payload heartbeat-alist))
         (heartbeat-id (getf normalized :heartbeat-id))
         (role-id (getf normalized :role-id))
         (task (getf normalized :task))
         (context (getf normalized :context))
         (estimated-cost (getf normalized :estimated-cost)))
    ;; Emit received event
    (ignore-errors
      (autopoiesis.integration:emit-integration-event
       :paperclip-heartbeat-received :paperclip
       (list :heartbeat-id heartbeat-id :role-id role-id :task task)))
    ;; Check budget
    (let ((budget-status (check-paperclip-budget role-id estimated-cost)))
      (when (eq budget-status :exceeded)
        (return-from handle-paperclip-heartbeat
          `((:heartbeat--id . ,heartbeat-id)
            (:status . "budget_exceeded")
            (:role . ,role-id)
            (:budget--status . "exceeded")))))
    ;; Get or create agent
    (let ((agent (paperclip-get-or-create-agent role-id)))
      ;; Run cognitive cycle if task provided
      (let ((result nil)
            (actual-cost estimated-cost))
        (when (and task (stringp task) (> (length task) 0))
          (handler-case
              (let ((env (if context
                             `(:task ,task :context ,context)
                             `(:task ,task))))
                (setf result (autopoiesis.agent:cognitive-cycle agent env)))
            (error (e)
              (setf result (format nil "Error: ~a" e)))))
        ;; Record cost
        (when (> actual-cost 0)
          (record-paperclip-cost role-id actual-cost))
        ;; Build response
        (let ((response
                `((:heartbeat--id . ,heartbeat-id)
                  (:status . ,(if task "completed" "idle"))
                  (:role . ,role-id)
                  (:agent--id . ,(autopoiesis.agent:agent-id agent))
                  (:result . ,(when result (prin1-to-string result)))
                  (:cost--report . ((:spent . ,actual-cost)
                                    (:budget--status . ,(string-downcase
                                                         (string (check-paperclip-budget role-id 0))))))
                  (:capabilities . ,(mapcar (lambda (c) (string-downcase (string c)))
                                            (autopoiesis.agent:agent-capabilities agent))))))
          ;; Emit responded event
          (ignore-errors
            (autopoiesis.integration:emit-integration-event
             :paperclip-heartbeat-responded :paperclip
             (list :heartbeat-id heartbeat-id :role-id role-id
                   :status (if task "completed" "idle"))))
          response)))))

;;; ===================================================================
;;; Mark adapter as loaded
;;; ===================================================================

(setf *paperclip-adapter-loaded* t)
