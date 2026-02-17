;;;; op-definitions.lisp - Unified operation definitions using defoperation
;;;;
;;;; All REST + MCP operations defined via defoperation macro.
;;;; Each operation generates a handler function and registers in
;;;; the operations registry for dispatch from either REST or MCP.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Agent Lifecycle Operations
;;; ===================================================================

(defoperation :list-agents
  (:description "List all registered agents")
  (:permission :read)
  (:handler
   (mapcar #'agent-to-json-alist (autopoiesis.agent:list-agents))))

(defoperation :create-agent
  (:description "Create a new cognitive agent")
  (:parameters (name :type "string" :description "Agent name"))
  (:permission :write)
  (:event "agent_created")
  (:handler
   (let ((agent (autopoiesis.agent:make-agent
                 :name (or name "unnamed"))))
     (autopoiesis.agent:register-agent agent)
     (agent-to-json-alist agent))))

(defoperation :get-agent
  (:description "Get details of a specific agent")
  (:parameters (agent-id :type "string" :description "Agent ID" :required t))
  (:permission :read)
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (agent-to-json-alist agent))))

(defoperation :start-agent
  (:description "Start an agent's cognitive loop")
  (:parameters (agent-id :type "string" :description "Agent ID" :required t))
  (:permission :write)
  (:event "agent_started")
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (autopoiesis.agent:start-agent agent)
     (agent-to-json-alist agent))))

(defoperation :pause-agent
  (:description "Pause a running agent")
  (:parameters (agent-id :type "string" :description "Agent ID" :required t))
  (:permission :write)
  (:event "agent_paused")
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (autopoiesis.agent:pause-agent agent)
     (agent-to-json-alist agent))))

(defoperation :resume-agent
  (:description "Resume a paused agent")
  (:parameters (agent-id :type "string" :description "Agent ID" :required t))
  (:permission :write)
  (:event "agent_resumed")
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (autopoiesis.agent:resume-agent agent)
     (agent-to-json-alist agent))))

(defoperation :stop-agent
  (:description "Stop an agent")
  (:parameters (agent-id :type "string" :description "Agent ID" :required t))
  (:permission :write)
  (:event "agent_stopped")
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (autopoiesis.agent:stop-agent agent)
     (agent-to-json-alist agent))))

(defoperation :delete-agent
  (:description "Stop and unregister an agent")
  (:parameters (agent-id :type "string" :description "Agent ID" :required t))
  (:permission :admin)
  (:event "agent_deleted")
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (autopoiesis.agent:stop-agent agent)
     (autopoiesis.agent:unregister-agent agent)
     `((:deleted . t) (:id . ,agent-id)
       (:name . ,(agent-name agent))))))

;;; ===================================================================
;;; Cognitive Operations
;;; ===================================================================

(defoperation :cognitive-cycle
  (:description "Run one perceive-reason-decide-act-reflect cycle on an agent")
  (:parameters
   (agent-id :type "string" :description "Agent ID" :required t)
   (environment :type "object" :description "Environment data to feed the cycle"))
  (:permission :write)
  (:event "cycle_complete")
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (let ((result (autopoiesis.agent:cognitive-cycle agent environment)))
       `((:agent--id . ,agent-id)
         (:state . ,(string-downcase
                     (string (autopoiesis.agent:agent-state agent))))
         (:result . ,(when result (prin1-to-string result))))))))

(defoperation :get-thoughts
  (:description "Get recent thoughts from an agent's thought stream")
  (:parameters
   (agent-id :type "string" :description "Agent ID" :required t)
   (limit :type "integer" :description "Max thoughts to return (default 20)"))
  (:permission :read)
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (let* ((n (or limit 20))
            (stream (agent-thought-stream agent))
            (thoughts (autopoiesis.core:stream-last stream n)))
       (mapcar #'thought-to-json-alist thoughts)))))

(defoperation :list-capabilities
  (:description "List an agent's capabilities")
  (:parameters (agent-id :type "string" :description "Agent ID" :required t))
  (:permission :read)
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (loop for name in (agent-capabilities agent)
           for cap = (autopoiesis.agent:find-capability name)
           when cap collect (capability-to-json-alist cap)))))

(defoperation :invoke-capability
  (:description "Invoke a specific capability on behalf of an agent")
  (:parameters
   (agent-id :type "string" :description "Agent ID" :required t)
   (capability :type "string" :description "Capability name" :required t)
   (arguments :type "object" :description "Arguments for the capability"))
  (:permission :write)
  (:event "capability_invoked")
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (let* ((cap-keyword (or (find-symbol (string-upcase capability) :keyword)
                             (error "Unknown capability: ~a" capability)))
            (result (apply #'autopoiesis.agent:invoke-capability
                           cap-keyword
                           (when (listp arguments)
                             (loop for (k . v) in arguments
                                   for kw = (or (find-symbol
                                                 (string-upcase (string k))
                                                 :keyword)
                                                (error "Unknown argument: ~a" k))
                                   collect kw
                                   collect v)))))
       `((:result . ,(prin1-to-string result))
         (:capability . ,capability))))))

;;; ===================================================================
;;; Snapshot Operations
;;; ===================================================================

(defoperation :take-snapshot
  (:description "Capture a point-in-time snapshot of agent cognitive state")
  (:parameters
   (agent-id :type "string" :description "Agent ID" :required t)
   (parent :type "string" :description "Parent snapshot ID")
   (metadata :type "object" :description "Additional metadata"))
  (:permission :write)
  (:event "snapshot_taken")
  (:handler
   (let ((agent (autopoiesis.agent:find-agent agent-id)))
     (unless agent (error "Agent not found: ~a" agent-id))
     (let* ((agent-state `(:agent
                           :id ,(agent-id agent)
                           :name ,(agent-name agent)
                           :state ,(agent-state agent)
                           :capabilities ,(agent-capabilities agent)
                           :thought-count ,(autopoiesis.core:stream-length
                                           (agent-thought-stream agent))))
            (snapshot (autopoiesis.snapshot:make-snapshot
                       agent-state
                       :parent parent
                       :metadata metadata)))
       (when autopoiesis.snapshot:*snapshot-store*
         (autopoiesis.snapshot:save-snapshot snapshot))
       (snapshot-to-json-alist snapshot)))))

(defoperation :list-snapshots
  (:description "List snapshots, optionally filtered by parent")
  (:parameters
   (parent-id :type "string" :description "Filter by parent snapshot ID")
   (root-only :type "boolean" :description "Return only root snapshots"))
  (:permission :read)
  (:handler
   (let ((ids (autopoiesis.snapshot:list-snapshots
               :parent-id parent-id
               :root-only root-only)))
     (loop for id in (if (> (length ids) 100) (subseq ids 0 100) ids)
           for snap = (autopoiesis.snapshot:load-snapshot id)
           when snap collect (snapshot-summary-alist snap)))))

(defoperation :get-snapshot
  (:description "Retrieve a specific snapshot by ID")
  (:parameters
   (snapshot-id :type "string" :description "Snapshot ID" :required t))
  (:permission :read)
  (:handler
   (let ((snapshot (autopoiesis.snapshot:load-snapshot snapshot-id)))
     (unless snapshot (error "Snapshot not found: ~a" snapshot-id))
     (snapshot-to-json-alist snapshot))))

(defoperation :diff-snapshots
  (:description "Compute the diff between two snapshots")
  (:parameters
   (from-id :type "string" :description "Source snapshot ID" :required t)
   (to-id :type "string" :description "Target snapshot ID" :required t))
  (:permission :read)
  (:handler
   (let ((snap-a (autopoiesis.snapshot:load-snapshot from-id))
         (snap-b (autopoiesis.snapshot:load-snapshot to-id)))
     (unless snap-a (error "Snapshot not found: ~a" from-id))
     (unless snap-b (error "Snapshot not found: ~a" to-id))
     `((:from . ,from-id)
       (:to . ,to-id)
       (:diff . ,(prin1-to-string
                  (autopoiesis.snapshot:snapshot-diff snap-a snap-b)))))))

;;; ===================================================================
;;; Branch Operations
;;; ===================================================================

(defoperation :list-branches
  (:description "List all cognitive branches")
  (:permission :read)
  (:handler
   (mapcar #'branch-to-json-alist
           (autopoiesis.snapshot:list-branches))))

(defoperation :create-branch
  (:description "Create a new branch for exploring alternative cognitive paths")
  (:parameters
   (name :type "string" :description "Branch name" :required t)
   (from-snapshot :type "string" :description "Snapshot to branch from"))
  (:permission :write)
  (:event "branch_created")
  (:handler
   (unless name (error "Missing 'name' field"))
   (let ((branch (autopoiesis.snapshot:create-branch
                  name :from-snapshot from-snapshot)))
     (branch-to-json-alist branch))))

(defoperation :checkout-branch
  (:description "Switch to a different branch")
  (:parameters
   (name :type "string" :description "Branch name" :required t))
  (:permission :write)
  (:event "branch_checkout")
  (:handler
   (let ((branch (autopoiesis.snapshot:switch-branch name)))
     (branch-to-json-alist branch))))

;;; ===================================================================
;;; Human-in-the-Loop Operations
;;; ===================================================================

(defoperation :list-pending-requests
  (:description "List pending human-in-the-loop input requests")
  (:permission :read)
  (:handler
   (mapcar #'blocking-request-to-json-alist
           (autopoiesis.interface:list-pending-blocking-requests))))

(defoperation :respond-to-request
  (:description "Provide a human response to a pending blocking request")
  (:parameters
   (request-id :type "string" :description "Pending request ID" :required t)
   (response :type "string" :description "The response to provide" :required t))
  (:permission :write)
  (:event "request_responded")
  (:handler
   (multiple-value-bind (success req)
       (autopoiesis.interface:respond-to-request request-id response)
     (declare (ignore req))
     (if success
         `((:responded . t) (:request--id . ,request-id))
         (error "Pending request not found: ~a" request-id)))))

;;; ===================================================================
;;; System Operations
;;; ===================================================================

(defoperation :system-info
  (:description "Get Autopoiesis system status: version, agent count, running state")
  (:permission :read)
  (:handler
   `((:version . "0.1.0")
     (:platform . "autopoiesis")
     (:agent--count . ,(length (autopoiesis.agent:list-agents)))
     (:running--agents . ,(length (autopoiesis.agent:running-agents)))
     (:branch--count . ,(length (autopoiesis.snapshot:list-branches)))
     (:pending--requests . ,(length
                             (autopoiesis.interface:list-pending-blocking-requests)))
     (:snapshot--store . ,(if autopoiesis.snapshot:*snapshot-store*
                              "initialized" "not initialized")))))
