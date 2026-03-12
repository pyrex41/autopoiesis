;;;; routes.lisp - REST API route handlers for external agent control
;;;;
;;;; Provides HTTP endpoints for:
;;;; - Agent lifecycle (create, list, get, pause, resume, stop, cycle)
;;;; - Snapshots (create, list, get, diff)
;;;; - Branches (create, list, switch)
;;;; - Capabilities (list, invoke)
;;;; - Human-in-the-loop (list pending, respond)
;;;; - Thought stream (list recent thoughts)
;;;;
;;;; NOTE: Handler function names use rest- prefix to avoid collision with
;;;; WebSocket handlers defined in handlers.lisp (which use define-handler macro).

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; URL Routing
;;; ===================================================================

(defun extract-path-segment (request prefix)
  "Extract the path segment after PREFIX from REQUEST's URI.
   E.g., for URI '/api/agents/abc123' and prefix '/api/agents/',
   returns 'abc123'."
  (let ((uri (hunchentoot:request-uri request)))
    ;; Strip query string
    (let ((qpos (position #\? uri)))
      (when qpos (setf uri (subseq uri 0 qpos))))
    (when (and (>= (length uri) (length prefix))
               (string= prefix (subseq uri 0 (length prefix))))
      (let ((rest (subseq uri (length prefix))))
        ;; Return up to next slash
        (let ((slash (position #\/ rest)))
          (if slash
              (subseq rest 0 slash)
              rest))))))

(defun path-after-segment (request prefix segment)
  "Get the path portion after a known segment.
   For URI '/api/agents/abc/thoughts' with prefix '/api/agents/' and segment 'abc',
   returns '/thoughts'."
  (let ((uri (hunchentoot:request-uri request)))
    (let ((qpos (position #\? uri)))
      (when qpos (setf uri (subseq uri 0 qpos))))
    (let ((full-prefix (concatenate 'string prefix segment)))
      (when (>= (length uri) (length full-prefix))
        (subseq uri (length full-prefix))))))

;;; ===================================================================
;;; Agent Endpoints
;;; ===================================================================

(defun rest-handle-agents (request)
  "Dispatch /api/agents requests."
  (let ((method (hunchentoot:request-method request))
        (agent-id (extract-path-segment request "/api/agents/")))
    (cond
      ;; GET /api/agents - list all agents
      ((and (eq method :get) (null agent-id))
       (rest-list-agents))
      ;; POST /api/agents - create agent
      ((and (eq method :post) (null agent-id))
       (rest-create-agent))
      ;; GET /api/agents/:id - get agent
      ((and (eq method :get) agent-id)
       (let ((sub-path (path-after-segment request "/api/agents/" agent-id)))
         (cond
           ;; GET /api/agents/:id/thoughts
           ((string= sub-path "/thoughts")
            (rest-agent-thoughts agent-id))
           ;; GET /api/agents/:id/capabilities
           ((string= sub-path "/capabilities")
            (rest-agent-capabilities agent-id))
           ;; GET /api/agents/:id/snapshots
           ((string= sub-path "/snapshots")
            (rest-agent-snapshots agent-id))
           ;; GET /api/agents/:id/pending
           ((string= sub-path "/pending")
            (rest-agent-pending agent-id))
           ;; GET /api/agents/:id
           ((or (null sub-path) (string= sub-path "") (string= sub-path "/"))
            (rest-get-agent agent-id))
           (t (json-not-found "Route" (format nil "/api/agents/~a~a" agent-id sub-path))))))
      ;; POST /api/agents/:id/... - agent actions
      ((and (eq method :post) agent-id)
       (let ((sub-path (path-after-segment request "/api/agents/" agent-id)))
         (cond
           ((string= sub-path "/start")
            (rest-start-agent agent-id))
           ((string= sub-path "/pause")
            (rest-pause-agent agent-id))
           ((string= sub-path "/resume")
            (rest-resume-agent agent-id))
           ((string= sub-path "/stop")
            (rest-stop-agent agent-id))
           ((string= sub-path "/cycle")
            (rest-agent-cycle agent-id))
           ((string= sub-path "/invoke")
            (rest-invoke-capability agent-id))
           ((string= sub-path "/snapshot")
            (rest-take-snapshot agent-id))
           ((string= sub-path "/respond")
            (rest-respond-to-request agent-id))
           (t (json-not-found "Route" (format nil "/api/agents/~a~a" agent-id sub-path))))))
      ;; DELETE /api/agents/:id - remove agent
      ((and (eq method :delete) agent-id)
       (rest-delete-agent agent-id))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

;;; --- Agent Handlers ---

(defun rest-list-agents ()
  "GET /api/agents - List all registered agents."
  (require-permission :read)
  (let ((agents (autopoiesis.agent:list-agents)))
    (json-ok (or (mapcar #'agent-to-json-alist agents) #()))))

(defun rest-create-agent ()
  "POST /api/agents - Create a new agent."
  (require-permission :write)
  (let* ((body (parse-json-body))
         (name (or (cdr (assoc :name body)) "unnamed"))
         (agent (autopoiesis.agent:make-agent :name name)))
    (autopoiesis.agent:register-agent agent)
    (sse-broadcast "agent_created" (agent-to-json-alist agent))
    (json-ok (agent-to-json-alist agent) :status 201)))

(defun rest-get-agent (agent-id)
  "GET /api/agents/:id - Get agent details."
  (require-permission :read)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (if agent
        (json-ok (agent-to-json-alist agent))
        (json-not-found "Agent" agent-id))))

(defun rest-start-agent (agent-id)
  "POST /api/agents/:id/start - Start an agent."
  (require-permission :write)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (if agent
        (progn
          (autopoiesis.agent:start-agent agent)
          (sse-broadcast "agent_started" (agent-to-json-alist agent))
          (json-ok (agent-to-json-alist agent)))
        (json-not-found "Agent" agent-id))))

(defun rest-pause-agent (agent-id)
  "POST /api/agents/:id/pause - Pause an agent."
  (require-permission :write)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (if agent
        (progn
          (autopoiesis.agent:pause-agent agent)
          (sse-broadcast "agent_paused" (agent-to-json-alist agent))
          (json-ok (agent-to-json-alist agent)))
        (json-not-found "Agent" agent-id))))

(defun rest-resume-agent (agent-id)
  "POST /api/agents/:id/resume - Resume a paused agent."
  (require-permission :write)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (if agent
        (progn
          (autopoiesis.agent:resume-agent agent)
          (sse-broadcast "agent_resumed" (agent-to-json-alist agent))
          (json-ok (agent-to-json-alist agent)))
        (json-not-found "Agent" agent-id))))

(defun rest-stop-agent (agent-id)
  "POST /api/agents/:id/stop - Stop an agent."
  (require-permission :write)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (if agent
        (progn
          (autopoiesis.agent:stop-agent agent)
          (sse-broadcast "agent_stopped" (agent-to-json-alist agent))
          (json-ok (agent-to-json-alist agent)))
        (json-not-found "Agent" agent-id))))

(defun rest-delete-agent (agent-id)
  "DELETE /api/agents/:id - Stop and unregister an agent."
  (require-permission :admin)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (if agent
        (progn
          (autopoiesis.agent:stop-agent agent)
          (autopoiesis.agent:unregister-agent agent)
          (sse-broadcast "agent_deleted"
                         `((:id . ,agent-id) (:name . ,(agent-name agent))))
          (json-ok `((:deleted . t) (:id . ,agent-id))))
        (json-not-found "Agent" agent-id))))

(defun rest-agent-cycle (agent-id)
  "POST /api/agents/:id/cycle - Run one cognitive cycle."
  (require-permission :write)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (unless agent
      (return-from rest-agent-cycle (json-not-found "Agent" agent-id)))
    (let* ((body (parse-json-body))
           (env-data (cdr (assoc :environment body)))
           (result (handler-case
                       (autopoiesis.agent:cognitive-cycle agent env-data)
                     (error (e)
                       (declare (ignore e))
                       (return-from rest-agent-cycle
                         (json-error "Cognitive cycle failed"
                                     :status 500 :error-type "Internal Error"))))))
      (sse-broadcast "cycle_complete"
                     `((:agent--id . ,agent-id)
                       (:result . ,(when result (prin1-to-string result)))))
      (json-ok `((:agent--id . ,agent-id)
                 (:state . ,(string-downcase (string (agent-state agent))))
                 (:result . ,(when result (prin1-to-string result))))))))

(defun rest-agent-thoughts (agent-id)
  "GET /api/agents/:id/thoughts - Get recent thoughts."
  (require-permission :read)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (unless agent
      (return-from rest-agent-thoughts (json-not-found "Agent" agent-id)))
    (let* ((limit (or (ignore-errors
                        (parse-integer
                         (or (hunchentoot:get-parameter "limit") "20")))
                      20))
           (stream (agent-thought-stream agent))
           (thoughts (autopoiesis.core:stream-last stream limit)))
      (json-ok (mapcar #'thought-to-json-alist thoughts)))))

;;; ===================================================================
;;; Capability Endpoints
;;; ===================================================================

(defun rest-agent-capabilities (agent-id)
  "GET /api/agents/:id/capabilities - List agent capabilities."
  (require-permission :read)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (unless agent
      (return-from rest-agent-capabilities (json-not-found "Agent" agent-id)))
    (let ((cap-names (agent-capabilities agent)))
      (json-ok
       (loop for name in cap-names
             for cap = (autopoiesis.agent:find-capability name)
             when cap collect (capability-to-json-alist cap))))))

(defun rest-invoke-capability (agent-id)
  "POST /api/agents/:id/invoke - Invoke a capability."
  (require-permission :write)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (unless agent
      (return-from rest-invoke-capability (json-not-found "Agent" agent-id)))
    (let* ((body (parse-json-body))
           (cap-name (cdr (assoc :capability body)))
           (args (cdr (assoc :arguments body))))
      (unless cap-name
        (return-from rest-invoke-capability
          (json-error "Missing 'capability' field")))
      (let ((cap-keyword (or (find-symbol (string-upcase cap-name) :keyword)
                             (return-from rest-invoke-capability
                               (json-error (format nil "Unknown capability: ~a" cap-name))))))
        (handler-case
            (let ((result (apply #'autopoiesis.agent:invoke-capability
                                 cap-keyword
                                 (when (listp args)
                                   (loop for pair in args
                                         for k = (find-symbol (string-upcase (string (car pair)))
                                                              :keyword)
                                         unless k do (return-from rest-invoke-capability
                                                       (json-error (format nil "Unknown argument: ~a" (car pair))))
                                         collect k
                                         collect (cdr pair))))))
              (sse-broadcast "capability_invoked"
                             `((:agent--id . ,agent-id)
                               (:capability . ,cap-name)))
              (json-ok `((:result . ,(prin1-to-string result))
                         (:capability . ,cap-name))))
          (error (e)
            (declare (ignore e))
            (json-error "Capability invocation failed"
                        :status 500 :error-type "Internal Error")))))))

;;; ===================================================================
;;; Snapshot Endpoints
;;; ===================================================================

(defun rest-handle-snapshots (request)
  "Dispatch /api/snapshots requests."
  (let ((method (hunchentoot:request-method request))
        (snapshot-id (extract-path-segment request "/api/snapshots/")))
    (cond
      ;; GET /api/snapshots - list all snapshots
      ((and (eq method :get) (null snapshot-id))
       (rest-list-snapshots))
      ;; GET /api/snapshots/:id
      ((and (eq method :get) snapshot-id)
       (let ((sub-path (path-after-segment request "/api/snapshots/" snapshot-id)))
         (cond
           ;; GET /api/snapshots/:id/diff/:other-id
           ((and sub-path (>= (length sub-path) 6)
                 (string= "/diff/" (subseq sub-path 0 6)))
            (let ((other-id (subseq sub-path 6)))
              (rest-snapshot-diff snapshot-id other-id)))
           ;; GET /api/snapshots/:id/children
           ((string= sub-path "/children")
            (rest-snapshot-children snapshot-id))
           ;; GET /api/snapshots/:id
           (t (rest-get-snapshot snapshot-id)))))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

(defun rest-agent-snapshots (agent-id)
  "GET /api/agents/:id/snapshots - List snapshots for an agent."
  (require-permission :read)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (unless agent
      (return-from rest-agent-snapshots (json-not-found "Agent" agent-id)))
    ;; List all snapshots (filtering by agent would require metadata inspection)
    (let ((ids (autopoiesis.snapshot:list-snapshots)))
      (json-ok (loop for id in (if (> (length ids) 100) (subseq ids 0 100) ids)
                     for snap = (autopoiesis.snapshot:load-snapshot id)
                     when snap collect (snapshot-summary-alist snap))))))

(defun rest-list-snapshots ()
  "GET /api/snapshots - List all snapshots."
  (require-permission :read)
  (let* ((root-only (hunchentoot:get-parameter "root_only"))
         (parent-id (hunchentoot:get-parameter "parent_id"))
         (ids (autopoiesis.snapshot:list-snapshots
               :root-only (and root-only (string/= root-only "false"))
               :parent-id parent-id)))
    (json-ok (loop for id in (if (> (length ids) 100) (subseq ids 0 100) ids)
                   for snap = (autopoiesis.snapshot:load-snapshot id)
                   when snap collect (snapshot-summary-alist snap)))))

(defun rest-get-snapshot (snapshot-id)
  "GET /api/snapshots/:id - Get a snapshot."
  (require-permission :read)
  (let ((snapshot (autopoiesis.snapshot:load-snapshot snapshot-id)))
    (if snapshot
        (json-ok (snapshot-to-json-alist snapshot))
        (json-not-found "Snapshot" snapshot-id))))

(defun rest-take-snapshot (agent-id)
  "POST /api/agents/:id/snapshot - Take a snapshot of agent state."
  (require-permission :write)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (unless agent
      (return-from rest-take-snapshot (json-not-found "Agent" agent-id)))
    (let* ((body (parse-json-body))
           (parent-id (cdr (assoc :parent body)))
           (metadata (cdr (assoc :metadata body)))
           ;; Serialize agent state as S-expression
           (agent-state `(:agent
                          :id ,(agent-id agent)
                          :name ,(agent-name agent)
                          :state ,(agent-state agent)
                          :capabilities ,(agent-capabilities agent)
                          :thought-count ,(autopoiesis.core:stream-length
                                          (agent-thought-stream agent))))
           (snapshot (autopoiesis.snapshot:make-snapshot
                      agent-state
                      :parent parent-id
                      :metadata metadata)))
      ;; Save if store is available
      (when autopoiesis.snapshot:*snapshot-store*
        (autopoiesis.snapshot:save-snapshot snapshot))
      (sse-broadcast "snapshot_taken"
                     `((:agent--id . ,agent-id)
                       (:snapshot--id . ,(snapshot-id snapshot))))
      (json-ok (snapshot-to-json-alist snapshot) :status 201))))

(defun rest-snapshot-diff (id-a id-b)
  "GET /api/snapshots/:id/diff/:other-id - Diff two snapshots."
  (require-permission :read)
  (let ((snap-a (autopoiesis.snapshot:load-snapshot id-a))
        (snap-b (autopoiesis.snapshot:load-snapshot id-b)))
    (unless snap-a
      (return-from rest-snapshot-diff (json-not-found "Snapshot" id-a)))
    (unless snap-b
      (return-from rest-snapshot-diff (json-not-found "Snapshot" id-b)))
    (let ((diff (autopoiesis.snapshot:snapshot-diff snap-a snap-b)))
      (json-ok `((:from . ,id-a)
                 (:to . ,id-b)
                 (:diff . ,(prin1-to-string diff)))))))

(defun rest-snapshot-children (snapshot-id)
  "GET /api/snapshots/:id/children - Get children of a snapshot."
  (require-permission :read)
  (let ((children-ids (autopoiesis.snapshot:snapshot-children snapshot-id)))
    (json-ok (loop for id in children-ids
                   for snap = (autopoiesis.snapshot:load-snapshot id)
                   when snap collect (snapshot-summary-alist snap)))))

;;; ===================================================================
;;; Branch Endpoints
;;; ===================================================================

(defun rest-handle-branches (request)
  "Dispatch /api/branches requests."
  (let ((method (hunchentoot:request-method request))
        (branch-name (extract-path-segment request "/api/branches/")))
    (cond
      ;; GET /api/branches - list branches
      ((and (eq method :get) (null branch-name))
       (rest-list-branches))
      ;; POST /api/branches - create branch
      ((and (eq method :post) (null branch-name))
       (rest-create-branch))
      ;; GET /api/branches/:name - get branch
      ((and (eq method :get) branch-name)
       (rest-get-branch branch-name))
      ;; POST /api/branches/:name/checkout
      ((and (eq method :post) branch-name)
       (let ((sub-path (path-after-segment request "/api/branches/" branch-name)))
         (cond
           ((string= sub-path "/checkout")
            (rest-checkout-branch branch-name))
           (t (json-error "Unknown branch action"
                          :status 404 :error-type "Not Found")))))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

(defun rest-list-branches ()
  "GET /api/branches - List all branches."
  (require-permission :read)
  (let ((branches (autopoiesis.snapshot:list-branches)))
    (json-ok (mapcar #'branch-to-json-alist branches))))

(defun rest-create-branch ()
  "POST /api/branches - Create a new branch."
  (require-permission :write)
  (let* ((body (parse-json-body))
         (name (cdr (assoc :name body)))
         (from-snapshot (cdr (assoc :from--snapshot body))))
    (unless name
      (return-from rest-create-branch
        (json-error "Missing 'name' field")))
    (let ((branch (autopoiesis.snapshot:create-branch
                   name :from-snapshot from-snapshot)))
      (sse-broadcast "branch_created" (branch-to-json-alist branch))
      (json-ok (branch-to-json-alist branch) :status 201))))

(defun rest-get-branch (branch-name)
  "GET /api/branches/:name - Get branch details."
  (require-permission :read)
  (let ((branches (autopoiesis.snapshot:list-branches)))
    (let ((branch (find branch-name branches
                        :key #'branch-name :test #'string=)))
      (if branch
          (json-ok (branch-to-json-alist branch))
          (json-not-found "Branch" branch-name)))))

(defun rest-checkout-branch (branch-name)
  "POST /api/branches/:name/checkout - Switch to a branch."
  (require-permission :write)
  (handler-case
      (let ((branch (autopoiesis.snapshot:switch-branch branch-name)))
        (sse-broadcast "branch_checkout"
                       `((:name . ,branch-name)
                         (:head . ,(branch-head branch))))
        (json-ok (branch-to-json-alist branch)))
    (autopoiesis.core:autopoiesis-error (e)
      (json-not-found "Branch" branch-name))))

;;; ===================================================================
;;; Human-in-the-Loop Endpoints
;;; ===================================================================

(defun rest-agent-pending (agent-id)
  "GET /api/agents/:id/pending - List pending human input requests."
  (declare (ignore agent-id))
  (require-permission :read)
  ;; The blocking request system is global, not per-agent.
  ;; Return all pending requests.
  (let ((requests (autopoiesis.interface:list-pending-blocking-requests)))
    (json-ok (mapcar #'blocking-request-to-json-alist requests))))

(defun rest-handle-pending (request)
  "Dispatch /api/pending requests."
  (let ((method (hunchentoot:request-method request))
        (request-id (extract-path-segment request "/api/pending/")))
    (cond
      ;; GET /api/pending - list all pending
      ((and (eq method :get) (null request-id))
       (rest-list-pending))
      ;; POST /api/pending/:id/respond
      ((and (eq method :post) request-id)
       (let ((sub-path (path-after-segment request "/api/pending/" request-id)))
         (cond
           ((string= sub-path "/respond")
            (rest-respond request-id))
           ((string= sub-path "/cancel")
            (rest-cancel-request request-id))
           (t (json-error "Unknown action" :status 404 :error-type "Not Found")))))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

(defun rest-list-pending ()
  "GET /api/pending - List all pending human input requests."
  (require-permission :read)
  (let ((requests (autopoiesis.interface:list-pending-blocking-requests)))
    (json-ok (mapcar #'blocking-request-to-json-alist requests))))

(defun rest-respond (request-id)
  "POST /api/pending/:id/respond - Provide a response to a pending request."
  (require-permission :write)
  (let* ((body (parse-json-body))
         (response (cdr (assoc :response body))))
    (unless response
      (return-from rest-respond
        (json-error "Missing 'response' field")))
    (multiple-value-bind (success request-obj)
        (autopoiesis.interface:respond-to-request request-id response)
      (if success
          (progn
            (sse-broadcast "request_responded"
                           `((:request--id . ,request-id)))
            (json-ok `((:responded . t) (:request--id . ,request-id))))
          (json-not-found "Pending request" request-id)))))

(defun rest-respond-to-request (agent-id)
  "POST /api/agents/:id/respond - Respond to a pending request (agent-scoped)."
  (declare (ignore agent-id))
  (require-permission :write)
  (let* ((body (parse-json-body))
         (request-id (cdr (assoc :request--id body)))
         (response (cdr (assoc :response body))))
    (unless (and request-id response)
      (return-from rest-respond-to-request
        (json-error "Missing 'request_id' or 'response' field")))
    (multiple-value-bind (success req)
        (autopoiesis.interface:respond-to-request request-id response)
      (declare (ignore req))
      (if success
          (json-ok `((:responded . t) (:request--id . ,request-id)))
          (json-not-found "Pending request" request-id)))))

(defun rest-cancel-request (request-id)
  "POST /api/pending/:id/cancel - Cancel a pending request."
  (require-permission :write)
  (let* ((body (parse-json-body))
         (reason (cdr (assoc :reason body))))
    (let ((request-obj (autopoiesis.interface:find-blocking-request request-id)))
      (if request-obj
          (progn
            (autopoiesis.interface:cancel-blocking-request request-obj :reason reason)
            (sse-broadcast "request_cancelled"
                           `((:request--id . ,request-id)))
            (json-ok `((:cancelled . t) (:request--id . ,request-id))))
          (json-not-found "Pending request" request-id)))))

;;; ===================================================================
;;; Events Endpoint
;;; ===================================================================

(defun rest-handle-events (request)
  "Dispatch /api/events requests."
  (let ((method (hunchentoot:request-method request)))
    (cond
      ;; GET /api/events - get event history (JSON) or SSE stream
      ((eq method :get)
       (let ((accept (hunchentoot:header-in* :accept)))
         (if (and accept (search "text/event-stream" accept))
             (handle-sse-stream)
             (rest-event-history))))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

(defun rest-event-history ()
  "GET /api/events - Return recent event history as JSON."
  (require-permission :read)
  (let* ((limit (or (ignore-errors
                      (parse-integer
                       (or (hunchentoot:get-parameter "limit") "50")))
                    50))
         (event-type (let ((t-param (hunchentoot:get-parameter "type")))
                       (when t-param
                         (or (find-symbol (string-upcase t-param) :keyword)
                             (return-from rest-event-history
                               (json-error (format nil "Unknown event type: ~a" t-param)))))))
         (events (autopoiesis.integration:get-event-history
                  :limit limit :type event-type)))
    (json-ok (mapcar #'event-to-json-alist events))))

;;; ===================================================================
;;; System Info Endpoint
;;; ===================================================================

(defun rest-system-info ()
  "GET /api/system - Return system information."
  (require-permission :read)
  (json-ok `((:version . "0.1.0")
             (:platform . "autopoiesis")
             (:agent--count . ,(length (autopoiesis.agent:list-agents)))
             (:running--agents . ,(length (autopoiesis.agent:running-agents)))
             (:branch--count . ,(length (autopoiesis.snapshot:list-branches)))
             (:pending--requests . ,(length
                                     (autopoiesis.interface:list-pending-blocking-requests)))
             (:snapshot--store . ,(if autopoiesis.snapshot:*snapshot-store*
                                      "initialized" "not initialized")))))

;;; ===================================================================
;;; Main Router
;;; ===================================================================

(defun api-dispatch-handler ()
  "Main dispatcher for the /api/ prefix.
   Routes requests to the appropriate handler based on URL path."
  (let* ((request hunchentoot:*request*)
         (uri (hunchentoot:request-uri request)))
    ;; Strip query string for routing
    (let ((qpos (position #\? uri)))
      (when qpos (setf uri (subseq uri 0 qpos))))
    (handler-case
        (cond
          ;; /api/system (exact match)
          ((string= uri "/api/system")
           (rest-system-info))
          ;; /api/agents or /api/agents/...
          ((or (string= uri "/api/agents")
               (and (> (length uri) 12)
                    (string= "/api/agents/" (subseq uri 0 12))))
           (rest-handle-agents request))
          ;; /api/snapshots or /api/snapshots/...
          ((or (string= uri "/api/snapshots")
               (and (> (length uri) 15)
                    (string= "/api/snapshots/" (subseq uri 0 15))))
           (rest-handle-snapshots request))
          ;; /api/branches or /api/branches/...
          ((or (string= uri "/api/branches")
               (and (> (length uri) 14)
                    (string= "/api/branches/" (subseq uri 0 14))))
           (rest-handle-branches request))
          ;; /api/pending or /api/pending/...
          ((or (string= uri "/api/pending")
               (and (> (length uri) 13)
                    (string= "/api/pending/" (subseq uri 0 13))))
           (rest-handle-pending request))
          ;; /api/events (exact match)
          ((string= uri "/api/events")
           (rest-handle-events request))
          ;; Unknown API route
          (t
           (json-not-found "API route" uri)))
      (error (e)
        (json-error (format nil "~a" e)
                    :status 500 :error-type "Internal Error")))))
