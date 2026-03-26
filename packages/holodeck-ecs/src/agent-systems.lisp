;;;; agent-systems.lisp - ECS systems for persistent agent visualization
;;;;
;;;; Systems that run each frame to synchronize persistent-agent data into
;;;; ECS components and drive visual effects (color cycling, metabolic glow,
;;;; lineage layout).
;;;;
;;;; Systems defined:
;;;;   persistent-sync-system     - Syncs struct state into ECS components
;;;;   cognitive-animation-system - Maps cognitive phase to entity color
;;;;   metabolic-glow-system      - Drives glow/pulse from energy/fitness
;;;;   lineage-rendering-system   - Positions children around parents

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Persistent Sync System
;;; ===================================================================
;;;
;;; Iterates entities with persistent-root component.  For each, checks
;;; if the version hash has changed by looking up the struct in
;;; *persistent-root-table* and computing a version string.  If changed,
;;; updates cognitive-state, genome-state, and metabolic-state from the
;;; struct fields.

(defun compute-agent-version-hash (agent)
  "Compute a version hash string for a persistent-agent struct.
   Uses the version number as a cheap change-detection key."
  (if agent
      (format nil "v~D" (autopoiesis.agent::persistent-agent-version agent))
      ""))

(defun persistent-sync-system (dt)
  "Sync persistent-agent struct state into ECS components.
   DT is the frame delta time (unused, but kept for system signature consistency).
   Iterates all entities in *persistent-root-table* and updates their
   ECS components when the version hash has changed."
  (declare (ignore dt))
  (maphash
   (lambda (entity-id agent)
     (when (and agent (entity-valid-p entity-id))
       (let ((new-hash (compute-agent-version-hash agent))
             (old-hash (persistent-root-version-hash entity-id)))
         (when (or (persistent-root-dirty-p entity-id)
                   (not (string= new-hash old-hash)))
           ;; Update version hash and clear dirty flag
           (setf (persistent-root-version-hash entity-id) new-hash)
           (setf (persistent-root-dirty-p entity-id) nil)
           ;; Sync cognitive state
           (when (ignore-errors (cognitive-state-phase entity-id))
             (setf (cognitive-state-thought-count entity-id)
                   (let ((thoughts (autopoiesis.agent::persistent-agent-thoughts agent)))
                     (if thoughts
                         (autopoiesis.core:pvec-length thoughts)
                         0))))
           ;; Sync genome state
           (when (ignore-errors (genome-state-capability-count entity-id))
             (let ((caps (autopoiesis.agent::persistent-agent-capabilities agent))
                   (genome (autopoiesis.agent::persistent-agent-genome agent)))
               (setf (genome-state-capability-count entity-id)
                     (if caps (autopoiesis.core:pset-count caps) 0))
               (setf (genome-state-genome-size entity-id)
                     (length genome))))
           ;; Sync metabolic state from membrane
           (when (ignore-errors (metabolic-state-energy entity-id))
             (let ((membrane (autopoiesis.agent::persistent-agent-membrane agent)))
               (when membrane
                 (let ((energy (or (autopoiesis.core:pmap-get membrane :energy) 1.0))
                       (fitness (or (autopoiesis.core:pmap-get membrane :fitness) 0.0)))
                   (setf (metabolic-state-energy entity-id)
                         (coerce (min 1.0 (max 0.0 energy)) 'single-float))
                   (setf (metabolic-state-fitness entity-id)
                         (coerce (min 1.0 (max 0.0 fitness)) 'single-float))))))))))
   *persistent-root-table*))

;;; ===================================================================
;;; Cognitive Animation System
;;; ===================================================================
;;;
;;; Maps cognitive phase to visual-style color, creating a visual
;;; indication of what phase the agent's cognitive loop is in.

(defun phase-color (phase)
  "Return (r g b) color values for a cognitive PHASE keyword."
  (case phase
    (:perceive (values 0.3 0.6 1.0))    ; blue
    (:reason   (values 0.2 0.9 0.3))    ; green
    (:decide   (values 1.0 0.9 0.2))    ; yellow
    (:act      (values 1.0 0.4 0.2))    ; red
    (:reflect  (values 0.8 0.3 1.0))    ; purple
    (otherwise (values 0.5 0.5 0.5))))  ; dim white (:idle)

(defun cognitive-animation-system (dt)
  "Animate entity colors based on cognitive phase.
   DT is the frame delta time (unused).
   Iterates entities in *persistent-root-table* that have both
   cognitive-state and visual-style components."
  (declare (ignore dt))
  (maphash
   (lambda (entity-id agent)
     (declare (ignore agent))
     (when (entity-valid-p entity-id)
       (handler-case
           (let ((phase (cognitive-state-phase entity-id)))
             (multiple-value-bind (r g b) (phase-color phase)
               (setf (visual-style-color-r entity-id) r)
               (setf (visual-style-color-g entity-id) g)
               (setf (visual-style-color-b entity-id) b)))
         (error () nil))))
   *persistent-root-table*))

;;; ===================================================================
;;; Metabolic Glow System
;;; ===================================================================
;;;
;;; Drives glow intensity from energy level and pulse rate from fitness.
;;; Higher energy = brighter glow; higher fitness = faster pulse.

(defun metabolic-glow-system (dt)
  "Update visual glow and pulse from metabolic state.
   DT is the frame delta time (unused).
   Sets glow-intensity proportional to energy (0.3 base + 1.7 * energy)
   and pulse-rate proportional to fitness (0.0 to 4.0 Hz)."
  (declare (ignore dt))
  (maphash
   (lambda (entity-id agent)
     (declare (ignore agent))
     (when (entity-valid-p entity-id)
       (handler-case
           (let ((energy (metabolic-state-energy entity-id))
                 (fitness (metabolic-state-fitness entity-id)))
             (setf (visual-style-glow-intensity entity-id)
                   (coerce (+ 0.3 (* 1.7 energy)) 'single-float))
             (setf (visual-style-pulse-rate entity-id)
                   (coerce (* 4.0 fitness) 'single-float)))
         (error () nil))))
   *persistent-root-table*))

;;; ===================================================================
;;; Lineage Rendering System
;;; ===================================================================
;;;
;;; Positions child entities in an arc around their parent entity and
;;; creates/updates connection entities between parent and children.

(defvar *lineage-connections* (make-hash-table :test 'equal)
  "Maps (parent-id . child-id) cons -> connection entity ID.
   Tracks created connection entities to avoid duplicates.")

(defun lineage-rendering-system (dt)
  "Position child agents around their parent and maintain connection entities.
   DT is the frame delta time (unused).
   Children are arranged in an arc at SPACING distance from parent."
  (declare (ignore dt))
  (let ((spacing 4.0))
    (maphash
     (lambda (entity-id agent)
       (declare (ignore agent))
       (when (entity-valid-p entity-id)
         (handler-case
             (let ((parent-eid (lineage-binding-parent-entity entity-id))
                   (child-count (lineage-binding-child-count entity-id)))
               (declare (ignore child-count))
               ;; Position this entity relative to parent if it has one
               (when (and (>= parent-eid 0) (entity-valid-p parent-eid))
                 (let* ((parent-x (position3d-x parent-eid))
                        (parent-y (position3d-y parent-eid))
                        (parent-z (position3d-z parent-eid))
                        (gen (lineage-binding-generation entity-id))
                        ;; Offset based on generation and entity ID for spread
                        (angle (coerce (* (mod entity-id 12) (/ pi 6.0)) 'single-float))
                        (radius (coerce (* spacing (1+ gen)) 'single-float))
                        (target-x (+ parent-x (* radius (cos angle))))
                        (target-z (+ parent-z (* radius (sin angle))))
                        (target-y (+ parent-y (* 2.0 gen))))
                   ;; Lerp toward target position
                   (let ((lerp-factor (min 1.0 (* 3.0 *delta-time*))))
                     (setf (position3d-x entity-id)
                           (coerce (+ (position3d-x entity-id)
                                      (* lerp-factor (- target-x (position3d-x entity-id))))
                                   'single-float))
                     (setf (position3d-y entity-id)
                           (coerce (+ (position3d-y entity-id)
                                      (* lerp-factor (- target-y (position3d-y entity-id))))
                                   'single-float))
                     (setf (position3d-z entity-id)
                           (coerce (+ (position3d-z entity-id)
                                      (* lerp-factor (- target-z (position3d-z entity-id))))
                                   'single-float)))
                   ;; Ensure connection entity exists
                   (let ((conn-key (cons parent-eid entity-id)))
                     (unless (gethash conn-key *lineage-connections*)
                       (let ((conn (make-connection-entity parent-eid entity-id
                                                           :kind :lineage)))
                         (setf (gethash conn-key *lineage-connections*) conn)
                         (track-connection-entity conn)))))))
           (error () nil))))
     *persistent-root-table*)))
