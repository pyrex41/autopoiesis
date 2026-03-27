;;;; agent-components.lisp - ECS components for persistent agent embodiment
;;;;
;;;; Defines components that bind persistent-agent structs into the holodeck
;;;; ECS world.  Components hold only primitive ECS-compatible types; the
;;;; actual persistent-agent struct reference lives in a side hash-table
;;;; because cl-fast-ecs defcomponent only supports fixnum, single-float,
;;;; keyword, boolean, and string slot types.
;;;;
;;;; Component categories:
;;;;   Binding     - persistent-root (links entity to persistent-agent struct)
;;;;   Cognitive   - cognitive-state (phase, thought count)
;;;;   Genome      - genome-state (capability count, genome size, mutations)
;;;;   Lineage     - lineage-binding (parent/child relationships, generation)
;;;;   Metabolic   - metabolic-state (energy, production, fitness)

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Side Table for Persistent Agent Struct References
;;; ===================================================================

(defvar *persistent-root-table* (make-hash-table)
  "Maps entity-id -> persistent-agent struct.  Side table because ECS
   components cannot hold arbitrary object references.")

;;; ===================================================================
;;; Persistent Root Component
;;; ===================================================================

(defcomponent persistent-root
  "Marks an entity as the ECS embodiment of a persistent-agent struct.
   The actual struct is stored in *persistent-root-table* keyed by entity ID.
   VERSION-HASH tracks the last-synced version for change detection."
  (version-hash "" :type string)
  (dirty-p nil :type boolean))

;;; ===================================================================
;;; Cognitive State Component
;;; ===================================================================

(defcomponent cognitive-state
  "Tracks the cognitive loop phase and thought accumulation of an agent.
   PHASE maps to the cognitive cycle stages: :perceive, :reason, :decide,
   :act, :reflect, or :idle."
  (phase :idle :type keyword)
  (thought-count 0 :type fixnum))

;;; ===================================================================
;;; Genome State Component
;;; ===================================================================

(defcomponent genome-state
  "Tracks the genome and capability configuration of a persistent agent.
   Updated from the persistent-agent struct during sync."
  (capability-count 0 :type fixnum)
  (genome-size 0 :type fixnum)
  (mutation-count 0 :type fixnum))

;;; ===================================================================
;;; Lineage Binding Component
;;; ===================================================================

(defcomponent lineage-binding
  "Tracks parent-child lineage relationships between persistent agents.
   PARENT-ENTITY is the ECS entity ID of the parent agent (-1 if root).
   FORK-TYPE indicates how this agent was created: :none, :fork, :spawn."
  (parent-entity -1 :type fixnum)
  (child-count 0 :type fixnum)
  (generation 0 :type fixnum)
  (fork-type :none :type keyword))

;;; ===================================================================
;;; Metabolic State Component
;;; ===================================================================

(defcomponent metabolic-state
  "Tracks energy and fitness metrics for metabolic visualization.
   ENERGY drives glow intensity; FITNESS drives pulse rate.
   PRODUCTION-RATE reflects thought generation speed."
  (energy 1.0 :type single-float)
  (production-rate 0.0 :type single-float)
  (fitness 0.0 :type single-float))
