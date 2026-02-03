;;;; packages.lisp - Package definitions for Autopoiesis 3D Holodeck
;;;;
;;;; Defines packages for the Entity-Component-System architecture
;;;; powering the 3D holodeck visualization (Phase 8).

(in-package #:cl-user)

;;; ═══════════════════════════════════════════════════════════════════
;;; Holodeck ECS Package
;;; ═══════════════════════════════════════════════════════════════════

(defpackage #:autopoiesis.holodeck
  (:use #:cl #:cl-fast-ecs)
  (:import-from #:3d-vectors #:vec3 #:vx #:vy #:vz #:v+ #:v- #:v* #:vlength)
  (:import-from #:3d-matrices #:mat4 #:meye #:m* #:mtranslation)

  (:export
   ;; ECS storage initialization
   #:init-holodeck-storage

   ;; Spatial components
   #:position3d
   #:make-position3d
   #:position3d-x
   #:position3d-y
   #:position3d-z
   #:velocity3d
   #:make-velocity3d
   #:velocity3d-dx
   #:velocity3d-dy
   #:velocity3d-dz
   #:scale3d
   #:make-scale3d
   #:scale3d-sx
   #:scale3d-sy
   #:scale3d-sz
   #:rotation3d
   #:make-rotation3d
   #:rotation3d-rx
   #:rotation3d-ry
   #:rotation3d-rz

   ;; Visual components
   #:visual-style
   #:make-visual-style
   #:visual-style-node-type
   #:visual-style-color-r
   #:visual-style-color-g
   #:visual-style-color-b
   #:visual-style-color-a
   #:visual-style-glow-intensity
   #:visual-style-pulse-rate
   #:node-label
   #:make-node-label
   #:node-label-text
   #:node-label-visible-p
   #:node-label-offset-y

   ;; Data binding components
   #:snapshot-binding
   #:make-snapshot-binding
   #:snapshot-binding-snapshot-id
   #:snapshot-binding-snapshot-type
   #:agent-binding
   #:make-agent-binding
   #:agent-binding-agent-id
   #:agent-binding-agent-name
   #:connection
   #:make-connection
   #:connection-from-entity
   #:connection-to-entity
   #:connection-kind

   ;; Interaction components
   #:interactive
   #:make-interactive
   #:interactive-hover-p
   #:interactive-selected-p
   #:detail-level
   #:make-detail-level
   #:detail-level-current
   #:detail-level-low-distance
   #:detail-level-cull-distance

   ;; Simulation state
   #:*delta-time*
   #:*elapsed-time*
   #:*camera-position*

   ;; Systems
   #:movement-system
   #:pulse-system
   #:lod-system

   ;; Entity creation helpers
   #:make-snapshot-entity
   #:make-connection-entity

   ;; Utility functions
   #:distance-to-camera
   #:snapshot-type-to-color

   ;; Window class and protocol
   #:holodeck-window
   #:*window-width*
   #:*window-height*
   #:*window-title*
   #:window-width
   #:window-height
   #:window-title
   #:holodeck-scene
   #:holodeck-camera
   #:holodeck-hud
   #:holodeck-running-p
   #:holodeck-store
   #:setup-scene
   #:holodeck-render
   #:holodeck-update
   #:handle-holodeck-event
   #:window-aspect-ratio
   #:resize-window

   ;; Shader sources
   #:*hologram-node-vertex-shader*
   #:*hologram-node-fragment-shader*
   #:*energy-beam-vertex-shader*
   #:*energy-beam-fragment-shader*
   #:*glow-vertex-shader*
   #:*glow-fragment-shader*
   #:*shader-sources*

   ;; Shader program class and registry
   #:shader-program
   #:shader-program-name
   #:shader-program-vertex-source
   #:shader-program-fragment-source
   #:shader-program-uniforms
   #:shader-program-uniform-names
   #:register-shader-program
   #:find-shader-program
   #:list-shader-programs
   #:clear-shader-registry
   #:*shader-registry*
   #:make-hologram-node-shader
   #:make-energy-beam-shader
   #:make-glow-shader
   #:register-holodeck-shaders
   #:validate-shader-source
   #:validate-shader-program

   ;; Hologram material
   #:hologram-material
   #:material-base-color
   #:material-glow-intensity
   #:material-glow-color
   #:material-fresnel-power
   #:material-scanline-frequency
   #:material-scanline-speed
   #:material-scanline-intensity
   #:material-shader
   #:make-hologram-material-for-type

   ;; Energy beam material
   #:energy-beam-material
   #:beam-material-color
   #:beam-material-flow-speed
   #:beam-material-flow-scale
   #:beam-material-pulse-intensity
   #:beam-material-base-alpha
   #:beam-material-color-boost
   #:connection-type-to-color
   #:make-energy-beam-material-for-connection-type

   ;; CPU-side shader computation
   #:compute-fresnel
   #:compute-scanline
   #:compute-hologram-color
   #:compute-energy-flow
   #:compute-beam-color

   ;; Mesh primitives
   #:mesh-primitive
   #:mesh-name
   #:mesh-vertices
   #:mesh-normals
   #:mesh-indices
   #:mesh-lod
   #:mesh-vertex-count
   #:mesh-triangle-count
   #:register-mesh
   #:find-mesh
   #:list-meshes
   #:clear-mesh-registry
   #:*mesh-registry*
   #:normalize-xyz
   #:make-sphere-mesh
   #:make-octahedron-mesh
   #:make-branching-node-mesh
   #:make-mesh-for-type
   #:lod-mesh-id
   #:register-holodeck-meshes

   ;; Rendering - snapshot entities
   #:snapshot-type-to-mesh-type
   #:detail-level-to-mesh-lod
   #:render-snapshot-entity
   #:render-desc-entity
   #:render-desc-visible-p
   #:render-desc-position
   #:render-desc-scale
   #:render-desc-rotation
   #:render-desc-mesh
   #:render-desc-material
   #:render-desc-color
   #:render-desc-glow-p
   #:render-desc-label-text
   #:render-desc-label-offset
   #:render-desc-lod
   #:*snapshot-entities*
   #:reset-snapshot-entities
   #:track-snapshot-entity
   #:collect-snapshot-render-descriptions
   #:compute-snapshot-entity-color

   ;; Rendering - connection entities
   #:render-connection-entity
   #:conn-desc-entity
   #:conn-desc-visible-p
   #:conn-desc-from-position
   #:conn-desc-to-position
   #:conn-desc-midpoint
   #:conn-desc-connection-kind
   #:conn-desc-material
   #:conn-desc-color
   #:conn-desc-energy-flow
   #:*connection-entities*
   #:reset-connection-entities
   #:track-connection-entity
   #:collect-connection-render-descriptions
   #:compute-connection-beam-color

   ;; Orbit camera
   #:orbit-camera
   #:make-orbit-camera
   #:camera-target
   #:camera-up
   #:camera-theta
   #:camera-phi
   #:camera-distance
   #:camera-fov
   #:camera-near-plane
   #:camera-far-plane
   #:camera-min-distance
   #:camera-max-distance
   #:camera-orbit-speed
   #:camera-zoom-speed
   #:camera-pan-speed
   #:camera-position
   #:camera-forward
   #:camera-right
   #:orbit-camera-by
   #:zoom-camera-by
   #:pan-camera-by
   #:camera-view-matrix-data
   #:camera-projection-matrix-data
   #:sync-camera-state
   #:*phi-min*
   #:*phi-max*

   ;; Lifecycle
   #:*holodeck*
   #:launch-holodeck
   #:stop-holodeck))
