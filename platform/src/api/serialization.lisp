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
