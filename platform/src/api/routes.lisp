;;;; routes.lisp - REST API route handlers for external agent control
;;;;
;;;; Provides HTTP endpoints dispatching to unified operations via
;;;; dispatch-operation-rest (shared with MCP), plus REST-only endpoints
;;;; for features without MCP equivalents.

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

(defun handle-agents (request)
  "Dispatch /api/agents requests."
  (let ((method (hunchentoot:request-method request))
        (agent-id (extract-path-segment request "/api/agents/")))
    (cond
      ;; GET /api/agents - list all agents
      ((and (eq method :get) (null agent-id))
       (dispatch-operation-rest "list_agents" nil))
      ;; POST /api/agents - create agent
      ((and (eq method :post) (null agent-id))
       (dispatch-operation-rest "create_agent" (parse-json-body)))
      ;; GET /api/agents/:id - get agent or sub-resources
      ((and (eq method :get) agent-id)
       (let ((sub-path (path-after-segment request "/api/agents/" agent-id))
             (id-args `((:agent-id . ,agent-id))))
         (cond
           ;; GET /api/agents/:id/thoughts
           ((string= sub-path "/thoughts")
            (let ((limit (or (ignore-errors
                               (parse-integer
                                (or (hunchentoot:get-parameter "limit") "20")))
                             20)))
              (dispatch-operation-rest "get_thoughts"
                `((:agent-id . ,agent-id) (:limit . ,limit)))))
           ;; GET /api/agents/:id/capabilities
           ((string= sub-path "/capabilities")
            (dispatch-operation-rest "list_capabilities" id-args))
           ;; GET /api/agents/:id/snapshots (REST-only)
           ((string= sub-path "/snapshots")
            (handle-agent-snapshots agent-id))
           ;; GET /api/agents/:id/pending (REST-only)
           ((string= sub-path "/pending")
            (handle-agent-pending agent-id))
           ;; GET /api/agents/:id
           ((or (null sub-path) (string= sub-path "") (string= sub-path "/"))
            (dispatch-operation-rest "get_agent" id-args))
           (t (json-not-found "Route" (format nil "/api/agents/~a~a" agent-id sub-path))))))
      ;; POST /api/agents/:id/... - agent actions
      ((and (eq method :post) agent-id)
       (let ((sub-path (path-after-segment request "/api/agents/" agent-id))
             (id-args `((:agent-id . ,agent-id))))
         (cond
           ((string= sub-path "/start")
            (dispatch-operation-rest "start_agent" id-args))
           ((string= sub-path "/pause")
            (dispatch-operation-rest "pause_agent" id-args))
           ((string= sub-path "/resume")
            (dispatch-operation-rest "resume_agent" id-args))
           ((string= sub-path "/stop")
            (dispatch-operation-rest "stop_agent" id-args))
           ((string= sub-path "/cycle")
            (let ((body (parse-json-body)))
              (dispatch-operation-rest "cognitive_cycle"
                (acons :agent-id agent-id body))))
           ((string= sub-path "/invoke")
            (let ((body (parse-json-body)))
              (dispatch-operation-rest "invoke_capability"
                (acons :agent-id agent-id body))))
           ((string= sub-path "/snapshot")
            (let ((body (parse-json-body)))
              (dispatch-operation-rest "take_snapshot"
                (acons :agent-id agent-id body))))
           ((string= sub-path "/respond")
            (handle-respond-to-request agent-id))
           (t (json-not-found "Route" (format nil "/api/agents/~a~a" agent-id sub-path))))))
      ;; DELETE /api/agents/:id - remove agent
      ((and (eq method :delete) agent-id)
       (dispatch-operation-rest "delete_agent" `((:agent-id . ,agent-id))))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

;;; --- REST-Only Agent Handlers ---

(defun handle-agent-snapshots (agent-id)
  "GET /api/agents/:id/snapshots - List snapshots for an agent."
  (require-permission :read)
  (let ((agent (autopoiesis.agent:find-agent agent-id)))
    (unless agent
      (return-from handle-agent-snapshots (json-not-found "Agent" agent-id)))
    (let ((ids (autopoiesis.snapshot:list-snapshots)))
      (json-ok (loop for id in (if (> (length ids) 100) (subseq ids 0 100) ids)
                     for snap = (autopoiesis.snapshot:load-snapshot id)
                     when snap collect (snapshot-summary-alist snap))))))

(defun handle-agent-pending (agent-id)
  "GET /api/agents/:id/pending - List pending human input requests."
  (declare (ignore agent-id))
  (require-permission :read)
  (let ((requests (autopoiesis.interface:list-pending-blocking-requests)))
    (json-ok (mapcar #'blocking-request-to-json-alist requests))))

(defun handle-respond-to-request (agent-id)
  "POST /api/agents/:id/respond - Respond to a pending request (agent-scoped)."
  (declare (ignore agent-id))
  (require-permission :write)
  (let* ((body (parse-json-body))
         (request-id (cdr (assoc :request--id body)))
         (response (cdr (assoc :response body))))
    (unless (and request-id response)
      (return-from handle-respond-to-request
        (json-error "Missing 'request_id' or 'response' field")))
    (multiple-value-bind (success req)
        (autopoiesis.interface:respond-to-request request-id response)
      (declare (ignore req))
      (if success
          (json-ok `((:responded . t) (:request--id . ,request-id)))
          (json-not-found "Pending request" request-id)))))

;;; ===================================================================
;;; Snapshot Endpoints
;;; ===================================================================

(defun handle-snapshots (request)
  "Dispatch /api/snapshots requests."
  (let ((method (hunchentoot:request-method request))
        (snapshot-id (extract-path-segment request "/api/snapshots/")))
    (cond
      ;; GET /api/snapshots - list all snapshots
      ((and (eq method :get) (null snapshot-id))
       (let ((parent-id (hunchentoot:get-parameter "parent_id"))
             (root-only-str (hunchentoot:get-parameter "root_only")))
         (dispatch-operation-rest "list_snapshots"
           `(,@(when parent-id `((:parent-id . ,parent-id)))
             ,@(when root-only-str
                 `((:root-only . ,(and (string/= root-only-str "false") t))))))))
      ;; GET /api/snapshots/:id
      ((and (eq method :get) snapshot-id)
       (let ((sub-path (path-after-segment request "/api/snapshots/" snapshot-id)))
         (cond
           ;; GET /api/snapshots/:id/diff/:other-id
           ((and sub-path (>= (length sub-path) 6)
                 (string= "/diff/" (subseq sub-path 0 6)))
            (let ((other-id (subseq sub-path 6)))
              (dispatch-operation-rest "diff_snapshots"
                `((:from-id . ,snapshot-id) (:to-id . ,other-id)))))
           ;; GET /api/snapshots/:id/children (REST-only)
           ((string= sub-path "/children")
            (handle-snapshot-children snapshot-id))
           ;; GET /api/snapshots/:id
           (t (dispatch-operation-rest "get_snapshot"
                `((:snapshot-id . ,snapshot-id)))))))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

(defun handle-snapshot-children (snapshot-id)
  "GET /api/snapshots/:id/children - Get children of a snapshot."
  (require-permission :read)
  (let ((children-ids (autopoiesis.snapshot:snapshot-children snapshot-id)))
    (json-ok (loop for id in children-ids
                   for snap = (autopoiesis.snapshot:load-snapshot id)
                   when snap collect (snapshot-summary-alist snap)))))

;;; ===================================================================
;;; Branch Endpoints
;;; ===================================================================

(defun handle-branches (request)
  "Dispatch /api/branches requests."
  (let ((method (hunchentoot:request-method request))
        (branch-name (extract-path-segment request "/api/branches/")))
    (cond
      ;; GET /api/branches - list branches
      ((and (eq method :get) (null branch-name))
       (dispatch-operation-rest "list_branches" nil))
      ;; POST /api/branches - create branch
      ((and (eq method :post) (null branch-name))
       (dispatch-operation-rest "create_branch" (parse-json-body)))
      ;; GET /api/branches/:name - get branch (REST-only)
      ((and (eq method :get) branch-name)
       (handle-get-branch branch-name))
      ;; POST /api/branches/:name/checkout
      ((and (eq method :post) branch-name)
       (let ((sub-path (path-after-segment request "/api/branches/" branch-name)))
         (cond
           ((string= sub-path "/checkout")
            (dispatch-operation-rest "checkout_branch"
              `((:name . ,branch-name))))
           (t (json-error "Unknown branch action"
                          :status 404 :error-type "Not Found")))))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

(defun handle-get-branch (branch-name)
  "GET /api/branches/:name - Get branch details."
  (require-permission :read)
  (let ((branches (autopoiesis.snapshot:list-branches)))
    (let ((branch (find branch-name branches
                        :key #'branch-name :test #'string=)))
      (if branch
          (json-ok (branch-to-json-alist branch))
          (json-not-found "Branch" branch-name)))))

;;; ===================================================================
;;; Human-in-the-Loop Endpoints
;;; ===================================================================

(defun handle-pending-requests (request)
  "Dispatch /api/pending requests."
  (let ((method (hunchentoot:request-method request))
        (request-id (extract-path-segment request "/api/pending/")))
    (cond
      ;; GET /api/pending - list all pending
      ((and (eq method :get) (null request-id))
       (dispatch-operation-rest "list_pending_requests" nil))
      ;; POST /api/pending/:id/...
      ((and (eq method :post) request-id)
       (let ((sub-path (path-after-segment request "/api/pending/" request-id)))
         (cond
           ((string= sub-path "/respond")
            (let ((body (parse-json-body)))
              (dispatch-operation-rest "respond_to_request"
                (acons :request-id request-id body))))
           ((string= sub-path "/cancel")
            (handle-cancel-request request-id))
           (t (json-error "Unknown action" :status 404 :error-type "Not Found")))))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

(defun handle-cancel-request (request-id)
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

(defun handle-events (request)
  "Dispatch /api/events requests."
  (let ((method (hunchentoot:request-method request)))
    (cond
      ;; GET /api/events - get event history (JSON) or SSE stream
      ((eq method :get)
       (let ((accept (hunchentoot:header-in* :accept)))
         (if (and accept (search "text/event-stream" accept))
             (handle-sse-stream)
             (handle-event-history))))
      (t (json-error "Method not allowed" :status 405 :error-type "Method Not Allowed")))))

(defun handle-event-history ()
  "GET /api/events - Return recent event history as JSON."
  (require-permission :read)
  (let* ((limit (or (ignore-errors
                      (parse-integer
                       (or (hunchentoot:get-parameter "limit") "50")))
                    50))
         (event-type (let ((t-param (hunchentoot:get-parameter "type")))
                       (when t-param
                         (or (find-symbol (string-upcase t-param) :keyword)
                             (return-from handle-event-history
                               (json-error (format nil "Unknown event type: ~a" t-param)))))))
         (events (autopoiesis.integration:get-event-history
                  :limit limit :type event-type)))
    (json-ok (mapcar #'event-to-json-alist events))))

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
           (dispatch-operation-rest "system_info" nil))
          ;; /api/agents or /api/agents/...
          ((or (string= uri "/api/agents")
               (and (> (length uri) 12)
                    (string= "/api/agents/" (subseq uri 0 12))))
           (handle-agents request))
          ;; /api/snapshots or /api/snapshots/...
          ((or (string= uri "/api/snapshots")
               (and (> (length uri) 15)
                    (string= "/api/snapshots/" (subseq uri 0 15))))
           (handle-snapshots request))
          ;; /api/branches or /api/branches/...
          ((or (string= uri "/api/branches")
               (and (> (length uri) 14)
                    (string= "/api/branches/" (subseq uri 0 14))))
           (handle-branches request))
          ;; /api/pending or /api/pending/...
          ((or (string= uri "/api/pending")
               (and (> (length uri) 13)
                    (string= "/api/pending/" (subseq uri 0 13))))
           (handle-pending-requests request))
          ;; /api/events (exact match)
          ((string= uri "/api/events")
           (handle-events request))
          ;; Unknown API route
          (t
           (json-not-found "API route" uri)))
      (error (e)
        (declare (ignore e))
        (json-error "An internal error occurred"
                    :status 500 :error-type "Internal Error")))))
