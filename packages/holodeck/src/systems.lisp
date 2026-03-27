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

(defvar *view-mode* :3d
  "Current view mode: :2d or :3d. In 2D mode, Y coordinates are flattened.")

(defvar *2d-flatten-threshold* 0.1
  "Threshold below which Y coordinates are considered 'flat' in 2D mode.")

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

;;; ═══════════════════════════════════════════════════════════════════
;;; Force-Directed Layout System
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Implements force-directed graph layout using spring-electrical model.
;;; Nodes repel each other (like charged particles), edges attract (like springs).
;;; Uses Verlet integration for stable simulation.

(defsystem force-directed-layout-system
  (:components-rw (position3d velocity3d force-directed-body)
   :components-ro (spring-connection)
   :when :every-frame)
  "Apply force-directed layout forces to entities with force-directed-body components.

   This system:
   1. Computes repulsive forces between all node pairs
   2. Computes attractive forces along spring connections
   3. Applies forces to update velocities
   4. Integrates velocities to update positions"
  ;; Clear accumulated forces (we'll accumulate them in this system)
  ;; Note: ECS doesn't have a built-in force accumulator, so we use velocity as proxy

  ;; Apply repulsive forces between all nodes
  (apply-repulsive-forces entity)

  ;; Apply attractive forces along connections
  (apply-attractive-forces entity)

  ;; Apply damping and velocity limits
  (apply-damping-and-limits entity)

  ;; Integrate velocity to position (simple Euler integration)
  (integrate-velocity entity))

(defvar *repulsion-constant* 1000.0
  "Global repulsion constant for force-directed layout.")

(defvar *repulsion-min-distance* 1.0
  "Minimum distance for repulsion calculation to avoid singularities.")

(defvar *attraction-constant* 0.01
  "Global attraction constant for spring connections.")

(defvar *default-spring-length* 10.0
  "Default rest length for springs between connected nodes.")

(defvar *layout-time-step* 0.016
  "Time step for force-directed layout integration (matches *delta-time*).")

(defvar *max-force* 100.0
  "Maximum force magnitude to prevent instability.")

(defun apply-repulsive-forces (entity)
  "Apply repulsive forces from ENTITY to all other force-directed entities."
  (let ((pos-x (position3d-x entity))
        (pos-y (position3d-y entity))
        (pos-z (position3d-z entity))
        (strength (force-directed-body-repulsion-strength entity)))
    ;; Iterate over all other entities with force-directed-body
    (ecs:do-entities (other-entity (position3d force-directed-body))
      (unless (= entity other-entity)
        (let* ((other-x (position3d-x other-entity))
               (other-y (position3d-y other-entity))
               (other-z (position3d-z other-entity))
               (dx (- other-x pos-x))
               (dy (- other-y pos-y))
               (dz (- other-z pos-z)))
          ;; In 2D mode, ignore Y component for distance and force calculation
          (if (view-mode-2d-p)
              (let* ((distance-squared (+ (* dx dx) (* dz dz))))
                (when (> distance-squared (* *repulsion-min-distance* *repulsion-min-distance*))
                  (let* ((distance (sqrt distance-squared))
                         (force-magnitude (/ (* *repulsion-constant* strength)
                                             distance-squared))
                         (force-magnitude (min force-magnitude *max-force*))
                         (force-x (* force-magnitude (/ dx distance)))
                         (force-z (* force-magnitude (/ dz distance))))
                    ;; Apply force to velocity (only X and Z in 2D mode)
                    (incf (velocity3d-dx entity) (- force-x))
                    (incf (velocity3d-dz entity) (- force-z)))))
              ;; 3D mode: include all dimensions
              (let* ((distance-squared (+ (* dx dx) (* dy dy) (* dz dz))))
                (when (> distance-squared (* *repulsion-min-distance* *repulsion-min-distance*))
                  (let* ((distance (sqrt distance-squared))
                         (force-magnitude (/ (* *repulsion-constant* strength)
                                             distance-squared))
                         (force-magnitude (min force-magnitude *max-force*))
                         (force-x (* force-magnitude (/ dx distance)))
                         (force-y (* force-magnitude (/ dy distance)))
                         (force-z (* force-magnitude (/ dz distance))))
                    ;; Apply force to velocity
                    (incf (velocity3d-dx entity) (- force-x))
                    (incf (velocity3d-dy entity) (- force-y))
                    (incf (velocity3d-dz entity) (- force-z))))))))))

(defun apply-attractive-forces (entity)
  "Apply attractive forces along spring connections from ENTITY."
  ;; Find all spring connections where entity is the 'from' node
  (ecs:do-components ((conn spring-connection))
    (when (= (spring-connection-from-entity conn) entity)
      (let ((to-entity (spring-connection-to-entity conn)))
        (when (and (>= to-entity 0)
                   (entity-exists-p to-entity))
          ;; Calculate spring force
          (let* ((from-x (position3d-x entity))
                 (from-y (position3d-y entity))
                 (from-z (position3d-z entity))
                 (to-x (position3d-x to-entity))
                 (to-y (position3d-y to-entity))
                 (to-z (position3d-z to-entity))
                 (dx (- to-x from-x))
                 (dy (- to-y from-y))
                 (dz (- to-z from-z)))
            ;; In 2D mode, ignore Y component for distance and force calculation
            (if (view-mode-2d-p)
                (let* ((distance (sqrt (+ (* dx dx) (* dz dz))))
                       (rest-length (spring-connection-rest-length conn))
                       (displacement (- distance rest-length))
                       (spring-k (spring-connection-spring-constant conn))
                       (force-magnitude (* spring-k displacement))
                       (force-magnitude (min (abs force-magnitude) *max-force*))
                       (force-magnitude (if (> displacement 0) force-magnitude (- force-magnitude))))
                  (when (> distance 0.001)  ; Avoid division by zero
                    (let ((force-x (* force-magnitude (/ dx distance)))
                          (force-z (* force-magnitude (/ dz distance))))
                      ;; Apply force to velocity (only X and Z in 2D mode)
                      (incf (velocity3d-dx entity) force-x)
                      (incf (velocity3d-dz entity) force-z))))
                ;; 3D mode: include all dimensions
                (let* ((distance (sqrt (+ (* dx dx) (* dy dy) (* dz dz))))
                       (rest-length (spring-connection-rest-length conn))
                       (displacement (- distance rest-length))
                       (spring-k (spring-connection-spring-constant conn))
                       (force-magnitude (* spring-k displacement))
                       (force-magnitude (min (abs force-magnitude) *max-force*))
                       (force-magnitude (if (> displacement 0) force-magnitude (- force-magnitude))))
                  (when (> distance 0.001)  ; Avoid division by zero
                    (let ((force-x (* force-magnitude (/ dx distance)))
                          (force-y (* force-magnitude (/ dy distance)))
                          (force-z (* force-magnitude (/ dz distance))))
                      ;; Apply force to velocity
                      (incf (velocity3d-dx entity) force-x)
                      (incf (velocity3d-dy entity) force-y)
                      (incf (velocity3d-dz entity) force-z))))))))))

(defun apply-damping-and-limits (entity)
  "Apply damping and velocity limits to prevent instability."
  (let ((damping (force-directed-body-damping entity))
        (max-vel (force-directed-body-max-velocity entity)))
    ;; Apply damping
    (setf (velocity3d-dx entity) (* (velocity3d-dx entity) damping))
    (setf (velocity3d-dy entity) (* (velocity3d-dy entity) damping))
    (setf (velocity3d-dz entity) (* (velocity3d-dz entity) damping))

    ;; Apply velocity limits
    (let ((vel-mag (sqrt (+ (* (velocity3d-dx entity) (velocity3d-dx entity))
                            (* (velocity3d-dy entity) (velocity3d-dy entity))
                            (* (velocity3d-dz entity) (velocity3d-dz entity))))))
      (when (> vel-mag max-vel)
        (let ((scale (/ max-vel vel-mag)))
          (setf (velocity3d-dx entity) (* (velocity3d-dx entity) scale))
          (setf (velocity3d-dy entity) (* (velocity3d-dy entity) scale))
          (setf (velocity3d-dz entity) (* (velocity3d-dz entity) scale)))))))

(defun integrate-velocity (entity)
  "Integrate velocity to update position."
  (let ((mass (force-directed-body-mass entity)))
    (when (> mass 0.0)
      ;; F = ma, so a = F/m, but we're using velocity as force accumulator
      ;; So we need to scale by 1/mass and time step
      (let ((accel-scale (/ *layout-time-step* mass)))
        (incf (position3d-x entity) (* (velocity3d-dx entity) accel-scale))
        (if (view-mode-2d-p)
            ;; In 2D mode, flatten Y coordinate
            (setf (position3d-y entity) (flatten-y-coordinate (position3d-y entity)))
            ;; In 3D mode, update normally
            (incf (position3d-y entity) (* (velocity3d-dy entity) accel-scale)))
        (incf (position3d-z entity) (* (velocity3d-dz entity) accel-scale)))))))

(defun set-view-mode (mode)
  "Set the view mode to :2d or :3d.
   In 2D mode, forces only act in XZ plane and Y coordinates are flattened."
  (ecase mode
    (:2d (setf *view-mode* :2d))
    (:3d (setf *view-mode* :3d))))

(defun view-mode-2d-p ()
  "Return T if currently in 2D view mode."
  (eq *view-mode* :2d))

(defun flatten-y-coordinate (y)
  "Flatten Y coordinate toward zero for 2D mode."
  (if (view-mode-2d-p)
      (if (< (abs y) *2d-flatten-threshold*)
          0.0
          (* y 0.1))  ; Gradually flatten
      y))

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
