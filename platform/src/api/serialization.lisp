;;;; serialization.lisp - JSON serialization for internal objects
;;;;
;;;; Converts Autopoiesis internal objects to JSON-friendly alists
;;;; that cl-json can encode directly.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; JSON Response Helpers
;;; ===================================================================

(defun json-ok (data &key (status 200))
  "Return a JSON response with the given DATA and STATUS code."
  (setf (hunchentoot:content-type*) "application/json")
  (setf (hunchentoot:return-code*) status)
  (cl-json:encode-json-to-string data))

(defun json-error (message &key (status 400) (error-type "Bad Request"))
  "Return a JSON error response."
  (setf (hunchentoot:content-type*) "application/json")
  (setf (hunchentoot:return-code*) status)
  (cl-json:encode-json-to-string
   `((:error . ,error-type) (:message . ,message))))

(defun json-not-found (what id)
  "Return a 404 JSON response."
  (json-error (format nil "~a not found: ~a" what id)
              :status 404 :error-type "Not Found"))

(defun parse-json-body ()
  "Parse the JSON body of the current Hunchentoot request.
   Returns an alist or NIL on parse failure."
  (handler-case
      (let ((body (hunchentoot:raw-post-data :force-text t)))
        (when (and body (> (length body) 0))
          (cl-json:decode-json-from-string body)))
    (error () nil)))

;;; ===================================================================
;;; Object Serialization
;;; ===================================================================

(defun agent-to-json-alist (agent)
  "Convert an agent to a JSON-encodable alist."
  `((:id . ,(agent-id agent))
    (:name . ,(agent-name agent))
    (:state . ,(string-downcase (string (agent-state agent))))
    (:capabilities . ,(or (agent-capabilities agent) #()))
    (:parent . ,(agent-parent agent))
    (:children . ,(or (agent-children agent) #()))
    (:thought--count . ,(autopoiesis.core:stream-length
                         (agent-thought-stream agent)))))

(defun snapshot-to-json-alist (snapshot)
  "Convert a snapshot to a JSON-encodable alist."
  `((:id . ,(snapshot-id snapshot))
    (:timestamp . ,(snapshot-timestamp snapshot))
    (:parent . ,(snapshot-parent snapshot))
    (:hash . ,(snapshot-hash snapshot))
    (:metadata . ,(or (snapshot-metadata snapshot) nil))
    (:agent--state . ,(let ((state (snapshot-agent-state snapshot)))
                        (if state
                            (prin1-to-string state)
                            nil)))))

(defun snapshot-summary-alist (snapshot)
  "Convert a snapshot to a summary alist (no agent-state, for listings)."
  `((:id . ,(snapshot-id snapshot))
    (:timestamp . ,(snapshot-timestamp snapshot))
    (:parent . ,(snapshot-parent snapshot))
    (:hash . ,(snapshot-hash snapshot))
    (:metadata . ,(or (snapshot-metadata snapshot) nil))))

(defun branch-to-json-alist (branch)
  "Convert a branch to a JSON-encodable alist."
  `((:name . ,(branch-name branch))
    (:head . ,(branch-head branch))
    (:created . ,(branch-created branch))))

(defun capability-to-json-alist (cap)
  "Convert a capability to a JSON-encodable alist."
  `((:name . ,(string-downcase (string (capability-name cap))))
    (:description . ,(or (capability-description cap) ""))
    (:parameters . ,(mapcar #'capability-param-to-alist
                            (or (capability-parameters cap) nil)))))

(defun capability-param-to-alist (param)
  "Convert a capability parameter spec to an alist."
  (cond
    ((and (listp param) (>= (length param) 2))
     `((:name . ,(string-downcase (string (first param))))
       (:type . ,(string-downcase (string (second param))))))
    ((symbolp param)
     `((:name . ,(string-downcase (string param)))
       (:type . "any")))
    (t `((:name . ,(prin1-to-string param))
         (:type . "any")))))

(defun blocking-request-to-json-alist (request)
  "Convert a blocking input request to a JSON-encodable alist."
  `((:id . ,(blocking-request-id request))
    (:prompt . ,(blocking-request-prompt request))
    (:context . ,(blocking-request-context request))
    (:options . ,(or (blocking-request-options request) #()))
    (:status . ,(string-downcase (string (blocking-request-status request))))
    (:default . ,(blocking-request-default request))
    (:created--at . ,(autopoiesis.interface::blocking-request-created request))))

(defun thought-to-json-alist (thought)
  "Convert a thought to a JSON-encodable alist."
  `((:id . ,(autopoiesis.core:thought-id thought))
    (:type . ,(string-downcase
               (string (autopoiesis.core:thought-type thought))))
    (:content . ,(prin1-to-string (autopoiesis.core:thought-content thought)))
    (:confidence . ,(autopoiesis.core:thought-confidence thought))
    (:timestamp . ,(autopoiesis.core:thought-timestamp thought))))

(defun event-to-json-alist (event)
  "Convert an integration event to a JSON-encodable alist."
  `((:id . ,(autopoiesis.integration:integration-event-id event))
    (:type . ,(string-downcase
               (string (autopoiesis.integration:integration-event-kind event))))
    (:source . ,(string-downcase
                 (string (autopoiesis.integration:integration-event-source event))))
    (:agent--id . ,(autopoiesis.integration:integration-event-agent-id event))
    (:data . ,(let ((d (autopoiesis.integration:integration-event-data event)))
                (if d (prin1-to-string d) nil)))
    (:timestamp . ,(autopoiesis.integration:integration-event-timestamp event))))

;;; ===================================================================
;;; Command Center Serialization
;;; ===================================================================

(defun department-to-json-alist (eid)
  "Convert a department entity to a JSON-encodable alist."
  (let ((state (autopoiesis.substrate:entity-state eid)))
    `((:id . ,eid)
      (:name . ,(getf state :department/name))
      (:parent . ,(getf state :department/parent))
      (:description . ,(getf state :department/description))
      (:budget--limit . ,(getf state :department/budget-limit))
      (:currency . ,(getf state :department/currency))
      (:created--at . ,(getf state :department/created-at)))))

(defun goal-to-json-alist (eid)
  "Convert a goal entity to a JSON-encodable alist."
  (let ((state (autopoiesis.substrate:entity-state eid)))
    `((:id . ,eid)
      (:title . ,(getf state :goal/title))
      (:description . ,(getf state :goal/description))
      (:department . ,(getf state :goal/department))
      (:agent . ,(getf state :goal/agent))
      (:status . ,(string-downcase (string (or (getf state :goal/status) :unknown))))
      (:parent . ,(getf state :goal/parent))
      (:created--at . ,(getf state :goal/created-at)))))

(defun budget-to-json-alist (eid)
  "Convert a budget entity to a JSON-encodable alist."
  (let ((state (autopoiesis.substrate:entity-state eid)))
    `((:id . ,eid)
      (:entity--id . ,(getf state :budget/target-id))
      (:entity--type . ,(string-downcase (string (or (getf state :budget/target-type) :unknown))))
      (:limit . ,(getf state :budget/limit))
      (:spent . ,(getf state :budget/spent))
      (:currency . ,(getf state :budget/currency))
      (:updated--at . ,(getf state :budget/updated-at)))))

;;; ===================================================================
;;; Eval Lab Serialization (uses autopoiesis.eval if loaded)
;;; ===================================================================

(defun eval-scenario-to-json-alist (eid)
  "Convert an eval-scenario entity to a JSON-encodable alist."
  (let ((pkg (find-package :autopoiesis.eval)))
    (if pkg
        (let ((fn (find-symbol "SCENARIO-TO-ALIST" pkg)))
          (when (and fn (fboundp fn))
            (funcall fn eid)))
        ;; Fallback: read directly from substrate
        `((:id . ,eid)
          (:name . ,(autopoiesis.substrate:entity-attr eid :eval-scenario/name))))))

(defun eval-run-to-json-alist (eid)
  "Convert an eval-run entity to a JSON-encodable alist."
  (let ((pkg (find-package :autopoiesis.eval)))
    (if pkg
        (let ((fn (find-symbol "RUN-TO-ALIST" pkg)))
          (when (and fn (fboundp fn))
            (funcall fn eid)))
        `((:id . ,eid)
          (:name . ,(autopoiesis.substrate:entity-attr eid :eval-run/name))))))

(defun eval-trial-to-json-alist (eid)
  "Convert an eval-trial entity to a JSON-encodable alist."
  (let ((pkg (find-package :autopoiesis.eval)))
    (if pkg
        (let ((fn (find-symbol "TRIAL-TO-ALIST" pkg)))
          (when (and fn (fboundp fn))
            (funcall fn eid)))
        `((:id . ,eid)))))

;;; --- Eval WS serializers (hash-table) ---

(defun eval-scenario-to-json-plist (eid)
  "Convert an eval-scenario to a hash-table for WS."
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash "id" ht) eid
          (gethash "name" ht) (autopoiesis.substrate:entity-attr eid :eval-scenario/name)
          (gethash "description" ht) (autopoiesis.substrate:entity-attr eid :eval-scenario/description)
          (gethash "prompt" ht) (autopoiesis.substrate:entity-attr eid :eval-scenario/prompt)
          (gethash "domain" ht) (let ((d (autopoiesis.substrate:entity-attr eid :eval-scenario/domain)))
                                   (when d (string-downcase (symbol-name d))))
          (gethash "hasVerifier" ht) (if (autopoiesis.substrate:entity-attr eid :eval-scenario/verifier) t nil)
          (gethash "hasRubric" ht) (if (autopoiesis.substrate:entity-attr eid :eval-scenario/rubric) t nil)
          (gethash "createdAt" ht) (autopoiesis.substrate:entity-attr eid :eval-scenario/created-at))
    ht))

(defun eval-run-to-json-plist (eid)
  "Convert an eval-run to a hash-table for WS."
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash "id" ht) eid
          (gethash "name" ht) (autopoiesis.substrate:entity-attr eid :eval-run/name)
          (gethash "status" ht) (string-downcase (symbol-name (or (autopoiesis.substrate:entity-attr eid :eval-run/status) :unknown)))
          (gethash "scenarios" ht) (autopoiesis.substrate:entity-attr eid :eval-run/scenarios)
          (gethash "harnesses" ht) (autopoiesis.substrate:entity-attr eid :eval-run/harnesses)
          (gethash "trialsPerCombo" ht) (autopoiesis.substrate:entity-attr eid :eval-run/trials)
          (gethash "createdAt" ht) (autopoiesis.substrate:entity-attr eid :eval-run/created-at)
          (gethash "completedAt" ht) (autopoiesis.substrate:entity-attr eid :eval-run/completed-at))
    ht))

(defun eval-trial-to-json-plist (eid)
  "Convert an eval-trial to a hash-table for WS."
  (let ((ht (make-hash-table :test 'equal)))
    (setf (gethash "id" ht) eid
          (gethash "runId" ht) (autopoiesis.substrate:entity-attr eid :eval-trial/run)
          (gethash "scenarioId" ht) (autopoiesis.substrate:entity-attr eid :eval-trial/scenario)
          (gethash "harnessName" ht) (autopoiesis.substrate:entity-attr eid :eval-trial/harness)
          (gethash "trialNum" ht) (autopoiesis.substrate:entity-attr eid :eval-trial/trial-num)
          (gethash "status" ht) (string-downcase (symbol-name (or (autopoiesis.substrate:entity-attr eid :eval-trial/status) :unknown)))
          (gethash "duration" ht) (autopoiesis.substrate:entity-attr eid :eval-trial/duration)
          (gethash "cost" ht) (autopoiesis.substrate:entity-attr eid :eval-trial/cost)
          (gethash "turns" ht) (autopoiesis.substrate:entity-attr eid :eval-trial/turns)
          (gethash "passed" ht) (let ((p (autopoiesis.substrate:entity-attr eid :eval-trial/passed)))
                                   (when p (string-downcase (symbol-name p))))
          (gethash "judgeScores" ht) (autopoiesis.substrate:entity-attr eid :eval-trial/judge-scores)
          (gethash "completedAt" ht) (autopoiesis.substrate:entity-attr eid :eval-trial/completed-at))
    ht))

;;; --- Hash-table serializers for WS handlers ---

(defun department-to-json-plist (eid)
  "Convert a department entity to a hash-table for WS response."
  (let ((state (autopoiesis.substrate:entity-state eid))
        (ht (make-hash-table :test 'equal)))
    (setf (gethash "id" ht) eid
          (gethash "name" ht) (getf state :department/name)
          (gethash "parent" ht) (getf state :department/parent)
          (gethash "description" ht) (getf state :department/description)
          (gethash "budgetLimit" ht) (getf state :department/budget-limit)
          (gethash "currency" ht) (getf state :department/currency)
          (gethash "createdAt" ht) (getf state :department/created-at))
    ht))

(defun goal-to-json-plist (eid)
  "Convert a goal entity to a hash-table for WS response."
  (let ((state (autopoiesis.substrate:entity-state eid))
        (ht (make-hash-table :test 'equal)))
    (setf (gethash "id" ht) eid
          (gethash "title" ht) (getf state :goal/title)
          (gethash "description" ht) (getf state :goal/description)
          (gethash "department" ht) (getf state :goal/department)
          (gethash "agent" ht) (getf state :goal/agent)
          (gethash "status" ht) (string-downcase (string (or (getf state :goal/status) :unknown)))
          (gethash "parent" ht) (getf state :goal/parent)
          (gethash "createdAt" ht) (getf state :goal/created-at))
    ht))

(defun budget-to-json-plist (eid)
  "Convert a budget entity to a hash-table for WS response."
  (let ((state (autopoiesis.substrate:entity-state eid))
        (ht (make-hash-table :test 'equal)))
    (setf (gethash "id" ht) eid
          (gethash "entityId" ht) (getf state :budget/target-id)
          (gethash "entityType" ht) (string-downcase (string (or (getf state :budget/target-type) :unknown)))
          (gethash "limit" ht) (getf state :budget/limit)
          (gethash "spent" ht) (getf state :budget/spent)
          (gethash "currency" ht) (getf state :budget/currency)
          (gethash "updatedAt" ht) (getf state :budget/updated-at))
    ht))
