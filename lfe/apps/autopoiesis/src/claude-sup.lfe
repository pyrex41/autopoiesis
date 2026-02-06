(defmodule claude-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)
          (spawn-claude-agent 1)
          (stop-claude-agent 1)
          (list-claude-agents 0)))

(defun start_link ()
  (supervisor:start_link #(local claude-sup) 'claude-sup '()))

(defun init (_args)
  (let* ((sup-flags #M(strategy simple_one_for_one
                       intensity 3
                       period 60))
         (children (list (claude-worker-spec))))
    `#(ok #(,sup-flags ,children))))

(defun claude-worker-spec ()
  #M(id claude-worker
     start #(claude-worker start_link ())
     restart transient
     shutdown 10000
     type worker
     modules (claude-worker)))

(defun spawn-claude-agent (task-config)
  "Spawn a Claude Code agent worker for a task."
  (supervisor:start_child 'claude-sup (list task-config)))

(defun stop-claude-agent (pid)
  "Stop a Claude agent worker."
  (supervisor:terminate_child 'claude-sup pid))

(defun list-claude-agents ()
  "List all running Claude agent workers."
  (supervisor:which_children 'claude-sup))
