;;;; team-systems.lisp - ECS systems for team topology visualization
;;;;
;;;; Systems that run each frame to synchronize team data into ECS
;;;; components and drive spatial arrangement of team members.
;;;;
;;;; Systems defined:
;;;;   team-sync-system   - Syncs team registry into ECS entities
;;;;   team-layout-system - Positions team members based on strategy

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; Team Entity Tracking
;;; ===================================================================

(defvar *team-entity-map* (make-hash-table :test 'equal)
  "Maps team-id (string) -> team anchor entity ID.
   Tracks which teams have ECS anchor entities.")

(defvar *team-member-bindings* (make-hash-table :test 'equal)
  "Maps team-id (string) -> list of member entity IDs.
   Tracks which member entities have been bound to each team.")

(defvar *team-sync-interval* 1.0
  "Minimum interval between team sync operations in seconds.")

(defvar *last-team-sync-time* 0.0
  "Timestamp of the last team sync operation.")

;;; ===================================================================
;;; Strategy to Layout Mapping
;;; ===================================================================

(defun strategy-class-to-keyword (strategy-obj)
  "Convert a strategy class instance to a keyword for layout mapping.
   Uses type-of and extracts the class name."
  (handler-case
      (let ((type-name (string-upcase (symbol-name (type-of strategy-obj)))))
        (cond
          ((search "LEADER-WORKER" type-name) :leader-worker)
          ((search "HIERARCHICAL" type-name) :hierarchical-leader-worker)
          ((search "PARALLEL" type-name) :parallel)
          ((search "PIPELINE" type-name) :pipeline)
          ((search "DEBATE-CONSENSUS" type-name) :debate-consensus)
          ((search "DEBATE" type-name) :debate)
          ((search "CONSENSUS" type-name) :consensus)
          ((search "ROTATING" type-name) :rotating-leader)
          ((search "LEADER-PARALLEL" type-name) :leader-parallel)
          (t :parallel)))
    (error () :parallel)))

(defun strategy-to-arrangement (strategy-keyword)
  "Map a strategy keyword to a default layout arrangement keyword.
   Returns an arrangement keyword for team-layout."
  (case strategy-keyword
    (:leader-worker :star)
    (:hierarchical-leader-worker :star)
    (:parallel :line)
    (:pipeline :chain)
    (:debate :circle)
    (:consensus :circle)
    (:rotating-leader :circle)
    (:leader-parallel :two-tier)
    (:debate-consensus :circle)
    (otherwise :circle)))

;;; ===================================================================
;;; Team Sync System
;;; ===================================================================

(defun team-sync-system (dt)
  "Sync team registry into ECS entities.
   DT is the frame delta time.
   Runs at *team-sync-interval* to avoid excessive registry access.
   For each team, ensures an anchor entity exists and binds member
   entities with team-binding components."
  (declare (ignore dt))
  ;; Rate-limit sync operations
  (when (< (- *elapsed-time* *last-team-sync-time*) *team-sync-interval*)
    (return-from team-sync-system nil))
  (setf *last-team-sync-time* *elapsed-time*)
  ;; Access team registry via find-package/find-symbol
  (let ((team-pkg (find-package :autopoiesis.team)))
    (unless team-pkg
      (return-from team-sync-system nil))
    (let ((list-teams-fn (find-symbol "LIST-TEAMS" team-pkg))
          (team-id-fn (find-symbol "TEAM-ID" team-pkg))
          (team-members-fn (find-symbol "TEAM-MEMBERS" team-pkg))
          (team-leader-fn (find-symbol "TEAM-LEADER" team-pkg))
          (team-strategy-fn (find-symbol "TEAM-STRATEGY" team-pkg))
          (team-status-fn (find-symbol "TEAM-STATUS" team-pkg)))
      (unless (and list-teams-fn (fboundp list-teams-fn)
                   team-id-fn (fboundp team-id-fn)
                   team-members-fn (fboundp team-members-fn))
        (return-from team-sync-system nil))
      ;; Get all teams
      (let ((teams (handler-case (funcall list-teams-fn)
                     (error () nil))))
        (dolist (team teams)
          (handler-case
              (let* ((tid (funcall team-id-fn team))
                     (members (funcall team-members-fn team))
                     (leader (when (and team-leader-fn (fboundp team-leader-fn))
                               (funcall team-leader-fn team)))
                     (strategy-obj (when (and team-strategy-fn (fboundp team-strategy-fn))
                                     (funcall team-strategy-fn team)))
                     (strategy-kw (if strategy-obj
                                      (strategy-class-to-keyword strategy-obj)
                                      :parallel))
                     (arrangement (strategy-to-arrangement strategy-kw))
                     (tid-str (format nil "~A" tid)))
                ;; Ensure team anchor entity exists
                (unless (gethash tid-str *team-entity-map*)
                  (let ((anchor (cl-fast-ecs:make-entity)))
                    (make-position3d anchor :x 0.0 :y 0.0 :z 0.0)
                    (make-team-layout anchor
                                      :center-x 0.0
                                      :center-y 0.0
                                      :center-z 0.0
                                      :radius 8.0
                                      :arrangement arrangement)
                    (setf (gethash tid-str *team-entity-map*) anchor)))
                ;; Update arrangement on anchor
                (let ((anchor (gethash tid-str *team-entity-map*)))
                  (when (entity-valid-p anchor)
                    (handler-case
                        (setf (team-layout-arrangement anchor) arrangement)
                      (error () nil))))
                ;; Bind member entities
                (let ((bound-members nil))
                  (dolist (member-id members)
                    (let ((member-str (format nil "~A" member-id)))
                      ;; Look for the member in *persistent-root-table*
                      (maphash
                       (lambda (eid agent)
                         (declare (ignore agent))
                         (when (entity-valid-p eid)
                           (handler-case
                               (let ((agent-name (ignore-errors
                                                   (node-label-text eid))))
                                 (when (and agent-name
                                            (string= agent-name member-str))
                                   (push eid bound-members)
                                   ;; Apply team-binding component
                                   (handler-case
                                       (team-binding-team-id eid)
                                     (error ()
                                       ;; Component doesn't exist yet, create it
                                       (make-team-binding eid
                                                          :team-id tid-str
                                                          :role (if (and leader
                                                                         (equal member-id leader))
                                                                    :leader
                                                                    :member)
                                                          :strategy strategy-kw)))
                                   ;; Update existing binding
                                   (handler-case
                                       (progn
                                         (setf (team-binding-team-id eid) tid-str)
                                         (setf (team-binding-role eid)
                                               (if (and leader (equal member-id leader))
                                                   :leader
                                                   :member))
                                         (setf (team-binding-strategy eid) strategy-kw))
                                     (error () nil))))
                             (error () nil))))
                       *persistent-root-table*)))
                  (setf (gethash tid-str *team-member-bindings*) bound-members)))
            (error () nil)))
        ;; Clean up anchor entities for teams that no longer exist
        (let ((active-team-ids (make-hash-table :test 'equal)))
          (dolist (team teams)
            (handler-case
                (let ((tid (funcall team-id-fn team)))
                  (setf (gethash (format nil "~A" tid) active-team-ids) t))
              (error () nil)))
          (let ((to-remove nil))
            (maphash (lambda (tid anchor)
                       (unless (gethash tid active-team-ids)
                         (push (cons tid anchor) to-remove)))
                     *team-entity-map*)
            (dolist (entry to-remove)
              (let ((tid (car entry))
                    (anchor (cdr entry)))
                (when (entity-valid-p anchor)
                  (handler-case (cl-fast-ecs:delete-entity anchor)
                    (error () nil)))
                (remhash tid *team-entity-map*)
                (remhash tid *team-member-bindings*)))))))))

;;; ===================================================================
;;; Team Layout System
;;; ===================================================================

(defun team-layout-system (dt)
  "Position team members based on strategy and layout arrangement.
   DT is the frame delta time, used for smooth lerp transitions.
   Iterates all team anchors and positions bound members according
   to the team's arrangement pattern."
  (let ((lerp-factor (min 1.0 (* 3.0 dt))))
    (maphash
     (lambda (tid anchor)
       (when (entity-valid-p anchor)
         (handler-case
             (let* ((arrangement (team-layout-arrangement anchor))
                    (center-x (team-layout-center-x anchor))
                    (center-y (team-layout-center-y anchor))
                    (center-z (team-layout-center-z anchor))
                    (radius (team-layout-radius anchor))
                    (members (gethash tid *team-member-bindings*))
                    (member-count (length members)))
               ;; Compute anchor center as average of member positions
               (when (> member-count 0)
                 (let ((sum-x 0.0) (sum-y 0.0) (sum-z 0.0)
                       (valid-count 0))
                   (dolist (eid members)
                     (when (entity-valid-p eid)
                       (handler-case
                           (progn
                             (incf sum-x (position3d-x eid))
                             (incf sum-y (position3d-y eid))
                             (incf sum-z (position3d-z eid))
                             (incf valid-count))
                         (error () nil))))
                   (when (> valid-count 0)
                     (setf center-x (coerce (/ sum-x valid-count) 'single-float))
                     (setf center-y (coerce (/ sum-y valid-count) 'single-float))
                     (setf center-z (coerce (/ sum-z valid-count) 'single-float))
                     (setf (team-layout-center-x anchor) center-x)
                     (setf (team-layout-center-y anchor) center-y)
                     (setf (team-layout-center-z anchor) center-z)
                     (setf (position3d-x anchor) center-x)
                     (setf (position3d-y anchor) center-y)
                     (setf (position3d-z anchor) center-z)))
                 ;; Position each member based on arrangement
                 (let ((idx 0))
                   (dolist (eid members)
                     (when (entity-valid-p eid)
                       (handler-case
                           (multiple-value-bind (target-x target-y target-z)
                               (compute-team-member-position
                                arrangement center-x center-y center-z
                                radius member-count idx
                                (handler-case (team-binding-role eid)
                                  (error () :member)))
                             ;; Lerp toward target
                             (let ((cur-x (position3d-x eid))
                                   (cur-y (position3d-y eid))
                                   (cur-z (position3d-z eid)))
                               (setf (position3d-x eid)
                                     (coerce (+ cur-x (* lerp-factor (- target-x cur-x)))
                                             'single-float))
                               (setf (position3d-y eid)
                                     (coerce (+ cur-y (* lerp-factor (- target-y cur-y)))
                                             'single-float))
                               (setf (position3d-z eid)
                                     (coerce (+ cur-z (* lerp-factor (- target-z cur-z)))
                                             'single-float))))
                         (error () nil)))
                     (incf idx)))))
           (error () nil))))
     *team-entity-map*)))

;;; ===================================================================
;;; Position Computation by Arrangement
;;; ===================================================================

(defun compute-team-member-position (arrangement cx cy cz radius count idx role)
  "Compute the target position for a team member based on arrangement.
   ARRANGEMENT is :star, :line, :chain, :circle, or :two-tier.
   CX/CY/CZ is the team center, RADIUS is the spread distance.
   COUNT is total members, IDX is this member's index.
   ROLE is :leader or :member.
   Returns (VALUES target-x target-y target-z)."
  (case arrangement
    ;; Star: leader at center, workers orbit around
    (:star
     (if (eq role :leader)
         (values cx cy cz)
         (let* ((angle (coerce (* idx (/ (* 2.0 pi) (max 1 (1- count)))) 'single-float))
                (target-x (+ cx (* radius (cos angle))))
                (target-z (+ cz (* radius (sin angle)))))
           (values (coerce target-x 'single-float)
                   cy
                   (coerce target-z 'single-float)))))
    ;; Line: horizontal spread
    (:line
     (let* ((spacing (if (> count 1) (/ (* 2.0 radius) (1- count)) 0.0))
            (offset (- (* idx spacing) radius)))
       (values (coerce (+ cx offset) 'single-float)
               cy
               cz)))
    ;; Chain: vertical pipeline with spacing
    (:chain
     (let* ((spacing (if (> count 1) (/ (* 2.0 radius) (1- count)) 0.0))
            (offset (- (* idx spacing) radius)))
       (values cx
               cy
               (coerce (+ cz offset) 'single-float))))
    ;; Circle: equal spacing around circumference
    (:circle
     (let* ((angle (coerce (* idx (/ (* 2.0 pi) (max 1 count))) 'single-float))
            (target-x (+ cx (* radius (cos angle))))
            (target-z (+ cz (* radius (sin angle)))))
       (values (coerce target-x 'single-float)
               cy
               (coerce target-z 'single-float))))
    ;; Two-tier: leader on top, workers on bottom ring
    (:two-tier
     (if (eq role :leader)
         (values cx
                 (coerce (+ cy (* radius 0.5)) 'single-float)
                 cz)
         (let* ((worker-count (max 1 (1- count)))
                (angle (coerce (* (max 0 (1- idx)) (/ (* 2.0 pi) worker-count)) 'single-float))
                (target-x (+ cx (* radius (cos angle))))
                (target-z (+ cz (* radius (sin angle)))))
           (values (coerce target-x 'single-float)
                   (coerce (- cy (* radius 0.3)) 'single-float)
                   (coerce target-z 'single-float)))))
    ;; Default: circle
    (otherwise
     (let* ((angle (coerce (* idx (/ (* 2.0 pi) (max 1 count))) 'single-float))
            (target-x (+ cx (* radius (cos angle))))
            (target-z (+ cz (* radius (sin angle)))))
       (values (coerce target-x 'single-float)
               cy
               (coerce target-z 'single-float))))))
