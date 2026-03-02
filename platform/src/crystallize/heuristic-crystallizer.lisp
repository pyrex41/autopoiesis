;;;; heuristic-crystallizer.lisp - Crystallize high-confidence heuristics
;;;;
;;;; Extracts learned heuristics as loadable S-expression data.

(in-package #:autopoiesis.crystallize)

;;; ===================================================================
;;; Heuristic Crystallization
;;; ===================================================================

(defun crystallize-heuristics (&key (min-confidence 0.7) (store autopoiesis.agent:*heuristic-store*))
  "Extract high-confidence heuristics as loadable S-expression data.
   Returns a list of (id . sexpr-form) pairs for heuristics at or above MIN-CONFIDENCE."
  (let ((results nil))
    (dolist (heur (autopoiesis.agent:list-heuristics :store store))
      (when (>= (autopoiesis.agent:heuristic-confidence heur) min-confidence)
        (push (cons (autopoiesis.agent:heuristic-id heur)
                    (autopoiesis.agent:heuristic-to-sexpr heur))
              results)))
    (nreverse results)))
