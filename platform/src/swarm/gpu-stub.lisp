;;;; gpu-stub.lisp - GPU acceleration stub for swarm fitness evaluation
;;;;
;;;; Defines the interface contract for future Rust+Metal GPU acceleration.
;;;; Currently falls back to CPU via lparallel.

(in-package #:autopoiesis.swarm)

(defvar *gpu-available* nil
  "When non-nil, GPU acceleration is available for fitness evaluation.
   Set to T after successfully loading the ap-metabolism foreign library.")

(defun evaluate-fitness-gpu (evaluator population environment)
  "GPU-accelerated fitness evaluation path.
   Falls back to CPU via lparallel when GPU is unavailable.

   GPU path will be implemented when:
   - Population size > 1000
   - Per-generation evaluation > 10s on CPU
   - Fitness is primarily numeric

   See platform/docs/specs/09-gpu-acceleration.md for the full interface contract."
  (if *gpu-available*
      (error 'autopoiesis.core:autopoiesis-error
             :message "GPU path not yet implemented - build ap-metabolism Rust crate.
See platform/docs/specs/09-gpu-acceleration.md")
      ;; CPU fallback
      (evaluate-population evaluator population environment :parallel t)))
