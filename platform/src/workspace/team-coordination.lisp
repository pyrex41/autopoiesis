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

(defun workspace-claim-task (workspace-id &optional agent-id)
  "Atomically claim a pending task from the workspace queue.
   Uses take! to ensure only one agent gets each task.
   AGENT-ID is the claiming agent's identifier.
   Returns (values task-id content) or nil if no tasks available."
  (let ((task-entities (autopoiesis.substrate:find-entities
                        :task/workspace-id workspace-id)))
    ;; Try to claim the first pending task
    (dolist (eid task-entities)
      (let ((status (autopoiesis.substrate:entity-attr eid :task/status)))
        (when (eq status :pending)
          ;; Atomic claim via take!
          (let ((claimed (autopoiesis.substrate:take!
                          :task/status :pending :new-value :in-progress)))
            (when claimed
              ;; Record who claimed it
              (when agent-id
                (autopoiesis.substrate:transact!
                 (list (autopoiesis.substrate:make-datom
                        eid :task/claimed-by agent-id)
                       (autopoiesis.substrate:make-datom
                        eid :task/claimed-at (get-universal-time)))))
              (let ((content (autopoiesis.substrate:entity-attr eid :task/content))
                    (task-id (autopoiesis.substrate:resolve-id eid)))
                (return (values task-id content))))))))))

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
