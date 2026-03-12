;;;; team-components.lisp - ECS components for team topology visualization
;;;;
;;;; Defines components that bind team data into the holodeck ECS world.
;;;; Components hold only primitive ECS-compatible types (fixnum,
;;;; single-float, keyword, boolean, string).
;;;;
;;;; Component categories:
;;;;   Binding  - team-binding (links entity to a team)
;;;;   Layout   - team-layout (spatial arrangement parameters)

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Team Binding Component
;;; ===================================================================

(defcomponent team-binding
  "Links an entity to a team.  TEAM-ID identifies which team,
   ROLE indicates the agent's role within the team, and STRATEGY
   records the team's coordination strategy keyword."
  (team-id "" :type string)
  (role :member :type keyword)
  (strategy :parallel :type keyword))

;;; ===================================================================
;;; Team Layout Component
;;; ===================================================================

(defcomponent team-layout
  "Spatial arrangement parameters for a team anchor entity.
   CENTER-X/Y/Z define the team's center position in world space.
   RADIUS controls how far members spread out.
   ARRANGEMENT selects the layout pattern."
  (center-x 0.0 :type single-float)
  (center-y 0.0 :type single-float)
  (center-z 0.0 :type single-float)
  (radius 8.0 :type single-float)
  (arrangement :circle :type keyword))
