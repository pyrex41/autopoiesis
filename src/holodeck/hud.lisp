;;;; hud.lisp - Heads-up display panel system
;;;;
;;;; Implements the HUD overlay for the 3D holodeck visualization.
;;;; The HUD provides four standard panels: position info (top-left),
;;;; agent status (top-right), timeline scrubber (bottom), and action
;;;; hints (bottom-right).  Each panel has position, dimensions,
;;;; content lines, visibility, and transparency.
;;;;
;;;; The HUD is a data-only layer.  Actual rendering to screen is
;;;; delegated to whatever rendering backend is available (Trial/OpenGL
;;;; or a headless stub).  The public API produces render descriptions
;;;; that backends consume.
;;;;
;;;; Phase 8.4 - HUD System (first task)

(in-package #:autopoiesis.holodeck)

;;; ===================================================================
;;; HUD Panel Class
;;; ===================================================================

(defclass hud-panel ()
  ((x :initarg :x
      :accessor panel-x
      :initform 0
      :documentation "X position of the panel in screen pixels.")
   (y :initarg :y
      :accessor panel-y
      :initform 0
      :documentation "Y position of the panel in screen pixels.")
   (width :initarg :width
          :accessor panel-width
          :initform 200
          :documentation "Width of the panel in pixels.")
   (height :initarg :height
           :accessor panel-height
           :initform 100
           :documentation "Height of the panel in pixels.")
   (title :initarg :title
          :accessor panel-title
          :initform nil
          :documentation "Optional title string displayed at top of panel.")
   (content :initarg :content
            :accessor panel-content
            :initform nil
            :documentation "List of strings to display as panel content lines.")
   (visible-p :initarg :visible-p
              :accessor panel-visible-p
              :initform t
              :documentation "Whether this panel is currently visible.")
   (alpha :initarg :alpha
          :accessor panel-alpha
          :initform 0.7
          :documentation "Background transparency (0.0 = fully transparent, 1.0 = opaque)."))
  (:documentation
   "A rectangular overlay panel in the HUD.
    Panels have a position, dimensions, optional title, content lines,
    visibility toggle, and transparency level."))

;;; ===================================================================
;;; HUD Class
;;; ===================================================================

(defclass hud ()
  ((panels :initform (make-hash-table)
           :accessor hud-panels
           :documentation "Hash table mapping panel keyword names to hud-panel instances.")
   (visible-p :initform t
              :accessor hud-visible-p
              :documentation "Master visibility toggle for the entire HUD.")
   (opacity :initform 0.8
            :accessor hud-opacity
            :documentation "Global opacity multiplier applied to all panels."))
  (:documentation
   "Heads-up display overlay containing named panels.
    The HUD manages a collection of hud-panel instances indexed by keyword
    name.  It provides a master visibility toggle and global opacity."))

;;; ===================================================================
;;; HUD Panel Accessors
;;; ===================================================================

(defgeneric hud-panel (hud name)
  (:documentation "Retrieve the panel named NAME from HUD, or NIL if not found."))

(defmethod hud-panel ((hud hud) name)
  (gethash name (hud-panels hud)))

(defgeneric (setf hud-panel) (panel hud name)
  (:documentation "Set the panel named NAME in HUD to PANEL."))

(defmethod (setf hud-panel) ((panel hud-panel) (hud hud) name)
  (setf (gethash name (hud-panels hud)) panel))

(defun hud-panel-names (hud)
  "Return a list of panel name keywords registered in HUD."
  (let ((names nil))
    (maphash (lambda (k v) (declare (ignore v)) (push k names))
             (hud-panels hud))
    (nreverse names)))

(defun hud-panel-count (hud)
  "Return the number of panels in HUD."
  (hash-table-count (hud-panels hud)))

;;; ===================================================================
;;; HUD Construction
;;; ===================================================================

(defun make-hud (&key (window-width *window-width*)
                      (window-height *window-height*))
  "Create a HUD with the four standard panels positioned for a window
   of WINDOW-WIDTH x WINDOW-HEIGHT pixels.

   Standard panels:
     :position  - Top-left: current branch, snapshot ID, type
     :agent     - Top-right: agent name, status, current task
     :timeline  - Bottom: timeline scrubber bar
     :hints     - Bottom-right: keyboard shortcut reference"
  (let ((hud (make-instance 'hud)))
    ;; Position panel (top-left)
    (setf (hud-panel hud :position)
          (make-instance 'hud-panel
                         :x 20 :y 20
                         :width 250 :height 100
                         :title "LOCATION"))
    ;; Agent panel (top-right)
    (setf (hud-panel hud :agent)
          (make-instance 'hud-panel
                         :x (- window-width 270) :y 20
                         :width 250 :height 150
                         :title "AGENT"
                         :visible-p nil))
    ;; Timeline scrubber (bottom)
    (setf (hud-panel hud :timeline)
          (make-instance 'hud-panel
                         :x 20 :y (- window-height 80)
                         :width (- window-width 40) :height 60
                         :title nil))
    ;; Action hints (bottom-right)
    (setf (hud-panel hud :hints)
          (make-instance 'hud-panel
                         :x (- window-width 220) :y (- window-height 150)
                         :width 200 :height 130
                         :alpha 0.5
                         :content (list "[WASD] Move"
                                        "[Scroll] Zoom"
                                        "[[ ]] Step"
                                        "[F] Fork"
                                        "[Enter] Interact"
                                        "[?] Help")))
    hud))

;;; ===================================================================
;;; HUD Visibility
;;; ===================================================================

(defun toggle-hud-visibility (hud)
  "Toggle master HUD visibility on/off.  Returns the new state."
  (setf (hud-visible-p hud) (not (hud-visible-p hud))))

(defun toggle-panel-visibility (hud panel-name)
  "Toggle visibility of the panel named PANEL-NAME.  Returns the new state,
   or NIL if no such panel exists."
  (let ((panel (hud-panel hud panel-name)))
    (when panel
      (setf (panel-visible-p panel) (not (panel-visible-p panel))))))

;;; ===================================================================
;;; HUD Panel Content Updates
;;; ===================================================================

(defun update-position-panel (hud &key branch snapshot-id snapshot-type)
  "Update the position panel content with current navigation state."
  (let ((panel (hud-panel hud :position)))
    (when panel
      (setf (panel-content panel)
            (list (format nil "Branch: ~A" (or branch "—"))
                  (format nil "Snapshot: ~A"
                          (if snapshot-id
                              (truncate-id snapshot-id 20)
                              "—"))
                  (format nil "Type: ~A" (or snapshot-type "—")))))))

(defun update-agent-panel (hud &key agent-name agent-status agent-task)
  "Update the agent panel content.  Makes the panel visible if content
   is provided, hides it if AGENT-NAME is NIL."
  (let ((panel (hud-panel hud :agent)))
    (when panel
      (if agent-name
          (progn
            (setf (panel-visible-p panel) t)
            (setf (panel-content panel)
                  (list (format nil "Agent: ~A" agent-name)
                        (format nil "Status: ~A" (or agent-status "—"))
                        (format nil "Task: ~A"
                                (if agent-task
                                    (truncate-id agent-task 30)
                                    "—")))))
          (setf (panel-visible-p panel) nil)))))

(defun update-timeline-panel (hud &key total-snapshots current-index branch-count)
  "Update the timeline scrubber panel with snapshot navigation info."
  (let ((panel (hud-panel hud :timeline)))
    (when panel
      (setf (panel-content panel)
            (list (format nil "~D/~D snapshots  ~D branch~:P"
                          (or current-index 0)
                          (or total-snapshots 0)
                          (or branch-count 1)))))))

;;; ===================================================================
;;; Update HUD from Current State
;;; ===================================================================

(defun find-selected-snapshot-entity ()
  "Find the first snapshot entity with interactive selected-p set.
   Returns the entity ID or NIL."
  (dolist (entity *snapshot-entities*)
    (when (and (entity-valid-p entity)
               (interactive-selected-p entity))
      (return entity))))

(defun find-focused-agent-entity ()
  "Find the first entity with an agent-binding.
   Returns the entity ID or NIL."
  (dolist (entity *snapshot-entities*)
    (when (and (entity-valid-p entity)
               (ignore-errors (agent-binding-agent-id entity))
               (not (string= "" (agent-binding-agent-id entity))))
      (return entity))))

(defun count-unique-branches ()
  "Count distinct snapshot types among tracked snapshot entities.
   Uses snapshot-binding-snapshot-type as a proxy for branch diversity
   when no explicit branch data is available."
  (let ((types (make-hash-table)))
    (dolist (entity *snapshot-entities*)
      (when (entity-valid-p entity)
        (setf (gethash (snapshot-binding-snapshot-type entity) types) t)))
    (hash-table-count types)))

(defun selected-entity-index (entity)
  "Return the 1-based index of ENTITY in *snapshot-entities*, or 0 if not found."
  (let ((idx 0))
    (dolist (e *snapshot-entities* 0)
      (incf idx)
      (when (eql e entity)
        (return idx)))))

(defun update-hud (hud)
  "Update all HUD panels from the current holodeck state.
   Reads ECS entity data to populate the position, agent, and timeline panels.
   The hints panel has static content and is not modified.

   This function should be called once per frame (or when state changes)
   before collecting render descriptions."
  (let ((selected (find-selected-snapshot-entity)))
    ;; Update position panel from selected snapshot
    (if selected
        (update-position-panel hud
                               :branch (format nil "~A"
                                               (snapshot-binding-snapshot-type selected))
                               :snapshot-id (snapshot-binding-snapshot-id selected)
                               :snapshot-type (snapshot-binding-snapshot-type selected))
        (update-position-panel hud
                               :branch nil
                               :snapshot-id nil
                               :snapshot-type nil))
    ;; Update agent panel from focused agent entity
    (let ((agent-entity (find-focused-agent-entity)))
      (if agent-entity
          (update-agent-panel hud
                              :agent-name (agent-binding-agent-name agent-entity)
                              :agent-status "active"
                              :agent-task nil)
          (update-agent-panel hud :agent-name nil)))
    ;; Update timeline panel with snapshot counts
    (let ((total (length *snapshot-entities*))
          (current-idx (if selected (selected-entity-index selected) 0))
          (branches (count-unique-branches)))
      (update-timeline-panel hud
                             :total-snapshots total
                             :current-index current-idx
                             :branch-count branches))))

;;; ===================================================================
;;; HUD Render Descriptions
;;; ===================================================================
;;;
;;; Rather than coupling to a specific rendering API, the HUD produces
;;; render descriptions that any backend can consume.

(defun collect-visible-panels (hud)
  "Return a list of (name . panel) pairs for all currently visible panels.
   Returns NIL if the HUD itself is hidden."
  (when (hud-visible-p hud)
    (let ((result nil))
      (maphash (lambda (name panel)
                 (when (panel-visible-p panel)
                   (push (cons name panel) result)))
               (hud-panels hud))
      (nreverse result))))

(defun panel-render-description (panel &optional (global-opacity 1.0))
  "Produce a property list render description for PANEL.
   The description contains all data needed to draw the panel:
     :x :y :width :height  - screen rect
     :alpha                 - effective alpha (panel alpha * global opacity)
     :title                 - title string or NIL
     :lines                 - list of content line strings
     :border-color          - (r g b a) for panel border
     :text-color            - (r g b a) for content text
     :bg-color              - (r g b a) for background fill"
  (let ((effective-alpha (* (panel-alpha panel) global-opacity)))
    (list :x (panel-x panel)
          :y (panel-y panel)
          :width (panel-width panel)
          :height (panel-height panel)
          :alpha effective-alpha
          :title (panel-title panel)
          :lines (panel-content panel)
          :border-color (list 0.3 0.6 1.0 0.8)
          :text-color (list 0.8 0.9 1.0 1.0)
          :bg-color (list 0.0 0.0 0.0 effective-alpha))))

(defun collect-hud-render-descriptions (hud)
  "Collect render descriptions for all visible HUD panels.
   Returns a list of property lists, one per visible panel."
  (let ((visible (collect-visible-panels hud)))
    (mapcar (lambda (pair)
              (panel-render-description (cdr pair) (hud-opacity hud)))
            visible)))

;;; ===================================================================
;;; Utility
;;; ===================================================================

(defun truncate-id (string max-length)
  "Truncate STRING to MAX-LENGTH characters, appending ellipsis if needed."
  (if (> (length string) max-length)
      (concatenate 'string (subseq string 0 (max 0 (- max-length 1))) "~")
      string))
