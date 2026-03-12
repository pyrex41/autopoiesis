;;;; components.lisp - ECS component definitions for holodeck visualization
;;;;
;;;; Defines the Entity-Component-System components for the 3D holodeck.
;;;; Components are plain data containers; all behavior lives in systems.
;;;;
;;;; Component categories:
;;;;   Spatial    - position3d, velocity3d, scale3d, rotation3d
;;;;   Visual    - visual-style, node-label
;;;;   Binding   - snapshot-binding, agent-binding, connection
;;;;   Interact  - interactive, detail-level

(in-package #:autopoiesis.holodeck)

;;; ═══════════════════════════════════════════════════════════════════
;;; ECS Storage Initialization
;;; ═══════════════════════════════════════════════════════════════════

(defun init-holodeck-storage ()
  "Initialize the ECS storage for the holodeck.
   Must be called before creating any entities or components."
  (make-storage))

;;; ═══════════════════════════════════════════════════════════════════
;;; Spatial Components
;;; ═══════════════════════════════════════════════════════════════════

(defcomponent position3d
  "Position in 3D cognitive space.
   X = time axis, Y = abstraction level, Z = branch divergence."
  (x 0.0 :type single-float)
  (y 0.0 :type single-float)
  (z 0.0 :type single-float))

(defcomponent velocity3d
  "Movement velocity for animated entities."
  (dx 0.0 :type single-float)
  (dy 0.0 :type single-float)
  (dz 0.0 :type single-float))

(defcomponent scale3d
  "Size scaling for entities."
  (sx 1.0 :type single-float)
  (sy 1.0 :type single-float)
  (sz 1.0 :type single-float))

(defcomponent rotation3d
  "Euler rotation angles in radians."
  (rx 0.0 :type single-float)
  (ry 0.0 :type single-float)
  (rz 0.0 :type single-float))

;;; ═══════════════════════════════════════════════════════════════════
;;; Visual Components
;;; ═══════════════════════════════════════════════════════════════════

(defcomponent visual-style
  "Visual appearance properties for rendering.
    Colors stored as separate RGBA floats for ECS storage efficiency."
  (node-type :snapshot :type keyword)
  (color-r 0.3 :type single-float)
  (color-g 0.6 :type single-float)
  (color-b 1.0 :type single-float)
  (color-a 0.8 :type single-float)
  (glow-intensity 1.0 :type single-float)
  (pulse-rate 0.0 :type single-float)
  ;; Enhanced visual effects
  (scanline-speed 2.0 :type single-float)
  (noise-intensity 0.01 :type single-float)
  (chromatic-aberration 0.002 :type single-float)
  (fresnel-power 2.0 :type single-float))

(defcomponent node-label
  "Text label displayed near entity."
  (text "" :type string)
  (visible-p t :type boolean)
  (offset-y 1.5 :type single-float))

;;; ═══════════════════════════════════════════════════════════════════
;;; Data Binding Components
;;; ═══════════════════════════════════════════════════════════════════

(defcomponent snapshot-binding
  "Links entity to snapshot data in the DAG."
  (snapshot-id "" :type string)
  (snapshot-type :snapshot :type keyword))

(defcomponent agent-binding
  "Links entity to an agent instance."
  (agent-id "" :type string)
  (agent-name "" :type string))

(defcomponent connection
  "Directed connection between two entities (parent-child, branch, merge)."
  (from-entity -1 :type fixnum)
  (to-entity -1 :type fixnum)
  (kind :parent-child :type keyword))

;;; ═══════════════════════════════════════════════════════════════════
;;; Interaction Components
;;; ═══════════════════════════════════════════════════════════════════

(defcomponent interactive
  "Marks entity as interactable (hover, select)."
  (hover-p nil :type boolean)
  (selected-p nil :type boolean))

(defcomponent detail-level
  "Level-of-detail control based on camera distance."
  (current :high :type keyword)
  (low-distance 100.0 :type single-float)
  (cull-distance 200.0 :type single-float))

;;; ═══════════════════════════════════════════════════════════════════
;;; Force-Directed Layout Components
;;; ═══════════════════════════════════════════════════════════════════

(defcomponent force-directed-body
  "Physical properties for force-directed layout simulation."
  (mass 1.0 :type single-float)
  (repulsion-strength 100.0 :type single-float)
  (damping 0.9 :type single-float)
  (max-velocity 50.0 :type single-float))

(defcomponent spring-connection
  "Spring properties for edges in force-directed layout."
  (from-entity -1 :type fixnum)
  (to-entity -1 :type fixnum)
  (rest-length 5.0 :type single-float)
  (spring-constant 0.5 :type single-float)
  (damping 0.8 :type single-float))

;;; ═══════════════════════════════════════════════════════════════════
;;; Color Mapping
;;; ═══════════════════════════════════════════════════════════════════

(defun snapshot-type-to-color (snapshot-type)
  "Return (r g b a) color values for a snapshot type.
   Matches the holographic sci-fi aesthetic from the spec."
  (case snapshot-type
    (:genesis    (values 0.2 1.0 0.2 0.9))   ; bright green
    (:decision   (values 1.0 0.8 0.2 0.9))   ; gold
    (:action     (values 0.3 0.6 1.0 0.8))   ; blue
    (:fork       (values 1.0 0.4 0.1 0.9))   ; orange
    (:merge      (values 0.8 0.3 1.0 0.9))   ; purple
    (:human      (values 0.2 1.0 0.8 0.9))   ; cyan
    (:error      (values 1.0 0.2 0.2 0.9))   ; red
    (otherwise   (values 0.3 0.6 1.0 0.8)))) ; default blue

;;; ═══════════════════════════════════════════════════════════════════
;;; Entity Creation Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun make-snapshot-entity (snapshot-id snapshot-type
                              &key (x 0.0) (y 0.0) (z 0.0)
                                   (enable-force-directed t))
  "Create a complete snapshot entity with all standard components.
    Returns the entity ID."
  (let ((entity (make-entity)))
    (make-position3d entity :x x :y y :z z)
    (make-velocity3d entity)
    (make-scale3d entity)
    (make-rotation3d entity)
    (make-snapshot-binding entity
                           :snapshot-id snapshot-id
                           :snapshot-type snapshot-type)
    (multiple-value-bind (r g b a)
        (snapshot-type-to-color snapshot-type)
      (make-visual-style entity
                         :node-type snapshot-type
                         :color-r r :color-g g :color-b b :color-a a
                         :glow-intensity 1.0
                         :pulse-rate 0.0
                         :scanline-speed 2.0
                         :noise-intensity 0.01
                         :chromatic-aberration 0.002
                         :fresnel-power 2.0))
    (make-node-label entity
                     :text (format nil "~a" snapshot-id)
                     :visible-p t)
    (make-interactive entity)
    (make-detail-level entity)
    ;; Add force-directed layout components if enabled
    (when enable-force-directed
      (make-force-directed-body entity))
    entity))

(defun make-connection-entity (from-entity to-entity
                               &key (kind :parent-child)
                                    (spring-constant 0.5)
                                    (rest-length *default-spring-length*))
  "Create a connection entity linking two snapshot entities.
    Returns the entity ID."
  (let ((entity (make-entity)))
    (make-connection entity
                     :from-entity from-entity
                     :to-entity to-entity
                     :kind kind)
    ;; Add spring connection for force-directed layout
    (make-spring-connection entity
                           :from-entity from-entity
                           :to-entity to-entity
                           :rest-length rest-length
                           :spring-constant spring-constant)
    ;; Connection entities get position midpoint (computed by layout system)
    (make-position3d entity)
    (make-visual-style entity
                       :node-type :connection
                       :color-r 0.4 :color-g 0.4 :color-b 0.8 :color-a 0.5
                       :glow-intensity 0.5)
    entity))
