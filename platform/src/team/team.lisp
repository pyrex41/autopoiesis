;;;; team.lisp - Team class, lifecycle, registry, serialization
;;;;
;;;; A team coordinates multiple agents via a strategy pattern.
;;;; Teams persist to substrate and maintain an in-memory registry.

(in-package #:autopoiesis.team)

;;; ═══════════════════════════════════════════════════════════════════
;;; Team Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass team ()
  ((id :initarg :id
       :accessor team-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique team identifier")
   (strategy :initarg :strategy
             :accessor team-strategy
             :initform nil
             :documentation "Strategy object governing coordination")
   (leader :initarg :leader
           :accessor team-leader
           :initform nil
           :documentation "Agent ID of the team leader (if applicable)")
   (members :initarg :members
            :accessor team-members
            :initform nil
            :documentation "List of agent IDs participating in this team")
   (status :initarg :status
           :accessor team-status
           :initform :created
           :type (member :created :active :paused :completed :failed)
           :documentation "Current team lifecycle state")
   (workspace-id :initarg :workspace-id
                 :accessor team-workspace-id
                 :initform nil
                 :documentation "Associated workspace ID for shared state")
   (task :initarg :task
         :accessor team-task
         :initform nil
         :documentation "The task or goal the team is working on")
   (config :initarg :config
           :accessor team-config
           :initform nil
           :documentation "Strategy-specific configuration plist")
   (created-at :initarg :created-at
               :accessor team-created-at
               :initform (get-universal-time)
               :documentation "When the team was created"))
  (:documentation "A coordinated group of agents working together."))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thread-safe Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *team-registry* (make-hash-table :test 'equal)
  "Maps team-id -> team object.")

(defvar *team-registry-lock* (bt:make-lock "team-registry")
  "Lock protecting the *team-registry* hash-table.")

(defun register-team (team)
  "Register TEAM in the in-memory registry."
  (bt:with-lock-held (*team-registry-lock*)
    (setf (gethash (team-id team) *team-registry*) team))
  team)

(defun find-team (team-id)
  "Find a team by ID. Returns nil if not found."
  (bt:with-lock-held (*team-registry-lock*)
    (gethash team-id *team-registry*)))

(defun list-teams ()
  "Return a list of all registered teams."
  (bt:with-lock-held (*team-registry-lock*)
    (hash-table-values *team-registry*)))

(defun active-teams ()
  "Return a list of teams with :active status."
  (remove-if-not (lambda (t-obj) (eq (team-status t-obj) :active))
                 (list-teams)))

(defun unregister-team (team-id)
  "Remove a team from the registry."
  (bt:with-lock-held (*team-registry-lock*)
    (remhash team-id *team-registry*)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Emission (decoupled from integration layer)
;;; ═══════════════════════════════════════════════════════════════════

(defun %emit-team-event (event-type team-id &key data agent-id)
  "Emit a team event through the integration event bus, if available.
   Uses find-symbol to avoid compile-time circular dependency."
  (when (find-package :autopoiesis.integration)
    (let ((emit-fn (find-symbol "EMIT-INTEGRATION-EVENT" :autopoiesis.integration)))
      (when emit-fn
        (funcall emit-fn event-type :team
                 (append (list :team-id team-id) data)
                 :agent-id agent-id)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Substrate Persistence
;;; ═══════════════════════════════════════════════════════════════════

(defun %persist-team (team)
  "Persist team state to substrate datoms."
  (when (and (find-package :autopoiesis.substrate)
             (boundp (find-symbol "*STORE*" :autopoiesis.substrate))
             (symbol-value (find-symbol "*STORE*" :autopoiesis.substrate)))
    (let ((intern-fn (find-symbol "INTERN-ID" :autopoiesis.substrate))
          (transact-fn (find-symbol "TRANSACT!" :autopoiesis.substrate))
          (make-datom-fn (find-symbol "MAKE-DATOM" :autopoiesis.substrate)))
      (when (and intern-fn transact-fn make-datom-fn)
        (let ((eid (funcall intern-fn (team-id team))))
          (funcall transact-fn
                   (list (funcall make-datom-fn eid :team/id (team-id team))
                         (funcall make-datom-fn eid :team/status (team-status team))
                         (funcall make-datom-fn eid :team/task (or (team-task team) ""))
                         (funcall make-datom-fn eid :team/leader (or (team-leader team) ""))
                         (funcall make-datom-fn eid :team/members (team-members team))
                         (funcall make-datom-fn eid :team/created-at (team-created-at team)))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Lifecycle Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun create-team (name &key strategy task members leader config)
  "Create a new team with the given strategy.
   NAME - human-readable name (used as part of the team-id).
   STRATEGY - keyword (:leader-worker :parallel :pipeline :debate :consensus).
   TASK - the team's goal or task description.
   MEMBERS - list of agent IDs to include.
   LEADER - agent ID of the team leader.
   CONFIG - strategy-specific configuration plist.
   Returns the team object."
  (let* ((team-id (format nil "team-~A-~A" name (autopoiesis.core:make-uuid)))
         (strategy-obj (when strategy (make-strategy strategy config)))
         (workspace-id nil))
    ;; Create workspace if the workspace module is available
    (when (find-package :autopoiesis.workspace)
      (let ((create-ws-fn (find-symbol "CREATE-WORKSPACE" :autopoiesis.workspace)))
        (when create-ws-fn
          (let ((ws (ignore-errors
                      (funcall create-ws-fn
                               :agent-id (or leader "team-system")
                               :task (or task "team workspace")))))
            (when ws
              (let ((ws-id-fn (find-symbol "WORKSPACE-ID" :autopoiesis.workspace)))
                (when ws-id-fn
                  (setf workspace-id (funcall ws-id-fn ws)))))))))
    (let ((team (make-instance 'team
                               :id team-id
                               :strategy strategy-obj
                               :leader leader
                               :members (or members nil)
                               :task task
                               :workspace-id workspace-id
                               :config config)))
      (%persist-team team)
      (register-team team)
      (%emit-team-event :team-created team-id
                        :data (list :task task :strategy strategy))
      team)))

(defun start-team (team)
  "Transition team to :active state and initialize strategy."
  (setf (team-status team) :active)
  (%persist-team team)
  (when (team-strategy team)
    (strategy-initialize (team-strategy team) team))
  (%emit-team-event :team-started (team-id team))
  team)

(defun pause-team (team)
  "Pause an active team."
  (when (eq (team-status team) :active)
    (setf (team-status team) :paused)
    (%persist-team team)
    team))

(defun resume-team (team)
  "Resume a paused team."
  (when (eq (team-status team) :paused)
    (setf (team-status team) :active)
    (%persist-team team)
    team))

(defun disband-team (team)
  "Disband a team: mark completed, optionally destroy workspace."
  (setf (team-status team) :completed)
  (%persist-team team)
  ;; Destroy workspace if it exists
  (when (and (team-workspace-id team)
             (find-package :autopoiesis.workspace))
    (let ((destroy-fn (find-symbol "DESTROY-WORKSPACE" :autopoiesis.workspace))
          (find-ws-fn (find-symbol "FIND-WORKSPACE" :autopoiesis.workspace)))
      (when (and destroy-fn find-ws-fn)
        (let ((ws (funcall find-ws-fn (team-workspace-id team))))
          (when ws
            (ignore-errors (funcall destroy-fn ws)))))))
  (unregister-team (team-id team))
  (%emit-team-event :team-completed (team-id team))
  team)

(defun query-team-status (team)
  "Return a comprehensive status plist for TEAM."
  (list :id (team-id team)
        :status (team-status team)
        :task (team-task team)
        :leader (team-leader team)
        :members (team-members team)
        :member-count (length (team-members team))
        :workspace-id (team-workspace-id team)
        :strategy (when (team-strategy team)
                    (type-of (team-strategy team)))
        :created-at (team-created-at team)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Team Member Management
;;; ═══════════════════════════════════════════════════════════════════

(defun add-team-member (team agent-id)
  "Add AGENT-ID to the team's member list."
  (pushnew agent-id (team-members team) :test #'equal)
  (%persist-team team)
  (%emit-team-event :team-member-joined (team-id team)
                    :agent-id agent-id)
  team)

(defun remove-team-member (team agent-id)
  "Remove AGENT-ID from the team's member list."
  (setf (team-members team)
        (remove agent-id (team-members team) :test #'equal))
  (%persist-team team)
  (%emit-team-event :team-member-left (team-id team)
                    :agent-id agent-id)
  team)

;;; ═══════════════════════════════════════════════════════════════════
;;; Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun team-to-plist (team)
  "Serialize TEAM to a plist."
  (list :id (team-id team)
        :status (team-status team)
        :task (team-task team)
        :leader (team-leader team)
        :members (team-members team)
        :workspace-id (team-workspace-id team)
        :config (team-config team)
        :created-at (team-created-at team)))

(defun plist-to-team (plist)
  "Deserialize a team from PLIST."
  (make-instance 'team
                 :id (getf plist :id)
                 :status (getf plist :status)
                 :task (getf plist :task)
                 :leader (getf plist :leader)
                 :members (getf plist :members)
                 :workspace-id (getf plist :workspace-id)
                 :config (getf plist :config)
                 :created-at (getf plist :created-at)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Swarm Fitness Evaluation
;;; ═══════════════════════════════════════════════════════════════════

(defclass team-performance-fitness ()
  ((task-completion-rate :initarg :task-completion-rate
                         :accessor fitness-task-completion
                         :initform 0.0)
   (average-task-time :initarg :average-task-time
                      :accessor fitness-avg-task-time
                      :initform 0.0)
   (communication-efficiency :initarg :communication-efficiency
                             :accessor fitness-communication-efficiency
                             :initform 0.0)
   (conflict-resolution-score :initarg :conflict-resolution-score
                              :accessor fitness-conflict-resolution
                              :initform 0.0))
  (:documentation "Fitness metrics for team performance evaluation."))

(defun evaluate-team-fitness (team)
  "Evaluate TEAM's performance and return a fitness score [0,1].
    Uses workspace logs and task completion data."
  (let ((ws-id (team-workspace-id team)))
    (if ws-id
        (calculate-team-fitness-from-workspace team ws-id)
        0.5))) ;; Default fitness if no workspace data

(defun calculate-team-fitness-from-workspace (team workspace-id)
  "Calculate fitness metrics from workspace data."
  (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
    (if list-fn
        (let* ((tasks (funcall list-fn workspace-id))
               (completed (count :complete tasks :key (lambda (t) (getf t :status))))
               (total (length tasks))
               (completion-rate (if (> total 0) (/ completed total) 0.0)))
          ;; Create fitness object
          (make-instance 'team-performance-fitness
                         :task-completion-rate completion-rate
                         :average-task-time (estimate-avg-task-time tasks)
                         :communication-efficiency (estimate-communication-efficiency team workspace-id)
                         :conflict-resolution-score (estimate-conflict-resolution team workspace-id)))
        (make-instance 'team-performance-fitness))))

(defun estimate-avg-task-time (tasks)
  "Estimate average task completion time from TASKS data."
  (let ((times nil))
    (dolist (task tasks)
      (when (eq (getf task :status) :complete)
        (let ((created (getf task :created-at))
              (completed (getf task :completed-at)))
          (when (and created completed)
            (push (- completed created) times)))))
    (if times (/ (reduce #'+ times) (length times)) 0.0)))

(defun estimate-communication-efficiency (team workspace-id)
  "Estimate communication efficiency from workspace logs."
  ;; Simplified: higher efficiency = fewer log entries per task
  (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
    (if list-fn
        (let* ((tasks (funcall list-fn workspace-id))
               (task-count (max (length tasks) 1)))
          ;; Mock efficiency calculation
          (min 1.0 (/ 1.0 (log (1+ task-count)))))
        0.5)))

(defun estimate-conflict-resolution (team workspace-id)
  "Estimate conflict resolution effectiveness."
  ;; Simplified: based on team size and task completion
  (let ((member-count (length (team-members team))))
    (min 1.0 (/ 1.0 (log (1+ member-count))))))

(defun swarm-optimize-team-composition (team target-task)
  "Use swarm evolution to optimize TEAM composition for TARGET-TASK.
    Returns suggestions for team member changes."
  (let ((current-fitness (evaluate-team-fitness team)))
    ;; Generate composition variants and evaluate
    (let ((variants (generate-team-variants team target-task)))
      (evaluate-composition-variants variants target-task))))

(defun generate-team-variants (team target-task)
  "Generate alternative team compositions."
  ;; Simplified: return current team as single variant
  (list team))

(defun evaluate-composition-variants (variants target-task)
  "Evaluate different team compositions."
  ;; Return best variant (simplified)
  (first variants))

;;; ═══════════════════════════════════════════════════════════════════
;;; Dynamic Team Composition
;;; ═══════════════════════════════════════════════════════════════════

(defun optimize-team-for-task (team task)
  "Optimize TEAM composition for TASK using swarm evolution.
    Returns a new team with optimized member selection."
  (let ((available-agents (find-available-agents-for-task task)))
    (if available-agents
        (evolve-optimal-team-composition team available-agents task)
        team)))

(defun find-available-agents-for-task (task)
  "Find agents that could potentially work on TASK.
    Returns list of agent IDs suitable for the task."
  ;; Simplified: return mock agent list
  ;; Real implementation would query agent registry by capabilities
  '("agent-1" "agent-2" "agent-3" "agent-4"))

(defun evolve-optimal-team-composition (base-team available-agents task)
  "Use swarm evolution to find optimal team composition."
  (let* ((population-size 20)
         (generations 5)
         (population (generate-composition-population base-team available-agents population-size)))
    ;; Evolve population
    (let ((evolved (evolve-compositions population generations task)))
      ;; Return best composition
      (first evolved))))

(defun generate-composition-population (base-team available-agents size)
  "Generate initial population of team compositions."
  (loop for i from 1 to size
        collect (random-team-composition base-team available-agents)))

(defun random-team-composition (base-team available-agents)
  "Create a random team composition variant."
  (let* ((base-members (team-members base-team))
         (additional (set-difference available-agents base-members :test #'equal))
         (new-members (append base-members
                             (subseq additional 0 (random (length additional))))))
    (make-instance 'team
                   :id (format nil "~A-variant-~A" (team-id base-team) (random 1000))
                   :members new-members
                   :leader (or (team-leader base-team)
                              (when new-members (first new-members)))
                   :task (team-task base-team)
                   :workspace-id (team-workspace-id base-team))))

(defun evolve-compositions (population generations task)
  "Evolve team compositions over GENERATIONS."
  ;; Simplified evolution: just sort by fitness and return top
  (let ((scored (mapcar (lambda (team)
                         (cons team (evaluate-team-fitness team)))
                       population)))
    (mapcar #'car (sort scored #'> :key #'cdr))))

(defun evolve-team-membership (team evolution-params)
  "Evolve team membership over time based on performance.
    EVOLUTION-PARAMS contains evolution settings."
  (let ((generations (getf evolution-params :generations 3))
        (mutation-rate (getf evolution-params :mutation-rate 0.1)))
    ;; Track performance history and evolve membership
    (let ((performance-history (collect-team-performance-history team)))
      (generate-evolved-membership team performance-history evolution-params))))

(defun collect-team-performance-history (team)
  "Collect historical performance data for TEAM."
  ;; Simplified: return mock history
  '((:fitness 0.7 :tasks-completed 5)
    (:fitness 0.8 :tasks-completed 7)
    (:fitness 0.6 :tasks-completed 4)))

(defun generate-evolved-membership (team history params)
  "Generate evolved team membership based on HISTORY and PARAMS."
  ;; Simplified: return current team
  team)
