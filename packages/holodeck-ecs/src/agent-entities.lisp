;;;; agent-entities.lisp - Factory functions for persistent agent ECS entities
;;;;
;;;; Creates and manages ECS entities that embody persistent-agent structs
;;;; in the holodeck.  Each persistent agent gets a full set of components:
;;;; spatial (position, scale, rotation), visual (style, label), binding
;;;; (persistent-root), cognitive, genome, lineage, metabolic, and interaction.
;;;;
;;;; The *persistent-agent-entity-map* tracks the mapping from agent ID
;;;; strings to ECS entity IDs for fast lookup.

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Persistent Agent Entity Map
;;; ===================================================================

(defvar *persistent-agent-entity-map* (make-hash-table :test 'equal)
  "Maps persistent-agent ID (string) to ECS entity ID (fixnum).
   Used for fast lookup when updating or querying agent entities.")

;;; ===================================================================
;;; Entity Factory
;;; ===================================================================

(defun make-persistent-agent-entity (agent &key (x 0.0) (y 0.0) (z 0.0))
  "Create an ECS entity embodying a persistent-agent struct.
   Sets up all components: position3d, scale3d, rotation3d, visual-style,
   node-label, persistent-root, cognitive-state, genome-state,
   lineage-binding, metabolic-state, interactive, and detail-level.
   Stores AGENT in *persistent-root-table* and registers in
   *persistent-agent-entity-map*.  Returns the entity ID."
  (let* ((entity (make-entity))
         (agent-id (autopoiesis.agent::persistent-agent-id agent))
         (agent-name (autopoiesis.agent::persistent-agent-name agent))
         (xf (coerce x 'single-float))
         (yf (coerce y 'single-float))
         (zf (coerce z 'single-float)))
    ;; Spatial components
    (make-position3d entity :x xf :y yf :z zf)
    (make-scale3d entity :sx 1.2 :sy 1.2 :sz 1.2)
    (make-rotation3d entity)
    ;; Visual style - green for agents, with moderate glow
    (make-visual-style entity
                       :node-type :agent
                       :color-r 0.2 :color-g 0.9 :color-b 0.3 :color-a 0.9
                       :glow-intensity 1.0
                       :pulse-rate 0.5)
    ;; Label
    (make-node-label entity
                     :text agent-name
                     :visible-p t
                     :offset-y 1.8)
    ;; Persistent root binding
    (make-persistent-root entity
                          :version-hash (compute-agent-version-hash agent)
                          :dirty-p nil)
    ;; Cognitive state
    (make-cognitive-state entity :phase :idle :thought-count 0)
    ;; Genome state
    (let ((caps (autopoiesis.agent::persistent-agent-capabilities agent))
          (genome (autopoiesis.agent::persistent-agent-genome agent)))
      (make-genome-state entity
                         :capability-count (if caps
                                               (autopoiesis.core:pset-count caps)
                                               0)
                         :genome-size (length genome)
                         :mutation-count 0))
    ;; Lineage binding
    (let* ((children (autopoiesis.agent::persistent-agent-children agent))
           (parent (autopoiesis.agent::persistent-agent-parent-root agent))
           (parent-entity (if parent
                              (or (gethash (autopoiesis.agent::persistent-agent-id parent)
                                           *persistent-agent-entity-map*)
                                  -1)
                              -1)))
      (make-lineage-binding entity
                            :parent-entity parent-entity
                            :child-count (length children)
                            :generation (compute-agent-generation agent)
                            :fork-type (if parent :fork :none)))
    ;; Metabolic state
    (let ((membrane (autopoiesis.agent::persistent-agent-membrane agent)))
      (make-metabolic-state entity
                            :energy (coerce
                                     (or (and membrane
                                              (autopoiesis.core:pmap-get membrane :energy))
                                         1.0)
                                     'single-float)
                            :production-rate 0.0
                            :fitness (coerce
                                      (or (and membrane
                                               (autopoiesis.core:pmap-get membrane :fitness))
                                          0.0)
                                      'single-float)))
    ;; Interaction
    (make-interactive entity)
    (make-detail-level entity :current :high)
    ;; Register in tables
    (setf (gethash entity *persistent-root-table*) agent)
    (setf (gethash agent-id *persistent-agent-entity-map*) entity)
    ;; Track for rendering
    (track-snapshot-entity entity)
    entity))

;;; ===================================================================
;;; Generation Computation
;;; ===================================================================

(defun compute-agent-generation (agent)
  "Compute the generation depth of AGENT by walking parent-root links.
   Returns 0 for root agents, 1 for direct children, etc."
  (let ((gen 0)
        (current agent))
    (loop
      (let ((parent (autopoiesis.agent::persistent-agent-parent-root current)))
        (unless parent (return gen))
        (incf gen)
        (setf current parent)
        ;; Safety limit
        (when (> gen 100) (return gen))))))

;;; ===================================================================
;;; Tree Materialization
;;; ===================================================================

(defun materialize-agent-tree (agent registry
                               &key (x 0.0) (y 0.0) (z 0.0))
  "Create ECS entities for AGENT and all ancestors/children found in REGISTRY.
   REGISTRY is a hash-table mapping agent-id (string) to persistent-agent structs.
   Uses default-agent-layout for positioning.
   Returns a list of created entity IDs."
  (let* ((agents-to-create (collect-agent-family agent registry))
         (layout (default-agent-layout agents-to-create
                                       :center-x x :center-y y :center-z z))
         (entities nil))
    ;; Create entities in generation order (parents first)
    (dolist (a (sort (copy-list agents-to-create)
                     #'< :key #'compute-agent-generation))
      (let* ((aid (autopoiesis.agent::persistent-agent-id a))
             (pos (cdr (assoc aid layout :test #'string=)))
             (px (if pos (first pos) x))
             (py (if pos (second pos) y))
             (pz (if pos (third pos) z)))
        (unless (gethash aid *persistent-agent-entity-map*)
          (push (make-persistent-agent-entity a :x px :y py :z pz)
                entities))))
    ;; Wire up lineage bindings now that all entities exist
    (dolist (entity-id entities)
      (let ((agent (gethash entity-id *persistent-root-table*)))
        (when agent
          (let ((parent (autopoiesis.agent::persistent-agent-parent-root agent)))
            (when parent
              (let ((parent-eid (gethash (autopoiesis.agent::persistent-agent-id parent)
                                         *persistent-agent-entity-map*)))
                (when (and parent-eid (entity-valid-p parent-eid))
                  (setf (lineage-binding-parent-entity entity-id) parent-eid))))))))
    (nreverse entities)))

(defun collect-agent-family (agent registry)
  "Collect AGENT plus all ancestors and children found in REGISTRY.
   Returns a list of persistent-agent structs (no duplicates)."
  (let ((seen (make-hash-table :test 'equal))
        (result nil))
    (labels ((visit (a)
               (when a
                 (let ((aid (autopoiesis.agent::persistent-agent-id a)))
                   (unless (gethash aid seen)
                     (setf (gethash aid seen) t)
                     (push a result)
                     ;; Visit parent
                     (let ((parent (autopoiesis.agent::persistent-agent-parent-root a)))
                       (when parent (visit parent)))
                     ;; Visit children found in registry
                     (dolist (child-id (autopoiesis.agent::persistent-agent-children a))
                       (let ((child (gethash child-id registry)))
                         (when child (visit child)))))))))
      (visit agent))
    result))

;;; ===================================================================
;;; Entity Update
;;; ===================================================================

(defun update-agent-entity (entity-id agent)
  "Update *persistent-root-table* entry for ENTITY-ID with new AGENT struct.
   Marks the persistent-root component as dirty so the sync system will
   pick up changes on the next frame."
  (setf (gethash entity-id *persistent-root-table*) agent)
  (when (entity-valid-p entity-id)
    (setf (persistent-root-dirty-p entity-id) t))
  entity-id)

;;; ===================================================================
;;; Default Agent Layout
;;; ===================================================================

(defun default-agent-layout (agents &key (center-x 0.0) (center-y 0.0)
                                         (center-z 0.0) (spacing 3.0))
  "Compute positions for a list of persistent-agent structs.
   Arranges agents in a tree layout by generation, with each generation
   on a higher Y level and children spread in an arc around center.
   Returns an alist of (agent-id . (x y z)) entries."
  (let ((by-gen (make-hash-table))
        (result nil))
    ;; Group agents by generation
    (dolist (a agents)
      (let ((gen (compute-agent-generation a)))
        (push a (gethash gen by-gen))))
    ;; Layout each generation
    (maphash
     (lambda (gen gen-agents)
       (let* ((count (length gen-agents))
              (y-offset (* gen spacing 1.5))
              (arc-spread (if (> count 1)
                              (* spacing (1- count))
                              0.0)))
         (loop for a in gen-agents
               for i from 0
               for angle = (if (> count 1)
                               (- (* (/ i (max 1.0 (1- (coerce count 'single-float))))
                                     pi)
                                  (/ pi 2.0))
                               0.0)
               for x = (+ center-x (* (/ arc-spread 2.0) (cos angle)))
               for z = (+ center-z (* (/ arc-spread 2.0) (sin angle)))
               do (push (cons (autopoiesis.agent::persistent-agent-id a)
                              (list x (+ center-y y-offset) z))
                        result))))
     by-gen)
    result))
