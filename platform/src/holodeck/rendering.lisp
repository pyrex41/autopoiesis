;;;; rendering.lisp - Entity rendering with LOD support
;;;;
;;;; Implements render-snapshot-entity and render-connection-entity which
;;;; produce render descriptions for snapshot and connection entities.
;;;; Render descriptions are property lists containing all data needed to
;;;; draw entities, either on the GPU or via CPU-side headless rendering.
;;;;
;;;; LOD levels map to detail-level component values:
;;;;   :culled - Entity not visible, returns NIL
;;;;   :low    - Minimal geometry, no label, reduced glow
;;;;   :high   - Full detail mesh, label visible, full material effects
;;;;
;;;; Phase 8.2 - Rendering

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Snapshot Type to Mesh Type Mapping
;;; ===================================================================

(defun snapshot-type-to-mesh-type (snapshot-type)
  "Map a snapshot type keyword to the appropriate mesh primitive type.
   :decision and :action use octahedron, :fork uses branching-node,
   all others use sphere."
  (case snapshot-type
    ((:decision :action) :octahedron)
    ((:fork :branch)     :branching-node)
    (otherwise           :sphere)))

;;; ===================================================================
;;; LOD to Mesh LOD Mapping
;;; ===================================================================

(defun detail-level-to-mesh-lod (detail-keyword)
  "Map a detail-level keyword to a numeric mesh LOD.
   :high -> 2 (medium-high detail)
   :low  -> 0 (minimal detail)
   :culled -> nil (not rendered)"
  (case detail-keyword
    (:high   2)
    (:low    0)
    (:culled nil)
    (otherwise 1)))

;;; ===================================================================
;;; Render Description Structure
;;; ===================================================================
;;;
;;; A render description is a property list with the following keys:
;;;   :entity       - The ECS entity ID
;;;   :visible-p    - Whether the entity should be drawn
;;;   :position     - (x y z) world position
;;;   :scale        - (sx sy sz) scale factors
;;;   :rotation     - (rx ry rz) Euler angles
;;;   :mesh         - mesh-primitive instance (or NIL)
;;;   :material     - hologram-material instance
;;;   :color        - (r g b a) computed color at current LOD
;;;   :glow-p       - Whether to draw the glow effect
;;;   :label-text   - Label string (or NIL if not shown)
;;;   :label-offset - Label Y offset
;;;   :lod          - Current detail level keyword

(defun render-snapshot-entity (entity)
  "Produce a render description plist for a snapshot ENTITY.
   Uses the entity's detail-level, visual-style, snapshot-binding,
   position3d, scale3d, rotation3d, and node-label components to
   determine what and how to render.

   Returns a property list suitable for passing to a rendering backend,
   or NIL if the entity is culled (not visible)."
  (let ((detail (detail-level-current entity)))
    ;; Culled entities produce no render description
    (when (eq detail :culled)
      (return-from render-snapshot-entity nil))
    (let* ((snap-type (snapshot-binding-snapshot-type entity))
           (mesh-type (snapshot-type-to-mesh-type snap-type))
           (mesh-lod (detail-level-to-mesh-lod detail))
           (mesh (when mesh-lod (find-mesh mesh-type mesh-lod)))
           ;; Fall back to any available LOD if exact not found
           (mesh (or mesh
                     (when mesh-lod
                       (or (find-mesh mesh-type 0)
                           (find-mesh mesh-type 1)
                           (find-mesh mesh-type 2)
                           (find-mesh mesh-type 3)))))
           ;; Material for holographic rendering
           (material (make-hologram-material-for-type snap-type))
           ;; Position, scale, rotation
           (px (position3d-x entity))
           (py (position3d-y entity))
           (pz (position3d-z entity))
           (sx (scale3d-sx entity))
           (sy (scale3d-sy entity))
           (sz (scale3d-sz entity))
           (rx (rotation3d-rx entity))
           (ry (rotation3d-ry entity))
           (rz (rotation3d-rz entity))
           ;; Visual style
           (color-r (visual-style-color-r entity))
           (color-g (visual-style-color-g entity))
           (color-b (visual-style-color-b entity))
           (color-a (visual-style-color-a entity))
           ;; LOD-dependent features
           (glow-p (eq detail :high))
           (label-text (when (and (eq detail :high)
                                  (node-label-visible-p entity))
                         (node-label-text entity)))
           (label-offset (when label-text
                           (node-label-offset-y entity))))
      ;; At :low detail, reduce alpha for a faded appearance
      (when (eq detail :low)
        (setf color-a (* color-a 0.5))
        ;; Also reduce glow intensity in the material
        (setf (material-glow-intensity material)
              (* (material-glow-intensity material) 0.3)))
      (list :entity entity
            :visible-p t
            :position (list px py pz)
            :scale (list sx sy sz)
            :rotation (list rx ry rz)
            :mesh mesh
            :material material
            :color (list color-r color-g color-b color-a)
            :glow-p glow-p
            :label-text label-text
            :label-offset label-offset
            :lod detail))))

;;; ===================================================================
;;; Render Description Accessors
;;; ===================================================================

(defun render-desc-entity (desc)
  "Get the entity from a render description."
  (getf desc :entity))

(defun render-desc-visible-p (desc)
  "Get visibility flag from a render description."
  (getf desc :visible-p))

(defun render-desc-position (desc)
  "Get (x y z) position from a render description."
  (getf desc :position))

(defun render-desc-scale (desc)
  "Get (sx sy sz) scale from a render description."
  (getf desc :scale))

(defun render-desc-rotation (desc)
  "Get (rx ry rz) rotation from a render description."
  (getf desc :rotation))

(defun render-desc-mesh (desc)
  "Get mesh-primitive from a render description (may be NIL)."
  (getf desc :mesh))

(defun render-desc-material (desc)
  "Get hologram-material from a render description."
  (getf desc :material))

(defun render-desc-color (desc)
  "Get (r g b a) color from a render description."
  (getf desc :color))

(defun render-desc-glow-p (desc)
  "Get glow flag from a render description."
  (getf desc :glow-p))

(defun render-desc-label-text (desc)
  "Get label text from a render description (may be NIL)."
  (getf desc :label-text))

(defun render-desc-label-offset (desc)
  "Get label Y offset from a render description (may be NIL)."
  (getf desc :label-offset))

(defun render-desc-lod (desc)
  "Get LOD keyword from a render description."
  (getf desc :lod))

;;; ===================================================================
;;; Snapshot Entity Tracking
;;; ===================================================================

(defvar *snapshot-entities* nil
  "List of entity IDs that represent snapshot nodes.
   Maintained by make-snapshot-entity-tracked and used by
   collect-snapshot-render-descriptions.")

(defun reset-snapshot-entities ()
  "Clear the tracked snapshot entity list."
  (setf *snapshot-entities* nil))

(defun track-snapshot-entity (entity)
  "Add ENTITY to the tracked snapshot entity list."
  (pushnew entity *snapshot-entities*)
  entity)

;;; ===================================================================
;;; Batch Rendering Helper
;;; ===================================================================

(defun collect-snapshot-render-descriptions ()
  "Produce render descriptions for all tracked snapshot entities.
   Culled entities are excluded from the result."
  (let ((descriptions nil))
    (dolist (entity *snapshot-entities*)
      (when (entity-valid-p entity)
        (let ((desc (render-snapshot-entity entity)))
          (when desc
            (push desc descriptions)))))
    (nreverse descriptions)))

;;; ===================================================================
;;; CPU-Side Rendered Color for Snapshot Entity
;;; ===================================================================

(defun compute-snapshot-entity-color (entity &key (normal-dot-view 0.5)
                                                   (time *elapsed-time*))
  "Compute the CPU-side holographic color for a snapshot ENTITY.
   Uses the entity's snapshot type to select a material, then runs
   the CPU-side hologram color computation.
   NORMAL-DOT-VIEW controls the Fresnel angle (0=edge, 1=face-on).
   TIME is the animation time for scanline effects.
   Returns four values: R G B A."
  (let* ((snap-type (snapshot-binding-snapshot-type entity))
         (material (make-hologram-material-for-type snap-type))
         (py (position3d-y entity)))
    (compute-hologram-color material normal-dot-view py time)))

;;; ===================================================================
;;; Connection Render Description Structure
;;; ===================================================================
;;;
;;; A connection render description is a property list with the following keys:
;;;   :entity         - The connection entity ID
;;;   :visible-p      - Whether the connection should be drawn
;;;   :from-position  - (x y z) world position of source node
;;;   :to-position    - (x y z) world position of target node
;;;   :midpoint       - (x y z) midpoint for position queries
;;;   :connection-kind - :parent-child, :fork, :branch, :merge
;;;   :material       - energy-beam-material instance
;;;   :color          - (r g b a) base color for the beam
;;;   :energy-flow    - Current energy flow value at midpoint [0,1]

(defun render-connection-entity (entity &key (time *elapsed-time*))
  "Produce a render description plist for a connection ENTITY.
   Uses the entity's connection component to determine the from/to
   endpoints (by reading position3d of the referenced entities) and
   the connection kind to select an appropriate energy-beam-material.

   Returns a property list suitable for passing to a rendering backend,
   or NIL if either endpoint entity is missing or culled."
  (let* ((from-id (connection-from-entity entity))
         (to-id (connection-to-entity entity))
         (kind (connection-kind entity)))
    ;; If either endpoint is invalid, don't render
    (when (or (< from-id 0) (< to-id 0))
      (return-from render-connection-entity nil))
    (let* (;; Read positions from the endpoint entities
           (from-x (position3d-x from-id))
           (from-y (position3d-y from-id))
           (from-z (position3d-z from-id))
           (to-x (position3d-x to-id))
           (to-y (position3d-y to-id))
           (to-z (position3d-z to-id))
           ;; Midpoint for the connection's own position
           (mid-x (* 0.5 (+ from-x to-x)))
           (mid-y (* 0.5 (+ from-y to-y)))
           (mid-z (* 0.5 (+ from-z to-z)))
           ;; Select energy beam material based on connection kind
           (material (make-energy-beam-material-for-connection-type kind))
           ;; Base color from material
           (beam-color (beam-material-color material))
           (color-r (coerce (first beam-color) 'single-float))
           (color-g (coerce (second beam-color) 'single-float))
           (color-b (coerce (third beam-color) 'single-float))
           (color-a (coerce (fourth beam-color) 'single-float))
           ;; Compute energy flow at midpoint for preview/CPU rendering
           (energy-flow (compute-energy-flow
                         0.5 time
                         (beam-material-flow-speed material)
                         (beam-material-flow-scale material))))
      ;; Update the connection entity's own position to the midpoint
      (setf (position3d-x entity) (coerce mid-x 'single-float))
      (setf (position3d-y entity) (coerce mid-y 'single-float))
      (setf (position3d-z entity) (coerce mid-z 'single-float))
      (list :entity entity
            :visible-p t
            :from-position (list from-x from-y from-z)
            :to-position (list to-x to-y to-z)
            :midpoint (list mid-x mid-y mid-z)
            :connection-kind kind
            :material material
            :color (list color-r color-g color-b color-a)
            :energy-flow energy-flow))))

;;; ===================================================================
;;; Connection Render Description Accessors
;;; ===================================================================

(defun conn-desc-entity (desc)
  "Get the entity from a connection render description."
  (getf desc :entity))

(defun conn-desc-visible-p (desc)
  "Get visibility flag from a connection render description."
  (getf desc :visible-p))

(defun conn-desc-from-position (desc)
  "Get (x y z) source position from a connection render description."
  (getf desc :from-position))

(defun conn-desc-to-position (desc)
  "Get (x y z) target position from a connection render description."
  (getf desc :to-position))

(defun conn-desc-midpoint (desc)
  "Get (x y z) midpoint from a connection render description."
  (getf desc :midpoint))

(defun conn-desc-connection-kind (desc)
  "Get connection kind keyword from a connection render description."
  (getf desc :connection-kind))

(defun conn-desc-material (desc)
  "Get energy-beam-material from a connection render description."
  (getf desc :material))

(defun conn-desc-color (desc)
  "Get (r g b a) color from a connection render description."
  (getf desc :color))

(defun conn-desc-energy-flow (desc)
  "Get energy flow value [0,1] from a connection render description."
  (getf desc :energy-flow))

;;; ===================================================================
;;; Connection Entity Tracking
;;; ===================================================================

(defvar *connection-entities* nil
  "List of entity IDs that represent connections.
   Maintained by track-connection-entity and used by
   collect-connection-render-descriptions.")

(defun reset-connection-entities ()
  "Clear the tracked connection entity list."
  (setf *connection-entities* nil))

(defun track-connection-entity (entity)
  "Add ENTITY to the tracked connection entity list."
  (pushnew entity *connection-entities*)
  entity)

;;; ===================================================================
;;; Connection Batch Rendering Helper
;;; ===================================================================

(defun collect-connection-render-descriptions ()
  "Produce render descriptions for all tracked connection entities.
   Connections with invalid endpoints are excluded from the result."
  (let ((descriptions nil))
    (dolist (entity *connection-entities*)
      (let ((desc (render-connection-entity entity)))
        (when desc
          (push desc descriptions))))
    (nreverse descriptions)))

;;; ===================================================================
;;; CPU-Side Connection Color Computation
;;; ===================================================================

(defun compute-connection-beam-color (entity progress
                                      &key (time *elapsed-time*))
  "Compute the CPU-side energy beam color for a connection ENTITY at
   a given PROGRESS point along the beam (0.0 = start, 1.0 = end).
   TIME is the animation time for flow effects.
   Returns four values: R G B A."
  (let* ((kind (connection-kind entity))
         (material (make-energy-beam-material-for-connection-type kind)))
    (compute-beam-color material progress time)))
