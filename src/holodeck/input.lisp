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
