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
