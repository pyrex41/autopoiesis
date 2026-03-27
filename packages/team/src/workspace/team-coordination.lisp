;;;; team-coordination.lisp - Workspace extensions for team coordination
;;;;
;;;; Provides shared memory, task queue, and coordination log via
;;;; substrate datoms within a team's workspace context.

(in-package #:autopoiesis.workspace)

;;; ═══════════════════════════════════════════════════════════════════
;;; Shared Memory (key-value via substrate)
;;; ═══════════════════════════════════════════════════════════════════

(defun workspace-put (workspace-id key value)
  "Store VALUE under KEY in the workspace's shared memory.
   KEY is a string; VALUE can be any serializable value."
  (let* ((ns-key (format nil "ws-kv/~A/~A" workspace-id key))
         (eid (autopoiesis.substrate:intern-id ns-key)))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom eid :kv/workspace workspace-id)
           (autopoiesis.substrate:make-datom eid :kv/key key)
           (autopoiesis.substrate:make-datom eid :kv/value value)))
    value))

(defun workspace-get (workspace-id key)
  "Retrieve the value stored under KEY in the workspace's shared memory.
   Returns nil if not found."
  (let* ((ns-key (format nil "ws-kv/~A/~A" workspace-id key))
         (eid (autopoiesis.substrate:intern-id ns-key)))
    (autopoiesis.substrate:entity-attr eid :kv/value)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Task Queue (individual substrate entities for atomic claim)
;;; ═══════════════════════════════════════════════════════════════════

(defun workspace-push-task (workspace-id content &key priority)
  "Create a new task entity in the workspace's task queue.
   CONTENT is the task description/data.
   PRIORITY is an optional numeric priority (lower = higher priority).
   Returns the task entity ID."
  (let* ((task-id (format nil "ws-task/~A/~A" workspace-id
                          (autopoiesis.core:make-uuid)))
         (eid (autopoiesis.substrate:intern-id task-id)))
    (autopoiesis.substrate:transact!
     (append
      (list (autopoiesis.substrate:make-datom eid :task/workspace-id workspace-id)
            (autopoiesis.substrate:make-datom eid :task/status :pending)
            (autopoiesis.substrate:make-datom eid :task/content content)
            (autopoiesis.substrate:make-datom eid :task/created-at (get-universal-time)))
      (when priority
        (list (autopoiesis.substrate:make-datom eid :task/priority priority)))))
    task-id))

(defun task-priority-greater-p (eid1 eid2)
  "Return T if EID1 has higher priority than EID2.
    Higher priority = lower numeric priority value, or earlier creation time if equal."
  (let ((p1 (or (autopoiesis.substrate:entity-attr eid1 :task/priority) 0))
        (p2 (or (autopoiesis.substrate:entity-attr eid2 :task/priority) 0)))
    (cond
      ((< p1 p2) t)
      ((> p1 p2) nil)
      (t ;; Same priority, earlier creation time wins
       (let ((t1 (autopoiesis.substrate:entity-attr eid1 :task/created-at))
             (t2 (autopoiesis.substrate:entity-attr eid2 :task/created-at)))
         (< t1 t2))))))

(defun workspace-claim-task (workspace-id &optional agent-id agent-fitness)
  "Atomically claim a pending task from the workspace queue.
    Uses take! to ensure only one agent gets each task.
    AGENT-ID is the claiming agent's identifier.
    AGENT-FITNESS is an optional fitness score [0,1] for swarm-based prioritization.
    Returns (values task-id content) or nil if no tasks available."
  (let ((task-entities (autopoiesis.substrate:find-entities
                        :task/workspace-id workspace-id)))
    ;; Sort tasks by priority (higher priority first), then by creation time
    (let ((pending-tasks
           (sort (remove-if-not
                  (lambda (eid)
                    (eq (autopoiesis.substrate:entity-attr eid :task/status) :pending))
                  task-entities)
                 #'task-priority-greater-p)))
      ;; Try to claim the highest priority pending task
      (dolist (eid pending-tasks)
        ;; Atomic claim via take!
        (let ((claimed (autopoiesis.substrate:take!
                        :task/status :pending :new-value :in-progress)))
          (when claimed
            ;; Record who claimed it and their fitness
            (when agent-id
              (autopoiesis.substrate:transact!
               (append
                (list (autopoiesis.substrate:make-datom
                       eid :task/claimed-by agent-id)
                      (autopoiesis.substrate:make-datom
                       eid :task/claimed-at (get-universal-time)))
                (when agent-fitness
                  (list (autopoiesis.substrate:make-datom
                         eid :task/claimed-fitness agent-fitness))))))
            (let ((content (autopoiesis.substrate:entity-attr eid :task/content))
                  (task-id (autopoiesis.substrate:resolve-id eid)))
              (return (values task-id content)))))))))

(defun workspace-submit-result (task-id result)
  "Mark TASK-ID as complete and store its RESULT."
  (let ((eid (autopoiesis.substrate:intern-id task-id)))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom eid :task/status :complete)
           (autopoiesis.substrate:make-datom eid :task/result result)
           (autopoiesis.substrate:make-datom eid :task/completed-at (get-universal-time))))
    task-id))

(defun workspace-list-tasks (workspace-id &key status)
  "List all tasks in the workspace, optionally filtered by STATUS.
   Returns a list of plists with task details."
  (let ((task-entities (autopoiesis.substrate:find-entities
                        :task/workspace-id workspace-id))
        (results nil))
    (dolist (eid task-entities)
      (let* ((attrs (autopoiesis.substrate:pull eid
                      '(:task/status :task/content :task/claimed-by :task/result)))
             (task-status (getf attrs :task/status)))
        (when (or (null status) (eq task-status status))
          (push (list :id (autopoiesis.substrate:resolve-id eid)
                      :status task-status
                      :content (getf attrs :task/content)
                      :claimed-by (getf attrs :task/claimed-by)
                      :result (getf attrs :task/result))
                results))))
    (nreverse results)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Coordination Log
;;; ═══════════════════════════════════════════════════════════════════

(defun workspace-log-entry (workspace-id agent-id message &key level)
  "Append a log entry to the workspace's coordination log.
    LEVEL defaults to :info."
  (let* ((log-id (format nil "ws-log/~A/~A" workspace-id
                         (autopoiesis.core:make-uuid)))
         (eid (autopoiesis.substrate:intern-id log-id)))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom eid :log/workspace-id workspace-id)
           (autopoiesis.substrate:make-datom eid :log/agent-id agent-id)
           (autopoiesis.substrate:make-datom eid :log/message message)
           (autopoiesis.substrate:make-datom eid :log/level (or level :info))
           (autopoiesis.substrate:make-datom eid :log/timestamp (get-universal-time))))
    log-id))

;;; ═══════════════════════════════════════════════════════════════════
;;; Swarm Evolution State Storage
;;; ═══════════════════════════════════════════════════════════════════

(defclass swarm-evolution-state ()
  ((population :initarg :population :accessor swarm-population)
   (generation :initarg :generation :accessor swarm-generation)
   (fitness-scores :initarg :fitness-scores :accessor swarm-fitness-scores)
   (best-individual :initarg :best-individual :accessor swarm-best-individual))
  (:documentation "Serializable state of a swarm evolution run."))

(defun workspace-store-swarm-state (workspace-id evolution-state)
  "Store SWARM-EVOLUTION-STATE in the workspace's shared storage."
  (let ((key "swarm-evolution-state"))
    (workspace-put workspace-id key evolution-state)))

(defun workspace-load-swarm-state (workspace-id)
  "Load swarm evolution state from workspace storage.
    Returns nil if no state stored."
  (let ((key "swarm-evolution-state"))
    (workspace-get workspace-id key)))

(defun workspace-store-swarm-results (workspace-id results)
  "Store swarm evolution RESULTS in the workspace."
  (let ((key "swarm-evolution-results"))
    (workspace-put workspace-id key results)))

(defun workspace-load-swarm-results (workspace-id)
  "Load swarm evolution results from workspace storage."
  (let ((key "swarm-evolution-results"))
    (workspace-get workspace-id key)))

(defun workspace-record-swarm-metrics (workspace-id generation fitness-stats)
  "Record swarm evolution metrics for GENERATION."
  (let ((key (format nil "swarm-metrics-~A" generation)))
    (workspace-put workspace-id key fitness-stats)))

(defun workspace-get-swarm-history (workspace-id)
  "Return historical swarm metrics across all generations."
  (let ((metrics nil))
    (dotimes (gen 100) ;; Reasonable upper bound
      (let ((key (format nil "swarm-metrics-~A" gen))
            (stats (workspace-get workspace-id key)))
        (when stats
          (push (cons gen stats) metrics))))
    (nreverse metrics)))
