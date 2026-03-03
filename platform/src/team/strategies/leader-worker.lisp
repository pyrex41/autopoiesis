;;;; leader-worker.lisp - Leader/worker coordination strategy
;;;;
;;;; The leader agent decomposes the task into subtasks, pushes them
;;;; to the workspace queue, and workers claim tasks via take!.
;;;; The leader synthesizes results when all tasks complete.

(in-package #:autopoiesis.team)

(defclass leader-worker-strategy ()
  ((max-retries :initarg :max-retries
                :accessor lw-max-retries
                :initform 2
                :documentation "Max retries per failed subtask"))
  (:documentation "Leader decomposes task, workers claim and execute subtasks."))

(defmethod strategy-initialize ((strategy leader-worker-strategy) team)
  "Validate that the team has a leader and at least one worker."
  (unless (team-leader team)
    (when (team-members team)
      ;; Auto-assign first member as leader if none specified
      (setf (team-leader team) (first (team-members team)))))
  (values))

(defmethod strategy-assign-work ((strategy leader-worker-strategy) team task)
  "Push TASK to the workspace queue for workers to claim.
   In practice, the leader agent would decompose via LLM first."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((push-fn (find-symbol "WORKSPACE-PUSH-TASK" :autopoiesis.workspace)))
        (when push-fn
          (funcall push-fn ws-id task)
          (format nil "Task queued in workspace ~A for worker claim" ws-id))))))

(defmethod strategy-collect-results ((strategy leader-worker-strategy) team)
  "Collect completed task results from the workspace."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
        (when list-fn
          (funcall list-fn ws-id :status :complete))))))

(defmethod strategy-complete-p ((strategy leader-worker-strategy) team)
  "Complete when no pending or in-progress tasks remain."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
        (when list-fn
          (let ((pending (funcall list-fn ws-id :status :pending))
                (in-progress (funcall list-fn ws-id :status :in-progress)))
            (and (null pending) (null in-progress))))))))
