(defmodule agent-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)
          (spawn-agent 1) (stop-agent 1) (list-agents 0)))

;;; Supervisor startup

(defun start_link ()
  (supervisor:start_link #(local agent-sup) 'agent-sup '()))

(defun init (_args)
  (let* ((sup-flags #M(strategy simple_one_for_one
                       intensity 3
                       period 60))
         (children (list (agent-worker-spec))))
    `#(ok #(,sup-flags ,children))))

(defun agent-worker-spec ()
  #M(id agent-worker
     start #(agent-worker start_link ())
     restart transient
     shutdown 5000
     type worker
     modules (agent-worker)))

;;; Public API

(defun spawn-agent (agent-config)
  "Start a new agent-worker child with the given config.
   The agent-config is appended to the child spec's start args,
   so agent-worker:start_link/1 receives it directly."
  (supervisor:start_child 'agent-sup (list agent-config)))

(defun stop-agent (pid)
  "Terminate an agent-worker by its pid."
  (supervisor:terminate_child 'agent-sup pid))

(defun list-agents ()
  "Return the list of active agent-worker children.
   Each entry is a tuple: #(id pid type modules)."
  (supervisor:which_children 'agent-sup))
