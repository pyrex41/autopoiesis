;;;; packages.lisp - Swarm layer package definitions
;;;;
;;;; Defines packages for evolutionary swarm primitives and production rules.

(in-package #:cl-user)

(defpackage #:autopoiesis.swarm
  (:use #:cl #:alexandria #:autopoiesis.core)
  (:export
   ;; Genome
   #:genome
   #:make-genome
   #:genome-id
   #:genome-capabilities
   #:genome-heuristic-weights
   #:genome-parameters
   #:genome-lineage
   #:genome-fitness
   #:genome-generation
   #:genome-to-sexpr
   #:sexpr-to-genome
   #:instantiate-agent-from-genome

   ;; Fitness evaluation
   #:fitness-evaluator
   #:make-fitness-evaluator
   #:evaluator-name
   #:evaluator-fn
   #:evaluator-weights
   #:evaluate-fitness
   #:evaluate-population

   ;; Selection operators
   #:tournament-select
   #:roulette-select
   #:elitism-select

   ;; Genetic operators
   #:crossover-genomes
   #:mutate-genome

   ;; Population
   #:population
   #:make-population
   #:population-genomes
   #:population-generation
   #:population-size
   #:population-history
   #:evolve-generation
   #:run-evolution

   ;; Production rules
   #:production-rule
   #:make-production-rule
   #:rule-condition
   #:rule-action
   #:rule-priority
   #:rule-source
   #:apply-production-rules
   #:extract-production-rules

   ;; Persistent agent genome bridge
   #:persistent-agent-to-genome
   #:genome-to-persistent-agent-patch
   #:pa-genome-round-trip-p
   ;; Persistent evolution
   #:make-persistent-population
   #:evolve-persistent-agents
   #:persistent-agent-fitness-evaluator
   ;; Persistent fitness functions
   #:thought-diversity-fitness
   #:capability-breadth-fitness
   #:genome-efficiency-fitness
   #:make-standard-pa-evaluator))
