;;;; camera.lisp - Camera system with orbit, zoom, and pan controls
;;;;
;;;; Implements an orbit camera that revolves around a target point using
;;;; spherical coordinates (theta, phi, distance).  Provides orbit, zoom,
;;;; pan, and smooth transition operations.
;;;;
;;;; Spherical coordinate convention:
;;;;   theta - azimuthal angle around Y axis (radians, 0 = looking along +Z)
;;;;   phi   - polar angle from the XZ plane (radians, 0 = level, positive = up)
;;;;   distance - radial distance from target
;;;;
;;;; Phase 8.3 - Camera System (first task)

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Camera Class
;;; ===================================================================

(defclass orbit-camera ()
  ((target :initarg :target
           :accessor camera-target
           :initform (vec3 0.0 0.0 0.0)
           :documentation "Point the camera orbits around and looks at.")
   (up :initarg :up
       :accessor camera-up
       :initform (vec3 0.0 1.0 0.0)
       :documentation "World up direction vector.")
   (theta :initarg :theta
          :accessor camera-theta
          :initform 0.0
          :type single-float
          :documentation "Azimuthal angle around Y axis in radians.")
   (phi :initarg :phi
        :accessor camera-phi
        :initform 0.3
        :type single-float
        :documentation "Polar angle from XZ plane in radians (positive = up).")
   (distance :initarg :distance
             :accessor camera-distance
             :initform 30.0
             :type single-float
             :documentation "Distance from target to camera.")
   (fov :initarg :fov
        :accessor camera-fov
        :initform 60.0
        :type single-float
        :documentation "Vertical field of view in degrees.")
   (near-plane :initarg :near-plane
               :accessor camera-near-plane
               :initform 0.1
               :type single-float
               :documentation "Near clipping plane distance.")
   (far-plane :initarg :far-plane
              :accessor camera-far-plane
              :initform 1000.0
              :type single-float
              :documentation "Far clipping plane distance.")
   (min-distance :initarg :min-distance
                 :accessor camera-min-distance
                 :initform 5.0
                 :type single-float
                 :documentation "Minimum zoom distance.")
   (max-distance :initarg :max-distance
                 :accessor camera-max-distance
                 :initform 200.0
                 :type single-float
                 :documentation "Maximum zoom distance.")
   (orbit-speed :initarg :orbit-speed
                :accessor camera-orbit-speed
                :initform 0.01
                :type single-float
                :documentation "Radians per pixel of mouse delta for orbiting.")
   (zoom-speed :initarg :zoom-speed
               :accessor camera-zoom-speed
               :initform 0.5
               :type single-float
               :documentation "Distance units per scroll step for zooming.")
   (pan-speed :initarg :pan-speed
              :accessor camera-pan-speed
              :initform 0.1
              :type single-float
              :documentation "World units per pixel of mouse delta for panning."))
  (:documentation
   "Orbit camera that revolves around a target point using spherical coordinates.
    Position is derived from (target + spherical offset) each frame.
    Supports orbit (rotate around target), zoom (change distance), and
    pan (translate both camera and target)."))

;;; ===================================================================
;;; Spherical Coordinate Constants
;;; ===================================================================

(defparameter *phi-min* -1.5
  "Minimum polar angle in radians (avoids gimbal lock at south pole).")

(defparameter *phi-max* 1.5
  "Maximum polar angle in radians (avoids gimbal lock at north pole).")

;;; ===================================================================
;;; Camera Position Computation
;;; ===================================================================

(defgeneric camera-position (camera)
  (:documentation "Compute the world-space camera position from spherical coordinates."))

(defmethod camera-position ((cam orbit-camera))
  "Compute camera position from target + spherical offset.
   Converts (theta, phi, distance) to Cartesian offset and adds to target."
  (let* ((theta (coerce (camera-theta cam) 'single-float))
         (phi (coerce (camera-phi cam) 'single-float))
         (dist (coerce (camera-distance cam) 'single-float))
         (cos-phi (cos phi))
         (offset-x (* dist (sin theta) cos-phi))
         (offset-y (* dist (sin phi)))
         (offset-z (* dist (cos theta) cos-phi)))
    (v+ (camera-target cam)
        (vec3 offset-x offset-y offset-z))))

;;; ===================================================================
;;; Camera Direction Vectors
;;; ===================================================================

(defgeneric camera-forward (camera)
  (:documentation "Compute the normalized forward direction (camera to target)."))

(defmethod camera-forward ((cam orbit-camera))
  "Compute normalized direction from camera position toward target."
  (let* ((pos (camera-position cam))
         (diff (v- (camera-target cam) pos))
         (len (vlength diff)))
    (if (< len 1.0e-6)
        (vec3 0.0 0.0 -1.0)
        (v* diff (/ 1.0 len)))))

(defgeneric camera-right (camera)
  (:documentation "Compute the normalized right direction."))

(defmethod camera-right ((cam orbit-camera))
  "Compute normalized right vector from forward cross up."
  (let* ((fwd (camera-forward cam))
         (cross (3d-vectors:vc fwd (camera-up cam)))
         (len (vlength cross)))
    (if (< len 1.0e-6)
        (vec3 1.0 0.0 0.0)
        (v* cross (/ 1.0 len)))))

;;; ===================================================================
;;; Orbit Operation
;;; ===================================================================

(defgeneric orbit-camera-by (camera delta-x delta-y)
  (:documentation "Orbit the camera around its target by mouse delta amounts."))

(defmethod orbit-camera-by ((cam orbit-camera) delta-x delta-y)
  "Orbit camera around target by (DELTA-X, DELTA-Y) mouse pixels.
   DELTA-X rotates around Y axis (theta).
   DELTA-Y tilts up/down (phi), clamped to avoid gimbal lock."
  (let ((speed (camera-orbit-speed cam)))
    (incf (camera-theta cam) (coerce (* delta-x speed) 'single-float))
    (let ((new-phi (+ (camera-phi cam) (coerce (* delta-y speed) 'single-float))))
      (setf (camera-phi cam)
            (coerce (max *phi-min* (min *phi-max* new-phi)) 'single-float))))
  cam)

;;; ===================================================================
;;; Zoom Operation
;;; ===================================================================

(defgeneric zoom-camera-by (camera delta)
  (:documentation "Zoom the camera in/out by scroll delta.
    Positive delta zooms in (decreases distance)."))

(defmethod zoom-camera-by ((cam orbit-camera) delta)
  "Zoom camera by DELTA scroll units.
   Positive DELTA moves closer to target, negative moves farther.
   Distance is clamped to [min-distance, max-distance]."
  (let* ((speed (camera-zoom-speed cam))
         (new-dist (- (camera-distance cam)
                      (coerce (* delta speed) 'single-float))))
    (setf (camera-distance cam)
          (coerce (max (camera-min-distance cam)
                       (min (camera-max-distance cam) new-dist))
                  'single-float)))
  cam)

;;; ===================================================================
;;; Pan Operation
;;; ===================================================================

(defgeneric pan-camera-by (camera delta-x delta-y)
  (:documentation "Pan the camera (translate both camera and target) by mouse delta."))

(defmethod pan-camera-by ((cam orbit-camera) delta-x delta-y)
  "Pan camera and target by (DELTA-X, DELTA-Y) mouse pixels.
   Translates in the camera's local right and up directions."
  (let* ((speed (camera-pan-speed cam))
         (right-dir (camera-right cam))
         (up-dir (camera-up cam))
         (right-offset (v* right-dir (coerce (* delta-x (- speed)) 'single-float)))
         (up-offset (v* up-dir (coerce (* delta-y speed) 'single-float)))
         (total-offset (v+ right-offset up-offset)))
    (setf (camera-target cam)
          (v+ (camera-target cam) total-offset)))
  cam)

;;; ===================================================================
;;; Camera Matrix Helpers
;;; ===================================================================
;;;
;;; These produce view and projection matrix data as lists suitable for
;;; passing to shader uniforms.  When a real rendering backend is present,
;;; these can be replaced with native matrix operations.

(defgeneric camera-view-matrix-data (camera)
  (:documentation "Compute view matrix elements as a flat 16-element list (column-major)."))

(defmethod camera-view-matrix-data ((cam orbit-camera))
  "Compute a look-at view matrix for the camera.
   Returns a 3d-matrices:mat4 representing the view transform."
  (let ((eye (camera-position cam))
        (target (camera-target cam))
        (up (camera-up cam)))
    ;; Compute look-at basis vectors
    (let* ((f-raw (v- target eye))
           (f-len (vlength f-raw))
           (f (if (< f-len 1.0e-6)
                  (vec3 0.0 0.0 -1.0)
                  (v* f-raw (/ 1.0 f-len))))
           (s-raw (3d-vectors:vc f up))
           (s-len (vlength s-raw))
           (s (if (< s-len 1.0e-6)
                  (vec3 1.0 0.0 0.0)
                  (v* s-raw (/ 1.0 s-len))))
           (u (3d-vectors:vc s f)))
      ;; Build column-major 4x4 view matrix using flat indices
      ;; Column-major layout: index = col*4 + row
      ;; Row 0: sx   sy   sz  -dot(s,eye)
      ;; Row 1: ux   uy   uz  -dot(u,eye)
      ;; Row 2: -fx  -fy  -fz  dot(f,eye)
      ;; Row 3: 0    0    0    1
      (let ((dot-s (+ (* (vx s) (vx eye)) (* (vy s) (vy eye)) (* (vz s) (vz eye))))
            (dot-u (+ (* (vx u) (vx eye)) (* (vy u) (vy eye)) (* (vz u) (vz eye))))
            (dot-f (+ (* (vx f) (vx eye)) (* (vy f) (vy eye)) (* (vz f) (vz eye))))
            (m (3d-matrices:mat4)))
        ;; Column 0
        (setf (3d-matrices:miref m 0) (vx s))
        (setf (3d-matrices:miref m 1) (vx u))
        (setf (3d-matrices:miref m 2) (- (vx f)))
        (setf (3d-matrices:miref m 3) 0.0)
        ;; Column 1
        (setf (3d-matrices:miref m 4) (vy s))
        (setf (3d-matrices:miref m 5) (vy u))
        (setf (3d-matrices:miref m 6) (- (vy f)))
        (setf (3d-matrices:miref m 7) 0.0)
        ;; Column 2
        (setf (3d-matrices:miref m 8) (vz s))
        (setf (3d-matrices:miref m 9) (vz u))
        (setf (3d-matrices:miref m 10) (- (vz f)))
        (setf (3d-matrices:miref m 11) 0.0)
        ;; Column 3
        (setf (3d-matrices:miref m 12) (- dot-s))
        (setf (3d-matrices:miref m 13) (- dot-u))
        (setf (3d-matrices:miref m 14) dot-f)
        (setf (3d-matrices:miref m 15) 1.0)
        m))))

(defgeneric camera-projection-matrix-data (camera aspect-ratio)
  (:documentation "Compute perspective projection matrix for the given aspect ratio."))

(defmethod camera-projection-matrix-data ((cam orbit-camera) aspect-ratio)
  "Compute a perspective projection matrix.
   ASPECT-RATIO is width/height.
   Returns a 3d-matrices:mat4."
  (let* ((fov-rad (coerce (* (camera-fov cam) (/ pi 180.0)) 'single-float))
         (f (coerce (/ 1.0 (tan (* fov-rad 0.5))) 'single-float))
         (near (camera-near-plane cam))
         (far (camera-far-plane cam))
         (ar (coerce aspect-ratio 'single-float))
         (range (- near far))
         (m (3d-matrices:mat4)))
    ;; Column 0
    (setf (3d-matrices:miref m 0) (/ f ar))
    ;; Column 1
    (setf (3d-matrices:miref m 5) f)
    ;; Column 2
    (setf (3d-matrices:miref m 10) (/ (+ far near) range))
    (setf (3d-matrices:miref m 11) -1.0)
    ;; Column 3
    (setf (3d-matrices:miref m 14) (/ (* 2.0 far near) range))
    m))

;;; ===================================================================
;;; Camera State Update (for syncing *camera-position*)
;;; ===================================================================

(defgeneric sync-camera-state (camera)
  (:documentation "Update global simulation state from camera.
    Sets *camera-position* for LOD system."))

(defmethod sync-camera-state ((cam orbit-camera))
  "Update *camera-position* from the orbit camera's computed position."
  (setf *camera-position* (camera-position cam))
  cam)

;;; ===================================================================
;;; Convenience Constructor
;;; ===================================================================

(defun make-orbit-camera (&key (target (vec3 0.0 0.0 0.0))
                                (theta 0.0) (phi 0.3) (distance 30.0)
                                (fov 60.0) (near 0.1) (far 1000.0)
                                (min-distance 5.0) (max-distance 200.0)
                                (orbit-speed 0.01) (zoom-speed 0.5)
                                (pan-speed 0.1))
  "Create a new orbit-camera with the given parameters."
  (make-instance 'orbit-camera
                 :target target
                 :theta (coerce theta 'single-float)
                 :phi (coerce phi 'single-float)
                 :distance (coerce distance 'single-float)
                 :fov (coerce fov 'single-float)
                 :near-plane (coerce near 'single-float)
                 :far-plane (coerce far 'single-float)
                 :min-distance (coerce min-distance 'single-float)
                 :max-distance (coerce max-distance 'single-float)
                 :orbit-speed (coerce orbit-speed 'single-float)
                 :zoom-speed (coerce zoom-speed 'single-float)
                 :pan-speed (coerce pan-speed 'single-float)))
