;;;; systems.lisp - ECS system definitions for holodeck visualization
;;;;
;;;; Systems process entities with matching component sets each frame.
;;;; They contain all behavior; components are pure data.
;;;;
;;;; Systems defined:
;;;;   movement-system - Updates positions from velocities
;;;;   pulse-system    - Animated pulsing effect on entities
;;;;   lod-system      - Level-of-detail based on camera distance

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
