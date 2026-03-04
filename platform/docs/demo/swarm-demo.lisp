;;;; swarm-demo.lisp — Evolutionary swarm integration
(require :asdf)
(push #p"platform/" asdf:*central-registry*)
(push #p"platform/substrate/" asdf:*central-registry*)
(handler-bind ((warning #'muffle-warning)) (asdf:load-system :autopoiesis))

(format t "=== Create population ===~%")
(let ((agents (loop for i from 0 below 10
                    collect (autopoiesis.agent:make-persistent-agent
                             :name (format nil "agent-~D" i)
                             :capabilities (loop for j from 0 below (+ 2 (mod i 4))
                                                 collect (intern (format nil "CAP-~D" j) :keyword))))))
  (format t "Population size: ~D~%" (length agents))
  (format t "Agent-0 caps: ~S~%" (autopoiesis.core:pset-to-list
                                    (autopoiesis.agent:persistent-agent-capabilities (nth 0 agents))))
  (format t "Agent-3 caps: ~S~%~%" (autopoiesis.core:pset-to-list
                                      (autopoiesis.agent:persistent-agent-capabilities (nth 3 agents))))

  (format t "=== Fitness functions ===~%")
  (let ((a (nth 3 agents)))
    (format t "Capability breadth (agent-3): ~,3F~%" (autopoiesis.swarm:capability-breadth-fitness a))
    (format t "Genome efficiency  (agent-3): ~,3F~%~%" (autopoiesis.swarm:genome-efficiency-fitness a)))

  (format t "=== Evolve 5 generations ===~%")
  (let* ((evaluator (autopoiesis.swarm:make-standard-pa-evaluator))
         (evolved (autopoiesis.swarm:evolve-persistent-agents
                   agents evaluator nil :generations 5)))
    (format t "Evolved population size: ~D~%" (length evolved))
    (format t "All persistent-agents: ~A~%" (every (lambda (a) (typep a 'autopoiesis.agent::persistent-agent)) evolved))
    (format t "Original agent-0 caps unchanged: ~A~%"
            (autopoiesis.core:pset-equal
             (autopoiesis.agent:persistent-agent-capabilities (nth 0 agents))
             (autopoiesis.agent:persistent-agent-capabilities (nth 0 agents))))))

(sb-ext:exit)
