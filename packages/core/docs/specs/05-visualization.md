# Autopoiesis: 3D Visualization System

## Specification Document 05: Holodeck Visualization

**Version:** 0.1.0-draft
**Status:** Specification
**Last Updated:** 2026-02-02

---

## Overview

The Visualization System provides a 3D "Jarvis-style" interface for navigating agent cognition. Built on an Entity-Component-System (ECS) architecture, it renders the snapshot DAG as an explorable 3D space where time flows along one axis, branches diverge along another, and abstraction levels occupy the third dimension.

---

## Design Goals

1. **Intuitive Spatial Metaphor**: Navigate agent cognition like navigating physical space
2. **Semantic Zoom**: Detail emerges as you approach; overview when distant
3. **Real-time Updates**: Live agents pulse and move in the visualization
4. **Sci-Fi Aesthetic**: Holographic, glowing, cinematic feel ("Jarvis")
5. **Interactive**: Full manipulation via mouse, keyboard, touch, and voice
6. **Self-Documenting**: The visualization can visualize itself

---

## Architectural Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         VISUALIZATION SYSTEM                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        PRESENTATION LAYER                            │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  │   │
│  │  │   Scene     │  │  Camera     │  │    HUD      │  │   Audio    │  │   │
│  │  │  Renderer   │  │  Controller │  │  Overlays   │  │  Feedback  │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                           ECS LAYER                                  │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │   │
│  │  │  Entities   │  │ Components  │  │         Systems             │  │   │
│  │  │  (nodes,    │  │ (visual,    │  │ (render, layout, interact,  │  │   │
│  │  │   edges)    │  │  spatial)   │  │  animate, physics)          │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         DATA LAYER                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐  │   │
│  │  │  Snapshot   │  │   Agent     │  │       Event                 │  │   │
│  │  │   DAG       │  │   States    │  │       Stream                │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## The Cognitive Space

### Axis Mapping

```
         ▲ Y-Axis: Abstraction Level
         │
         │   High-level (strategy, goals)
         │        │
         │        ▼
         │   Mid-level (plans, decisions)
         │        │
         │        ▼
         │   Low-level (actions, tool calls)
         │
         └─────────────────────────────────────────────▶ X-Axis: Time


                          ╱
                         ╱
                        ╱ Z-Axis: Branches / Parallel Realities
                       ╱
                      ▼
```

### Visual Space Layout

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; space.lisp - Cognitive space layout
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; Space Configuration
;;; ─────────────────────────────────────────────────────────────────

(defparameter *space-config*
  '(:time-scale 10.0           ; Units per second of agent time
    :branch-spacing 20.0       ; Distance between parallel branches
    :abstraction-scale 5.0     ; Units per abstraction level
    :node-base-size 1.0        ; Base size of snapshot nodes
    :connection-width 0.1      ; Width of connection beams
    :grid-size 100.0           ; Size of reference grid
    :fog-distance 200.0        ; Where fog begins
    :far-plane 1000.0))        ; Maximum render distance

;;; ─────────────────────────────────────────────────────────────────
;;; Position Calculation
;;; ─────────────────────────────────────────────────────────────────

(defun snapshot-to-position (snapshot)
  "Calculate 3D position for SNAPSHOT."
  (let ((time-x (* (snapshot-relative-time snapshot)
                   (getf *space-config* :time-scale)))
        (abstract-y (* (snapshot-abstraction-level snapshot)
                       (getf *space-config* :abstraction-scale)))
        (branch-z (* (branch-index (snapshot-branch snapshot))
                     (getf *space-config* :branch-spacing))))
    (make-vec3 time-x abstract-y branch-z)))

(defun snapshot-relative-time (snapshot)
  "Get SNAPSHOT's time relative to genesis."
  (let ((genesis-time (get-genesis-timestamp (snapshot-agent-id snapshot))))
    (- (snapshot-timestamp snapshot) genesis-time)))

(defun snapshot-abstraction-level (snapshot)
  "Determine abstraction level based on snapshot type and content."
  (case (snapshot-type snapshot)
    (:genesis 0.0)
    (:decision 2.0)
    (:action 0.5)
    (:thought 1.5)
    (:reflection 3.0)
    (:fork 2.5)
    (t 1.0)))

(defun branch-index (branch-name)
  "Get numeric index for BRANCH-NAME for Z-positioning."
  (let ((branches (list-branches :status :active)))
    (or (position branch-name branches :key #'branch-name :test #'equal)
        0)))
```

---

## Entity-Component-System Architecture

### Components

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; components.lisp - ECS component definitions
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz.ecs)

;;; ─────────────────────────────────────────────────────────────────
;;; Component Definitions using cl-fast-ecs style
;;; ─────────────────────────────────────────────────────────────────

;; Spatial Components

(ecs:defcomponent position
  "Position in 3D cognitive space"
  (x 0.0 :type single-float)
  (y 0.0 :type single-float)
  (z 0.0 :type single-float))

(ecs:defcomponent velocity
  "Movement velocity for animated entities"
  (dx 0.0 :type single-float)
  (dy 0.0 :type single-float)
  (dz 0.0 :type single-float))

(ecs:defcomponent scale
  "Size scaling"
  (x 1.0 :type single-float)
  (y 1.0 :type single-float)
  (z 1.0 :type single-float))

(ecs:defcomponent rotation
  "Rotation as quaternion"
  (w 1.0 :type single-float)
  (x 0.0 :type single-float)
  (y 0.0 :type single-float)
  (z 0.0 :type single-float))

;; Visual Components

(ecs:defcomponent visual-style
  "Visual appearance properties"
  (node-type :snapshot :type keyword)  ; :snapshot :agent :branch :decision
  (color-r 0.3 :type single-float)
  (color-g 0.6 :type single-float)
  (color-b 1.0 :type single-float)
  (color-a 1.0 :type single-float)
  (glow-intensity 0.5 :type single-float)
  (glow-color-r 0.5 :type single-float)
  (glow-color-g 0.8 :type single-float)
  (glow-color-b 1.0 :type single-float))

(ecs:defcomponent mesh-ref
  "Reference to renderable mesh"
  (mesh-id nil :type (or null string))
  (material-id nil :type (or null string)))

(ecs:defcomponent trail
  "Motion trail for moving entities"
  (points nil :type list)
  (max-points 50 :type fixnum)
  (fade-rate 0.02 :type single-float))

;; Data Binding Components

(ecs:defcomponent snapshot-binding
  "Binds entity to a snapshot"
  (snapshot-id nil :type (or null string))
  (agent-id nil :type (or null string)))

(ecs:defcomponent agent-binding
  "Binds entity to a live agent"
  (agent-id nil :type (or null string))
  (is-current nil :type boolean))

(ecs:defcomponent connection
  "Connection between two entities"
  (from-entity 0 :type fixnum)
  (to-entity 0 :type fixnum)
  (connection-type :temporal :type keyword)  ; :temporal :fork :merge
  (energy-flow 1.0 :type single-float))

;; Interaction Components

(ecs:defcomponent interactive
  "Entity can be interacted with"
  (selectable t :type boolean)
  (hoverable t :type boolean)
  (clickable t :type boolean)
  (draggable nil :type boolean))

(ecs:defcomponent selection-state
  "Current selection/hover state"
  (selected nil :type boolean)
  (hovered nil :type boolean)
  (focused nil :type boolean))

(ecs:defcomponent tooltip
  "Tooltip information"
  (text "" :type string)
  (detail-level 0 :type fixnum))

;; Animation Components

(ecs:defcomponent animation
  "Active animation state"
  (animation-type :idle :type keyword)
  (progress 0.0 :type single-float)
  (speed 1.0 :type single-float)
  (looping t :type boolean))

(ecs:defcomponent pulse
  "Pulsing effect for live agents"
  (rate 1.0 :type single-float)
  (amplitude 0.3 :type single-float)
  (phase 0.0 :type single-float))

(ecs:defcomponent transition
  "Smooth transition between states"
  (target-x 0.0 :type single-float)
  (target-y 0.0 :type single-float)
  (target-z 0.0 :type single-float)
  (duration 0.5 :type single-float)
  (elapsed 0.0 :type single-float)
  (easing :ease-out :type keyword))

;; Level of Detail

(ecs:defcomponent lod
  "Level of detail control"
  (current-lod 1 :type fixnum)
  (min-lod 0 :type fixnum)
  (max-lod 3 :type fixnum)
  (auto-lod t :type boolean))

;; Annotation Components

(ecs:defcomponent label
  "Text label"
  (text "" :type string)
  (font-size 14.0 :type single-float)
  (offset-x 0.0 :type single-float)
  (offset-y 1.5 :type single-float)
  (visible t :type boolean))

(ecs:defcomponent tag-markers
  "Visual markers for tags"
  (tags nil :type list)
  (colors nil :type list))
```

### Systems

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; systems.lisp - ECS systems
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz.ecs)

;;; ─────────────────────────────────────────────────────────────────
;;; Layout System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem layout-system
  "Positions entities based on their snapshot data"
  (:components-ro (snapshot-binding)
   :components-rw (position)
   :when :on-change)
  (let* ((snap-id (snapshot-binding-snapshot-id entity))
         (snapshot (load-snapshot snap-id))
         (target-pos (snapshot-to-position snapshot)))
    (setf (position-x entity) (vec3-x target-pos)
          (position-y entity) (vec3-y target-pos)
          (position-z entity) (vec3-z target-pos))))

;;; ─────────────────────────────────────────────────────────────────
;;; Movement System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem movement-system
  "Updates positions based on velocity"
  (:components-ro (velocity)
   :components-rw (position)
   :when :every-frame)
  (let ((dt *delta-time*))
    (incf (position-x entity) (* (velocity-dx entity) dt))
    (incf (position-y entity) (* (velocity-dy entity) dt))
    (incf (position-z entity) (* (velocity-dz entity) dt))))

;;; ─────────────────────────────────────────────────────────────────
;;; Transition System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem transition-system
  "Smoothly transitions entities to target positions"
  (:components-ro (transition)
   :components-rw (position)
   :when :every-frame)
  (let* ((t-comp (entity-transition entity))
         (elapsed (incf (transition-elapsed t-comp) *delta-time*))
         (progress (min 1.0 (/ elapsed (transition-duration t-comp))))
         (eased (apply-easing (transition-easing t-comp) progress)))
    (setf (position-x entity) (lerp (position-x entity)
                                    (transition-target-x t-comp)
                                    eased)
          (position-y entity) (lerp (position-y entity)
                                    (transition-target-y t-comp)
                                    eased)
          (position-z entity) (lerp (position-z entity)
                                    (transition-target-z t-comp)
                                    eased))
    ;; Remove transition when complete
    (when (>= progress 1.0)
      (ecs:remove-component entity 'transition))))

;;; ─────────────────────────────────────────────────────────────────
;;; Pulse System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem pulse-system
  "Animates pulsing effect for live agents"
  (:components-ro (pulse agent-binding)
   :components-rw (visual-style scale)
   :when :every-frame)
  (let* ((p (entity-pulse entity))
         (phase (incf (pulse-phase p) (* *delta-time* (pulse-rate p))))
         (pulse-value (+ 1.0 (* (pulse-amplitude p) (sin phase)))))
    ;; Pulse glow intensity
    (setf (visual-style-glow-intensity entity)
          (* 0.5 (+ 1.0 pulse-value)))
    ;; Slight scale pulse
    (setf (scale-x entity) pulse-value
          (scale-y entity) pulse-value
          (scale-z entity) pulse-value)))

;;; ─────────────────────────────────────────────────────────────────
;;; Trail System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem trail-system
  "Updates motion trails"
  (:components-ro (position)
   :components-rw (trail)
   :when :every-frame)
  (let ((tr (entity-trail entity))
        (current-pos (make-vec3 (position-x entity)
                                (position-y entity)
                                (position-z entity))))
    ;; Add current position to trail
    (push current-pos (trail-points tr))
    ;; Limit trail length
    (when (> (length (trail-points tr)) (trail-max-points tr))
      (setf (trail-points tr)
            (subseq (trail-points tr) 0 (trail-max-points tr))))))

;;; ─────────────────────────────────────────────────────────────────
;;; LOD System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem lod-system
  "Adjusts level of detail based on camera distance"
  (:components-ro (position)
   :components-rw (lod mesh-ref label)
   :when :every-frame)
  (when (lod-auto-lod entity)
    (let* ((distance (distance-to-camera (entity-position entity)))
           (new-lod (cond ((< distance 10) 3)   ; Full detail
                          ((< distance 30) 2)   ; Medium
                          ((< distance 100) 1)  ; Low
                          (t 0))))              ; Minimal
      (setf new-lod (clamp new-lod (lod-min-lod entity) (lod-max-lod entity)))
      (unless (= new-lod (lod-current-lod entity))
        (setf (lod-current-lod entity) new-lod)
        ;; Update mesh based on LOD
        (setf (mesh-ref-mesh-id entity)
              (lod-mesh-id (lod-current-lod entity)))
        ;; Show/hide label based on LOD
        (setf (label-visible entity) (>= new-lod 2))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Interaction System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem interaction-system
  "Handles mouse/touch interaction with entities"
  (:components-ro (interactive position)
   :components-rw (selection-state visual-style)
   :when :on-input)
  (when (interactive-hoverable entity)
    (let ((ray (camera-pick-ray *mouse-position*)))
      (if (ray-intersects-entity ray entity)
          (progn
            (setf (selection-state-hovered entity) t)
            ;; Highlight on hover
            (setf (visual-style-glow-intensity entity) 1.0))
          (progn
            (setf (selection-state-hovered entity) nil)
            ;; Return to normal glow
            (setf (visual-style-glow-intensity entity) 0.5)))))

  (when (and (interactive-clickable entity)
             (selection-state-hovered entity)
             *mouse-clicked*)
    (setf (selection-state-selected entity) t)
    (emit-event :entity-selected entity)))

;;; ─────────────────────────────────────────────────────────────────
;;; Render System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem render-system
  "Renders entities to screen"
  (:components-ro (position scale rotation visual-style mesh-ref lod)
   :when :render)
  (let ((transform (make-transform-matrix
                    (entity-position entity)
                    (entity-rotation entity)
                    (entity-scale entity)))
        (style (entity-visual-style entity)))
    ;; Draw main mesh
    (draw-mesh (mesh-ref-mesh-id entity)
               :transform transform
               :material (mesh-ref-material-id entity)
               :color (make-color (visual-style-color-r style)
                                  (visual-style-color-g style)
                                  (visual-style-color-b style)
                                  (visual-style-color-a style)))
    ;; Draw glow effect
    (when (> (visual-style-glow-intensity style) 0)
      (draw-glow (entity-position entity)
                 :intensity (visual-style-glow-intensity style)
                 :color (make-color (visual-style-glow-color-r style)
                                    (visual-style-glow-color-g style)
                                    (visual-style-glow-color-b style))
                 :size (* 2.0 (scale-x entity))))))

;;; ─────────────────────────────────────────────────────────────────
;;; Connection Render System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem connection-render-system
  "Renders connections between entities"
  (:components-ro (connection)
   :when :render)
  (let* ((conn (entity-connection entity))
         (from-pos (entity-position (connection-from-entity conn)))
         (to-pos (entity-position (connection-to-entity conn)))
         (color (connection-type-color (connection-connection-type conn))))
    ;; Draw energy beam
    (draw-energy-beam from-pos to-pos
                      :color color
                      :width (getf *space-config* :connection-width)
                      :energy-flow (connection-energy-flow conn)
                      :time *animation-time*)))

;;; ─────────────────────────────────────────────────────────────────
;;; Label Render System
;;; ─────────────────────────────────────────────────────────────────

(ecs:defsystem label-render-system
  "Renders text labels"
  (:components-ro (position label)
   :when :render-ui)
  (when (label-visible entity)
    (let ((screen-pos (world-to-screen (entity-position entity))))
      (draw-text (label-text entity)
                 :position (vec2-add screen-pos
                                     (make-vec2 (label-offset-x entity)
                                                (label-offset-y entity)))
                 :size (label-font-size entity)
                 :color *label-color*
                 :font *hologram-font*))))
```

---

## Visual Theme

### Holographic Aesthetic

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; theme.lisp - Visual theme configuration
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; Color Palette
;;; ─────────────────────────────────────────────────────────────────

(defparameter *theme*
  '(;; Background
    :background-color (0.02 0.02 0.05 1.0)
    :grid-color (0.1 0.2 0.3 0.3)
    :fog-color (0.02 0.05 0.1 1.0)

    ;; Node types
    :snapshot-color (0.2 0.6 1.0 0.9)       ; Blue
    :decision-color (1.0 0.8 0.2 0.9)        ; Gold
    :fork-color (0.8 0.2 1.0 0.9)            ; Purple
    :merge-color (0.2 1.0 0.5 0.9)           ; Green
    :current-color (0.2 1.0 0.8 0.9)         ; Cyan
    :error-color (1.0 0.2 0.2 0.9)           ; Red
    :human-color (1.0 0.6 0.2 0.9)           ; Orange

    ;; Connections
    :temporal-connection (0.3 0.5 0.8 0.6)
    :fork-connection (0.8 0.3 1.0 0.8)
    :merge-connection (0.2 1.0 0.5 0.8)

    ;; Glow
    :glow-falloff 2.0
    :glow-bloom 1.5
    :glow-saturation 1.2

    ;; Effects
    :scanline-opacity 0.03
    :noise-intensity 0.01
    :chromatic-aberration 0.002

    ;; Text
    :text-color (0.7 0.9 1.0 1.0)
    :text-shadow-color (0.0 0.3 0.5 0.5)))

;;; ─────────────────────────────────────────────────────────────────
;;; Node Type Styling
;;; ─────────────────────────────────────────────────────────────────

(defun node-type-style (type)
  "Get visual style for node TYPE."
  (ecase type
    (:snapshot
     '(:color :snapshot-color
       :glow-intensity 0.3
       :mesh :sphere
       :size 1.0))
    (:decision
     '(:color :decision-color
       :glow-intensity 0.6
       :mesh :octahedron
       :size 1.5))
    (:fork
     '(:color :fork-color
       :glow-intensity 0.8
       :mesh :branching-node
       :size 1.3))
    (:merge
     '(:color :merge-color
       :glow-intensity 0.7
       :mesh :merge-node
       :size 1.3))
    (:current
     '(:color :current-color
       :glow-intensity 1.0
       :mesh :sphere
       :size 1.8
       :pulse t))
    (:genesis
     '(:color :snapshot-color
       :glow-intensity 0.5
       :mesh :star
       :size 2.0))
    (:human
     '(:color :human-color
       :glow-intensity 0.7
       :mesh :hexagon
       :size 1.4))))

;;; ─────────────────────────────────────────────────────────────────
;;; Shader Definitions
;;; ─────────────────────────────────────────────────────────────────

(defparameter *shaders*
  '((:hologram-node
     :vertex "
       #version 330 core
       layout (location = 0) in vec3 aPos;
       layout (location = 1) in vec3 aNormal;

       uniform mat4 model;
       uniform mat4 view;
       uniform mat4 projection;
       uniform float time;

       out vec3 FragPos;
       out vec3 Normal;
       out float Scanline;

       void main() {
         FragPos = vec3(model * vec4(aPos, 1.0));
         Normal = mat3(transpose(inverse(model))) * aNormal;
         gl_Position = projection * view * vec4(FragPos, 1.0);
         Scanline = sin(FragPos.y * 50.0 + time * 2.0) * 0.5 + 0.5;
       }
     "
     :fragment "
       #version 330 core
       in vec3 FragPos;
       in vec3 Normal;
       in float Scanline;

       uniform vec4 color;
       uniform float glowIntensity;
       uniform vec3 viewPos;

       out vec4 FragColor;

       void main() {
         // Fresnel effect for hologram edge glow
         vec3 viewDir = normalize(viewPos - FragPos);
         float fresnel = pow(1.0 - max(dot(Normal, viewDir), 0.0), 2.0);

         // Combine base color with fresnel glow
         vec3 baseColor = color.rgb;
         vec3 glowColor = baseColor * 1.5;
         vec3 finalColor = mix(baseColor, glowColor, fresnel * glowIntensity);

         // Add scanlines
         finalColor *= mix(0.95, 1.0, Scanline * 0.03);

         // Add subtle noise
         float noise = fract(sin(dot(FragPos.xy, vec2(12.9898, 78.233))) * 43758.5453);
         finalColor += (noise - 0.5) * 0.02;

         FragColor = vec4(finalColor, color.a);
       }
     ")

    (:energy-beam
     :vertex "
       #version 330 core
       layout (location = 0) in vec3 aPos;
       layout (location = 1) in float aProgress;

       uniform mat4 view;
       uniform mat4 projection;
       uniform float time;
       uniform float energyFlow;

       out float Progress;
       out float Energy;

       void main() {
         gl_Position = projection * view * vec4(aPos, 1.0);
         Progress = aProgress;
         Energy = sin((aProgress - time * energyFlow) * 6.28) * 0.5 + 0.5;
       }
     "
     :fragment "
       #version 330 core
       in float Progress;
       in float Energy;

       uniform vec4 color;

       out vec4 FragColor;

       void main() {
         float alpha = color.a * (0.3 + Energy * 0.7);
         vec3 finalColor = color.rgb * (1.0 + Energy * 0.5);
         FragColor = vec4(finalColor, alpha);
       }
     ")

    (:glow
     :vertex "
       #version 330 core
       layout (location = 0) in vec3 aPos;
       layout (location = 1) in vec2 aTexCoord;

       uniform mat4 model;
       uniform mat4 view;
       uniform mat4 projection;

       out vec2 TexCoord;

       void main() {
         gl_Position = projection * view * model * vec4(aPos, 1.0);
         TexCoord = aTexCoord;
       }
     "
     :fragment "
       #version 330 core
       in vec2 TexCoord;

       uniform vec4 color;
       uniform float intensity;
       uniform float falloff;

       out vec4 FragColor;

       void main() {
         float dist = length(TexCoord - vec2(0.5));
         float glow = exp(-dist * dist * falloff) * intensity;
         FragColor = vec4(color.rgb, glow * color.a);
       }
     ")))
```

---

## Camera System

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; camera.lisp - Camera control
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; Camera Class
;;; ─────────────────────────────────────────────────────────────────

(defclass camera ()
  ((position :initarg :position
             :accessor camera-position
             :initform (make-vec3 0.0 5.0 30.0))
   (target :initarg :target
           :accessor camera-target
           :initform (make-vec3 0.0 0.0 0.0))
   (up :initarg :up
       :accessor camera-up
       :initform (make-vec3 0.0 1.0 0.0))
   (fov :initarg :fov
        :accessor camera-fov
        :initform 60.0)
   (near :initarg :near
         :accessor camera-near
         :initform 0.1)
   (far :initarg :far
        :accessor camera-far
        :initform 1000.0)

   ;; Control state
   (mode :initarg :mode
         :accessor camera-mode
         :initform :orbit
         :documentation ":orbit :fly :follow :cinematic")
   (follow-target :initarg :follow-target
                  :accessor camera-follow-target
                  :initform nil)
   (transition-active :initarg :transition-active
                      :accessor camera-transitioning-p
                      :initform nil))
  (:documentation "Scene camera"))

(defvar *camera* nil
  "Main scene camera.")

;;; ─────────────────────────────────────────────────────────────────
;;; Camera Modes
;;; ─────────────────────────────────────────────────────────────────

(defun orbit-camera (delta-x delta-y)
  "Orbit camera around target."
  (let* ((offset (vec3-sub (camera-position *camera*) (camera-target *camera*)))
         (distance (vec3-length offset))
         ;; Convert to spherical
         (theta (+ (atan (vec3-x offset) (vec3-z offset))
                   (* delta-x 0.01)))
         (phi (+ (asin (/ (vec3-y offset) distance))
                 (* delta-y 0.01))))
    ;; Clamp phi to avoid gimbal lock
    (setf phi (clamp phi -1.5 1.5))
    ;; Convert back to cartesian
    (setf (camera-position *camera*)
          (vec3-add (camera-target *camera*)
                    (make-vec3 (* distance (sin theta) (cos phi))
                               (* distance (sin phi))
                               (* distance (cos theta) (cos phi)))))))

(defun zoom-camera (delta)
  "Zoom camera in/out."
  (let* ((direction (vec3-normalize
                     (vec3-sub (camera-target *camera*)
                               (camera-position *camera*))))
         (distance (vec3-length
                    (vec3-sub (camera-target *camera*)
                              (camera-position *camera*)))))
    ;; Limit zoom
    (when (or (and (> delta 0) (> distance 5))
              (and (< delta 0) (< distance 200)))
      (setf (camera-position *camera*)
            (vec3-add (camera-position *camera*)
                      (vec3-scale direction (* delta 0.5)))))))

(defun pan-camera (delta-x delta-y)
  "Pan camera left/right/up/down."
  (let* ((forward (vec3-normalize
                   (vec3-sub (camera-target *camera*)
                             (camera-position *camera*))))
         (right (vec3-normalize (vec3-cross forward (camera-up *camera*))))
         (up (camera-up *camera*))
         (pan-offset (vec3-add (vec3-scale right (* delta-x -0.1))
                               (vec3-scale up (* delta-y 0.1)))))
    (setf (camera-position *camera*)
          (vec3-add (camera-position *camera*) pan-offset)
          (camera-target *camera*)
          (vec3-add (camera-target *camera*) pan-offset))))

(defun fly-camera (direction speed)
  "Move camera in fly mode."
  (let* ((forward (vec3-normalize
                   (vec3-sub (camera-target *camera*)
                             (camera-position *camera*))))
         (right (vec3-normalize (vec3-cross forward (camera-up *camera*))))
         (move-vec (ecase direction
                     (:forward forward)
                     (:backward (vec3-negate forward))
                     (:left (vec3-negate right))
                     (:right right)
                     (:up (camera-up *camera*))
                     (:down (vec3-negate (camera-up *camera*))))))
    (let ((offset (vec3-scale move-vec (* speed *delta-time*))))
      (setf (camera-position *camera*)
            (vec3-add (camera-position *camera*) offset)
            (camera-target *camera*)
            (vec3-add (camera-target *camera*) offset)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Smooth Camera Transitions
;;; ─────────────────────────────────────────────────────────────────

(defun animate-camera-to (target-position target-look-at &key (duration 1.0))
  "Smoothly animate camera to new position."
  (let ((start-pos (camera-position *camera*))
        (start-target (camera-target *camera*)))
    (setf (camera-transitioning-p *camera*)
          (make-transition
           :start-pos start-pos
           :end-pos target-position
           :start-target start-target
           :end-target target-look-at
           :duration duration
           :elapsed 0.0))))

(defun update-camera-transition ()
  "Update camera transition animation."
  (when-let (trans (camera-transitioning-p *camera*))
    (let* ((elapsed (incf (transition-elapsed trans) *delta-time*))
           (progress (min 1.0 (/ elapsed (transition-duration trans))))
           (eased (ease-out-cubic progress)))
      ;; Interpolate position
      (setf (camera-position *camera*)
            (vec3-lerp (transition-start-pos trans)
                       (transition-end-pos trans)
                       eased)
            (camera-target *camera*)
            (vec3-lerp (transition-start-target trans)
                       (transition-end-target trans)
                       eased))
      ;; Complete transition
      (when (>= progress 1.0)
        (setf (camera-transitioning-p *camera*) nil)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Focus Functions
;;; ─────────────────────────────────────────────────────────────────

(defun focus-on-snapshot (snapshot)
  "Focus camera on SNAPSHOT."
  (let* ((pos (snapshot-to-position snapshot))
         (camera-pos (vec3-add pos (make-vec3 5.0 3.0 10.0))))
    (animate-camera-to camera-pos pos)))

(defun focus-on-agent (agent)
  "Follow a live agent."
  (setf (camera-mode *camera*) :follow
        (camera-follow-target *camera*) agent))

(defun overview ()
  "Move camera to show overview of entire DAG."
  (let* ((bounds (calculate-scene-bounds))
         (center (bounds-center bounds))
         (size (bounds-size bounds))
         (distance (max (vec3-x size) (vec3-y size) (vec3-z size)))
         (camera-pos (vec3-add center (make-vec3 0.0 distance (* distance 0.7)))))
    (animate-camera-to camera-pos center :duration 1.5)))
```

---

## Input Handling

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; input.lisp - Input handling
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; Input State
;;; ─────────────────────────────────────────────────────────────────

(defvar *mouse-position* (make-vec2 0.0 0.0))
(defvar *mouse-delta* (make-vec2 0.0 0.0))
(defvar *mouse-buttons* (make-hash-table))
(defvar *keys-pressed* (make-hash-table))
(defvar *scroll-delta* 0.0)

;;; ─────────────────────────────────────────────────────────────────
;;; Key Bindings
;;; ─────────────────────────────────────────────────────────────────

(defparameter *key-bindings*
  '(;; Camera movement
    (:w . (:fly-camera :forward 20.0))
    (:s . (:fly-camera :backward 20.0))
    (:a . (:fly-camera :left 20.0))
    (:d . (:fly-camera :right 20.0))
    (:q . (:fly-camera :down 20.0))
    (:e . (:fly-camera :up 20.0))

    ;; Navigation
    (:left-bracket . :step-backward)
    (:right-bracket . :step-forward)
    (:home . :goto-genesis)
    (:end . :goto-head)

    ;; Branching
    (:f . :fork-here)
    (:m . :merge-prompt)
    (:b . :show-branches)

    ;; View modes
    (:1 . (:set-view :timeline))
    (:2 . (:set-view :tree))
    (:3 . (:set-view :constellation))
    (:4 . (:set-view :diff))

    ;; Focus
    (:tab . :cycle-focus-next)
    (:shift-tab . :cycle-focus-prev)
    (:space . :toggle-follow)
    (:o . :overview)

    ;; Detail
    (:plus . :increase-detail)
    (:minus . :decrease-detail)

    ;; Actions
    (:return . :enter-human-loop)
    (:escape . :exit-visualization)
    (:h . :toggle-hud)
    (:slash . :command-palette)))

(defun process-key-input ()
  "Process keyboard input."
  (maphash (lambda (key pressed)
             (when pressed
               (let ((binding (assoc key *key-bindings*)))
                 (when binding
                   (execute-key-action (cdr binding))))))
           *keys-pressed*))

(defun execute-key-action (action)
  "Execute a key binding action."
  (cond
    ((symbolp action)
     (funcall action))
    ((consp action)
     (apply (first action) (rest action)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Mouse Handling
;;; ─────────────────────────────────────────────────────────────────

(defun process-mouse-input ()
  "Process mouse input."
  ;; Orbit with right mouse
  (when (gethash :right *mouse-buttons*)
    (orbit-camera (vec2-x *mouse-delta*)
                  (vec2-y *mouse-delta*)))

  ;; Pan with middle mouse
  (when (gethash :middle *mouse-buttons*)
    (pan-camera (vec2-x *mouse-delta*)
                (vec2-y *mouse-delta*)))

  ;; Zoom with scroll
  (unless (zerop *scroll-delta*)
    (zoom-camera *scroll-delta*)
    (setf *scroll-delta* 0.0))

  ;; Selection with left click
  (when (and (gethash :left *mouse-buttons*)
             (not (gethash :left-prev *mouse-buttons*)))
    (handle-click)))

(defun handle-click ()
  "Handle mouse click for selection."
  (let ((hit (pick-entity *mouse-position*)))
    (when hit
      (select-entity hit))))

;;; ─────────────────────────────────────────────────────────────────
;;; Entity Picking
;;; ─────────────────────────────────────────────────────────────────

(defun pick-entity (screen-pos)
  "Pick entity at SCREEN-POS using ray casting."
  (let* ((ray (camera-pick-ray screen-pos))
         (hits nil))
    (ecs:do-entities (entity (interactive position))
      (when (interactive-clickable entity)
        (let ((dist (ray-sphere-intersection
                     ray
                     (entity-position entity)
                     (entity-radius entity))))
          (when dist
            (push (cons entity dist) hits)))))
    ;; Return closest hit
    (car (first (sort hits #'< :key #'cdr)))))

(defun camera-pick-ray (screen-pos)
  "Create picking ray from camera through SCREEN-POS."
  (let* ((ndc-x (- (* 2.0 (/ (vec2-x screen-pos) *screen-width*)) 1.0))
         (ndc-y (- 1.0 (* 2.0 (/ (vec2-y screen-pos) *screen-height*))))
         (clip-coords (make-vec4 ndc-x ndc-y -1.0 1.0))
         (eye-coords (mat4-mul-vec4 (mat4-inverse *projection-matrix*)
                                    clip-coords))
         (world-coords (mat4-mul-vec4 (mat4-inverse *view-matrix*)
                                      (make-vec4 (vec4-x eye-coords)
                                                 (vec4-y eye-coords)
                                                 -1.0 0.0)))
         (direction (vec3-normalize (make-vec3 (vec4-x world-coords)
                                               (vec4-y world-coords)
                                               (vec4-z world-coords)))))
    (make-ray :origin (camera-position *camera*)
              :direction direction)))
```

---

## HUD and Overlays

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; hud.lisp - Heads-up display
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; HUD Components
;;; ─────────────────────────────────────────────────────────────────

(defclass hud ()
  ((visible :initarg :visible
            :accessor hud-visible-p
            :initform t)
   (panels :initarg :panels
           :accessor hud-panels
           :initform nil)
   (opacity :initarg :opacity
            :accessor hud-opacity
            :initform 0.8))
  (:documentation "Heads-up display overlay"))

(defvar *hud* nil)

;;; ─────────────────────────────────────────────────────────────────
;;; HUD Panels
;;; ─────────────────────────────────────────────────────────────────

(defun render-hud ()
  "Render all HUD elements."
  (when (hud-visible-p *hud*)
    (with-hud-style ()
      ;; Top-left: Position info
      (render-position-panel)

      ;; Top-right: Agent status
      (render-agent-panel)

      ;; Bottom: Timeline scrubber
      (render-timeline-panel)

      ;; Bottom-right: Action hints
      (render-action-hints)

      ;; Center: Notifications (if any)
      (render-notifications))))

(defun render-position-panel ()
  "Render current position information."
  (let* ((snapshot (current-snapshot))
         (panel-x 20)
         (panel-y 20))
    (draw-panel panel-x panel-y 300 100
                :title "LOCATION"
                :style :hologram)
    (draw-text (format nil "Branch: ~a" (snapshot-branch snapshot))
               :position (make-vec2 (+ panel-x 10) (+ panel-y 30))
               :color (theme-color :text-color))
    (draw-text (format nil "Snapshot: ~a" (truncate-string (snapshot-id snapshot) 12))
               :position (make-vec2 (+ panel-x 10) (+ panel-y 50))
               :color (theme-color :text-color))
    (draw-text (format nil "Type: ~a" (snapshot-type snapshot))
               :position (make-vec2 (+ panel-x 10) (+ panel-y 70))
               :color (theme-color :text-color))))

(defun render-agent-panel ()
  "Render agent status if following one."
  (when *focused-agent*
    (let* ((panel-x (- *screen-width* 320))
           (panel-y 20))
      (draw-panel panel-x panel-y 300 120
                  :title "AGENT"
                  :style :hologram)
      (draw-text (format nil "Name: ~a" (agent-name *focused-agent*))
                 :position (make-vec2 (+ panel-x 10) (+ panel-y 30))
                 :color (theme-color :text-color))
      (draw-text (format nil "Status: ~a" (agent-status *focused-agent*))
                 :position (make-vec2 (+ panel-x 10) (+ panel-y 50))
                 :color (status-color (agent-status *focused-agent*)))
      (draw-text (format nil "Task: ~a"
                         (truncate-string
                          (format nil "~a" (agent-current-task *focused-agent*))
                          30))
                 :position (make-vec2 (+ panel-x 10) (+ panel-y 70))
                 :color (theme-color :text-color))
      ;; Confidence bar
      (draw-progress-bar (+ panel-x 10) (+ panel-y 95) 280 15
                         :value (agent-confidence *focused-agent*)
                         :label "Confidence"))))

(defun render-timeline-panel ()
  "Render timeline scrubber at bottom."
  (let* ((panel-x 50)
         (panel-y (- *screen-height* 80))
         (panel-width (- *screen-width* 100)))
    (draw-panel panel-x panel-y panel-width 60
                :title nil
                :style :minimal)
    ;; Draw timeline
    (draw-timeline panel-x (+ panel-y 20) panel-width 30
                   :snapshots (visible-snapshot-range)
                   :current (current-snapshot)
                   :branches (visible-branches))))

(defun render-action-hints ()
  "Render keyboard shortcut hints."
  (let ((x (- *screen-width* 200))
        (y (- *screen-height* 150)))
    (draw-panel x y 180 130 :style :minimal :opacity 0.5)
    (draw-text "[WASD] Move" :position (make-vec2 (+ x 10) (+ y 15)))
    (draw-text "[Scroll] Zoom" :position (make-vec2 (+ x 10) (+ y 35)))
    (draw-text "[]/[] Step" :position (make-vec2 (+ x 10) (+ y 55)))
    (draw-text "[F] Fork" :position (make-vec2 (+ x 10) (+ y 75)))
    (draw-text "[Enter] Interact" :position (make-vec2 (+ x 10) (+ y 95)))
    (draw-text "[?] Help" :position (make-vec2 (+ x 10) (+ y 115)))))

;;; ─────────────────────────────────────────────────────────────────
;;; Semantic Zoom Detail Panels
;;; ─────────────────────────────────────────────────────────────────

(defun render-snapshot-detail (snapshot screen-pos lod)
  "Render detailed view of SNAPSHOT at SCREEN-POS based on LOD."
  (ecase lod
    (0 nil)  ; No detail at minimum LOD

    (1  ; Icon + type indicator
     (draw-type-icon (snapshot-type snapshot) screen-pos))

    (2  ; Add short summary
     (draw-type-icon (snapshot-type snapshot) screen-pos)
     (draw-text (format nil "~a" (snapshot-type snapshot))
                :position (vec2-add screen-pos (make-vec2 15 -5))
                :size 12))

    (3  ; Full detail panel
     (draw-detail-panel snapshot screen-pos))))

(defun draw-detail-panel (snapshot screen-pos)
  "Draw full detail panel for SNAPSHOT."
  (let ((width 350)
        (height 250)
        (x (vec2-x screen-pos))
        (y (vec2-y screen-pos)))
    (draw-panel x y width height
                :title (format nil "Snapshot: ~a" (truncate-string (snapshot-id snapshot) 12))
                :style :hologram)

    ;; Content
    (let ((cy (+ y 30)))
      ;; Type and timestamp
      (draw-text (format nil "Type: ~a" (snapshot-type snapshot))
                 :position (make-vec2 (+ x 10) cy))
      (incf cy 20)
      (draw-text (format nil "Time: ~a" (format-timestamp (snapshot-timestamp snapshot)))
                 :position (make-vec2 (+ x 10) cy))
      (incf cy 25)

      ;; Context summary
      (draw-text "Context:" :position (make-vec2 (+ x 10) cy) :style :bold)
      (incf cy 15)
      (dolist (item (take 3 (snapshot-context snapshot)))
        (draw-text (truncate-string (format nil "  ~a" item) 45)
                   :position (make-vec2 (+ x 10) cy)
                   :size 11)
        (incf cy 15))
      (incf cy 10)

      ;; Decision if present
      (when (snapshot-decision snapshot)
        (draw-text "Decision:" :position (make-vec2 (+ x 10) cy) :style :bold)
        (incf cy 15)
        (draw-text (format nil "  Chose: ~a"
                           (truncate-string
                            (format nil "~a" (decision-chosen (snapshot-decision snapshot)))
                            40))
                   :position (make-vec2 (+ x 10) cy)
                   :size 11
                   :color (theme-color :decision-color))))))
```

---

## Main Loop

```lisp
;;;; ═══════════════════════════════════════════════════════════════
;;;; main.lisp - Visualization main loop
;;;; ═══════════════════════════════════════════════════════════════

(in-package #:autopoiesis.viz)

;;; ─────────────────────────────────────────────────────────────────
;;; Initialization
;;; ─────────────────────────────────────────────────────────────────

(defun start-holodeck (&key (width 1920) (height 1080) (title "Autopoiesis Holodeck"))
  "Start the 3D visualization."
  ;; Initialize window
  (init-window width height title)

  ;; Initialize renderer
  (init-renderer)
  (load-shaders *shaders*)
  (load-meshes *meshes*)

  ;; Initialize camera
  (setf *camera* (make-instance 'camera))

  ;; Initialize HUD
  (setf *hud* (make-instance 'hud))

  ;; Initialize ECS
  (ecs:initialize)

  ;; Sync with snapshot store
  (sync-entities-with-snapshots)

  ;; Enter main loop
  (main-loop))

(defun stop-holodeck ()
  "Stop the visualization."
  (ecs:shutdown)
  (close-window))

;;; ─────────────────────────────────────────────────────────────────
;;; Main Loop
;;; ─────────────────────────────────────────────────────────────────

(defvar *delta-time* 0.0)
(defvar *animation-time* 0.0)
(defvar *last-frame-time* 0)

(defun main-loop ()
  "Main visualization loop."
  (loop until (window-should-close-p) do
    ;; Calculate delta time
    (let ((current-time (get-time)))
      (setf *delta-time* (- current-time *last-frame-time*)
            *last-frame-time* current-time)
      (incf *animation-time* *delta-time*))

    ;; Process input
    (poll-events)
    (update-input-state)
    (process-key-input)
    (process-mouse-input)

    ;; Update camera
    (update-camera-transition)
    (when (eq (camera-mode *camera*) :follow)
      (update-camera-follow))

    ;; Run ECS systems
    (ecs:run-system 'layout-system)
    (ecs:run-system 'movement-system)
    (ecs:run-system 'transition-system)
    (ecs:run-system 'pulse-system)
    (ecs:run-system 'trail-system)
    (ecs:run-system 'lod-system)
    (ecs:run-system 'interaction-system)

    ;; Sync with live data
    (when (should-sync-p)
      (sync-with-live-agents))

    ;; Render
    (begin-frame)

    ;; Clear
    (clear-screen (theme-color :background-color))

    ;; Draw grid
    (draw-reference-grid)

    ;; Set up camera matrices
    (let ((*view-matrix* (camera-view-matrix *camera*))
          (*projection-matrix* (camera-projection-matrix *camera*)))

      ;; Render entities
      (ecs:run-system 'render-system)
      (ecs:run-system 'connection-render-system)
      (ecs:run-system 'trail-render-system))

    ;; Render UI layer
    (ecs:run-system 'label-render-system)
    (render-hud)

    ;; Apply post-processing
    (apply-post-processing)

    ;; Present
    (end-frame)
    (swap-buffers)))

;;; ─────────────────────────────────────────────────────────────────
;;; Entity Synchronization
;;; ─────────────────────────────────────────────────────────────────

(defun sync-entities-with-snapshots ()
  "Create/update entities for all snapshots."
  (let ((existing-entities (make-hash-table :test 'equal)))
    ;; Index existing entities
    (ecs:do-entities (entity (snapshot-binding))
      (setf (gethash (snapshot-binding-snapshot-id entity) existing-entities)
            entity))

    ;; Create entities for new snapshots
    (dolist (snapshot (list-snapshots))
      (unless (gethash (snapshot-id snapshot) existing-entities)
        (create-snapshot-entity snapshot)))

    ;; Create connection entities
    (dolist (snapshot (list-snapshots))
      (when (snapshot-parent-id snapshot)
        (create-connection-entity snapshot)))))

(defun create-snapshot-entity (snapshot)
  "Create ECS entity for SNAPSHOT."
  (let* ((style (node-type-style (snapshot-type snapshot)))
         (pos (snapshot-to-position snapshot))
         (entity (ecs:make-entity)))

    ;; Add components
    (ecs:add-component entity 'position
                       :x (vec3-x pos) :y (vec3-y pos) :z (vec3-z pos))
    (ecs:add-component entity 'scale
                       :x (getf style :size) :y (getf style :size) :z (getf style :size))
    (ecs:add-component entity 'rotation)

    (let ((color (theme-color (getf style :color))))
      (ecs:add-component entity 'visual-style
                         :node-type (snapshot-type snapshot)
                         :color-r (first color)
                         :color-g (second color)
                         :color-b (third color)
                         :glow-intensity (getf style :glow-intensity)))

    (ecs:add-component entity 'mesh-ref
                       :mesh-id (string (getf style :mesh))
                       :material-id "hologram")

    (ecs:add-component entity 'snapshot-binding
                       :snapshot-id (snapshot-id snapshot)
                       :agent-id (snapshot-agent-id snapshot))

    (ecs:add-component entity 'interactive
                       :selectable t :hoverable t :clickable t)
    (ecs:add-component entity 'selection-state)

    (ecs:add-component entity 'lod :auto-lod t)

    (ecs:add-component entity 'label
                       :text (format nil "~a" (snapshot-type snapshot))
                       :visible nil)

    ;; Add pulse for current/live snapshots
    (when (getf style :pulse)
      (ecs:add-component entity 'pulse :rate 2.0 :amplitude 0.2))

    entity))

(defun sync-with-live-agents ()
  "Update entities based on live agent state."
  (dolist (agent (list-agents :status :running))
    (let ((entity (find-agent-entity (agent-id agent))))
      (when entity
        ;; Update position to current snapshot
        (let* ((snapshot (agent-current-snapshot agent))
               (pos (snapshot-to-position snapshot)))
          ;; Smooth transition to new position
          (ecs:add-component entity 'transition
                             :target-x (vec3-x pos)
                             :target-y (vec3-y pos)
                             :target-z (vec3-z pos)
                             :duration 0.3))
        ;; Update agent binding
        (setf (agent-binding-is-current entity) t)))))
```

---

## Next Document

Continue to [06-integration.md](./06-integration.md) for external system integrations including Claude Code bridge and MCP servers.
