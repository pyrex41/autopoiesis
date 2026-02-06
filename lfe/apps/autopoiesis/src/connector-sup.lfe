(defmodule connector-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)))

(defun start_link ()
  (supervisor:start_link #(local connector-sup) 'connector-sup '()))

(defun init (_args)
  (let* ((sup-flags #M(strategy one_for_one
                       intensity 5
                       period 10))
         (children (list (webhook-server-spec))))
    `#(ok #(,sup-flags ,children))))

(defun webhook-server-spec ()
  #M(id webhook-server
     start #(webhook-server start_link ())
     restart permanent
     shutdown 5000
     type worker
     modules (webhook-server)))