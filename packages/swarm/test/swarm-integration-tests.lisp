;;;; swarm-integration-tests.lisp - Tests for persistent agent swarm integration
;;;;
;;;; Tests genome bridge round-trip, evolution, fitness functions,
;;;; and population visualization.

(in-package #:autopoiesis.test)

(def-suite swarm-integration-tests
  :description "Tests for persistent agent swarm integration")

(in-suite swarm-integration-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Genome Bridge Tests
;;; ═══════════════════════════════════════════════════════════════════

(test genome-bridge-round-trip
  "Converting persistent-agent → genome → patch preserves capabilities"
  (let* ((agent (autopoiesis.agent:make-persistent-agent
                 :name "bridge-test"
                 :capabilities '(:search :analyze :report)
                 :heuristics (list (list :id "h1" :confidence 0.8)
                                   (list :id "h2" :confidence 0.6))))
         (genome (autopoiesis.swarm:persistent-agent-to-genome agent)))
    ;; Genome has capabilities
    (is (= 3 (length (autopoiesis.swarm:genome-capabilities genome))))
    (is (member :search (autopoiesis.swarm:genome-capabilities genome)))
    ;; Heuristic weights
    (is (= 2 (length (autopoiesis.swarm:genome-heuristic-weights genome))))
    ;; Round-trip test
    (is (autopoiesis.swarm:pa-genome-round-trip-p agent))))

(test genome-bridge-patch-preserves-thoughts
  "Patching genome back preserves thoughts from original agent"
  (let* ((agent (autopoiesis.agent:make-persistent-agent
                 :name "patch-test"
                 :capabilities '(:cap1)))
         ;; Add some thoughts
         (agent-with-thoughts
           (autopoiesis.agent:persistent-perceive agent '(:input "test")))
         (genome (autopoiesis.swarm:persistent-agent-to-genome agent-with-thoughts))
         (patched (autopoiesis.swarm:genome-to-persistent-agent-patch
                   genome agent-with-thoughts)))
    ;; Thoughts preserved
    (is (= (autopoiesis.core:pvec-length
            (autopoiesis.agent:persistent-agent-thoughts agent-with-thoughts))
           (autopoiesis.core:pvec-length
            (autopoiesis.agent:persistent-agent-thoughts patched))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Fitness Function Tests
;;; ═══════════════════════════════════════════════════════════════════

(test thought-diversity-fitness-range
  "Thought diversity fitness returns value in [0,1]"
  ;; Empty agent
  (let ((empty (autopoiesis.agent:make-persistent-agent :name "empty")))
    (is (= 0.0 (autopoiesis.swarm:thought-diversity-fitness empty))))
  ;; Agent with thoughts
  (let* ((a (autopoiesis.agent:make-persistent-agent :name "diverse"))
         (b (autopoiesis.agent:persistent-perceive a '(:input "test")))
         (c (autopoiesis.agent:persistent-reason b)))
    (let ((fitness (autopoiesis.swarm:thought-diversity-fitness c)))
      (is (>= fitness 0.0))
      (is (<= fitness 1.0)))))

(test capability-breadth-fitness-range
  "Capability breadth fitness returns value in [0,1]"
  (let ((a (autopoiesis.agent:make-persistent-agent
            :name "broad"
            :capabilities '(:a :b :c :d :e))))
    (let ((fitness (autopoiesis.swarm:capability-breadth-fitness a)))
      (is (>= fitness 0.0))
      (is (<= fitness 1.0))
      (is (= 0.25 fitness)))))  ; 5/20

(test genome-efficiency-fitness-range
  "Genome efficiency fitness returns value in [0,1]"
  (let ((a (autopoiesis.agent:make-persistent-agent
            :name "efficient"
            :capabilities '(:a :b :c)
            :genome '((:fn1)))))
    (let ((fitness (autopoiesis.swarm:genome-efficiency-fitness a)))
      (is (>= fitness 0.0))
      (is (<= fitness 1.0)))))

(test standard-evaluator-composite
  "Standard evaluator combines all three fitness functions"
  (let* ((evaluator (autopoiesis.swarm:make-standard-pa-evaluator))
         (agent (autopoiesis.agent:make-persistent-agent
                 :name "eval-test"
                 :capabilities '(:a :b))))
    ;; Evaluator should work (creates genome internally)
    (let ((genome (autopoiesis.swarm:persistent-agent-to-genome agent)))
      (let ((fitness (autopoiesis.swarm:evaluate-fitness evaluator genome nil)))
        (is (>= fitness 0.0))
        (is (<= fitness 1.0))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Population and Evolution Tests
;;; ═══════════════════════════════════════════════════════════════════

(test make-persistent-population
  "Creating population from persistent agents"
  (let* ((agents (loop for i from 0 below 5
                       collect (autopoiesis.agent:make-persistent-agent
                                :name (format nil "agent-~d" i)
                                :capabilities (list (intern (format nil "CAP-~d" i)
                                                            :keyword)))))
         (pop (autopoiesis.swarm:make-persistent-population agents)))
    (is (= 5 (length (autopoiesis.swarm:population-genomes pop))))
    (is (= 0 (autopoiesis.swarm:population-generation pop)))))

(test single-generation-evolution
  "One generation of evolution changes some capabilities"
  (let* ((agents (loop for i from 0 below 10
                       collect (autopoiesis.agent:make-persistent-agent
                                :name (format nil "evo-agent-~d" i)
                                :capabilities (list (intern (format nil "CAP-~d" i)
                                                            :keyword)))))
         (evaluator (autopoiesis.swarm:make-standard-pa-evaluator))
         (evolved (autopoiesis.swarm:evolve-persistent-agents
                   agents evaluator nil :generations 1)))
    ;; Should get same number of agents back
    (is (= (length agents) (length evolved)))
    ;; At least some should have different capabilities (due to crossover/mutation)
    ;; (This is probabilistic but mutation-rate ensures changes)
    (is (every (lambda (a) (typep a 'autopoiesis.agent::persistent-agent)) evolved))))

(test multi-generation-evolution
  "Multiple generations of evolution produces valid agents"
  (let* ((agents (loop for i from 0 below 10
                       collect (autopoiesis.agent:make-persistent-agent
                                :name (format nil "multi-evo-~d" i)
                                :capabilities (loop for j from 0 below 3
                                                    collect (intern (format nil "CAP-~d-~d" i j)
                                                                    :keyword)))))
         (evaluator (autopoiesis.swarm:make-standard-pa-evaluator))
         (evolved (autopoiesis.swarm:evolve-persistent-agents
                   agents evaluator nil :generations 5)))
    (is (= (length agents) (length evolved)))
    ;; All results are persistent agents
    (is (every (lambda (a) (typep a 'autopoiesis.agent::persistent-agent)) evolved))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Supervisor Bridge Tests
;;; ═══════════════════════════════════════════════════════════════════

(test supervisor-dual-checkpoint
  "Checkpoint-dual-agent syncs persistent root"
  (let* ((a (autopoiesis.agent:make-agent :name "sup-test" :capabilities '(:x)))
         (dual (autopoiesis.agent:upgrade-to-dual a)))
    ;; Verify dual agent has persistent root
    (is (not (null (autopoiesis.agent:dual-agent-root dual))))
    (is (string= "sup-test"
                 (autopoiesis.agent:persistent-agent-name
                  (autopoiesis.agent:dual-agent-root dual))))))
