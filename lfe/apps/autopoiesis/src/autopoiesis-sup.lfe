(defmodule autopoiesis-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)))

(defun start_link ()
  (supervisor:start_link #(local autopoiesis-sup) 'autopoiesis-sup '()))

(defun init (_args)
  (let* ((sup-flags #M(strategy one_for_one
                       intensity 5
                       period 10))
         (children (list (conductor-spec)
                          (agent-sup-spec)
                          (connector-sup-spec))))
    `#(ok #(,sup-flags ,children))))

(defun agent-sup-spec ()
  #M(id agent-sup
     start #(agent-sup start_link ())
     restart permanent
     shutdown infinity
     type supervisor
     modules (agent-sup)))

(defun connector-sup-spec ()
   #M(id connector-sup
      start #(connector-sup start_link ())
      restart permanent
      shutdown infinity
      type supervisor
      modules (connector-sup)))

(defun conductor-spec ()
   #M(id conductor
      start #(conductor start_link ())
      restart permanent
      shutdown 5000
      type worker
      modules (conductor)))
