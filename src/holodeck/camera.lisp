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

;;; ===================================================================
;;; Fly Camera Class
;;; ===================================================================

(defclass fly-camera ()
  ((position :initarg :position
             :accessor fly-camera-position-vec
             :initform (vec3 0.0 5.0 30.0)
             :documentation "Camera position in world space.")
   (yaw :initarg :yaw
         :accessor fly-camera-yaw
         :initform 0.0
         :type single-float
         :documentation "Yaw angle around Y axis in radians (0 = looking along -Z).")
   (pitch :initarg :pitch
           :accessor fly-camera-pitch
           :initform 0.0
           :type single-float
           :documentation "Pitch angle from XZ plane in radians (positive = up).")
   (velocity :initarg :velocity
              :accessor fly-camera-velocity
              :initform (vec3 0.0 0.0 0.0)
              :documentation "Current velocity in world space.")
   (speed :initarg :speed
           :accessor fly-camera-speed
           :initform 20.0
           :type single-float
           :documentation "Movement speed in world units per second.")
   (sensitivity :initarg :sensitivity
                 :accessor fly-camera-sensitivity
                 :initform 0.003
                 :type single-float
                 :documentation "Mouse look sensitivity in radians per pixel.")
   (damping :initarg :damping
             :accessor fly-camera-damping
             :initform 0.9
             :type single-float
             :documentation "Velocity damping factor per frame (0.0 = instant stop, 1.0 = no damping).")
   (up :initarg :up
        :accessor camera-fly-up
        :initform (vec3 0.0 1.0 0.0)
        :documentation "World up direction vector.")
   (fov :initarg :fov
         :accessor fly-camera-fov
         :initform 60.0
         :type single-float
         :documentation "Vertical field of view in degrees.")
   (near-plane :initarg :near-plane
                :accessor fly-camera-near-plane
                :initform 0.1
                :type single-float
                :documentation "Near clipping plane distance.")
   (far-plane :initarg :far-plane
               :accessor fly-camera-far-plane
               :initform 1000.0
               :type single-float
               :documentation "Far clipping plane distance."))
  (:documentation
   "First-person fly camera with velocity-based movement.
    Uses yaw/pitch angles for orientation and applies velocity with
    damping for smooth acceleration and deceleration."))

;;; ===================================================================
;;; Fly Camera Pitch Limits
;;; ===================================================================

(defparameter *pitch-min* -1.5
  "Minimum pitch angle in radians (looking down).")

(defparameter *pitch-max* 1.5
  "Maximum pitch angle in radians (looking up).")

;;; ===================================================================
;;; Fly Camera Position (generic method specialization)
;;; ===================================================================

(defmethod camera-position ((cam fly-camera))
  "Return the fly camera's world-space position."
  (fly-camera-position-vec cam))

;;; ===================================================================
;;; Fly Camera Direction Vectors
;;; ===================================================================

(defmethod camera-forward ((cam fly-camera))
  "Compute normalized forward direction from yaw and pitch."
  (let* ((yaw (fly-camera-yaw cam))
         (pitch (fly-camera-pitch cam))
         (cos-pitch (cos pitch)))
    (let ((x (* (- (sin yaw)) cos-pitch))
          (y (sin pitch))
          (z (* (- (cos yaw)) cos-pitch)))
      (let* ((v (vec3 x y z))
             (len (vlength v)))
        (if (< len 1.0e-6)
            (vec3 0.0 0.0 -1.0)
            (v* v (/ 1.0 len)))))))

(defmethod camera-right ((cam fly-camera))
  "Compute normalized right vector from forward cross up."
  (let* ((fwd (camera-forward cam))
         (up (camera-fly-up cam))
         (cross (3d-vectors:vc fwd up))
         (len (vlength cross)))
    (if (< len 1.0e-6)
        (vec3 1.0 0.0 0.0)
        (v* cross (/ 1.0 len)))))

;;; ===================================================================
;;; Fly Camera Look (mouse input)
;;; ===================================================================

(defgeneric fly-camera-look (camera delta-x delta-y)
  (:documentation "Rotate the fly camera by mouse delta amounts."))

(defmethod fly-camera-look ((cam fly-camera) delta-x delta-y)
  "Rotate fly camera by (DELTA-X, DELTA-Y) mouse pixels.
   DELTA-X rotates yaw (left/right).
   DELTA-Y rotates pitch (up/down), clamped to avoid flipping."
  (let ((sens (fly-camera-sensitivity cam)))
    (incf (fly-camera-yaw cam) (coerce (* delta-x sens) 'single-float))
    (let ((new-pitch (+ (fly-camera-pitch cam) (coerce (* delta-y sens) 'single-float))))
      (setf (fly-camera-pitch cam)
            (coerce (max *pitch-min* (min *pitch-max* new-pitch)) 'single-float))))
  cam)

;;; ===================================================================
;;; Fly Camera Movement (acceleration-based)
;;; ===================================================================

(defgeneric fly-camera-move (camera direction)
  (:documentation "Apply acceleration to the fly camera in the given direction.
    DIRECTION is one of :forward :backward :left :right :up :down."))

(defmethod fly-camera-move ((cam fly-camera) direction)
  "Apply acceleration in DIRECTION relative to camera orientation.
   Adds to current velocity; damping will slow the camera over time."
  (let* ((fwd (camera-forward cam))
         (right (camera-right cam))
         (up (camera-fly-up cam))
         (speed (fly-camera-speed cam))
         (accel (ecase direction
                  (:forward (v* fwd speed))
                  (:backward (v* fwd (- speed)))
                  (:left (v* right (- speed)))
                  (:right (v* right speed))
                  (:up (v* up speed))
                  (:down (v* up (- speed))))))
    (setf (fly-camera-velocity cam)
          (v+ (fly-camera-velocity cam) accel)))
  cam)

;;; ===================================================================
;;; Fly Camera Update (per-frame)
;;; ===================================================================

(defgeneric fly-camera-update (camera dt)
  (:documentation "Update fly camera position from velocity, applying damping.
    DT is the frame delta time in seconds."))

(defmethod fly-camera-update ((cam fly-camera) dt)
  "Advance fly camera position by velocity * DT, then apply damping.
   Velocity is multiplied by damping factor each frame."
  (let* ((vel (fly-camera-velocity cam))
         (dt-f (coerce dt 'single-float))
         (displacement (v* vel dt-f))
         (new-pos (v+ (fly-camera-position-vec cam) displacement))
         (damp (fly-camera-damping cam)))
    (setf (fly-camera-position-vec cam) new-pos)
    (setf (fly-camera-velocity cam) (v* vel damp)))
  cam)

;;; ===================================================================
;;; Fly Camera Stop
;;; ===================================================================

(defgeneric fly-camera-stop (camera)
  (:documentation "Immediately stop all camera velocity."))

(defmethod fly-camera-stop ((cam fly-camera))
  "Set velocity to zero, stopping all movement."
  (setf (fly-camera-velocity cam) (vec3 0.0 0.0 0.0))
  cam)

;;; ===================================================================
;;; Fly Camera View Matrix
;;; ===================================================================

(defmethod camera-view-matrix-data ((cam fly-camera))
  "Compute a look-at view matrix for the fly camera.
   Returns a 3d-matrices:mat4."
  (let* ((eye (fly-camera-position-vec cam))
         (fwd (camera-forward cam))
         (target (v+ eye fwd))
         (up (camera-fly-up cam)))
    ;; Compute look-at basis vectors
    (let* ((f fwd)
           (s-raw (3d-vectors:vc f up))
           (s-len (vlength s-raw))
           (s (if (< s-len 1.0e-6)
                  (vec3 1.0 0.0 0.0)
                  (v* s-raw (/ 1.0 s-len))))
           (u (3d-vectors:vc s f)))
      ;; Build column-major 4x4 view matrix
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

;;; ===================================================================
;;; Fly Camera Projection Matrix
;;; ===================================================================

(defmethod camera-projection-matrix-data ((cam fly-camera) aspect-ratio)
  "Compute perspective projection matrix for the fly camera.
   ASPECT-RATIO is width/height. Returns a 3d-matrices:mat4."
  (let* ((fov-rad (coerce (* (fly-camera-fov cam) (/ pi 180.0)) 'single-float))
         (f (coerce (/ 1.0 (tan (* fov-rad 0.5))) 'single-float))
         (near (fly-camera-near-plane cam))
         (far (fly-camera-far-plane cam))
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
;;; Fly Camera Sync State
;;; ===================================================================

(defmethod sync-camera-state ((cam fly-camera))
  "Update *camera-position* from the fly camera's position."
  (setf *camera-position* (fly-camera-position-vec cam))
  cam)

;;; ===================================================================
;;; Fly Camera Convenience Constructor
;;; ===================================================================

(defun make-fly-camera (&key (position (vec3 0.0 5.0 30.0))
                              (yaw 0.0) (pitch 0.0)
                              (speed 20.0) (sensitivity 0.003)
                              (damping 0.9)
                              (fov 60.0) (near 0.1) (far 1000.0))
  "Create a new fly-camera with the given parameters."
  (make-instance 'fly-camera
                 :position position
                 :yaw (coerce yaw 'single-float)
                 :pitch (coerce pitch 'single-float)
                 :speed (coerce speed 'single-float)
                 :sensitivity (coerce sensitivity 'single-float)
                 :damping (coerce damping 'single-float)
                 :fov (coerce fov 'single-float)
                 :near-plane (coerce near 'single-float)
                 :far-plane (coerce far 'single-float)))

;;; ===================================================================
;;; Easing Functions
;;; ===================================================================
;;;
;;; Standard easing curves for smooth camera transitions.
;;; All functions take a normalized progress value T in [0,1]
;;; and return an eased value in [0,1].

(defun ease-linear (tt)
  "Linear interpolation (no easing).  TT is progress in [0,1]."
  (coerce (max 0.0 (min 1.0 tt)) 'single-float))

(defun ease-in-quad (tt)
  "Quadratic ease-in: starts slow, accelerates."
  (let ((t-clamped (coerce (max 0.0 (min 1.0 tt)) 'single-float)))
    (* t-clamped t-clamped)))

(defun ease-out-quad (tt)
  "Quadratic ease-out: starts fast, decelerates."
  (let ((t-clamped (coerce (max 0.0 (min 1.0 tt)) 'single-float)))
    (- 1.0 (* (- 1.0 t-clamped) (- 1.0 t-clamped)))))

(defun ease-in-out-quad (tt)
  "Quadratic ease-in-out: slow start and end, fast middle."
  (let ((t-clamped (coerce (max 0.0 (min 1.0 tt)) 'single-float)))
    (if (< t-clamped 0.5)
        (* 2.0 t-clamped t-clamped)
        (- 1.0 (* 2.0 (- 1.0 t-clamped) (- 1.0 t-clamped))))))

(defun ease-in-cubic (tt)
  "Cubic ease-in: starts very slow, accelerates sharply."
  (let ((t-clamped (coerce (max 0.0 (min 1.0 tt)) 'single-float)))
    (* t-clamped t-clamped t-clamped)))

(defun ease-out-cubic (tt)
  "Cubic ease-out: starts fast, decelerates smoothly."
  (let* ((t-clamped (coerce (max 0.0 (min 1.0 tt)) 'single-float))
         (inv (- 1.0 t-clamped)))
    (- 1.0 (* inv inv inv))))

(defun ease-in-out-cubic (tt)
  "Cubic ease-in-out: very smooth start and end."
  (let ((t-clamped (coerce (max 0.0 (min 1.0 tt)) 'single-float)))
    (if (< t-clamped 0.5)
        (* 4.0 t-clamped t-clamped t-clamped)
        (let ((inv (- 1.0 t-clamped)))
          (- 1.0 (* 4.0 inv inv inv))))))

(defun apply-easing (easing-type tt)
  "Apply the named easing function EASING-TYPE to progress TT.
   EASING-TYPE is a keyword: :linear, :ease-in-quad, :ease-out-quad,
   :ease-in-out-quad, :ease-in-cubic, :ease-out-cubic, :ease-in-out-cubic."
  (ecase easing-type
    (:linear (ease-linear tt))
    (:ease-in-quad (ease-in-quad tt))
    (:ease-out-quad (ease-out-quad tt))
    (:ease-in-out-quad (ease-in-out-quad tt))
    (:ease-in-cubic (ease-in-cubic tt))
    (:ease-out-cubic (ease-out-cubic tt))
    (:ease-in-out-cubic (ease-in-out-cubic tt))))

;;; ===================================================================
;;; Vector Interpolation Helper
;;; ===================================================================

(defun vec3-lerp (a b tt)
  "Linearly interpolate between vec3 A and vec3 B by factor TT.
   TT=0 returns A, TT=1 returns B."
  (let ((t-f (coerce tt 'single-float)))
    (v+ (v* a (- 1.0 t-f))
        (v* b t-f))))

;;; ===================================================================
;;; Camera Transition Class
;;; ===================================================================

(defclass camera-transition ()
  ((start-position :initarg :start-position
                   :accessor transition-start-position
                   :initform (vec3 0.0 0.0 0.0)
                   :documentation "Camera position at start of transition.")
   (end-position :initarg :end-position
                 :accessor transition-end-position
                 :initform (vec3 0.0 0.0 0.0)
                 :documentation "Camera position at end of transition.")
   (start-target :initarg :start-target
                 :accessor transition-start-target
                 :initform (vec3 0.0 0.0 0.0)
                 :documentation "Camera look-at target at start of transition.")
   (end-target :initarg :end-target
               :accessor transition-end-target
               :initform (vec3 0.0 0.0 0.0)
               :documentation "Camera look-at target at end of transition.")
   (duration :initarg :duration
             :accessor transition-duration
             :initform 1.0
             :type single-float
             :documentation "Total transition duration in seconds.")
   (elapsed :initarg :elapsed
            :accessor transition-elapsed
            :initform 0.0
            :type single-float
            :documentation "Time elapsed since transition started.")
   (easing :initarg :easing
           :accessor transition-easing
           :initform :ease-out-cubic
           :type keyword
           :documentation "Easing function to use for interpolation."))
  (:documentation
   "Represents an in-progress smooth camera transition.
    Interpolates both position and look-at target from start to end
    over the given duration using the specified easing function."))

(defun make-camera-transition (&key (start-position (vec3 0.0 0.0 0.0))
                                     (end-position (vec3 0.0 0.0 0.0))
                                     (start-target (vec3 0.0 0.0 0.0))
                                     (end-target (vec3 0.0 0.0 0.0))
                                     (duration 1.0)
                                     (easing :ease-out-cubic))
  "Create a new camera-transition with the given parameters."
  (make-instance 'camera-transition
                 :start-position start-position
                 :end-position end-position
                 :start-target start-target
                 :end-target end-target
                 :duration (coerce (max 0.001 duration) 'single-float)
                 :elapsed 0.0
                 :easing easing))

(defgeneric camera-transition-progress (transition)
  (:documentation "Return the raw (un-eased) progress of the transition in [0,1]."))

(defmethod camera-transition-progress ((trans camera-transition))
  "Compute normalized progress as elapsed/duration, clamped to [0,1]."
  (min 1.0 (/ (transition-elapsed trans) (transition-duration trans))))

(defgeneric camera-transition-complete-p (transition)
  (:documentation "Return T if the transition has completed."))

(defmethod camera-transition-complete-p ((trans camera-transition))
  "A transition is complete when elapsed >= duration."
  (>= (transition-elapsed trans) (transition-duration trans)))

(defgeneric advance-camera-transition (transition dt)
  (:documentation "Advance the transition by DT seconds and return interpolated
    position and target as two vec3 values."))

(defmethod advance-camera-transition ((trans camera-transition) dt)
  "Advance transition by DT seconds.  Returns two values:
   1. Interpolated position (vec3)
   2. Interpolated target (vec3)
   The transition's elapsed time is updated."
  (incf (transition-elapsed trans) (coerce dt 'single-float))
  (let* ((raw-progress (camera-transition-progress trans))
         (eased (apply-easing (transition-easing trans) raw-progress)))
    (values (vec3-lerp (transition-start-position trans)
                       (transition-end-position trans)
                       eased)
            (vec3-lerp (transition-start-target trans)
                       (transition-end-target trans)
                       eased))))

;;; ===================================================================
;;; Initiating Camera Transitions
;;; ===================================================================

(defgeneric animate-camera-to (camera end-position end-target &key duration easing)
  (:documentation "Begin a smooth transition of CAMERA to END-POSITION looking at END-TARGET.
    Returns the created camera-transition object."))

(defmethod animate-camera-to ((cam orbit-camera) end-position end-target
                              &key (duration 1.0) (easing :ease-out-cubic))
  "Begin a smooth transition for the orbit camera.
   Captures current position and target as the start state."
  (make-camera-transition
   :start-position (camera-position cam)
   :end-position end-position
   :start-target (camera-target cam)
   :end-target end-target
   :duration duration
   :easing easing))

(defmethod animate-camera-to ((cam fly-camera) end-position end-target
                              &key (duration 1.0) (easing :ease-out-cubic))
  "Begin a smooth transition for the fly camera.
   Captures current position and forward-derived target as the start state."
  (let ((current-pos (fly-camera-position-vec cam))
        (current-target (v+ (fly-camera-position-vec cam) (camera-forward cam))))
    (make-camera-transition
     :start-position current-pos
     :end-position end-position
     :start-target current-target
     :end-target end-target
     :duration duration
     :easing easing)))

;;; ===================================================================
;;; Applying Transitions to Cameras
;;; ===================================================================

(defgeneric apply-camera-transition (camera transition dt)
  (:documentation "Advance TRANSITION by DT and apply the interpolated state to CAMERA.
    Returns T if the transition is still active, NIL if complete."))

(defmethod apply-camera-transition ((cam orbit-camera) (trans camera-transition) dt)
  "Apply transition to orbit camera by updating target and recomputing
   spherical coordinates from the interpolated position."
  (multiple-value-bind (new-pos new-target)
      (advance-camera-transition trans dt)
    ;; Update target
    (setf (camera-target cam) new-target)
    ;; Derive spherical coordinates from new position relative to new target
    (let* ((offset (v- new-pos new-target))
           (dist (vlength offset)))
      (when (> dist 1.0e-6)
        (setf (camera-distance cam) (coerce dist 'single-float))
        (let* ((ox (vx offset))
               (oy (vy offset))
               (oz (vz offset)))
          (setf (camera-phi cam) (coerce (asin (/ oy dist)) 'single-float))
          (setf (camera-theta cam) (coerce (atan ox oz) 'single-float))))))
  (not (camera-transition-complete-p trans)))

(defmethod apply-camera-transition ((cam fly-camera) (trans camera-transition) dt)
  "Apply transition to fly camera by updating position and deriving
   yaw/pitch from the interpolated target direction."
  (multiple-value-bind (new-pos new-target)
      (advance-camera-transition trans dt)
    ;; Update position
    (setf (fly-camera-position-vec cam) new-pos)
    ;; Derive yaw and pitch from direction to target
    (let* ((dir (v- new-target new-pos))
           (len (vlength dir)))
      (when (> len 1.0e-6)
        (let* ((dx (/ (vx dir) len))
               (dy (/ (vy dir) len))
               (dz (/ (vz dir) len)))
          (setf (fly-camera-pitch cam) (coerce (asin dy) 'single-float))
          (setf (fly-camera-yaw cam)
                (coerce (atan (- dx) (- dz)) 'single-float)))))
    ;; Stop any velocity during transition
    (setf (fly-camera-velocity cam) (vec3 0.0 0.0 0.0)))
  (not (camera-transition-complete-p trans)))
