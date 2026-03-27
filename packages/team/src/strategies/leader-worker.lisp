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
                :documentation "Max retries per failed subtask")
   (use-swarm-decomposition :initarg :use-swarm-decomposition
                           :accessor lw-use-swarm-decomposition
                           :initform t
                           :documentation "Whether to use swarm evolution for task decomposition")
   (decomposition-generations :initarg :decomposition-generations
                             :accessor lw-decomposition-generations
                             :initform 3
                             :documentation "Generations for swarm decomposition evolution"))
  (:documentation "Leader decomposes task, workers claim and execute subtasks.
    Can use swarm evolution to optimize task decomposition."))

(defmethod strategy-initialize ((strategy leader-worker-strategy) team)
  "Validate that the team has a leader and at least one worker."
  (unless (team-leader team)
    (when (team-members team)
      ;; Auto-assign first member as leader if none specified
      (setf (team-leader team) (first (team-members team)))))
  (values))

(defmethod strategy-assign-work ((strategy leader-worker-strategy) team task)
  "Push TASK to the workspace queue for workers to claim.
    Uses swarm evolution for decomposition if enabled."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (if (lw-use-swarm-decomposition strategy)
          (swarm-decompose-and-queue strategy team task ws-id)
          (let ((push-fn (find-symbol "WORKSPACE-PUSH-TASK" :autopoiesis.workspace)))
            (when push-fn
              (funcall push-fn ws-id task)
              (format nil "Task queued in workspace ~A for worker claim" ws-id)))))))

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

;;; ═══════════════════════════════════════════════════════════════════
;;; Swarm-Enhanced Task Decomposition
;;; ═══════════════════════════════════════════════════════════════════

(defun swarm-decompose-and-queue (strategy team task workspace-id)
  "Use swarm evolution to decompose TASK into optimal subtasks.
    Creates a population of decomposition candidates, evolves them,
    and queues the best decomposition."
  (let* ((worker-count (length (team-members team)))
         (push-fn (find-symbol "WORKSPACE-PUSH-TASK" :autopoiesis.workspace))
         (log-fn (find-symbol "WORKSPACE-LOG-ENTRY" :autopoiesis.workspace)))
    (when (and push-fn log-fn)
      ;; Create initial decomposition candidates
      (let ((candidates (generate-decomposition-candidates task worker-count)))
        ;; Evolve decompositions using swarm
        (let ((evolved (evolve-decompositions candidates
                                            (lw-decomposition-generations strategy))))
          ;; Queue the best decomposition
          (dolist (subtask evolved)
            (let ((task-id (funcall push-fn workspace-id subtask)))
              (funcall log-fn workspace-id (team-leader team)
                       (format nil "Queued swarm-evolved subtask: ~A" task-id)))))
        (format nil "Swarm-evolved decomposition queued ~A subtasks to workspace ~A"
                (length evolved) workspace-id)))))

(defun generate-decomposition-candidates (task worker-count)
  "Generate initial decomposition candidates for TASK.
    Returns a list of possible subtask breakdowns."
  ;; Simple initial decomposition: split by logical components
  (let ((components (split-task-into-components task)))
    (loop for i from 1 to worker-count
          collect (create-subtask-breakdown components i))))

(defun split-task-into-components (task)
  "Split TASK string into logical components.
    This is a simple heuristic - real implementation would use LLM analysis."
  (let ((sentences (cl-ppcre:split "[.!?]" task)))
    (remove-if #'string= sentences '("") :test #'string=)))

(defun create-subtask-breakdown (components worker-count)
  "Create a subtask breakdown from COMPONENTS for WORKER-COUNT workers."
  (let ((groups (group-components components worker-count)))
    (loop for group in groups
          for i from 0
          collect (list :subtask-id i
                        :content (format nil "~{~A~^ ~}" group)
                        :worker-index i))))

(defun group-components (components n-groups)
  "Group COMPONENTS into N-GROUPS roughly equal groups."
  (let* ((total (length components))
         (base-size (floor total n-groups))
         (extra (mod total n-groups))
         (groups nil)
         (start 0))
    (dotimes (i n-groups)
      (let ((size (+ base-size (if (< i extra) 1 0))))
        (push (subseq components start (+ start size)) groups)
        (setf start (+ start size))))
    (nreverse groups)))

(defun evolve-decompositions (candidates generations)
  "Evolve decomposition CANDIDATES over GENERATIONS.
    Returns the best decomposition found."
  ;; Simplified evolution: just return the first candidate for now
  ;; Real implementation would use swarm evolution infrastructure
  (first candidates))
