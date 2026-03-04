;;;; persistent-fitness.lisp - Built-in fitness functions for persistent agents
;;;;
;;;; Provides composable fitness evaluators that score persistent agents
;;;; on thought diversity, capability breadth, and genome efficiency.

(in-package #:autopoiesis.swarm)

;;; ═══════════════════════════════════════════════════════════════════
;;; Fitness Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun thought-diversity-fitness (agent)
  "Score agent on diversity of thought types in [0,1].
   Ratio of unique thought types to total thoughts, with bonus for
   having all 5 cognitive phases represented."
  (let* ((thoughts (autopoiesis.core:pvec-to-list
                    (autopoiesis.agent:persistent-agent-thoughts agent)))
         (total (length thoughts))
         (types (remove-duplicates
                 (mapcar (lambda (th) (getf th :type)) thoughts))))
    (if (zerop total)
        0.0
        (let* ((unique-count (length types))
               (all-phases '(:observation :reasoning :decision :action :reflection))
               (phase-coverage (/ (length (intersection types all-phases))
                                  (length all-phases))))
          (min 1.0 (* 0.5 (/ unique-count (max 1 (min total 10)))
                       (+ 0.5 (* 0.5 phase-coverage))))))))

(defun capability-breadth-fitness (agent &key (max-capabilities 20))
  "Score agent on capability count in [0,1].
   Normalized by MAX-CAPABILITIES."
  (let ((count (autopoiesis.core:pset-count
                (autopoiesis.agent:persistent-agent-capabilities agent))))
    (min 1.0 (/ (float count) (float max-capabilities)))))

(defun genome-efficiency-fitness (agent)
  "Score agent on ratio of capabilities per genome form in [0,1].
   Higher efficiency means more capabilities from less code."
  (let ((cap-count (autopoiesis.core:pset-count
                    (autopoiesis.agent:persistent-agent-capabilities agent)))
        (genome-size (max 1 (length (autopoiesis.agent:persistent-agent-genome agent)))))
    (min 1.0 (/ (float cap-count) (float genome-size)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Standard Composite Evaluator
;;; ═══════════════════════════════════════════════════════════════════

(defun make-standard-pa-evaluator (&key (diversity-weight 0.4)
                                        (breadth-weight 0.3)
                                        (efficiency-weight 0.3)
                                        (max-capabilities 20))
  "Create a composite fitness evaluator for persistent agents.
   Combines thought-diversity, capability-breadth, and genome-efficiency
   with configurable weights (must sum to 1.0).

   Returns a fitness-evaluator suitable for use with evolve-persistent-agents."
  (persistent-agent-fitness-evaluator
   (lambda (agent)
     (+ (* diversity-weight (thought-diversity-fitness agent))
        (* breadth-weight (capability-breadth-fitness agent
                                                      :max-capabilities max-capabilities))
        (* efficiency-weight (genome-efficiency-fitness agent))))))
