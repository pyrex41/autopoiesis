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
