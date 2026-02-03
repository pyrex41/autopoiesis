;;;; input.lisp - Camera input handling for orbit, zoom, pan, and selection
;;;;
;;;; Processes mouse and scroll events and dispatches them to the camera
;;;; system.  Right-drag orbits, middle-drag pans, scroll zooms, and
;;;; left-click selects entities.
;;;;
;;;; The camera-input-handler class tracks mouse button state and previous
;;;; cursor position to compute deltas each frame.
;;;;
;;;; Phase 8.3 - Camera System (input handling)

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Mouse Button Constants
;;; ===================================================================

(defparameter *mouse-button-left* :left
  "Keyword identifying the left mouse button.")

(defparameter *mouse-button-right* :right
  "Keyword identifying the right mouse button.")

(defparameter *mouse-button-middle* :middle
  "Keyword identifying the middle mouse button.")

;;; ===================================================================
;;; Camera Input Handler Class
;;; ===================================================================

(defclass camera-input-handler ()
  ((camera :initarg :camera
           :accessor input-handler-camera
           :initform nil
           :documentation "The camera controlled by this input handler.")
   (mouse-x :initarg :mouse-x
             :accessor input-handler-mouse-x
             :initform 0.0
             :type single-float
             :documentation "Current mouse X position in screen pixels.")
   (mouse-y :initarg :mouse-y
             :accessor input-handler-mouse-y
             :initform 0.0
             :type single-float
             :documentation "Current mouse Y position in screen pixels.")
   (prev-mouse-x :initarg :prev-mouse-x
                  :accessor input-handler-prev-mouse-x
                  :initform 0.0
                  :type single-float
                  :documentation "Previous frame mouse X position.")
   (prev-mouse-y :initarg :prev-mouse-y
                  :accessor input-handler-prev-mouse-y
                  :initform 0.0
                  :type single-float
                  :documentation "Previous frame mouse Y position.")
   (buttons-pressed :initarg :buttons-pressed
                    :accessor input-handler-buttons-pressed
                    :initform nil
                    :type list
                    :documentation "List of currently held mouse button keywords.")
   (scroll-accumulator :initarg :scroll-accumulator
                       :accessor input-handler-scroll-accumulator
                       :initform 0.0
                       :type single-float
                       :documentation "Accumulated scroll delta since last processing."))
  (:documentation
   "Tracks mouse state and dispatches input events to a camera.
    Right-drag orbits the camera around its target.
    Middle-drag pans the camera.
    Scroll wheel zooms in/out.
    Left-click is reserved for entity selection."))

;;; ===================================================================
;;; Constructor
;;; ===================================================================

(defun make-camera-input-handler (&key camera)
  "Create a new camera-input-handler attached to CAMERA."
  (make-instance 'camera-input-handler :camera camera))

;;; ===================================================================
;;; Mouse Position Update
;;; ===================================================================

(defgeneric handle-mouse-move (handler x y)
  (:documentation "Update the mouse position in the input handler.
    X and Y are screen-space pixel coordinates."))

(defmethod handle-mouse-move ((handler camera-input-handler) x y)
  "Record new mouse position.  Delta is computed during process-input."
  (setf (input-handler-mouse-x handler) (coerce x 'single-float))
  (setf (input-handler-mouse-y handler) (coerce y 'single-float))
  handler)

;;; ===================================================================
;;; Mouse Button Events
;;; ===================================================================

(defgeneric handle-mouse-button-press (handler button)
  (:documentation "Record that BUTTON has been pressed.
    BUTTON is a keyword: :left, :right, or :middle."))

(defmethod handle-mouse-button-press ((handler camera-input-handler) button)
  "Add BUTTON to the pressed set.  Snaps prev-mouse to current position
   to avoid a jump on the first drag frame."
  (unless (member button (input-handler-buttons-pressed handler))
    (push button (input-handler-buttons-pressed handler)))
  ;; Snap previous position to prevent delta spike on press
  (setf (input-handler-prev-mouse-x handler) (input-handler-mouse-x handler))
  (setf (input-handler-prev-mouse-y handler) (input-handler-mouse-y handler))
  handler)

(defgeneric handle-mouse-button-release (handler button)
  (:documentation "Record that BUTTON has been released.
    BUTTON is a keyword: :left, :right, or :middle."))

(defmethod handle-mouse-button-release ((handler camera-input-handler) button)
  "Remove BUTTON from the pressed set."
  (setf (input-handler-buttons-pressed handler)
        (remove button (input-handler-buttons-pressed handler)))
  handler)

(defgeneric button-pressed-p (handler button)
  (:documentation "Return T if BUTTON is currently pressed."))

(defmethod button-pressed-p ((handler camera-input-handler) button)
  "Check if BUTTON is in the pressed set."
  (if (member button (input-handler-buttons-pressed handler)) t nil))

;;; ===================================================================
;;; Scroll Input
;;; ===================================================================

(defgeneric handle-scroll (handler delta)
  (:documentation "Accumulate a scroll wheel DELTA.
    Positive DELTA typically means scroll up (zoom in)."))

(defmethod handle-scroll ((handler camera-input-handler) delta)
  "Add DELTA to the scroll accumulator for processing on next frame."
  (incf (input-handler-scroll-accumulator handler)
        (coerce delta 'single-float))
  handler)

;;; ===================================================================
;;; Per-Frame Input Processing
;;; ===================================================================

(defgeneric process-camera-input (handler)
  (:documentation "Process accumulated input events and apply them to the camera.
    Computes mouse delta, dispatches drag actions based on held buttons,
    applies scroll zoom, and resets per-frame accumulators.
    Returns the handler."))

(defmethod process-camera-input ((handler camera-input-handler))
  "Process all accumulated input and apply to the attached camera.

   Right-drag: orbit the camera around its target.
   Middle-drag: pan the camera.
   Scroll: zoom the camera in/out.

   Resets mouse delta and scroll accumulator after processing."
  (let ((cam (input-handler-camera handler)))
    (when cam
      ;; Compute mouse delta
      (let ((dx (- (input-handler-mouse-x handler)
                   (input-handler-prev-mouse-x handler)))
            (dy (- (input-handler-mouse-y handler)
                   (input-handler-prev-mouse-y handler))))

        ;; Right-drag: orbit
        (when (button-pressed-p handler *mouse-button-right*)
          (orbit-camera-by cam dx dy))

        ;; Middle-drag: pan
        (when (button-pressed-p handler *mouse-button-middle*)
          (pan-camera-by cam dx dy)))

      ;; Scroll: zoom
      (let ((scroll (input-handler-scroll-accumulator handler)))
        (unless (< (abs scroll) 1.0e-6)
          (zoom-camera-by cam scroll)))))

  ;; Update previous mouse position for next frame's delta
  (setf (input-handler-prev-mouse-x handler) (input-handler-mouse-x handler))
  (setf (input-handler-prev-mouse-y handler) (input-handler-mouse-y handler))

  ;; Reset scroll accumulator
  (setf (input-handler-scroll-accumulator handler) 0.0)

  handler)

;;; ===================================================================
;;; Mouse Delta Query (for external use)
;;; ===================================================================

(defgeneric mouse-delta (handler)
  (:documentation "Return the current mouse delta as two values: DX, DY.
    This is the difference between current and previous mouse positions."))

(defmethod mouse-delta ((handler camera-input-handler))
  "Compute mouse delta from current and previous positions."
  (values (- (input-handler-mouse-x handler)
             (input-handler-prev-mouse-x handler))
          (- (input-handler-mouse-y handler)
             (input-handler-prev-mouse-y handler))))

;;; ===================================================================
;;; Ray Picking for Entity Selection
;;; ===================================================================
;;;
;;; Ray picking converts a 2D screen position to a 3D ray in world space,
;;; then tests that ray against entity bounding volumes to determine which
;;; entity (if any) the user clicked on.

;;; -------------------------------------------------------------------
;;; Ray Structure
;;; -------------------------------------------------------------------

(defstruct (pick-ray (:constructor make-pick-ray (&key origin direction)))
  "A ray in 3D space defined by an origin point and normalized direction."
  (origin (vec3 0.0 0.0 0.0) :type 3d-vectors:vec3)
  (direction (vec3 0.0 0.0 -1.0) :type 3d-vectors:vec3))

;;; -------------------------------------------------------------------
;;; Screen to World Ray Conversion
;;; -------------------------------------------------------------------

(defgeneric screen-to-world-ray (camera screen-x screen-y screen-width screen-height)
  (:documentation "Convert screen coordinates to a world-space picking ray.
    SCREEN-X, SCREEN-Y are pixel coordinates (0,0 at top-left).
    SCREEN-WIDTH, SCREEN-HEIGHT are the viewport dimensions.
    Returns a pick-ray structure with origin at camera position and
    direction pointing into the scene through the screen point."))

(defmethod screen-to-world-ray ((cam orbit-camera) screen-x screen-y
                                screen-width screen-height)
  "Convert screen coordinates to a picking ray for an orbit camera.
   Uses the camera's view and projection matrices to unproject the point."
  (let* ((aspect (if (zerop screen-height) 1.0
                     (/ (coerce screen-width 'single-float)
                        (coerce screen-height 'single-float))))
         ;; Convert screen coords to normalized device coordinates [-1, 1]
         (ndc-x (- (* 2.0 (/ (coerce screen-x 'single-float)
                            (coerce screen-width 'single-float)))
                   1.0))
         (ndc-y (- 1.0 (* 2.0 (/ (coerce screen-y 'single-float)
                                (coerce screen-height 'single-float)))))
         ;; Get camera matrices
         (view-mat (camera-view-matrix-data cam))
         (proj-mat (camera-projection-matrix-data cam aspect))
         ;; Invert projection to get eye-space ray direction
         (inv-proj (3d-matrices:minv proj-mat))
         ;; Point on near plane in clip space
         (clip-near (3d-vectors:vec4 ndc-x ndc-y -1.0 1.0))
         ;; Transform to eye space
         (eye-near (3d-matrices:m* inv-proj clip-near))
         ;; Perspective divide
         (eye-w (3d-vectors:vw eye-near))
         (eye-dir (if (< (abs eye-w) 1.0e-6)
                      (3d-vectors:vec3 0.0 0.0 -1.0)
                      (3d-vectors:vec3 (/ (3d-vectors:vx eye-near) eye-w)
                                       (/ (3d-vectors:vy eye-near) eye-w)
                                       (/ (3d-vectors:vz eye-near) eye-w))))
         ;; Invert view matrix to get world-space direction
         (inv-view (3d-matrices:minv view-mat))
         ;; Transform direction to world space (w=0 for direction vector)
         (world-dir-4 (3d-matrices:m* inv-view
                                      (3d-vectors:vec4 (3d-vectors:vx eye-dir)
                                                       (3d-vectors:vy eye-dir)
                                                       (3d-vectors:vz eye-dir)
                                                       0.0)))
         (world-dir (3d-vectors:vec3 (3d-vectors:vx world-dir-4)
                                      (3d-vectors:vy world-dir-4)
                                      (3d-vectors:vz world-dir-4)))
         ;; Normalize the direction
         (dir-len (vlength world-dir))
         (norm-dir (if (< dir-len 1.0e-6)
                       (3d-vectors:vec3 0.0 0.0 -1.0)
                       (v* world-dir (/ 1.0 dir-len)))))
    (make-pick-ray :origin (camera-position cam)
                   :direction norm-dir)))

(defmethod screen-to-world-ray ((cam fly-camera) screen-x screen-y
                                screen-width screen-height)
  "Convert screen coordinates to a picking ray for a fly camera.
   Uses the camera's view and projection matrices to unproject the point."
  (let* ((aspect (if (zerop screen-height) 1.0
                     (/ (coerce screen-width 'single-float)
                        (coerce screen-height 'single-float))))
         ;; Convert screen coords to normalized device coordinates [-1, 1]
         (ndc-x (- (* 2.0 (/ (coerce screen-x 'single-float)
                            (coerce screen-width 'single-float)))
                   1.0))
         (ndc-y (- 1.0 (* 2.0 (/ (coerce screen-y 'single-float)
                                (coerce screen-height 'single-float)))))
         ;; Get camera matrices
         (view-mat (camera-view-matrix-data cam))
         (proj-mat (camera-projection-matrix-data cam aspect))
         ;; Invert projection to get eye-space ray direction
         (inv-proj (3d-matrices:minv proj-mat))
         ;; Point on near plane in clip space
         (clip-near (3d-vectors:vec4 ndc-x ndc-y -1.0 1.0))
         ;; Transform to eye space
         (eye-near (3d-matrices:m* inv-proj clip-near))
         ;; Perspective divide
         (eye-w (3d-vectors:vw eye-near))
         (eye-dir (if (< (abs eye-w) 1.0e-6)
                      (3d-vectors:vec3 0.0 0.0 -1.0)
                      (3d-vectors:vec3 (/ (3d-vectors:vx eye-near) eye-w)
                                       (/ (3d-vectors:vy eye-near) eye-w)
                                       (/ (3d-vectors:vz eye-near) eye-w))))
         ;; Invert view matrix to get world-space direction
         (inv-view (3d-matrices:minv view-mat))
         ;; Transform direction to world space (w=0 for direction vector)
         (world-dir-4 (3d-matrices:m* inv-view
                                      (3d-vectors:vec4 (3d-vectors:vx eye-dir)
                                                       (3d-vectors:vy eye-dir)
                                                       (3d-vectors:vz eye-dir)
                                                       0.0)))
         (world-dir (3d-vectors:vec3 (3d-vectors:vx world-dir-4)
                                      (3d-vectors:vy world-dir-4)
                                      (3d-vectors:vz world-dir-4)))
         ;; Normalize the direction
         (dir-len (vlength world-dir))
         (norm-dir (if (< dir-len 1.0e-6)
                       (3d-vectors:vec3 0.0 0.0 -1.0)
                       (v* world-dir (/ 1.0 dir-len)))))
    (make-pick-ray :origin (fly-camera-position-vec cam)
                   :direction norm-dir)))

;;; -------------------------------------------------------------------
;;; Ray-Sphere Intersection
;;; -------------------------------------------------------------------

(defun ray-sphere-intersect-p (ray center radius)
  "Test if RAY intersects a sphere at CENTER with RADIUS.
   Returns two values: T/NIL for hit, and the distance along the ray
   to the nearest intersection point (or NIL if no hit).
   
   Uses the geometric ray-sphere intersection algorithm:
   1. Compute vector from ray origin to sphere center
   2. Project that vector onto ray direction
   3. Check if closest approach is within radius"
  (let* ((origin (pick-ray-origin ray))
         (dir (pick-ray-direction ray))
         ;; Vector from ray origin to sphere center
         (oc (v- center origin))
         ;; Project oc onto ray direction to get closest approach distance
         (tca (+ (* (vx oc) (vx dir))
                 (* (vy oc) (vy dir))
                 (* (vz oc) (vz dir))))
         ;; If tca < 0, sphere is behind ray origin
         ;; (but we still check in case we're inside the sphere)
         ;; Distance squared from ray origin to sphere center
         (oc-len-sq (+ (* (vx oc) (vx oc))
                       (* (vy oc) (vy oc))
                       (* (vz oc) (vz oc))))
         ;; Distance squared from closest approach point to sphere center
         (d2 (- oc-len-sq (* tca tca)))
         (r2 (* radius radius)))
    ;; If d2 > r2, ray misses the sphere
    (if (> d2 r2)
        (values nil nil)
        ;; Compute the intersection distance
        (let* ((thc (sqrt (- r2 d2)))
               ;; Two intersection points: tca - thc and tca + thc
               (t0 (- tca thc))
               (t1 (+ tca thc)))
          ;; Return the nearest positive intersection
          (cond
            ((> t0 0.0) (values t t0))
            ((> t1 0.0) (values t t1))
            ;; Both intersections behind ray origin
            (t (values nil nil)))))))

;;; -------------------------------------------------------------------
;;; Entity Picking
;;; -------------------------------------------------------------------

(defparameter *default-pick-radius* 1.0
  "Default bounding sphere radius for entity picking when scale is 1.0.")

(defun entity-pick-radius (entity)
  "Compute the effective picking radius for ENTITY.
   Uses the entity's scale3d component to scale the default radius.
   Returns the maximum of the three scale dimensions times the base radius."
  (handler-case
      (let ((sx (scale3d-sx entity))
            (sy (scale3d-sy entity))
            (sz (scale3d-sz entity)))
        (* *default-pick-radius* (max sx sy sz)))
    (error () *default-pick-radius*)))

(defun entity-pick-center (entity)
  "Get the world-space center position of ENTITY for picking.
   Returns a vec3 from the entity's position3d component."
  (handler-case
      (vec3 (position3d-x entity)
            (position3d-y entity)
            (position3d-z entity))
    (error () (vec3 0.0 0.0 0.0))))

(defun ray-intersects-entity-p (ray entity)
  "Test if RAY intersects ENTITY's bounding sphere.
   Returns two values: T/NIL for hit, and distance to intersection."
  (let ((center (entity-pick-center entity))
        (radius (entity-pick-radius entity)))
    (ray-sphere-intersect-p ray center radius)))

(defun pick-entity (ray entities)
  "Find the nearest entity in ENTITIES that RAY intersects.
   Returns two values: the entity (or NIL), and the distance to it.
   Only considers entities with interactive component that have
   selected-p capability (checked via handler-case for robustness)."
  (let ((best-entity nil)
        (best-distance most-positive-single-float))
    (dolist (entity entities)
      ;; Check if entity is interactive (can be selected)
      ;; Skip entities that don't have an interactive component
      (when (handler-case
                (progn
                  (interactive-hover-p entity)  ; Just check component exists
                  t)
              (error () nil))
        ;; Test ray intersection
        (multiple-value-bind (hit-p distance)
            (ray-intersects-entity-p ray entity)
          (when (and hit-p (< distance best-distance))
            (setf best-entity entity
                  best-distance distance)))))
    (if best-entity
        (values best-entity best-distance)
        (values nil nil))))

(defun pick-entity-at-screen-pos (camera screen-x screen-y
                                  screen-width screen-height
                                  entities)
  "Pick the nearest entity at screen position (SCREEN-X, SCREEN-Y).
   CAMERA is the active camera (orbit-camera or fly-camera).
   SCREEN-WIDTH and SCREEN-HEIGHT are the viewport dimensions.
   ENTITIES is a list of entity IDs to test.
   Returns two values: the picked entity (or NIL), and the distance."
  (let ((ray (screen-to-world-ray camera screen-x screen-y
                                  screen-width screen-height)))
    (pick-entity ray entities)))

;;; -------------------------------------------------------------------
;;; Selection State Management
;;; -------------------------------------------------------------------

(defvar *selected-entity* nil
  "Currently selected entity, or NIL if nothing is selected.")

(defun select-entity (entity)
  "Select ENTITY, updating its interactive component and *selected-entity*.
   Deselects any previously selected entity first."
  ;; Deselect previous
  (when *selected-entity*
    (handler-case
        (setf (interactive-selected-p *selected-entity*) nil)
      (error () nil)))
  ;; Select new
  (setf *selected-entity* entity)
  (when entity
    (handler-case
        (setf (interactive-selected-p entity) t)
      (error () nil)))
  entity)

(defun deselect-entity ()
  "Clear the current selection."
  (select-entity nil))

(defun selected-entity ()
  "Return the currently selected entity, or NIL."
  *selected-entity*)

;;; -------------------------------------------------------------------
;;; Hover State Management
;;; -------------------------------------------------------------------

(defvar *hovered-entity* nil
  "Currently hovered entity, or NIL if nothing is hovered.")

(defun set-hovered-entity (entity)
  "Set ENTITY as the hovered entity, updating interactive components.
   Clears hover state from any previously hovered entity."
  ;; Clear previous hover
  (when *hovered-entity*
    (handler-case
        (setf (interactive-hover-p *hovered-entity*) nil)
      (error () nil)))
  ;; Set new hover
  (setf *hovered-entity* entity)
  (when entity
    (handler-case
        (setf (interactive-hover-p entity) t)
      (error () nil)))
  entity)

(defun hovered-entity ()
  "Return the currently hovered entity, or NIL."
  *hovered-entity*)

(defun update-hover-from-mouse (camera screen-x screen-y
                                screen-width screen-height
                                entities)
  "Update hover state based on current mouse position.
   Sets the hovered entity to whatever is under the mouse cursor."
  (let ((entity (pick-entity-at-screen-pos camera screen-x screen-y
                                           screen-width screen-height
                                           entities)))
    (set-hovered-entity entity)))
