;;;; population-viz.lisp - Population visualization for persistent agent evolution
;;;;
;;;; Materializes a population of persistent agents as ECS entities
;;;; in the holodeck with fitness-based layout.

(in-package #:autopoiesis.holodeck)

;;; ═══════════════════════════════════════════════════════════════════
;;; Population Materialization
;;; ═══════════════════════════════════════════════════════════════════

(defun materialize-population (agents &key (center-x 0.0) (center-z 0.0)
                                           (spacing 3.0))
  "Create ECS entities for all persistent agents in a population.
   Positions agents using fitness-landscape-layout.
   Returns a list of (agent-id . entity-id) pairs."
  (let ((layout (fitness-landscape-layout agents
                                          :center-x center-x
                                          :center-z center-z
                                          :spacing spacing)))
    (loop for (agent-id x y z) in layout
          for agent = (find agent-id agents
                            :key #'autopoiesis.agent:persistent-agent-id
                            :test #'equal)
          when agent
          collect (cons agent-id
                        (make-persistent-agent-entity agent :x x :y y :z z)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Fitness Landscape Layout
;;; ═══════════════════════════════════════════════════════════════════

(defun fitness-landscape-layout (agents &key (center-x 0.0) (center-z 0.0)
                                             (spacing 3.0) (height-scale 10.0))
  "Position agents by generation (x-axis) and fitness (y-axis).
   Returns a list of (agent-id x y z) tuples."
  (loop for agent in agents
        for i from 0
        for gen = (autopoiesis.agent:persistent-agent-version agent)
        for thoughts = (autopoiesis.agent:persistent-agent-thoughts agent)
        for thought-count = (autopoiesis.core:pvec-length thoughts)
        ;; Estimate fitness from thought count and capability count
        for cap-count = (autopoiesis.core:pset-count
                         (autopoiesis.agent:persistent-agent-capabilities agent))
        for fitness = (/ (+ thought-count cap-count) 20.0)
        for x = (+ center-x (* gen spacing))
        for y = (* (min 1.0 fitness) height-scale)
        for z = (+ center-z (* (mod i 5) spacing))
        collect (list (autopoiesis.agent:persistent-agent-id agent)
                      (coerce x 'single-float)
                      (coerce y 'single-float)
                      (coerce z 'single-float))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Population Update
;;; ═══════════════════════════════════════════════════════════════════

(defun update-population-viz (agents)
  "Refresh ECS entities for agents that already have entities.
   Creates new entities for agents not yet materialized.
   Returns the count of updated entities."
  (let ((updated 0))
    (dolist (agent agents updated)
      (let* ((aid (autopoiesis.agent:persistent-agent-id agent))
             (eid (gethash aid *agent-entity-map*)))
        (if eid
            (progn
              (update-agent-entity eid agent)
              (incf updated))
            ;; New agent - create entity at default position
            (progn
              (make-persistent-agent-entity agent)
              (incf updated)))))))
