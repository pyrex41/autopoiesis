;;;; window.lisp - Holodeck window, scene setup, and event handling
;;;;
;;;; Defines the holodeck-window class, which manages the 3D visualization
;;;; window, scene graph, camera, and HUD.  When the Trial game engine is
;;;; available (indicated by the :trial feature), holodeck-window extends
;;;; trial:main for native OpenGL rendering.  Without Trial, it provides
;;;; the same protocol as a standalone CLOS class for testing and headless
;;;; operation.
;;;;
;;;; Also defines the holodeck event types and event dispatching system
;;;; that routes keyboard, mouse, scroll, and resize events to the
;;;; appropriate input handlers.
;;;;
;;;; Phase 8.2 - Rendering (first task)
;;;; Phase 8.5 - Input Handling (keyboard and mouse events)

(in-package #:autopoiesis.holodeck)

;;; ═══════════════════════════════════════════════════════════════════
;;; Window Configuration
;;; ═══════════════════════════════════════════════════════════════════

(defparameter *window-width* 1920
  "Default holodeck window width in pixels.")

(defparameter *window-height* 1080
  "Default holodeck window height in pixels.")

(defparameter *window-title* "Autopoiesis Holodeck"
  "Default holodeck window title.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Holodeck Window Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass holodeck-window ()
  ((width :initarg :width
          :accessor window-width
          :initform *window-width*
          :documentation "Window width in pixels.")
   (height :initarg :height
           :accessor window-height
           :initform *window-height*
           :documentation "Window height in pixels.")
   (title :initarg :title
          :accessor window-title
          :initform *window-title*
          :documentation "Window title string.")
   (scene :initarg :scene
          :accessor holodeck-scene
          :initform nil
          :documentation "Scene graph root containing all renderable entities.")
   (camera :initarg :camera
           :accessor holodeck-camera
           :initform nil
           :documentation "Active camera for the holodeck view.")
   (hud :initarg :hud
        :accessor holodeck-hud
        :initform nil
        :documentation "Heads-up display overlay.")
   (running-p :initarg :running-p
              :accessor holodeck-running-p
              :initform nil
              :documentation "Whether the holodeck main loop is active.")
   (store :initarg :store
          :accessor holodeck-store
          :initform nil
          :documentation "Snapshot store to visualize.")
   (keyboard-handler :initarg :keyboard-handler
                     :accessor holodeck-keyboard-handler
                     :initform nil
                     :documentation "Keyboard input handler for key bindings.")
   (camera-input-handler :initarg :camera-input-handler
                         :accessor holodeck-camera-input-handler
                         :initform nil
                         :documentation "Camera input handler for mouse/scroll.")
   (chat-mode-p :initform nil
                :accessor holodeck-chat-mode-p
                :documentation "Whether the holodeck is in chat input mode.")
   (chat-input :initform ""
               :accessor holodeck-chat-input
               :documentation "Current chat input string.")
   (chat-messages :initform nil
                  :accessor holodeck-chat-messages
                  :documentation "List of (sender . text) cons pairs for chat history.")
   (follow-mode-p :initform nil
                   :accessor holodeck-follow-mode-p
                   :documentation "Whether the camera follows the focused entity.")
   (focused-entity-id :initform nil
                       :accessor holodeck-focused-entity-id
                       :documentation "Entity ID of the currently focused entity, or NIL."))
  (:documentation
   "Main window class for the 3D holodeck visualization.
    Manages the rendering context, scene graph, camera, HUD, and input handlers.
    When Trial is available, a subclass can extend trial:main for
    native OpenGL rendering."))

;;; ═══════════════════════════════════════════════════════════════════
;;; Holodeck Event Types
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Events are represented as structures for efficient dispatch.
;;; Each event type corresponds to a specific input category.

(defstruct (holodeck-event (:constructor nil))
  "Base structure for all holodeck events."
  (timestamp 0.0 :type single-float :read-only t))

(defstruct (key-event (:include holodeck-event)
                      (:constructor make-key-event
                          (&key (timestamp 0.0) key action modifiers)))
  "Keyboard key press or release event.
   KEY is a keyword identifying the key (e.g., :w, :escape).
   ACTION is :press or :release.
   MODIFIERS is a list of active modifiers (:shift :control :alt :super)."
  (key nil :type keyword :read-only t)
  (action :press :type keyword :read-only t)
  (modifiers nil :type list :read-only t))

(defstruct (mouse-move-event (:include holodeck-event)
                             (:constructor make-mouse-move-event
                                 (&key (timestamp 0.0) x y)))
  "Mouse cursor movement event.
   X and Y are screen-space pixel coordinates."
  (x 0.0 :type single-float :read-only t)
  (y 0.0 :type single-float :read-only t))

(defstruct (mouse-button-event (:include holodeck-event)
                               (:constructor make-mouse-button-event
                                   (&key (timestamp 0.0) button action x y)))
  "Mouse button press or release event.
   BUTTON is :left, :right, or :middle.
   ACTION is :press or :release.
   X and Y are the cursor position at the time of the event."
  (button :left :type keyword :read-only t)
  (action :press :type keyword :read-only t)
  (x 0.0 :type single-float :read-only t)
  (y 0.0 :type single-float :read-only t))

(defstruct (scroll-event (:include holodeck-event)
                         (:constructor make-scroll-event
                             (&key (timestamp 0.0) delta-x delta-y)))
  "Mouse scroll wheel event.
   DELTA-X is horizontal scroll (usually 0).
   DELTA-Y is vertical scroll (positive = up/zoom in)."
  (delta-x 0.0 :type single-float :read-only t)
  (delta-y 0.0 :type single-float :read-only t))

(defstruct (resize-event (:include holodeck-event)
                         (:constructor make-resize-event
                             (&key (timestamp 0.0) width height)))
  "Window resize event.
   WIDTH and HEIGHT are the new window dimensions in pixels."
  (width 0 :type fixnum :read-only t)
  (height 0 :type fixnum :read-only t))

;;; ═══════════════════════════════════════════════════════════════════
;;; Generic Protocol
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric setup-scene (window)
  (:documentation
   "Initialize the holodeck scene graph, camera, shaders, and HUD.
    Called once when the window is first opened."))

(defgeneric holodeck-render (window dt)
  (:documentation
   "Render one frame of the holodeck visualization.
    DT is the delta time in seconds since the last frame."))

(defgeneric handle-holodeck-event (window event)
  (:documentation
   "Handle an input event (keyboard, mouse, resize) in the holodeck."))

(defgeneric holodeck-update (window dt)
  (:documentation
   "Update simulation state (ECS systems, camera, etc.) for one frame.
    DT is the delta time in seconds since the last frame."))

;;; ═══════════════════════════════════════════════════════════════════
;;; Default Method Implementations
;;; ═══════════════════════════════════════════════════════════════════

(defmethod setup-scene ((window holodeck-window))
  "Default scene setup: initializes ECS storage, input handlers, HUD, and marks window ready."
  (init-holodeck-storage)
  ;; Initialize camera if not already set
  (unless (holodeck-camera window)
    (setf (holodeck-camera window) (make-orbit-camera)))
  ;; Initialize keyboard input handler
  (unless (holodeck-keyboard-handler window)
    (setf (holodeck-keyboard-handler window) (make-keyboard-input-handler)))
  ;; Register camera action handlers
  (register-camera-action-handlers
   (handler-registry (holodeck-keyboard-handler window))
   (holodeck-camera window))
  ;; Register additional action handlers
  (register-holodeck-action-handlers
   (handler-registry (holodeck-keyboard-handler window))
   window)
  ;; Initialize camera input handler attached to the camera
  (unless (holodeck-camera-input-handler window)
    (setf (holodeck-camera-input-handler window)
          (make-camera-input-handler :camera (holodeck-camera window))))
  ;; Initialize HUD with window dimensions
  (unless (holodeck-hud window)
    (setf (holodeck-hud window)
          (make-hud :window-width (window-width window)
                    :window-height (window-height window))))
  ;; Reset render loop state
  (setf *holodeck-transition* nil)
  (setf *last-frame-time* 0.0)
  ;; Reset entity tracking lists
  (reset-snapshot-entities)
  (reset-connection-entities)
  ;; Register default meshes and shaders
  (register-holodeck-meshes)
  (register-holodeck-shaders)
  (setf (holodeck-running-p window) t))

(defmethod holodeck-update ((window holodeck-window) dt)
  "Default update: runs ECS systems with the given delta time."
  (let ((*delta-time* (coerce dt 'single-float)))
    (incf *elapsed-time* *delta-time*)
    (cl-fast-ecs:run-systems)))

(defmethod holodeck-render ((window holodeck-window) dt)
  "Default render: no-op without a rendering backend."
  (declare (ignore dt))
  nil)

;;; ===================================================================
;;; Holodeck Event Emission Helper
;;; ===================================================================

(defun %emit-holodeck-event (event-type data)
  "Emit a holodeck event through the integration event bus, if available.
   Uses find-symbol to avoid compile-time circular dependency."
  (handler-case
      (when (find-package :autopoiesis.integration)
        (let ((emit-fn (find-symbol "EMIT-INTEGRATION-EVENT" :autopoiesis.integration)))
          (when (and emit-fn (fboundp emit-fn))
            (funcall emit-fn event-type :holodeck data))))
    (error () nil)))

;;; ===================================================================
;;; Entity Focus Helper
;;; ===================================================================

(defun focus-on-entity-smooth (window entity)
  "Smoothly move the camera to focus on ENTITY.
   Creates a camera transition to the entity's position using
   focus-on-snapshot which handles offset and transition creation."
  (when (and entity (entity-valid-p entity))
    (handler-case
        (let ((camera (holodeck-camera window)))
          (when camera
            (let ((transition (focus-on-snapshot camera entity
                                                 :duration *focus-duration*)))
              (when transition
                (setf *holodeck-transition* transition)))))
      (error () nil))))

;;; ===================================================================
;;; Additional Action Handlers
;;; ===================================================================

(defgeneric register-holodeck-action-handlers (registry window)
  (:documentation "Register action handlers for holodeck-specific actions."))

(defmethod register-holodeck-action-handlers ((registry key-binding-registry) (window holodeck-window))
  "Register handlers for holodeck-specific actions."
  ;; Camera mode switching
  (register-action-handler registry :switch-camera-mode
    (lambda ()
      (switch-camera-mode window)))
  ;; 2D/3D view mode toggle
  (register-action-handler registry :toggle-2d-3d
    (lambda ()
      (toggle-2d-3d-mode window)))

  ;; ── Navigation actions ──────────────────────────────────────────

  (register-action-handler registry :step-backward
    (lambda ()
      (let ((entities *snapshot-entities*))
        (when entities
          (let* ((current (holodeck-focused-entity-id window))
                 (idx (if current (position current entities) nil))
                 (prev-idx (if idx (max 0 (1- idx)) (1- (length entities))))
                 (target (nth prev-idx entities)))
            (when target
              (setf (holodeck-focused-entity-id window) target)
              (select-entity target)
              (focus-on-entity-smooth window target)))))))

  (register-action-handler registry :step-forward
    (lambda ()
      (let ((entities *snapshot-entities*))
        (when entities
          (let* ((current (holodeck-focused-entity-id window))
                 (idx (if current (position current entities) nil))
                 (next-idx (if idx (min (1- (length entities)) (1+ idx)) 0))
                 (target (nth next-idx entities)))
            (when target
              (setf (holodeck-focused-entity-id window) target)
              (select-entity target)
              (focus-on-entity-smooth window target)))))))

  (register-action-handler registry :goto-genesis
    (lambda ()
      (let ((entities *snapshot-entities*))
        (when entities
          (let ((first-entity (first entities)))
            (when first-entity
              (setf (holodeck-focused-entity-id window) first-entity)
              (select-entity first-entity)
              (focus-on-entity-smooth window first-entity)))))))

  (register-action-handler registry :goto-head
    (lambda ()
      (let ((entities *snapshot-entities*))
        (when entities
          (let ((last-entity (car (last entities))))
            (when last-entity
              (setf (holodeck-focused-entity-id window) last-entity)
              (select-entity last-entity)
              (focus-on-entity-smooth window last-entity)))))))

  ;; ── Branching actions ───────────────────────────────────────────

  (register-action-handler registry :fork-here
    (lambda ()
      (let ((focused (holodeck-focused-entity-id window)))
        (if focused
            (handler-case
                (let ((snapshot-id (ignore-errors (snapshot-binding-snapshot-id focused))))
                  (when snapshot-id
                    (%emit-holodeck-event :fork-requested
                                          (list :snapshot-id snapshot-id
                                                :entity-id focused))))
              (error () nil))
            (%emit-holodeck-event :fork-requested nil)))))

  (register-action-handler registry :merge-prompt
    (lambda ()
      (%emit-holodeck-event :merge-prompt-requested nil)))

  (register-action-handler registry :show-branches
    (lambda ()
      (let ((hud (holodeck-hud window)))
        (when hud
          (toggle-panel-visibility hud :branches)))))

  ;; ── View mode actions ──────────────────────────────────────────

  (register-action-handler registry :set-view-timeline
    (lambda ()
      (%emit-holodeck-event :view-mode-changed (list :mode :timeline))))

  (register-action-handler registry :set-view-tree
    (lambda ()
      (%emit-holodeck-event :view-mode-changed (list :mode :tree))))

  (register-action-handler registry :set-view-constellation
    (lambda ()
      (%emit-holodeck-event :view-mode-changed (list :mode :constellation))))

  (register-action-handler registry :set-view-diff
    (lambda ()
      (%emit-holodeck-event :view-mode-changed (list :mode :diff))))

  ;; ── Focus actions ──────────────────────────────────────────────

  (register-action-handler registry :cycle-focus-next
    (lambda ()
      (let ((entities *snapshot-entities*))
        (when entities
          (let* ((current (holodeck-focused-entity-id window))
                 (idx (if current (position current entities) nil))
                 (next-idx (if idx
                               (mod (1+ idx) (length entities))
                               0))
                 (target (nth next-idx entities)))
            (when target
              (setf (holodeck-focused-entity-id window) target)
              (select-entity target)
              (when (holodeck-follow-mode-p window)
                (focus-on-entity-smooth window target))))))))

  (register-action-handler registry :cycle-focus-prev
    (lambda ()
      (let ((entities *snapshot-entities*))
        (when entities
          (let* ((current (holodeck-focused-entity-id window))
                 (idx (if current (position current entities) nil))
                 (prev-idx (if idx
                                (mod (1- idx) (length entities))
                                (1- (length entities))))
                 (target (nth prev-idx entities)))
            (when target
              (setf (holodeck-focused-entity-id window) target)
              (select-entity target)
              (when (holodeck-follow-mode-p window)
                (focus-on-entity-smooth window target))))))))

  (register-action-handler registry :toggle-follow
    (lambda ()
      (setf (holodeck-follow-mode-p window)
            (not (holodeck-follow-mode-p window)))
      ;; If follow mode just turned on and we have a focused entity, snap to it
      (when (and (holodeck-follow-mode-p window)
                 (holodeck-focused-entity-id window))
        (focus-on-entity-smooth window (holodeck-focused-entity-id window)))))

  (register-action-handler registry :overview
    (lambda ()
      (let ((camera (holodeck-camera window)))
        (when camera
          (let ((transition (camera-overview camera)))
            (when transition
              (setf *holodeck-transition* transition)))))))

  ;; ── Detail actions ─────────────────────────────────────────────

  (register-action-handler registry :increase-detail
    (lambda ()
      (dolist (entity *snapshot-entities*)
        (when (entity-valid-p entity)
          (handler-case
              (let ((current (detail-level-current entity)))
                (case current
                  (:culled (setf (detail-level-current entity) :low))
                  (:low (setf (detail-level-current entity) :high))))
            (error () nil))))))

  (register-action-handler registry :decrease-detail
    (lambda ()
      (dolist (entity *snapshot-entities*)
        (when (entity-valid-p entity)
          (handler-case
              (let ((current (detail-level-current entity)))
                (case current
                  (:high (setf (detail-level-current entity) :low))
                  (:low (setf (detail-level-current entity) :culled))))
            (error () nil))))))

  ;; ── UI actions ─────────────────────────────────────────────────

  (register-action-handler registry :enter-human-loop
    (lambda ()
      (%emit-holodeck-event :human-loop-requested nil)))

  (register-action-handler registry :exit-visualization
    (lambda ()
      (stop-holodeck)))

  (register-action-handler registry :toggle-hud
    (lambda ()
      (let ((hud (holodeck-hud window)))
        (when hud
          (toggle-hud-visibility hud)))))

  (register-action-handler registry :command-palette
    (lambda ()
      (%emit-holodeck-event :command-palette-requested nil)))

  (register-action-handler registry :show-help
    (lambda ()
      (let ((hud (holodeck-hud window)))
        (when hud
          (toggle-panel-visibility hud :help))))))

(defgeneric switch-camera-mode (window)
  (:documentation "Switch between orbit and fly camera modes."))

(defmethod switch-camera-mode ((window holodeck-window))
  "Switch the camera mode between orbit and fly."
  (let ((current-camera (holodeck-camera window))
        (registry (handler-registry (holodeck-keyboard-handler window))))
    (cond
      ((typep current-camera 'orbit-camera)
       ;; Switch to fly camera
       (let ((fly-cam (make-fly-camera)))
         (setf (holodeck-camera window) fly-cam)
         ;; Update camera input handler
         (when (holodeck-camera-input-handler window)
           (setf (camera-input-handler-camera (holodeck-camera-input-handler window)) fly-cam))
         ;; Re-register camera action handlers
         (register-camera-action-handlers registry fly-cam)))
      ((typep current-camera 'fly-camera)
       ;; Switch to orbit camera
       (let ((orbit-cam (make-orbit-camera)))
         (setf (holodeck-camera window) orbit-cam)
         ;; Update camera input handler
         (when (holodeck-camera-input-handler window)
           (setf (camera-input-handler-camera (holodeck-camera-input-handler window)) orbit-cam))
         ;; Re-register camera action handlers
         (register-camera-action-handlers registry orbit-cam))))))

(defgeneric toggle-2d-3d-mode (window)
  (:documentation "Toggle between 2D and 3D view modes."))

(defmethod toggle-2d-3d-mode ((window holodeck-window))
  "Toggle the view mode between 2D and 3D."
  (if (eq *view-mode* :2d)
      (set-view-mode :3d)
      (set-view-mode :2d)))

(defmethod handle-holodeck-event ((window holodeck-window) event)
  "Dispatch EVENT to the appropriate input handler based on event type.
   Returns T if the event was handled, NIL otherwise."
  (typecase event
    (key-event
     (handle-key-event window event))
    (mouse-move-event
     (handle-mouse-move-event window event))
    (mouse-button-event
     (handle-mouse-button-event window event))
    (scroll-event
     (handle-scroll-event window event))
    (resize-event
     (handle-resize-event window event))
    (t nil)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Handler Methods
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric handle-key-event (window event)
  (:documentation "Handle a keyboard key press or release event."))

(defmethod handle-key-event ((window holodeck-window) (event key-event))
  "Dispatch key event to the keyboard input handler."
  (let ((handler (holodeck-keyboard-handler window)))
    (when handler
      (let ((key (key-event-key event))
            (action (key-event-action event)))
        (ecase action
          (:press (handle-key-press handler key))
          (:release (handle-key-release handler key)))
        t))))

(defgeneric handle-mouse-move-event (window event)
  (:documentation "Handle a mouse cursor movement event."))

(defmethod handle-mouse-move-event ((window holodeck-window) (event mouse-move-event))
  "Dispatch mouse move event to the camera input handler."
  (let ((handler (holodeck-camera-input-handler window)))
    (when handler
      (handle-mouse-move handler
                         (mouse-move-event-x event)
                         (mouse-move-event-y event))
      t)))

(defgeneric handle-mouse-button-event (window event)
  (:documentation "Handle a mouse button press or release event."))

(defmethod handle-mouse-button-event ((window holodeck-window) (event mouse-button-event))
  "Dispatch mouse button event to the camera input handler.
   Also handles entity selection on left-click."
  (let ((cam-handler (holodeck-camera-input-handler window))
        (button (mouse-button-event-button event))
        (action (mouse-button-event-action event)))
    (when cam-handler
      ;; Update cursor position first
      (handle-mouse-move cam-handler
                         (mouse-button-event-x event)
                         (mouse-button-event-y event))
      ;; Handle button state
      (ecase action
        (:press
         (handle-mouse-button-press cam-handler button)
         ;; Left-click triggers entity selection
         (when (eq button :left)
           (handle-left-click-selection window event)))
        (:release
         (handle-mouse-button-release cam-handler button)))
      t)))

(defgeneric handle-scroll-event (window event)
  (:documentation "Handle a mouse scroll wheel event."))

(defmethod handle-scroll-event ((window holodeck-window) (event scroll-event))
  "Dispatch scroll event to the camera input handler for zooming."
  (let ((handler (holodeck-camera-input-handler window)))
    (when handler
      ;; Use delta-y for zoom (vertical scroll)
      (handle-scroll handler (scroll-event-delta-y event))
      t)))

(defgeneric handle-resize-event (window event)
  (:documentation "Handle a window resize event."))

(defmethod handle-resize-event ((window holodeck-window) (event resize-event))
  "Update window dimensions on resize."
  (resize-window window
                 (resize-event-width event)
                 (resize-event-height event))
  t)

;;; ═══════════════════════════════════════════════════════════════════
;;; Entity Selection on Click
;;; ═══════════════════════════════════════════════════════════════════

(defun handle-left-click-selection (window event)
  "Handle left-click for entity selection via ray picking.
   Uses the camera to cast a ray through the click position and
   selects the nearest interactive entity."
  (let ((camera (holodeck-camera window)))
    (when camera
      (let* ((x (mouse-button-event-x event))
             (y (mouse-button-event-y event))
             (width (window-width window))
             (height (window-height window))
             ;; Get all entities with interactive component
             (entities (collect-interactive-entities)))
        (when entities
          (let ((picked (pick-entity-at-screen-pos camera x y width height entities)))
            (if picked
                (select-entity picked)
                (deselect-entity)))))))
  nil)

(defun collect-interactive-entities ()
  "Collect all entity IDs that have an interactive component.
   Returns a list of entity IDs.
   
   Note: cl-fast-ecs doesn't provide entity iteration, so this function
   returns the tracked snapshot entities from *snapshot-entities* which
   are created with interactive components."
  (handler-case
      (copy-list *snapshot-entities*)
    (error () nil)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Per-Frame Input Processing
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric process-holodeck-input (window)
  (:documentation "Process accumulated input for one frame.
    Call this once per frame after all events have been dispatched."))

(defmethod process-holodeck-input ((window holodeck-window))
  "Process keyboard and camera input for the current frame.
   Executes pending keyboard actions and applies camera transformations."
  ;; Process keyboard input and execute actions
  (let ((kb-handler (holodeck-keyboard-handler window)))
    (when kb-handler
      (update-keyboard-input kb-handler)))
  ;; Process camera input (orbit, pan, zoom)
  (let ((cam-handler (holodeck-camera-input-handler window)))
    (when cam-handler
      (process-camera-input cam-handler)))
  ;; Update hover state based on current mouse position
  (update-hover-state window)
  t)

(defun update-hover-state (window)
  "Update entity hover state based on current mouse position."
  (let ((cam-handler (holodeck-camera-input-handler window))
        (camera (holodeck-camera window)))
    (when (and cam-handler camera)
      (let ((x (input-handler-mouse-x cam-handler))
            (y (input-handler-mouse-y cam-handler))
            (width (window-width window))
            (height (window-height window))
            (entities (collect-interactive-entities)))
        (when entities
          (update-hover-from-mouse camera x y width height entities))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Shader Source Definitions
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Shader sources stored as data for use when a rendering backend
;;; (Trial/OpenGL) is available.

(defparameter *hologram-node-vertex-shader*
  "#version 330 core
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
out vec3 fragNormal;
out vec3 fragPosition;
void main() {
  fragPosition = vec3(model * vec4(position, 1.0));
  fragNormal = mat3(transpose(inverse(model))) * normal;
  gl_Position = projection * view * vec4(fragPosition, 1.0);
}"
  "Vertex shader for holographic node rendering.
   Passes world-space position and transformed normals to fragment shader.")

(defparameter *hologram-node-fragment-shader*
  "#version 330 core
in vec3 fragNormal;
in vec3 fragPosition;
uniform vec3 viewPos;
uniform vec4 baseColor;
uniform float glowIntensity;
uniform float time;
out vec4 fragColor;

void main() {
  // Fresnel effect for holographic edge glow
  vec3 viewDir = normalize(viewPos - fragPosition);
  float fresnel = pow(1.0 - max(dot(normalize(fragNormal), viewDir), 0.0), 3.0);

  // Scanline effect
  float scanline = sin(fragPosition.y * 50.0 + time * 2.0) * 0.5 + 0.5;
  scanline = mix(0.8, 1.0, scanline);

  // Combine effects
  vec3 color = baseColor.rgb * scanline;
  color += vec3(0.3, 0.6, 1.0) * fresnel * glowIntensity;

  fragColor = vec4(color, baseColor.a + fresnel * 0.3);
}"
  "Fragment shader for holographic node rendering.
   Implements Fresnel edge glow, animated scanlines, and holographic effects.")

(defparameter *energy-beam-vertex-shader*
  "#version 330 core
layout(location = 0) in vec3 position;
layout(location = 1) in float progress;
uniform mat4 view;
uniform mat4 projection;
uniform float time;
uniform float energyFlow;
out float vProgress;
out float vEnergy;
void main() {
  gl_Position = projection * view * vec4(position, 1.0);
  vProgress = progress;
  vEnergy = sin((progress - time * energyFlow) * 6.28) * 0.5 + 0.5;
}"
  "Vertex shader for energy beam connections.
   Computes animated energy flow along the beam path.")

(defparameter *energy-beam-fragment-shader*
  "#version 330 core
in float vProgress;
in float vEnergy;
uniform vec4 color;
out vec4 fragColor;
void main() {
  float alpha = color.a * (0.3 + vEnergy * 0.7);
  vec3 finalColor = color.rgb * (1.0 + vEnergy * 0.5);
  fragColor = vec4(finalColor, alpha);
}"
  "Fragment shader for energy beam connections.
   Renders animated flowing energy effect along connections.")

(defparameter *shader-sources*
  (list :hologram-node
        (list :vertex *hologram-node-vertex-shader*
              :fragment *hologram-node-fragment-shader*)
        :energy-beam
        (list :vertex *energy-beam-vertex-shader*
              :fragment *energy-beam-fragment-shader*))
  "Plist of shader program name to (:vertex source :fragment source) pairs.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Holodeck Lifecycle
;;; ═══════════════════════════════════════════════════════════════════

(defvar *holodeck* nil
  "Current holodeck window instance, or NIL if none is running.")

(defun launch-holodeck (&key (width *window-width*)
                              (height *window-height*)
                              (title *window-title*)
                              store)
  "Create and initialize a holodeck window.
   Returns the window instance.  Sets *holodeck* to the new instance."
  (when *holodeck*
    (warn "A holodeck instance is already running.  Replacing it."))
  (let ((window (make-instance 'holodeck-window
                               :width width
                               :height height
                               :title title
                               :store store)))
    (setup-scene window)
    (setf *holodeck* window)
    window))

(defun stop-holodeck ()
  "Stop the running holodeck and clean up."
  (when *holodeck*
    (setf (holodeck-running-p *holodeck*) nil)
    (setf *holodeck* nil)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Main Render Loop
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; The render loop follows this sequence each frame:
;;;   1. Calculate delta time
;;;   2. Process input events
;;;   3. Update camera (sync state, apply transitions)
;;;   4. Run ECS systems (movement, pulse, LOD)
;;;   5. Collect render descriptions for entities and connections
;;;   6. Update and render HUD
;;;   7. Present frame (backend-specific)
;;;
;;; The loop is designed to work with or without a real rendering backend.
;;; Without a backend, it produces render descriptions that can be used
;;; for testing or headless operation.

(defvar *holodeck-transition* nil
  "Active camera transition, or NIL if no transition in progress.")

(defvar *last-frame-time* 0.0
  "Timestamp of the last frame for delta time calculation.")

(defvar *snapshot-sync-interval* 0.5
  "Minimum interval between snapshot sync operations in seconds.")

(defvar *last-snapshot-sync-time* 0.0
  "Timestamp of the last snapshot sync operation.")

(defvar *last-snapshot-timestamp* 0.0
  "Timestamp of the most recent snapshot synced.")

(defgeneric holodeck-frame (window dt)
  (:documentation "Execute one frame of the holodeck render loop.
    DT is the delta time in seconds since the last frame.
    Returns a frame-result plist with render descriptions."))

(defmethod holodeck-frame ((window holodeck-window) dt)
  "Execute one frame: input → camera → systems → entities → HUD.
   Returns a plist with:
     :dt              - Delta time for this frame
     :camera-position - Current camera world position
     :view-matrix     - Camera view matrix
     :projection-matrix - Camera projection matrix
     :snapshot-descriptions - List of snapshot entity render descriptions
     :connection-descriptions - List of connection render descriptions
     :hud-commands    - HUD render commands"
  (let ((dt-f (coerce dt 'single-float)))
    ;; 1. Process accumulated input
    (process-holodeck-input window)
    
    ;; 2. Update camera
    (let ((camera (holodeck-camera window)))
      (when camera
        ;; Apply any active transition
        (when *holodeck-transition*
          (unless (apply-camera-transition camera *holodeck-transition* dt-f)
            ;; Transition complete
            (setf *holodeck-transition* nil)))
        ;; Sync camera state to global *camera-position* for LOD system
        (sync-camera-state camera)))
    
    ;; 3. Run ECS systems
    (holodeck-update window dt-f)

     ;; 3b. Run persistent agent systems
     (persistent-sync-system dt-f)
     (cognitive-animation-system dt-f)
     (metabolic-glow-system dt-f)
     (lineage-rendering-system dt-f)

     ;; 3d. Run team topology systems
     (handler-case
         (progn
           (team-sync-system dt-f)
           (team-layout-system dt-f))
       (error () nil))

     ;; 3e. Follow-mode camera update
     (when (and (holodeck-follow-mode-p window)
                (holodeck-focused-entity-id window))
       (let ((focused (holodeck-focused-entity-id window)))
         (when (entity-valid-p focused)
           (handler-case
               (focus-on-entity-smooth window focused)
             (error () nil)))))

     ;; 3f. Sync snapshots for real-time updates
     (sync-snapshots window)

     ;; 4. Collect snapshot entity render descriptions
    (let ((snapshot-descs (collect-snapshot-render-descriptions)))
      
      ;; 5. Collect connection render descriptions
      (let ((connection-descs (collect-connection-render-descriptions)))
        
        ;; 6. Update and render HUD
        (let ((hud (holodeck-hud window)))
          (when hud
            (update-hud hud))
          (let ((hud-result (when hud (render-hud hud))))
            
            ;; 7. Build frame result
            (let ((camera (holodeck-camera window)))
              (list :dt dt-f
                    :camera-position (when camera (camera-position camera))
                    :view-matrix (when camera
                                   (camera-view-matrix-data camera))
                    :projection-matrix (when camera
                                         (camera-projection-matrix-data
                                          camera
                                          (window-aspect-ratio window)))
                    :snapshot-descriptions snapshot-descs
                    :connection-descriptions connection-descs
                    :hud-commands (getf hud-result :commands)
                    :hud-visible-p (getf hud-result :visible-p)))))))))

(defgeneric run-holodeck-loop (window &key frame-callback)
  (:documentation "Run the main holodeck loop until stopped.
    FRAME-CALLBACK, if provided, is called with the frame result after each frame.
    This is the entry point for interactive use with a rendering backend."))

(defmethod run-holodeck-loop ((window holodeck-window) &key frame-callback)
  "Run the holodeck main loop.
   Without a real rendering backend, this simulates frames at ~60fps.
   The loop continues while (holodeck-running-p window) is true.
   
   Each iteration:
     1. Calculates delta time from wall clock
     2. Calls holodeck-frame to process the frame
     3. Calls FRAME-CALLBACK with the frame result (if provided)
     4. Sleeps to maintain ~60fps (in headless mode)"
  (setf *last-frame-time* (get-internal-real-time))
  (setf (holodeck-running-p window) t)
  
  (loop while (holodeck-running-p window) do
    ;; Calculate delta time
    (let* ((current-time (get-internal-real-time))
           (dt-internal (- current-time *last-frame-time*))
           (dt (/ (coerce dt-internal 'single-float)
                  (coerce internal-time-units-per-second 'single-float))))
      (setf *last-frame-time* current-time)
      
      ;; Clamp delta time to avoid huge jumps
      (setf dt (min dt 0.1))
      
      ;; Execute frame
      (let ((frame-result (holodeck-frame window dt)))
        ;; Call user callback if provided
        (when frame-callback
          (funcall frame-callback frame-result)))
      
      ;; In headless mode, sleep to avoid spinning CPU
      ;; Target ~60fps = 16.67ms per frame
      (sleep 0.016))))

(defun holodeck-single-frame (&optional (dt 0.016))
  "Execute a single frame of the holodeck render loop.
    Convenience function for testing and non-interactive use.
    DT defaults to ~60fps frame time.
    Returns the frame result plist."
  (when *holodeck*
    (holodeck-frame *holodeck* dt)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Terminal Viewport Rendering
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Renders holodeck frames to the terminal using ANSI escape sequences.
;;; Provides a 2D projection of the 3D scene for terminal-based visualization.

(defparameter *viewport-width* 80
  "Default terminal viewport width in characters.")

(defparameter *viewport-height* 24
  "Default terminal viewport height in characters.")

(defparameter *viewport-scale* 2.0
  "Scale factor for 3D-to-2D projection (world units per character).")

(defparameter *viewport-center-x* 40
  "X center of viewport in terminal coordinates.")

(defparameter *viewport-center-y* 12
  "Y center of viewport in terminal coordinates.")

(defun project-3d-to-2d (x y z &key (view-matrix nil) (projection-matrix nil))
  "Project 3D world coordinates to 2D terminal coordinates.
    Performs simple orthographic projection with optional view/projection matrices.
    Returns (VALUES screen-x screen-y) or NIL if behind camera."
  (declare (ignore view-matrix projection-matrix)) ; Simple orthographic for now
  ;; Simple orthographic projection: ignore Z, scale and center
  (let ((screen-x (+ *viewport-center-x*
                     (round (/ x *viewport-scale*))))
        (screen-y (+ *viewport-center-y*
                     (round (/ (- y) *viewport-scale*))))) ; Flip Y for screen coords
    (values screen-x screen-y)))

(defun render-snapshot-to-terminal (desc stream)
  "Render a snapshot entity description to the terminal STREAM.
    Uses ANSI escape sequences for positioning and color."
  (let* ((position (render-desc-position desc))
         (color (render-desc-color desc))
         (lod (render-desc-lod desc))
         (label-text (render-desc-label-text desc)))
    (multiple-value-bind (screen-x screen-y)
        (project-3d-to-2d (first position) (second position) (third position))
      ;; Only render if within viewport bounds
      (when (and (>= screen-x 1) (< screen-x *viewport-width*)
                 (>= screen-y 1) (< screen-y *viewport-height*))
        ;; Position cursor
        (format stream "~c[~d;~dH" #\Escape screen-y screen-x)
        ;; Set color (convert RGBA to ANSI 256-color)
        (let* ((r (coerce (first color) 'single-float))
               (g (coerce (second color) 'single-float))
               (b (coerce (third color) 'single-float))
               ;; Simple RGB to ANSI 256-color mapping
               (ansi-color (rgb-to-ansi256 r g b)))
          (format stream "~c[38;5;~dm" #\Escape ansi-color))
        ;; Render glyph based on LOD
        (let ((glyph (ecase lod
                       (:high "●")
                       (:low "○")
                       (:culled ""))))
          (write-string glyph stream))
        ;; Render label if present and high detail
        (when (and label-text (eq lod :high))
          (let ((label-x (+ screen-x 2))
                (label-y screen-y))
            (when (< label-x *viewport-width*)
              (format stream "~c[~d;~dH" #\Escape label-y label-x)
              (write-string label-text stream))))))))

(defun render-connection-to-terminal (desc stream)
  "Render a connection entity description to the terminal STREAM.
    Draws a simple line between endpoints using ANSI positioning."
  (let* ((from-pos (getf desc :from-position))
         (to-pos (getf desc :to-position))
         (color (getf desc :color)))
    (multiple-value-bind (from-x from-y)
        (project-3d-to-2d (first from-pos) (second from-pos) (third from-pos))
      (multiple-value-bind (to-x to-y)
          (project-3d-to-2d (first to-pos) (second to-pos) (third to-pos))
        ;; Simple line drawing using Bresenham-like algorithm
        (when (and from-x from-y to-x to-y)
          (let ((dx (abs (- to-x from-x)))
                (dy (abs (- to-y from-y)))
                (sx (if (< from-x to-x) 1 -1))
                (sy (if (< from-y to-y) 1 -1))
                (err (- dx dy))
                (x from-x)
                (y from-y))
            ;; Set connection color
            (let* ((r (coerce (first color) 'single-float))
                   (g (coerce (second color) 'single-float))
                   (b (coerce (third color) 'single-float))
                   (ansi-color (rgb-to-ansi256 r g b)))
              (format stream "~c[38;5;~dm" #\Escape ansi-color))
            ;; Draw line segments
            (loop
              (when (and (>= x 1) (< x *viewport-width*)
                         (>= y 1) (< y *viewport-height*))
                (format stream "~c[~d;~dH─" #\Escape y x))
              (when (and (= x to-x) (= y to-y)) (return))
              (let ((e2 (* 2 err)))
                (when (> e2 (- dy))
                  (setf err (- err dy))
                  (incf x sx))
                (when (< e2 dx)
                  (setf err (+ err dx))
                  (incf y sy))))))))))

(defun rgb-to-ansi256 (r g b)
  "Convert RGB values (0.0-1.0) to ANSI 256-color code.
    Uses simple mapping to the 256-color palette."
  (let* ((r-byte (round (* r 5)))
         (g-byte (round (* g 5)))
         (b-byte (round (* b 5)))
         (ansi-code (+ 16 (* 36 r-byte) (* 6 g-byte) b-byte)))
    (min 255 (max 0 ansi-code))))

(defun holodeck_viewport (frame-result &key (stream *standard-output*) (clear-screen t))
  "Render a holodeck frame result to the terminal using ANSI escape sequences.
    FRAME-RESULT is the plist returned by holodeck-frame.
    STREAM is the output stream (defaults to *standard-output*).
    CLEAR-SCREEN controls whether to clear the screen before rendering."
  (when clear-screen
    ;; Clear screen and hide cursor
    (format stream "~c[2J~c[H~c[?25l" #\Escape #\Escape #\Escape))
  ;; Render snapshot entities
  (let ((snapshot-descs (getf frame-result :snapshot-descriptions)))
    (dolist (desc snapshot-descs)
      (render-snapshot-to-terminal desc stream)))
  ;; Render connection entities
  (let ((connection-descs (getf frame-result :connection-descriptions)))
    (dolist (desc connection-descs)
      (render-connection-to-terminal desc stream)))
  ;; Render HUD (simplified - just status info)
  (let ((camera-pos (getf frame-result :camera-position)))
    (when camera-pos
      (format stream "~c[1;1H~c[37mCamera: (~,1f, ~,1f, ~,1f)~c[0m"
              #\Escape #\Escape
              (first camera-pos) (second camera-pos) (third camera-pos)
              #\Escape)))
  ;; Show cursor and flush output
  (format stream "~c[?25h" #\Escape)
  (force-output stream))

;;; ═══════════════════════════════════════════════════════════════════
;;; Grid Rendering
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; The reference grid provides spatial context in the 3D visualization.
;;; It renders as a flat grid on the XZ plane at Y=0.

(defparameter *grid-size* 100.0
  "Size of the reference grid in world units (extends from -size/2 to +size/2).")

(defparameter *grid-spacing* 10.0
  "Spacing between grid lines in world units.")

(defparameter *grid-color* '(0.1 0.2 0.3 0.3)
  "RGBA color for grid lines.")

(defparameter *grid-axis-color* '(0.2 0.4 0.6 0.5)
  "RGBA color for grid axis lines (X and Z axes).")

(defun render-grid-commands ()
  "Generate render commands for the reference grid.
   Returns a list of line command plists for drawing the grid.
   Each command has :type :grid-line and :x1 :y1 :z1 :x2 :y2 :z2 :color."
  (let ((commands nil)
        (half-size (/ *grid-size* 2.0))
        (spacing *grid-spacing*))
    ;; Generate lines parallel to X axis (varying Z)
    (loop for z from (- half-size) to half-size by spacing do
      (let ((color (if (< (abs z) 0.001)
                       *grid-axis-color*
                       *grid-color*)))
        (push (list :type :grid-line
                    :x1 (- half-size) :y1 0.0 :z1 z
                    :x2 half-size :y2 0.0 :z2 z
                    :color color)
              commands)))
    ;; Generate lines parallel to Z axis (varying X)
    (loop for x from (- half-size) to half-size by spacing do
      (let ((color (if (< (abs x) 0.001)
                       *grid-axis-color*
                       *grid-color*)))
        (push (list :type :grid-line
                    :x1 x :y1 0.0 :z1 (- half-size)
                    :x2 x :y2 0.0 :z2 half-size
                    :color color)
              commands)))
    (nreverse commands)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Live Agent Synchronization
;;; ═══════════════════════════════════════════════════════════════════
;;;
;;; Synchronizes holodeck visualization with live running agents.
;;; Updates entity positions to match current agent state and adds
;;; smooth transitions for visual continuity.

(defvar *agent-entity-map* (make-hash-table :test 'equal)
  "Maps agent IDs to their corresponding holodeck entity IDs.")

(defvar *sync-interval* 0.1
  "Minimum interval between sync operations in seconds.")

(defvar *last-sync-time* 0.0
  "Timestamp of the last sync operation.")

(defvar *transition-duration* 0.3
  "Duration of smooth position transitions in seconds.")

(defun should-sync-p ()
  "Return T if enough time has passed since the last sync."
  (> (- *elapsed-time* *last-sync-time*) *sync-interval*))

(defun find-agent-entity (agent-id)
  "Find the holodeck entity for an agent by AGENT-ID.
   Returns the entity ID or NIL if not found."
  (gethash agent-id *agent-entity-map*))

(defun register-agent-entity (agent-id entity)
  "Register ENTITY as the holodeck representation of agent AGENT-ID."
  (setf (gethash agent-id *agent-entity-map*) entity)
  entity)

(defun unregister-agent-entity (agent-id)
  "Remove the agent-entity mapping for AGENT-ID."
  (remhash agent-id *agent-entity-map*))

(defun clear-agent-entity-map ()
  "Clear all agent-entity mappings."
  (clrhash *agent-entity-map*))

(defun create-agent-marker-entity (agent)
  "Create a holodeck entity to represent a live AGENT.
   The entity is styled distinctively to indicate it's a live agent marker."
  (let* ((agent-id (autopoiesis.agent:agent-id agent))
         (agent-name (autopoiesis.agent:agent-name agent))
         (entity (cl-fast-ecs:make-entity)))
    ;; Position (will be updated by sync)
    (make-position3d entity :x 0.0 :y 0.0 :z 0.0)
    (make-scale3d entity :sx 1.5 :sy 1.5 :sz 1.5)
    (make-rotation3d entity)
    ;; Agent binding
    (make-agent-binding entity
                        :agent-id agent-id
                        :agent-name agent-name)
    ;; Visual style - cyan color with strong glow and pulse for live agents
    (make-visual-style entity
                       :node-type :agent
                       :color-r 0.2 :color-g 1.0 :color-b 0.8 :color-a 0.95
                       :glow-intensity 1.5
                       :pulse-rate 2.0)
    ;; Label showing agent name
    (make-node-label entity
                     :text agent-name
                     :visible-p t
                     :offset-y 2.0)
    ;; Interactive
    (make-interactive entity)
    (make-detail-level entity :current :high)
    ;; Register in tracking structures
    (track-snapshot-entity entity)
    (register-agent-entity agent-id entity)
    entity))

(defun compute-agent-position (agent)
  "Compute the 3D position for an AGENT based on its current state.
   Returns (VALUES x y z) for the agent's position in cognitive space.
   
   Position mapping:
   - X-axis: Time (based on thought stream length or elapsed time)
   - Y-axis: Abstraction level (based on agent state)
   - Z-axis: Branch/parallel dimension (based on agent ID hash for spread)"
  (let* ((thought-stream (autopoiesis.agent:agent-thought-stream agent))
         (stream-length (if thought-stream
                           (autopoiesis.core:stream-length thought-stream)
                           0))
         ;; X = time progression (10 units per thought, offset by 5 for visibility)
         (x (coerce (+ 5.0 (* stream-length 10.0)) 'single-float))
         ;; Y = abstraction level based on state
         (y (case (autopoiesis.agent:agent-state agent)
              (:running 2.0)
              (:paused 1.5)
              (:initialized 1.0)
              (otherwise 0.5)))
         ;; Z = spread agents across Z axis using hash of ID
         (agent-id (autopoiesis.agent:agent-id agent))
         (z (coerce (* 20.0 (mod (sxhash agent-id) 10) 0.1) 'single-float)))
    (values x y z)))

(defun update-agent-entity-position (entity agent)
  "Update ENTITY's position to match AGENT's current state.
   Uses smooth transitions for visual continuity."
  (multiple-value-bind (target-x target-y target-z)
      (compute-agent-position agent)
    (let* ((current-x (position3d-x entity))
           (current-y (position3d-y entity))
           (current-z (position3d-z entity))
           ;; Check if position has changed significantly
           (dx (abs (- target-x current-x)))
           (dy (abs (- target-y current-y)))
           (dz (abs (- target-z current-z)))
           (threshold 0.01))
      ;; Only update if position changed
      (when (or (> dx threshold) (> dy threshold) (> dz threshold))
        ;; For smooth transitions, we interpolate toward target
        ;; Using simple lerp with factor based on delta time
        (let ((lerp-factor (min 1.0 (* 5.0 *delta-time*))))
          (setf (position3d-x entity)
                (coerce (+ current-x (* lerp-factor (- target-x current-x)))
                        'single-float))
          (setf (position3d-y entity)
                (coerce (+ current-y (* lerp-factor (- target-y current-y)))
                        'single-float))
          (setf (position3d-z entity)
                (coerce (+ current-z (* lerp-factor (- target-z current-z)))
                        'single-float)))))))

(defun sync-live-agents ()
  "Synchronize holodeck visualization with live running agents.
   
   This function:
   1. Gets all currently running agents from the agent registry
   2. Creates entities for new agents not yet in the visualization
   3. Updates positions of existing agent entities
   4. Removes entities for agents that are no longer running
   
   Called periodically from the main render loop when should-sync-p returns T."
  (setf *last-sync-time* *elapsed-time*)
  (let ((running (autopoiesis.agent:running-agents))
        (seen-agents (make-hash-table :test 'equal)))
    ;; Process running agents
    (dolist (agent running)
      (let* ((agent-id (autopoiesis.agent:agent-id agent))
             (entity (find-agent-entity agent-id)))
        (setf (gethash agent-id seen-agents) t)
        (if entity
            ;; Update existing entity
            (update-agent-entity-position entity agent)
            ;; Create new entity for this agent
            (let ((new-entity (create-agent-marker-entity agent)))
              (multiple-value-bind (x y z) (compute-agent-position agent)
                (setf (position3d-x new-entity) (coerce x 'single-float))
                (setf (position3d-y new-entity) (coerce y 'single-float))
                (setf (position3d-z new-entity) (coerce z 'single-float)))))))
    ;; Remove entities for agents that are no longer running
    (let ((to-remove nil))
      (maphash (lambda (agent-id entity)
                 (declare (ignore entity))
                 (unless (gethash agent-id seen-agents)
                   (push agent-id to-remove)))
               *agent-entity-map*)
      (dolist (agent-id to-remove)
        (let ((entity (gethash agent-id *agent-entity-map*)))
          (when entity
            ;; Remove from snapshot entities tracking
            (setf *snapshot-entities* (remove entity *snapshot-entities*))
            ;; Delete the entity from ECS
            (handler-case
                (cl-fast-ecs:delete-entity entity)
              (error () nil)))
          (unregister-agent-entity agent-id))))))

(defun sync-live-agents-count ()
  "Return the number of agent entities currently being tracked."
  (hash-table-count *agent-entity-map*))

(defun sync-snapshots (window)
  "Synchronize snapshot entities with the substrate store."
  (when (> (- *elapsed-time* *last-snapshot-sync-time*) *snapshot-sync-interval*)
    (setf *last-snapshot-sync-time* *elapsed-time*)
    (let ((store (holodeck-store window)))
      (when store
        (let ((new-snapshots (autopoiesis.snapshot:find-snapshots-since *last-snapshot-timestamp* store)))
          (dolist (snapshot new-snapshots)
            (let ((entity (make-snapshot-entity snapshot)))
              (setf *last-snapshot-timestamp*
                    (max *last-snapshot-timestamp* (snapshot-timestamp snapshot))))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Aspect Ratio and Projection Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun window-aspect-ratio (window)
  "Compute the aspect ratio (width/height) for WINDOW."
  (let ((w (window-width window))
        (h (window-height window)))
    (if (zerop h)
        1.0
        (coerce (/ w h) 'single-float))))

(defun resize-window (window new-width new-height)
  "Handle window resize to NEW-WIDTH x NEW-HEIGHT."
  (setf (window-width window) new-width
        (window-height window) new-height))
