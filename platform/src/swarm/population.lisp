;;;; population.lisp - Population management and evolution loop
;;;;
;;;; Manages a population of genomes through generational evolution
;;;; with configurable selection, crossover, and mutation parameters.

(in-package #:autopoiesis.swarm)

;;; ===================================================================
;;; Population Class
;;; ===================================================================

(defclass population ()
  ((genomes :initarg :genomes
            :accessor population-genomes
            :initform nil
            :documentation "List of genomes in this population")
   (generation :initarg :generation
               :accessor population-generation
               :initform 0
               :documentation "Current generation number")
   (size :initarg :size
         :accessor population-size
         :initform 20
         :documentation "Target population size")
   (history :initarg :history
            :accessor population-history
            :initform nil
            :documentation "List of (generation best-fitness avg-fitness)"))
  (:documentation "A population of genomes undergoing evolution."))

(defun make-population (&key genomes (size 20))
  "Create a population. If GENOMES is nil, create SIZE empty genomes."
  (let ((actual-genomes (or genomes
                            (loop repeat size collect (make-genome)))))
    (make-instance 'population
                   :genomes actual-genomes
                   :size (or size (length actual-genomes)))))

;;; ===================================================================
;;; Evolution
;;; ===================================================================

(defun evolve-generation (evaluator population environment
                          &key (elite-count 2) (tournament-size 3)
                               (mutation-rate 0.1) parallel)
  "Evolve POPULATION by one generation.
   1. Evaluate all genomes
   2. Record stats in history
   3. Select elites
   4. Fill remaining slots via tournament + crossover + mutation
   Returns a new population with incremented generation."
  ;; Step 1: evaluate fitness
  (evaluate-population evaluator population environment :parallel parallel)
  ;; Step 2: record stats
  (let* ((genomes (population-genomes population))
         (fitnesses (mapcar #'genome-fitness genomes))
         (best-fit (reduce #'max fitnesses))
         (avg-fit (/ (reduce #'+ fitnesses) (max 1 (length fitnesses))))
         (gen (population-generation population))
         (new-history (cons (list gen best-fit avg-fit)
                            (population-history population))))
    ;; Step 3: select elites
    (let* ((elites (elitism-select population :count elite-count))
           (target-size (population-size population))
           (remaining (- target-size (length elites)))
           (offspring nil))
      ;; Step 4: fill remaining via tournament + crossover + mutation
      (dotimes (i remaining)
        (declare (ignore i))
        (let* ((parent-a (tournament-select population :tournament-size tournament-size))
               (parent-b (tournament-select population :tournament-size tournament-size))
               (child (crossover-genomes parent-a parent-b))
               (mutated (mutate-genome child :mutation-rate mutation-rate)))
          (push mutated offspring)))
      ;; Return new population
      (make-instance 'population
                     :genomes (append (copy-list elites) (nreverse offspring))
                     :generation (1+ gen)
                     :size target-size
                     :history new-history))))

(defun run-evolution (evaluator population environment
                      &key (generations 10) target-fitness
                           (elite-count 2) (tournament-size 3)
                           (mutation-rate 0.1) parallel)
  "Run evolution for GENERATIONS steps or until TARGET-FITNESS is reached.
   Returns the final population."
  (let ((current population))
    (dotimes (i generations current)
      (declare (ignore i))
      (setf current
            (evolve-generation evaluator current environment
                              :elite-count elite-count
                              :tournament-size tournament-size
                              :mutation-rate mutation-rate
                              :parallel parallel))
      ;; Check early termination
      (when target-fitness
        (let ((best (reduce #'max (population-genomes current)
                            :key #'genome-fitness)))
          (when (>= (genome-fitness best) target-fitness)
            (return current)))))))
