;;;; checkpoint.lisp - Agent checkpoint and revert operations
;;;;
;;;; Provides checkpoint creation, revert-to-stable, and promotion for
;;;; the supervisor's checkpoint-and-revert pattern.

(in-package #:autopoiesis.supervisor)

;;; ═══════════════════════════════════════════════════════════════════
;;; Checkpoint State
;;; ═══════════════════════════════════════════════════════════════════

(defvar *stable-root* nil
  "Snapshot ID of last known-good agent state.")

(defvar *checkpoint-stack* nil
  "Stack of (snapshot-id . operation-name) entries.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Checkpoint Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun checkpoint-agent (agent &key operation)
  "Create a checkpoint snapshot of AGENT's current state.

   Serializes the agent, creates a snapshot with metadata, optionally
   persists it, and pushes it onto the checkpoint stack.

   Returns the snapshot."
  (let* ((agent-state (autopoiesis.agent:agent-to-sexpr agent))
         (snap (autopoiesis.snapshot:make-snapshot
                agent-state
                :metadata (list :operation operation
                                :checkpoint-time (get-universal-time)))))
    ;; Persist if store is available
    (when autopoiesis.snapshot:*snapshot-store*
      (autopoiesis.snapshot:save-snapshot snap))
    ;; Push onto checkpoint stack
    (push (cons (autopoiesis.snapshot:snapshot-id snap) operation)
          *checkpoint-stack*)
    snap))

(defun revert-to-stable (agent &key target)
  "Revert AGENT to a checkpointed state.

   TARGET - specific snapshot ID to revert to. If not provided, uses the
   top of the checkpoint stack, or *stable-root* as fallback.

   Returns the modified agent."
  (let ((snap-id (or target
                     (car (first *checkpoint-stack*))
                     *stable-root*)))
    (unless snap-id
      (error 'autopoiesis-error
             :message "No checkpoint available for revert"))
    ;; Load the snapshot
    (unless autopoiesis.snapshot:*snapshot-store*
      (error 'autopoiesis-error
             :message "No snapshot store available for revert"))
    (let ((snap (autopoiesis.snapshot:load-snapshot snap-id)))
      (unless snap
        (error 'autopoiesis-error
               :message (format nil "Checkpoint snapshot not found: ~a" snap-id)))
      ;; Reconstruct agent from snapshot state
      (let ((restored (autopoiesis.agent:sexpr-to-agent
                       (autopoiesis.snapshot:snapshot-agent-state snap))))
        (unless restored
          (error 'autopoiesis-error
                 :message "Failed to reconstruct agent from checkpoint"))
        ;; Copy restored slots back into the live agent
        (setf (autopoiesis.agent:agent-state agent)
              (autopoiesis.agent:agent-state restored))
        (setf (autopoiesis.agent:agent-name agent)
              (autopoiesis.agent:agent-name restored))
        (setf (autopoiesis.agent:agent-capabilities agent)
              (autopoiesis.agent:agent-capabilities restored))
        (setf (autopoiesis.agent:agent-thought-stream agent)
              (autopoiesis.agent:agent-thought-stream restored))
        (setf (autopoiesis.agent:agent-parent agent)
              (autopoiesis.agent:agent-parent restored))
        (setf (autopoiesis.agent:agent-children agent)
              (autopoiesis.agent:agent-children restored))
        agent))))

(defun promote-checkpoint ()
  "Promote the most recent checkpoint to stable-root.

   Pops the top of the checkpoint stack and sets *stable-root* to it.
   Returns the promoted snapshot ID."
  (let ((entry (pop *checkpoint-stack*)))
    (unless entry
      (error 'autopoiesis-error
             :message "No checkpoint to promote"))
    (setf *stable-root* (car entry))
    (car entry)))

(defun supervisor-status ()
  "Return a plist describing the current supervisor state."
  (list :stable-root *stable-root*
        :checkpoint-depth (length *checkpoint-stack*)
        :stack (mapcar (lambda (entry)
                         (list :id (car entry) :operation (cdr entry)))
                       *checkpoint-stack*)))
