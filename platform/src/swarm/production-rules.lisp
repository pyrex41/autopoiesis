;;;; production-rules.lisp - Production rule system for genome transformation
;;;;
;;;; Production rules encode conditional genome transformations that can be
;;;; manually defined, learned from heuristics, or evolved through selection.

(in-package #:autopoiesis.swarm)

;;; ===================================================================
;;; Production Rule Class
;;; ===================================================================

(defclass production-rule ()
  ((condition :initarg :condition
              :accessor rule-condition
              :documentation "S-expr pattern to match")
   (action :initarg :action
           :accessor rule-action
           :documentation "Function (genome) -> genome transform")
   (priority :initarg :priority
             :accessor rule-priority
             :initform 0
             :documentation "Higher priority rules apply first")
   (source :initarg :source
           :accessor rule-source
           :initform :manual
           :documentation ":manual, :learned, or :evolved"))
  (:documentation "A conditional transformation rule for genomes."))

(defun make-production-rule (&key condition action (priority 0) (source :manual))
  "Create a new production rule."
  (make-instance 'production-rule
                 :condition condition
                 :action action
                 :priority priority
                 :source source))

;;; ===================================================================
;;; Rule Extraction from Heuristics
;;; ===================================================================

(defun extract-production-rules (heuristics &key (min-confidence 0.7))
  "Extract production rules from learned heuristics.
   Only heuristics with confidence >= MIN-CONFIDENCE are converted."
  (loop for h in heuristics
        when (>= (autopoiesis.agent:heuristic-confidence h) min-confidence)
          collect (let ((rec (autopoiesis.agent:heuristic-recommendation h)))
                    (make-production-rule
                     :condition (autopoiesis.agent:heuristic-condition h)
                     :action (lambda (genome)
                               ;; Add the heuristic's recommendation to genome parameters
                               (let ((params (copy-list (genome-parameters genome))))
                                 (setf (getf params :learned-recommendation) rec)
                                 (make-genome
                                  :capabilities (genome-capabilities genome)
                                  :heuristic-weights (genome-heuristic-weights genome)
                                  :parameters params
                                  :lineage (genome-lineage genome)
                                  :generation (genome-generation genome))))
                     :priority (round (* (autopoiesis.agent:heuristic-confidence h) 100))
                     :source :learned))))

;;; ===================================================================
;;; Rule Application
;;; ===================================================================

(defun condition-matches-genome-p (condition genome)
  "Check if CONDITION matches some property of GENOME.
   T always matches. Otherwise checks sexpr-equal against capabilities."
  (cond
    ((eq condition t) t)
    ((null condition) nil)
    ;; Check if condition matches capability list
    ((autopoiesis.core:sexpr-equal condition (genome-capabilities genome)) t)
    ;; Check if condition is a member of capabilities
    ((member condition (genome-capabilities genome) :test #'equal) t)
    ;; Check if condition matches any parameter value
    ((loop for (k v) on (genome-parameters genome) by #'cddr
           thereis (autopoiesis.core:sexpr-equal condition v))
     t)
    (t nil)))

(defun apply-production-rules (genome rules)
  "Apply RULES to GENOME in priority order (highest first).
   Rules whose condition matches are applied sequentially.
   Returns a (potentially modified) genome copy."
  (let ((sorted (sort (copy-list rules) #'> :key #'rule-priority))
        (current genome))
    (dolist (rule sorted current)
      (when (condition-matches-genome-p (rule-condition rule) current)
        (let ((result (funcall (rule-action rule) current)))
          (when result
            (setf current result)))))))
