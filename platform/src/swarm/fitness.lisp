;;;; fitness.lisp - Fitness evaluation for genomes
;;;;
;;;; Provides single and multi-objective fitness evaluation with
;;;; optional parallel evaluation support.

(in-package #:autopoiesis.swarm)

;;; ===================================================================
;;; Fitness Evaluator Class
;;; ===================================================================

(defclass fitness-evaluator ()
  ((name :initarg :name
         :accessor evaluator-name
         :initform "default"
         :documentation "Human-readable name for this evaluator")
   (eval-fn :initarg :eval-fn
            :accessor evaluator-fn
            :documentation "Function (genome environment) -> score")
   (weights :initarg :weights
            :accessor evaluator-weights
            :initform nil
            :documentation "Multi-objective weight alist"))
  (:documentation "Evaluates genome fitness against an environment."))

(defun make-fitness-evaluator (&key (name "default") eval-fn weights)
  "Create a new fitness evaluator."
  (make-instance 'fitness-evaluator
                 :name name
                 :eval-fn eval-fn
                 :weights weights))

;;; ===================================================================
;;; Evaluation
;;; ===================================================================

(defun evaluate-fitness (evaluator genome environment)
  "Evaluate GENOME fitness using EVALUATOR in ENVIRONMENT.
   Stores the result in the genome's fitness slot and returns the score."
  (let ((score (funcall (evaluator-fn evaluator) genome environment)))
    (setf (genome-fitness genome) score)
    score))

(defun evaluate-population (evaluator population environment &key parallel)
  "Evaluate fitness for all genomes in POPULATION.
   When PARALLEL is T, attempts to use lparallel:pmap if available.
   Returns list of scored genomes."
  (let* ((genomes (population-genomes population))
         (eval-one (lambda (g)
                     (evaluate-fitness evaluator g environment)
                     g)))
    (if (and parallel
             (find-package :lparallel)
             (let ((kernel-sym (find-symbol "*KERNEL*" :lparallel)))
               (and kernel-sym
                    (boundp kernel-sym)
                    (symbol-value kernel-sym))))
        ;; parallel path
        (funcall (find-symbol "PMAP" :lparallel) 'list eval-one genomes)
        ;; sequential fallback
        (mapcar eval-one genomes))))
