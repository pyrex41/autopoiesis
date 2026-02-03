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
   #:snapshot-type-to-color))
