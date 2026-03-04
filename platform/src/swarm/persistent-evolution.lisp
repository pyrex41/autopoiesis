;;;; persistent-evolution.lisp - Evolve persistent agents via swarm infrastructure
;;;;
;;;; Extracts genomes from persistent agents, runs the existing evolution
;;;; machinery, and patches results back into persistent agent structs.

(in-package #:autopoiesis.swarm)

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Population
;;; ═══════════════════════════════════════════════════════════════════

(defun make-persistent-population (agents)
  "Create a swarm population from a list of persistent-agent structs.
   Extracts genomes and creates a population ready for evolution."
  (let ((genomes (mapcar #'persistent-agent-to-genome agents)))
    (make-population :genomes genomes :size (length agents))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Evolution Loop
;;; ═══════════════════════════════════════════════════════════════════

(defun evolve-persistent-agents (agents evaluator environment
                                 &key (generations 10) target-fitness
                                      (elite-count 2) (tournament-size 3)
                                      (mutation-rate 0.1) parallel)
  "Evolve a list of persistent-agent structs through the swarm infrastructure.

   1. Extract genomes from agents
   2. Run evolution via existing run-evolution
   3. Patch evolved genomes back to persistent agent structs

   Returns a list of new persistent-agent structs with evolved traits.
   Original agents are not modified."
  (let* ((population (make-persistent-population agents))
         (evolved (run-evolution evaluator population environment
                                :generations generations
                                :target-fitness target-fitness
                                :elite-count elite-count
                                :tournament-size tournament-size
                                :mutation-rate mutation-rate
                                :parallel parallel))
         (evolved-genomes (population-genomes evolved)))
    ;; Patch evolved genomes back to persistent agents
    ;; Match by position: evolved-genomes[i] came from agents[i]
    ;; (accounting for selection/crossover, use best-effort matching)
    (loop for genome in evolved-genomes
          for i from 0
          for original = (if (< i (length agents))
                             (nth i agents)
                             (nth 0 agents))  ; fallback to first
          collect (genome-to-persistent-agent-patch genome original))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Fitness Evaluator Wrapper
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-agent-fitness-evaluator (eval-fn)
  "Create a fitness-evaluator that evaluates persistent agents.
   EVAL-FN receives a persistent-agent and returns a float in [0,1].
   The wrapper converts from genome to persistent-agent for evaluation."
  (make-fitness-evaluator
   :name "persistent-agent-evaluator"
   :eval-fn (lambda (genome environment)
         (declare (ignore environment))
         ;; Create a minimal persistent agent from the genome for evaluation
         (let ((pa (autopoiesis.agent:make-persistent-agent
                    :capabilities (genome-capabilities genome)
                    :genome (mapcar (lambda (p) (list :param (car p) :value (cdr p)))
                                    (genome-parameters genome)))))
           (funcall eval-fn pa)))))
