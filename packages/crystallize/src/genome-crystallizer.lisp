;;;; genome-crystallizer.lisp - Crystallize swarm genomes
;;;;
;;;; Converts genomes to S-expression form via the swarm module.

(in-package #:autopoiesis.crystallize)

;;; ===================================================================
;;; Genome Crystallization
;;; ===================================================================

(defun crystallize-genome (genome)
  "Crystallize a single genome to S-expression form.
   Uses genome-to-sexpr from the swarm module."
  (when (find-package :autopoiesis.swarm)
    (let ((fn (find-symbol "GENOME-TO-SEXPR" :autopoiesis.swarm)))
      (when fn (funcall fn genome)))))

(defun crystallize-genomes (genomes)
  "Crystallize a list of genomes. Returns list of (id . sexpr) pairs."
  (loop for genome in genomes
        for sexpr = (crystallize-genome genome)
        when sexpr
        collect (cons (if (find-package :autopoiesis.swarm)
                          (funcall (find-symbol "GENOME-ID" :autopoiesis.swarm) genome)
                          nil)
                      sexpr)))
