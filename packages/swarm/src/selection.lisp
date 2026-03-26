;;;; selection.lisp - Selection operators for evolutionary algorithms
;;;;
;;;; Provides tournament, roulette-wheel, and elitism selection strategies
;;;; for choosing genomes from a population.

(in-package #:autopoiesis.swarm)

;;; ===================================================================
;;; Tournament Selection
;;; ===================================================================

(defun tournament-select (population &key (tournament-size 3))
  "Select a genome via tournament selection.
   Picks TOURNAMENT-SIZE random genomes and returns the fittest."
  (let* ((genomes (population-genomes population))
         (n (length genomes))
         (contestants (loop repeat (min tournament-size n)
                            collect (nth (random n) genomes))))
    (first (sort (copy-list contestants) #'> :key #'genome-fitness))))

;;; ===================================================================
;;; Roulette Wheel Selection
;;; ===================================================================

(defun roulette-select (population)
  "Select a genome via fitness-proportionate (roulette wheel) selection.
   Genomes with higher fitness have proportionally higher selection probability."
  (let* ((genomes (population-genomes population))
         (total-fitness (reduce #'+ genomes :key #'genome-fitness))
         (threshold (if (zerop total-fitness)
                        0.0
                        (random (coerce total-fitness 'double-float))))
         (running 0.0))
    (if (zerop total-fitness)
        ;; All zero fitness: pick uniformly at random
        (nth (random (length genomes)) genomes)
        (dolist (g genomes (first (last genomes)))
          (incf running (genome-fitness g))
          (when (>= running threshold)
            (return g))))))

;;; ===================================================================
;;; Elitism Selection
;;; ===================================================================

(defun elitism-select (population &key (count 2))
  "Select the top COUNT genomes by fitness (elitism).
   Returns a list of the best genomes."
  (let ((sorted (sort (copy-list (population-genomes population))
                      #'> :key #'genome-fitness)))
    (subseq sorted 0 (min count (length sorted)))))
