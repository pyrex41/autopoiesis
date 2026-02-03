;;;; systems.lisp - ECS system definitions for holodeck visualization
;;;;
;;;; Systems process entities with matching component sets each frame.
;;;; They contain all behavior; components are pure data.
;;;;
;;;; Systems defined:
;;;;   movement-system - Updates positions from velocities
;;;;   pulse-system    - Animated pulsing effect on entities
;;;;   lod-system      - Level-of-detail based on camera distance
;;;;
;;;; Parallel execution:
;;;;   parallel-ecs-update - Execute independent systems in parallel

(in-package #:autopoiesis.holodeck)

;;; ═══════════════════════════════════════════════════════════════════
;;; Simulation State
;;; ═══════════════════════════════════════════════════════════════════

(defvar *delta-time* 0.016
  "Time elapsed since last frame in seconds (default ~60fps).")

(defvar *elapsed-time* 0.0
  "Total elapsed time in seconds since simulation start.")

(defvar *camera-position* (vec3 0.0 0.0 50.0)
  "Current camera position in 3D space.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Utility Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun distance-to-camera (x y z)
  "Compute Euclidean distance from point (X Y Z) to *camera-position*."
  (let ((dx (- x (vx *camera-position*)))
        (dy (- y (vy *camera-position*)))
        (dz (- z (vz *camera-position*))))
    (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Movement System
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Updates entity positions based on velocity and delta time.
;;; Entities must have both position3d and velocity3d components.

(defsystem movement-system
  (:components-rw (position3d velocity3d))
  (incf (position3d-x entity) (* (velocity3d-dx entity) *delta-time*))
  (incf (position3d-y entity) (* (velocity3d-dy entity) *delta-time*))
  (incf (position3d-z entity) (* (velocity3d-dz entity) *delta-time*)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Pulse System
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Animates entities with a pulsing scale effect.
;;; Only affects entities with non-zero pulse-rate in their visual-style.

(defsystem pulse-system
  (:components-rw (visual-style scale3d)
   :after (movement-system))
  (let ((rate (visual-style-pulse-rate entity)))
    (when (> rate 0.0)
      (let ((pulse (coerce (+ 1.0 (* 0.1 (sin (* *elapsed-time* rate))))
                           'single-float)))
        (setf (scale3d-sx entity) pulse)
        (setf (scale3d-sy entity) pulse)
        (setf (scale3d-sz entity) pulse)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; LOD System (Level of Detail)
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Adjusts detail-level based on distance from camera.
;;; Three levels: :high (close), :low (medium), :culled (far).

(defsystem lod-system
  (:components-rw (position3d detail-level)
   :after (movement-system))
  (let ((dist (distance-to-camera (position3d-x entity)
                                  (position3d-y entity)
                                  (position3d-z entity))))
    (setf (detail-level-current entity)
          (cond
            ((> dist (detail-level-cull-distance entity)) :culled)
            ((> dist (detail-level-low-distance entity)) :low)
            (t :high)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Parallel System Execution
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Provides infrastructure for parallel ECS system execution.
;;;
;;; Note: cl-fast-ecs runs all systems together via run-systems, which
;;; handles entity bitmap rebuilding and storage context. Individual
;;; system functions can be called directly but require proper setup.
;;;
;;; This module provides:
;;; - parallel-ecs-update: Execute work in parallel across threads
;;; - run-systems-optimized: Convenience wrapper for standard execution
;;; - analyze-system-dependencies: Determine which systems can run in parallel

(defvar *parallel-ecs-enabled* t
  "When T, parallel-ecs-update will use threads for independent work units.
   When NIL, work units run sequentially (useful for debugging).")

(defvar *parallel-ecs-thread-count* 0
  "Counter for naming parallel ECS threads.")

(defun parallel-ecs-update (work-units)
  "Execute groups of independent work units in parallel.

   WORK-UNITS is a list of work unit specifications, where each unit
   is a thunk (zero-argument function) to execute. Units within the
   same group can run in parallel; groups execute sequentially.

   Example:
     (parallel-ecs-update
       (list (list (lambda () (do-work-a))
                   (lambda () (do-work-b)))
             (list (lambda () (do-work-c)))))

   This runs work-a and work-b in parallel, then runs work-c.

   For ECS systems, use run-systems-optimized which handles the
   cl-fast-ecs infrastructure properly.

   Returns: Number of work units executed."
  (let ((total-units 0))
    (dolist (group work-units)
      (incf total-units (length group))
      (if (and *parallel-ecs-enabled* (> (length group) 1))
          ;; Run work units in this group in parallel
          (run-work-units-parallel group)
          ;; Run work units sequentially
          (dolist (work-fn group)
            (funcall work-fn))))
    total-units))

(defun run-work-units-parallel (work-fns)
  "Execute multiple work functions in parallel using threads.

   WORK-FNS is a list of zero-argument functions to run concurrently.
   Blocks until all functions complete.

   Note: The caller is responsible for ensuring work functions in the
   same parallel group don't have data races."
  (let ((threads nil)
        (errors nil)
        (errors-lock (bordeaux-threads:make-lock "parallel-ecs-errors")))
    ;; Start a thread for each work function
    (dolist (work-fn work-fns)
      (let ((fn work-fn)) ; Capture for closure
        (push (bordeaux-threads:make-thread
               (lambda ()
                 (handler-case
                     (funcall fn)
                   (error (e)
                     (bordeaux-threads:with-lock-held (errors-lock)
                       (push e errors)))))
               :name (format nil "parallel-ecs-~d"
                             (incf *parallel-ecs-thread-count*)))
              threads)))
    ;; Wait for all threads to complete
    (dolist (thread threads)
      (bordeaux-threads:join-thread thread))
    ;; Report any errors that occurred
    (when errors
      (error "Parallel execution failed with ~d error~:p: ~{~a~^, ~}"
             (length errors)
             errors))))

(defun analyze-system-dependencies ()
  "Analyze the defined systems and return dependency information.

   Returns a list of system groups where:
   - Systems within a group have no dependencies on each other
   - Groups must be executed sequentially (earlier groups first)

   Current analysis based on :after declarations in defsystem:
   - Group 1: movement-system (no dependencies)
   - Group 2: pulse-system, lod-system (both depend only on movement-system)

   Note: cl-fast-ecs handles system ordering internally via run-systems.
   This analysis is informational and for future optimization."
  '((movement-system)
    (pulse-system lod-system)))

(defun run-systems-optimized ()
  "Run all ECS systems with the standard cl-fast-ecs infrastructure.

   This is the recommended way to run ECS systems as it properly handles:
   - Entity bitmap rebuilding for component changes
   - Storage context management
   - System ordering based on :after/:before constraints

   For true parallel execution of independent systems, the cl-fast-ecs
   library would need to be extended to support running system subsets.

   Currently equivalent to (cl-fast-ecs:run-systems)."
  (cl-fast-ecs:run-systems))
