;;;; shaders.lisp - Holographic shader programs and materials
;;;;
;;;; Implements the hologram-node shader system with Fresnel edge glow,
;;;; animated scanlines, and additive glow effects.  Provides both GPU
;;;; shader source management and CPU-side color computation for testing
;;;; and headless rendering.
;;;;
;;;; Phase 8.2 - Rendering (hologram-node shader)

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Shader Program Class
;;; ===================================================================

(defclass shader-program ()
  ((name :initarg :name
         :accessor shader-program-name
         :type keyword
         :documentation "Unique name identifying this shader program.")
   (vertex-source :initarg :vertex-source
                  :accessor shader-program-vertex-source
                  :initform ""
                  :type string
                  :documentation "GLSL vertex shader source code.")
   (fragment-source :initarg :fragment-source
                    :accessor shader-program-fragment-source
                    :initform ""
                    :type string
                    :documentation "GLSL fragment shader source code.")
   (uniforms :initarg :uniforms
             :accessor shader-program-uniforms
             :initform nil
             :type list
             :documentation "List of (name type default-value) uniform declarations."))
  (:documentation
   "Encapsulates a GPU shader program with vertex and fragment stages.
    Stores shader source code and uniform declarations for both GPU
    compilation and CPU-side validation."))

(defgeneric shader-program-uniform-names (program)
  (:documentation "Return a list of uniform name strings for PROGRAM."))

(defmethod shader-program-uniform-names ((program shader-program))
  "Extract uniform names from the uniform declarations."
  (mapcar #'first (shader-program-uniforms program)))

(defmethod print-object ((program shader-program) stream)
  (print-unreadable-object (program stream :type t)
    (format stream "~A (~D uniforms)"
            (shader-program-name program)
            (length (shader-program-uniforms program)))))

;;; ===================================================================
;;; Shader Registry
;;; ===================================================================

(defvar *shader-registry* (make-hash-table :test 'eq)
  "Registry of shader programs by keyword name.")

(defun register-shader-program (program)
  "Register PROGRAM in the global shader registry."
  (setf (gethash (shader-program-name program) *shader-registry*)
        program))

(defun find-shader-program (name)
  "Look up shader program by NAME (keyword) in the registry.
   Returns NIL if not found."
  (gethash name *shader-registry*))

(defun list-shader-programs ()
  "Return a list of all registered shader program names."
  (let (names)
    (maphash (lambda (k v) (declare (ignore v)) (push k names))
             *shader-registry*)
    (nreverse names)))

(defun clear-shader-registry ()
  "Remove all shader programs from the registry."
  (clrhash *shader-registry*))

;;; ===================================================================
;;; Hologram Node Shader Program
;;; ===================================================================

(defparameter *hologram-node-uniforms*
  '(("model"         :mat4   nil)
    ("view"          :mat4   nil)
    ("projection"    :mat4   nil)
    ("viewPos"       :vec3   (0.0 0.0 50.0))
    ("baseColor"     :vec4   (0.3 0.6 1.0 0.8))
    ("glowIntensity" :float  1.0)
    ("time"          :float  0.0))
  "Uniform declarations for the hologram-node shader program.")

(defun make-hologram-node-shader ()
  "Create and return the hologram-node shader program.
   This shader implements:
   - Fresnel edge glow (brighter at glancing angles)
   - Animated scanlines (horizontal bands that scroll vertically)
   - Configurable glow intensity and base color"
  (make-instance 'shader-program
                 :name :hologram-node
                 :vertex-source *hologram-node-vertex-shader*
                 :fragment-source *hologram-node-fragment-shader*
                 :uniforms *hologram-node-uniforms*))

;;; ===================================================================
;;; Energy Beam Shader Program
;;; ===================================================================

(defparameter *energy-beam-uniforms*
  '(("view"       :mat4  nil)
    ("projection" :mat4  nil)
    ("time"       :float 0.0)
    ("energyFlow" :float 1.0)
    ("color"      :vec4  (0.4 0.4 0.8 0.5)))
  "Uniform declarations for the energy-beam shader program.")

(defun make-energy-beam-shader ()
  "Create and return the energy-beam shader program.
   This shader implements animated energy flow along connection beams."
  (make-instance 'shader-program
                 :name :energy-beam
                 :vertex-source *energy-beam-vertex-shader*
                 :fragment-source *energy-beam-fragment-shader*
                 :uniforms *energy-beam-uniforms*))

;;; ===================================================================
;;; Glow Post-Effect Shader
;;; ===================================================================

(defparameter *glow-vertex-shader*
  "#version 330 core
layout(location = 0) in vec3 position;
layout(location = 1) in vec2 texCoord;
uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
out vec2 vTexCoord;
void main() {
  gl_Position = projection * view * model * vec4(position, 1.0);
  vTexCoord = texCoord;
}"
  "Vertex shader for the additive glow billboard effect.")

(defparameter *glow-fragment-shader*
  "#version 330 core
in vec2 vTexCoord;
uniform vec4 glowColor;
uniform float intensity;
uniform float falloff;
out vec4 fragColor;
void main() {
  float dist = length(vTexCoord - vec2(0.5));
  float glow = exp(-dist * dist * falloff) * intensity;
  fragColor = vec4(glowColor.rgb, glow * glowColor.a);
}"
  "Fragment shader for the additive glow billboard effect.
   Renders a radial falloff glow centered on the billboard quad.")

(defparameter *glow-uniforms*
  '(("model"      :mat4  nil)
    ("view"       :mat4  nil)
    ("projection" :mat4  nil)
    ("glowColor"  :vec4  (0.5 0.8 1.0 1.0))
    ("intensity"  :float 1.0)
    ("falloff"    :float 4.0))
  "Uniform declarations for the glow shader program.")

(defun make-glow-shader ()
  "Create and return the glow post-effect shader program."
  (make-instance 'shader-program
                 :name :glow
                 :vertex-source *glow-vertex-shader*
                 :fragment-source *glow-fragment-shader*
                 :uniforms *glow-uniforms*))

;;; ===================================================================
;;; Shader Registration
;;; ===================================================================

(defun register-holodeck-shaders ()
  "Register all standard holodeck shader programs in the global registry."
  (register-shader-program (make-hologram-node-shader))
  (register-shader-program (make-energy-beam-shader))
  (register-shader-program (make-glow-shader))
  (list-shader-programs))

;;; ===================================================================
;;; Hologram Material Class
;;; ===================================================================

(defclass hologram-material ()
  ((base-color :initarg :base-color
               :accessor material-base-color
               :initform '(0.3 0.6 1.0 0.8)
               :type list
               :documentation "RGBA base color of the hologram.")
   (glow-intensity :initarg :glow-intensity
                   :accessor material-glow-intensity
                   :initform 1.0
                   :type single-float
                   :documentation "Intensity of the Fresnel edge glow (0.0 to 3.0).")
   (glow-color :initarg :glow-color
               :accessor material-glow-color
               :initform '(0.3 0.6 1.0)
               :type list
               :documentation "RGB color of the additive glow effect.")
   (fresnel-power :initarg :fresnel-power
                  :accessor material-fresnel-power
                  :initform 3.0
                  :type single-float
                  :documentation "Exponent for the Fresnel falloff curve.
                   Higher values concentrate the glow more at glancing angles.")
   (scanline-frequency :initarg :scanline-frequency
                       :accessor material-scanline-frequency
                       :initform 50.0
                       :type single-float
                       :documentation "Spatial frequency of scanlines (lines per world unit).")
   (scanline-speed :initarg :scanline-speed
                   :accessor material-scanline-speed
                   :initform 2.0
                   :type single-float
                   :documentation "Vertical scrolling speed of scanlines.")
   (scanline-intensity :initarg :scanline-intensity
                       :accessor material-scanline-intensity
                       :initform 0.2
                       :type single-float
                       :documentation "How strongly scanlines modulate the base color (0=none, 1=full).")
   (shader :initarg :shader
           :accessor material-shader
           :initform :hologram-node
           :type keyword
           :documentation "Name of the shader program to use."))
  (:documentation
   "Material properties for holographic node rendering.
    Combines shader selection with visual parameters that control
    the Fresnel edge glow, animated scanlines, and additive glow."))

(defmethod print-object ((mat hologram-material) stream)
  (print-unreadable-object (mat stream :type t)
    (format stream "glow=~,1F fresnel=~,1F scanlines=~,0F"
            (material-glow-intensity mat)
            (material-fresnel-power mat)
            (material-scanline-frequency mat))))

;;; ===================================================================
;;; Material Factory Functions
;;; ===================================================================

(defun make-hologram-material-for-type (snapshot-type)
  "Create a hologram-material configured for SNAPSHOT-TYPE.
   Each snapshot type gets a distinctive holographic appearance."
  (multiple-value-bind (r g b a) (snapshot-type-to-color snapshot-type)
    (let ((glow-r (min 1.0 (* r 1.5)))
          (glow-g (min 1.0 (* g 1.5)))
          (glow-b (min 1.0 (* b 1.5))))
      (case snapshot-type
        (:genesis
         (make-instance 'hologram-material
                        :base-color (list r g b a)
                        :glow-color (list glow-r glow-g glow-b)
                        :glow-intensity 1.5
                        :fresnel-power 2.0
                        :scanline-frequency 30.0
                        :scanline-speed 1.0
                        :scanline-intensity 0.15))
        (:decision
         (make-instance 'hologram-material
                        :base-color (list r g b a)
                        :glow-color (list glow-r glow-g glow-b)
                        :glow-intensity 1.8
                        :fresnel-power 3.0
                        :scanline-frequency 60.0
                        :scanline-speed 3.0
                        :scanline-intensity 0.25))
        (:fork
         (make-instance 'hologram-material
                        :base-color (list r g b a)
                        :glow-color (list glow-r glow-g glow-b)
                        :glow-intensity 2.0
                        :fresnel-power 2.5
                        :scanline-frequency 40.0
                        :scanline-speed 4.0
                        :scanline-intensity 0.3))
        (:error
         (make-instance 'hologram-material
                        :base-color (list r g b a)
                        :glow-color (list 1.0 0.3 0.3)
                        :glow-intensity 2.5
                        :fresnel-power 2.0
                        :scanline-frequency 80.0
                        :scanline-speed 5.0
                        :scanline-intensity 0.35))
        (otherwise
         (make-instance 'hologram-material
                        :base-color (list r g b a)
                        :glow-color (list glow-r glow-g glow-b)
                        :glow-intensity 1.0
                        :fresnel-power 3.0
                        :scanline-frequency 50.0
                        :scanline-speed 2.0
                        :scanline-intensity 0.2))))))

;;; ===================================================================
;;; CPU-Side Hologram Color Computation
;;; ===================================================================
;;;
;;; These functions replicate the GPU shader math on the CPU for testing,
;;; headless rendering, and preview thumbnails.

(defun compute-fresnel (normal-dot-view fresnel-power)
  "Compute the Fresnel term given NORMAL-DOT-VIEW angle and FRESNEL-POWER.
   Returns a value in [0,1] where 1 = edge-on (maximum glow) and
   0 = face-on (minimum glow)."
  (let ((clamped (max 0.0 (min 1.0 (coerce normal-dot-view 'single-float)))))
    (expt (- 1.0 clamped) (coerce fresnel-power 'single-float))))

(defun compute-scanline (y-position time frequency speed)
  "Compute the scanline modulation factor at Y-POSITION and TIME.
   Returns a value in [0,1] suitable for mixing with base color.
   FREQUENCY controls line density, SPEED controls scroll rate."
  (let* ((phase (+ (* (coerce y-position 'single-float)
                      (coerce frequency 'single-float))
                   (* (coerce time 'single-float)
                      (coerce speed 'single-float))))
         (raw (+ (* (sin phase) 0.5) 0.5)))
    (coerce raw 'single-float)))

(defun compute-hologram-color (material normal-dot-view y-position time)
  "Compute the final hologram color using MATERIAL properties.
   NORMAL-DOT-VIEW is the dot product of the surface normal and view direction.
   Y-POSITION is the world-space Y coordinate (for scanlines).
   TIME is the current animation time in seconds.

   Returns four values: R G B A as single-floats in [0,1]."
  (let* ((base-color (material-base-color material))
         (base-r (coerce (first base-color) 'single-float))
         (base-g (coerce (second base-color) 'single-float))
         (base-b (coerce (third base-color) 'single-float))
         (base-a (coerce (fourth base-color) 'single-float))
         ;; Fresnel edge glow
         (fresnel (compute-fresnel normal-dot-view
                                   (material-fresnel-power material)))
         (glow-int (material-glow-intensity material))
         (glow-color (material-glow-color material))
         (glow-r (coerce (first glow-color) 'single-float))
         (glow-g (coerce (second glow-color) 'single-float))
         (glow-b (coerce (third glow-color) 'single-float))
         ;; Scanline modulation
         (scanline-raw (compute-scanline y-position time
                                         (material-scanline-frequency material)
                                         (material-scanline-speed material)))
         (scan-intensity (material-scanline-intensity material))
         (scanline-factor (+ (- 1.0 scan-intensity)
                            (* scan-intensity scanline-raw)))
         ;; Apply scanlines to base color
         (color-r (* base-r scanline-factor))
         (color-g (* base-g scanline-factor))
         (color-b (* base-b scanline-factor))
         ;; Add Fresnel glow
         (fresnel-contribution (* fresnel glow-int))
         (final-r (min 1.0 (+ color-r (* glow-r fresnel-contribution))))
         (final-g (min 1.0 (+ color-g (* glow-g fresnel-contribution))))
         (final-b (min 1.0 (+ color-b (* glow-b fresnel-contribution))))
         ;; Alpha increases at edges due to Fresnel
         (final-a (min 1.0 (+ base-a (* fresnel 0.3)))))
    (values final-r final-g final-b final-a)))

;;; ===================================================================
;;; Energy Beam Material Class
;;; ===================================================================

(defclass energy-beam-material ()
  ((beam-color :initarg :beam-color
               :accessor beam-material-color
               :initform '(0.4 0.4 0.8 0.5)
               :type list
               :documentation "RGBA color of the energy beam.")
   (flow-speed :initarg :flow-speed
               :accessor beam-material-flow-speed
               :initform 1.0
               :type single-float
               :documentation "Speed of the energy flow animation along the beam.
                Higher values make the energy particles travel faster.")
   (flow-scale :initarg :flow-scale
               :accessor beam-material-flow-scale
               :initform 6.28
               :type single-float
               :documentation "Spatial frequency of the energy flow pattern.
                Controls how many energy pulses are visible along the beam.")
   (pulse-intensity :initarg :pulse-intensity
                    :accessor beam-material-pulse-intensity
                    :initform 0.7
                    :type single-float
                    :documentation "Intensity of the energy flow pulse effect (0.0 to 1.0).
                     Controls the contrast between bright and dim regions.")
   (base-alpha :initarg :base-alpha
               :accessor beam-material-base-alpha
               :initform 0.3
               :type single-float
               :documentation "Minimum alpha when the energy flow is at its dimmest.
                The beam is always at least this visible.")
   (color-boost :initarg :color-boost
                :accessor beam-material-color-boost
                :initform 0.5
                :type single-float
                :documentation "How much to brighten the color at energy peaks.
                 Values > 0 make the beam brighter than its base color at peaks."))
  (:documentation
   "Material properties for energy beam connection rendering.
    Controls the animated energy flow effect that makes connections
    between snapshot nodes look like flowing energy conduits."))

(defmethod print-object ((mat energy-beam-material) stream)
  (print-unreadable-object (mat stream :type t)
    (format stream "flow=~,1F pulse=~,1F alpha=~,1F"
            (beam-material-flow-speed mat)
            (beam-material-pulse-intensity mat)
            (beam-material-base-alpha mat))))

;;; ===================================================================
;;; Energy Beam Material Factory
;;; ===================================================================

(defun connection-type-to-color (connection-type)
  "Return (r g b a) color values for a connection type.
   Matches the holographic theme from the spec."
  (case connection-type
    (:temporal     (values 0.3 0.5 0.8 0.6))   ; blue
    (:parent-child (values 0.3 0.5 0.8 0.6))   ; blue (same as temporal)
    (:fork         (values 0.8 0.3 1.0 0.8))   ; purple
    (:branch       (values 0.8 0.3 1.0 0.8))   ; purple (same as fork)
    (:merge        (values 0.2 1.0 0.5 0.8))   ; green
    (otherwise     (values 0.4 0.4 0.8 0.5)))) ; default blue-grey

(defun make-energy-beam-material-for-connection-type (connection-type)
  "Create an energy-beam-material configured for CONNECTION-TYPE.
   Each connection type gets a distinctive energy flow appearance."
  (multiple-value-bind (r g b a) (connection-type-to-color connection-type)
    (case connection-type
      ((:temporal :parent-child)
       (make-instance 'energy-beam-material
                      :beam-color (list r g b a)
                      :flow-speed 1.0
                      :flow-scale 6.28
                      :pulse-intensity 0.7
                      :base-alpha 0.3
                      :color-boost 0.5))
      ((:fork :branch)
       (make-instance 'energy-beam-material
                      :beam-color (list r g b a)
                      :flow-speed 2.0
                      :flow-scale 9.42
                      :pulse-intensity 0.9
                      :base-alpha 0.4
                      :color-boost 0.7))
      (:merge
       (make-instance 'energy-beam-material
                      :beam-color (list r g b a)
                      :flow-speed 1.5
                      :flow-scale 4.71
                      :pulse-intensity 0.6
                      :base-alpha 0.35
                      :color-boost 0.4))
      (otherwise
       (make-instance 'energy-beam-material
                      :beam-color (list r g b a)
                      :flow-speed 1.0
                      :flow-scale 6.28
                      :pulse-intensity 0.7
                      :base-alpha 0.3
                      :color-boost 0.5)))))

;;; ===================================================================
;;; CPU-Side Energy Beam Computation
;;; ===================================================================
;;;
;;; These functions replicate the energy-beam GPU shader math on the CPU
;;; for testing, headless rendering, and preview thumbnails.

(defun compute-energy-flow (progress time flow-speed flow-scale)
  "Compute the energy flow value at a point along the beam.
   PROGRESS is the position along the beam in [0,1] (0=start, 1=end).
   TIME is the current animation time in seconds.
   FLOW-SPEED controls how fast the energy moves along the beam.
   FLOW-SCALE controls the spatial frequency of energy pulses.

   Returns a value in [0,1] where 1 = peak energy, 0 = minimum energy.
   Replicates: sin((progress - time * energyFlow) * 6.28) * 0.5 + 0.5"
  (let* ((phase (* (- (coerce progress 'single-float)
                      (* (coerce time 'single-float)
                         (coerce flow-speed 'single-float)))
                   (coerce flow-scale 'single-float)))
         (raw (+ (* (sin phase) 0.5) 0.5)))
    (coerce raw 'single-float)))

(defun compute-beam-color (material progress time)
  "Compute the final energy beam color using MATERIAL properties.
   PROGRESS is the position along the beam in [0,1].
   TIME is the current animation time in seconds.

   Returns four values: R G B A as single-floats.
   Replicates the energy-beam fragment shader logic:
     alpha = color.a * (base-alpha + energy * pulse-intensity)
     finalColor = color.rgb * (1.0 + energy * color-boost)"
  (let* ((beam-color (beam-material-color material))
         (base-r (coerce (first beam-color) 'single-float))
         (base-g (coerce (second beam-color) 'single-float))
         (base-b (coerce (third beam-color) 'single-float))
         (base-a (coerce (fourth beam-color) 'single-float))
         ;; Compute energy flow at this point
         (energy (compute-energy-flow progress time
                                      (beam-material-flow-speed material)
                                      (beam-material-flow-scale material)))
         ;; Alpha: base minimum + energy-modulated portion
         (pulse-int (beam-material-pulse-intensity material))
         (min-alpha (beam-material-base-alpha material))
         (alpha (* base-a (+ min-alpha (* energy pulse-int))))
         ;; Color: base + energy-modulated boost
         (boost (beam-material-color-boost material))
         (color-factor (+ 1.0 (* energy boost)))
         (final-r (min 1.0 (* base-r color-factor)))
         (final-g (min 1.0 (* base-g color-factor)))
         (final-b (min 1.0 (* base-b color-factor)))
         (final-a (min 1.0 alpha)))
    (values final-r final-g final-b final-a)))

;;; ===================================================================
;;; Shader Source Validation
;;; ===================================================================

(defun validate-shader-source (source)
  "Validate that SOURCE is a syntactically plausible GLSL shader string.
   Checks for required elements: version directive, main function.
   Returns T if valid, or signals a condition with the problem."
  (unless (stringp source)
    (error "Shader source must be a string, got ~A" (type-of source)))
  (unless (search "#version" source)
    (error "Shader source missing #version directive"))
  (unless (search "void main()" source)
    (error "Shader source missing void main() entry point"))
  t)

(defun validate-shader-program (program)
  "Validate all sources in PROGRAM.
   Returns T if both vertex and fragment shaders pass validation."
  (validate-shader-source (shader-program-vertex-source program))
  (validate-shader-source (shader-program-fragment-source program))
  t)
