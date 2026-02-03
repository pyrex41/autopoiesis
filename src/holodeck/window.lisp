;;;; window.lisp - Holodeck window and scene setup
;;;;
;;;; Defines the holodeck-window class, which manages the 3D visualization
;;;; window, scene graph, camera, and HUD.  When the Trial game engine is
;;;; available (indicated by the :trial feature), holodeck-window extends
;;;; trial:main for native OpenGL rendering.  Without Trial, it provides
;;;; the same protocol as a standalone CLOS class for testing and headless
;;;; operation.
;;;;
;;;; Phase 8.2 - Rendering (first task)

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
          :documentation "Snapshot store to visualize."))
  (:documentation
   "Main window class for the 3D holodeck visualization.
    Manages the rendering context, scene graph, camera, and HUD.
    When Trial is available, a subclass can extend trial:main for
    native OpenGL rendering."))

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
  "Default scene setup: initializes ECS storage and marks window ready."
  (init-holodeck-storage)
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

(defmethod handle-holodeck-event ((window holodeck-window) event)
  "Default event handler: no-op."
  (declare (ignore event))
  nil)

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
