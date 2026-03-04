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
            :documentation "Global opacity multiplier applied to all panels.")
   (timeline-scrubber :initform nil
                      :accessor hud-timeline-scrubber-slot
                      :documentation "Timeline scrubber data object, or NIL if not set."))
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
  "Update the timeline scrubber panel with snapshot navigation info.
   Also populates the timeline scrubber bar data for visual rendering."
  (let ((panel (hud-panel hud :timeline)))
    (when panel
      ;; Clear text content — the scrubber renders its own label
      (setf (panel-content panel) nil)))
  ;; Update the scrubber data
  (update-timeline-scrubber hud
                            :total-snapshots total-snapshots
                            :current-index current-index
                            :branch-count branch-count))

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
    ;; Update agent panel from focused agent entity or persistent agent
    (let ((agent-entity (find-focused-agent-entity))
          (persistent-entity (find-selected-persistent-entity)))
      (cond
        ;; Persistent agent takes priority when selected
        (persistent-entity
         (update-persistent-agent-panel hud persistent-entity))
        ;; Fall back to live agent binding
        (agent-entity
         (update-agent-panel hud
                             :agent-name (agent-binding-agent-name agent-entity)
                             :agent-status "active"
                             :agent-task nil))
        (t
         (update-agent-panel hud :agent-name nil))))
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
;;; HUD Render Constants
;;; ===================================================================

(defparameter *hud-border-color* '(0.3 0.6 1.0 0.8)
  "Default RGBA color for HUD panel borders (holographic blue).")

(defparameter *hud-border-glow-color* '(0.4 0.7 1.0 0.4)
  "RGBA color for the outer glow around HUD panel borders.")

(defparameter *hud-title-color* '(0.5 0.8 1.0 1.0)
  "RGBA color for panel title text.")

(defparameter *hud-text-color* '(0.8 0.9 1.0 1.0)
  "Default RGBA color for panel content text.")

(defparameter *hud-bg-color* '(0.02 0.03 0.08)
  "RGB base color for panel backgrounds (deep blue-black).")

(defparameter *hud-corner-size* 8
  "Size in pixels of decorative corner brackets on panels.")

(defparameter *hud-title-height* 22
  "Height in pixels of the title bar area within a panel.")

(defparameter *hud-line-height* 18
  "Vertical spacing in pixels between content text lines.")

(defparameter *hud-text-padding* 10
  "Horizontal padding in pixels for text within a panel.")

(defparameter *hud-border-width* 1.0
  "Width in pixels for panel border lines.")

(defparameter *hud-glow-width* 3.0
  "Width in pixels for the outer glow border effect.")

;;; ===================================================================
;;; Border Geometry Generation
;;; ===================================================================

(defun make-border-segments (x y width height corner-size)
  "Generate line segments for a panel border with decorative corners.
   Returns a list of segment plists, each with :x1 :y1 :x2 :y2.
   The border has corner brackets (L-shaped pieces) at each corner
   and continuous edges between them."
  (let ((cs corner-size)
        (right (+ x width))
        (bottom (+ y height)))
    (list
     ;; Top-left corner (two segments forming an L)
     (list :x1 x :y1 (+ y cs) :x2 x :y2 y)
     (list :x1 x :y1 y :x2 (+ x cs) :y2 y)
     ;; Top edge (between corners)
     (list :x1 (+ x cs) :y1 y :x2 (- right cs) :y2 y)
     ;; Top-right corner
     (list :x1 (- right cs) :y1 y :x2 right :y2 y)
     (list :x1 right :y1 y :x2 right :y2 (+ y cs))
     ;; Right edge
     (list :x1 right :y1 (+ y cs) :x2 right :y2 (- bottom cs))
     ;; Bottom-right corner
     (list :x1 right :y1 (- bottom cs) :x2 right :y2 bottom)
     (list :x1 right :y1 bottom :x2 (- right cs) :y2 bottom)
     ;; Bottom edge
     (list :x1 (- right cs) :y1 bottom :x2 (+ x cs) :y2 bottom)
     ;; Bottom-left corner
     (list :x1 (+ x cs) :y1 bottom :x2 x :y2 bottom)
     (list :x1 x :y1 bottom :x2 x :y2 (- bottom cs))
     ;; Left edge
     (list :x1 x :y1 (- bottom cs) :x2 x :y2 (+ y cs)))))

(defun make-corner-brackets (x y width height corner-size)
  "Generate only the corner bracket segments (no connecting edges).
   Returns a list of segment plists for the four L-shaped corners."
  (let ((cs corner-size)
        (right (+ x width))
        (bottom (+ y height)))
    (list
     ;; Top-left
     (list :x1 x :y1 (+ y cs) :x2 x :y2 y)
     (list :x1 x :y1 y :x2 (+ x cs) :y2 y)
     ;; Top-right
     (list :x1 (- right cs) :y1 y :x2 right :y2 y)
     (list :x1 right :y1 y :x2 right :y2 (+ y cs))
     ;; Bottom-right
     (list :x1 right :y1 (- bottom cs) :x2 right :y2 bottom)
     (list :x1 right :y1 bottom :x2 (- right cs) :y2 bottom)
     ;; Bottom-left
     (list :x1 (+ x cs) :y1 bottom :x2 x :y2 bottom)
     (list :x1 x :y1 bottom :x2 x :y2 (- bottom cs)))))

;;; ===================================================================
;;; Text Layout
;;; ===================================================================

(defun layout-panel-text (panel-desc)
  "Compute positioned text render commands for a panel description.
   Returns a list of text command plists with :text :x :y :color :size.
   Title is rendered in the title area; content lines below with padding."
  (let ((x (getf panel-desc :x))
        (y (getf panel-desc :y))
        (title (getf panel-desc :title))
        (lines (getf panel-desc :lines))
        (text-color (getf panel-desc :text-color))
        (padding *hud-text-padding*)
        (commands nil)
        (current-y 0))
    ;; Title text (rendered in title bar area if present)
    (when title
      (push (list :text title
                  :x (+ x padding)
                  :y (+ y padding 2)
                  :color *hud-title-color*
                  :size 13
                  :style :bold)
            commands)
      (setf current-y (+ *hud-title-height* 4)))
    ;; Content lines
    (when (null title)
      (setf current-y padding))
    (dolist (line lines)
      (when line
        (push (list :text line
                    :x (+ x padding)
                    :y (+ y current-y)
                    :color text-color
                    :size 12
                    :style :normal)
              commands))
      (incf current-y *hud-line-height*))
    (nreverse commands)))

;;; ===================================================================
;;; Panel Render Command Generation
;;; ===================================================================

(defun render-panel-commands (panel-desc)
  "Generate a list of render commands for a single panel description.
   Each command is a plist with :type indicating the primitive:
     :fill-rect  - Background fill with transparency
     :line       - Border line segment
     :text       - Text string at position
     :title-bar  - Title separator line

   Returns the list of commands in back-to-front draw order."
  (let ((x (getf panel-desc :x))
        (y (getf panel-desc :y))
        (w (getf panel-desc :width))
        (h (getf panel-desc :height))
        (alpha (getf panel-desc :alpha))
        (title (getf panel-desc :title))
        (commands nil))
    ;; 1. Background fill (drawn first)
    (push (list :type :fill-rect
                :x x :y y :width w :height h
                :color (list (first *hud-bg-color*)
                             (second *hud-bg-color*)
                             (third *hud-bg-color*)
                             alpha))
          commands)
    ;; 2. Outer glow border (wider, dimmer)
    (let ((glow-segs (make-border-segments x y w h *hud-corner-size*))
          (glow-color (let ((gc (copy-list *hud-border-glow-color*)))
                        (setf (fourth gc) (* (fourth gc) alpha))
                        gc)))
      (dolist (seg glow-segs)
        (push (list :type :line
                    :x1 (getf seg :x1) :y1 (getf seg :y1)
                    :x2 (getf seg :x2) :y2 (getf seg :y2)
                    :color glow-color
                    :width *hud-glow-width*)
              commands)))
    ;; 3. Inner border (sharp, brighter)
    (let ((border-segs (make-border-segments x y w h *hud-corner-size*))
          (border-color (let ((bc (copy-list *hud-border-color*)))
                          (setf (fourth bc) (* (fourth bc) alpha))
                          bc)))
      (dolist (seg border-segs)
        (push (list :type :line
                    :x1 (getf seg :x1) :y1 (getf seg :y1)
                    :x2 (getf seg :x2) :y2 (getf seg :y2)
                    :color border-color
                    :width *hud-border-width*)
              commands)))
    ;; 4. Corner brackets (highlighted, on top of edges)
    (let ((corners (make-corner-brackets x y w h *hud-corner-size*))
          (corner-color (list 0.5 0.8 1.0 (* 1.0 alpha))))
      (dolist (seg corners)
        (push (list :type :line
                    :x1 (getf seg :x1) :y1 (getf seg :y1)
                    :x2 (getf seg :x2) :y2 (getf seg :y2)
                    :color corner-color
                    :width 2.0)
              commands)))
    ;; 5. Title separator line (if title present)
    (when title
      (let ((sep-y (+ y *hud-title-height*)))
        (push (list :type :title-bar
                    :x1 (+ x *hud-text-padding*) :y1 sep-y
                    :x2 (+ x (- w *hud-text-padding*)) :y2 sep-y
                    :color (let ((bc (copy-list *hud-border-color*)))
                             (setf (fourth bc) (* (fourth bc) alpha 0.5))
                             bc)
                    :width 1.0)
              commands)))
    ;; 6. Text
    (dolist (txt-cmd (layout-panel-text panel-desc))
      ;; Apply alpha to text color
      (let ((tc (copy-list (getf txt-cmd :color))))
        (when (fourth tc)
          (setf (fourth tc) (* (fourth tc) alpha)))
        (push (list :type :text
                    :text (getf txt-cmd :text)
                    :x (getf txt-cmd :x)
                    :y (getf txt-cmd :y)
                    :color tc
                    :size (getf txt-cmd :size)
                    :style (getf txt-cmd :style))
              commands)))
    (nreverse commands)))

;;; ===================================================================
;;; Main render-hud Function
;;; ===================================================================

(defun render-hud (hud)
  "Render the HUD overlay by producing a complete list of draw commands.
   Returns a plist with:
     :visible-p  - Whether the HUD is visible at all
     :commands   - Ordered list of draw command plists (back to front)
     :panel-count - Number of panels rendered

   Each command in :commands has a :type key indicating the primitive:
     :fill-rect  - Filled rectangle (:x :y :width :height :color)
     :line       - Line segment (:x1 :y1 :x2 :y2 :color :width)
     :text       - Text string (:text :x :y :color :size :style)
     :title-bar  - Title separator (:x1 :y1 :x2 :y2 :color :width)

   All coordinates are in screen pixels.  Colors are (R G B A) with
   transparency already factored in.  Draw commands are ordered
   back-to-front for correct transparency compositing.

   If the HUD is not visible, returns a plist with :visible-p NIL
   and empty :commands."
  (unless (hud-visible-p hud)
    (return-from render-hud
      (list :visible-p nil :commands nil :panel-count 0)))
  (let ((panel-descs (collect-hud-render-descriptions hud))
        (all-commands nil)
        (panel-count 0))
    (dolist (desc panel-descs)
      (let ((cmds (render-panel-commands desc)))
        (setf all-commands (nconc all-commands cmds))
        (incf panel-count)))
    ;; Append timeline scrubber commands if scrubber data exists
    (let ((scrubber (hud-timeline-scrubber hud))
          (timeline-panel (hud-panel hud :timeline)))
      (when (and scrubber timeline-panel (panel-visible-p timeline-panel))
        (let ((scrubber-cmds (render-scrubber-commands
                              scrubber timeline-panel (hud-opacity hud))))
          (setf all-commands (nconc all-commands scrubber-cmds)))))
    (list :visible-p t
          :commands all-commands
          :panel-count panel-count)))

;;; ===================================================================
;;; Utility
;;; ===================================================================

(defun truncate-id (string max-length)
  "Truncate STRING to MAX-LENGTH characters, appending ellipsis if needed."
  (if (> (length string) max-length)
      (concatenate 'string (subseq string 0 (max 0 (- max-length 1))) "~")
      string))

;;; ===================================================================
;;; Timeline Scrubber
;;; ===================================================================
;;;
;;; The timeline scrubber renders a visual bar at the bottom of the HUD
;;; showing snapshot positions along a track, a current-position
;;; indicator, and branch-colored markers.  It is associated with the
;;; :timeline panel and produces additional render commands beyond the
;;; panel's basic chrome.

(defclass timeline-scrubber ()
  ((total-snapshots :initarg :total-snapshots
                    :accessor scrubber-total-snapshots
                    :initform 0
                    :documentation "Total number of snapshots in the timeline.")
   (current-index :initarg :current-index
                  :accessor scrubber-current-index
                  :initform 0
                  :documentation "1-based index of the currently selected snapshot.")
   (branch-count :initarg :branch-count
                 :accessor scrubber-branch-count
                 :initform 1
                 :documentation "Number of distinct branches.")
   (snapshot-entries :initarg :snapshot-entries
                     :accessor scrubber-snapshot-entries
                     :initform nil
                     :documentation "List of scrubber-entry plists for each snapshot.
                      Each entry is (:index N :type KEYWORD :selected-p BOOL)."))
  (:documentation
   "Data model for the timeline scrubber bar.
    Holds the state needed to render snapshot markers along a track
    with a current-position highlight."))

(defun make-timeline-scrubber (&key (total-snapshots 0)
                                     (current-index 0)
                                     (branch-count 1)
                                     (snapshot-entries nil))
  "Create a new timeline-scrubber instance."
  (make-instance 'timeline-scrubber
                 :total-snapshots total-snapshots
                 :current-index current-index
                 :branch-count branch-count
                 :snapshot-entries snapshot-entries))

;;; --- Scrubber Render Constants ---

(defparameter *scrubber-track-color* '(0.2 0.4 0.7 0.6)
  "RGBA color for the scrubber track line.")

(defparameter *scrubber-marker-color* '(0.3 0.6 1.0 0.8)
  "Default RGBA color for snapshot markers on the track.")

(defparameter *scrubber-current-color* '(0.6 1.0 0.8 1.0)
  "RGBA color for the current-position indicator.")

(defparameter *scrubber-track-height* 2
  "Height in pixels of the scrubber track line.")

(defparameter *scrubber-marker-radius* 3
  "Radius in pixels of snapshot markers on the track.")

(defparameter *scrubber-current-radius* 5
  "Radius in pixels of the current-position indicator.")

(defparameter *scrubber-track-margin* 15
  "Horizontal margin in pixels from panel edges to track ends.")

(defparameter *scrubber-track-y-offset* 30
  "Vertical offset in pixels from panel top to the track center.")

;;; --- Scrubber Render Commands ---

(defun scrubber-track-x-range (panel)
  "Compute the (start-x . end-x) pixel range for the scrubber track
   within PANEL, accounting for margins."
  (let ((start (+ (panel-x panel) *scrubber-track-margin*))
        (end (- (+ (panel-x panel) (panel-width panel))
                *scrubber-track-margin*)))
    (cons start end)))

(defun scrubber-index-to-x (index total start-x end-x)
  "Map a 1-based snapshot INDEX (out of TOTAL) to an x-pixel position
   along the scrubber track from START-X to END-X."
  (if (or (<= total 0) (<= index 0))
      start-x
      (let ((fraction (/ (1- (min index total))
                         (max 1 (1- total)))))
        (+ start-x (* fraction (- end-x start-x))))))

(defun render-scrubber-commands (scrubber panel &optional (global-alpha 1.0))
  "Generate render commands for the timeline scrubber visual elements.
   Returns a list of command plists to be appended to the panel's commands.

   Commands generated:
     :scrubber-track   - The horizontal track line
     :scrubber-marker  - A snapshot marker dot
     :scrubber-current - The current-position indicator (larger, highlighted)
     :text             - Count label text

   PANEL provides position/dimensions.  GLOBAL-ALPHA scales all alphas."
  (let* ((x-range (scrubber-track-x-range panel))
         (start-x (car x-range))
         (end-x (cdr x-range))
         (track-y (+ (panel-y panel) *scrubber-track-y-offset*))
         (total (scrubber-total-snapshots scrubber))
         (current (scrubber-current-index scrubber))
         (commands nil))
    ;; 1. Track line (horizontal bar)
    (let ((tc (copy-list *scrubber-track-color*)))
      (when (fourth tc)
        (setf (fourth tc) (* (fourth tc) global-alpha)))
      (push (list :type :scrubber-track
                  :x1 start-x :y1 track-y
                  :x2 end-x :y2 track-y
                  :color tc
                  :width *scrubber-track-height*)
            commands))
    ;; 2. Snapshot markers along track
    (dolist (entry (scrubber-snapshot-entries scrubber))
      (let* ((idx (getf entry :index))
             (selected-p (getf entry :selected-p))
             (mx (scrubber-index-to-x idx total start-x end-x))
             (mc (if selected-p
                     (copy-list *scrubber-current-color*)
                     (copy-list *scrubber-marker-color*)))
             (radius (if selected-p
                         *scrubber-current-radius*
                         *scrubber-marker-radius*)))
        (when (fourth mc)
          (setf (fourth mc) (* (fourth mc) global-alpha)))
        (push (list :type :scrubber-marker
                    :cx mx :cy track-y
                    :radius radius
                    :color mc
                    :selected-p selected-p)
              commands)))
    ;; 3. Current position indicator (even if not in entries)
    (when (and (> total 0) (> current 0))
      (let ((cx (scrubber-index-to-x current total start-x end-x))
            (cc (copy-list *scrubber-current-color*)))
        (when (fourth cc)
          (setf (fourth cc) (* (fourth cc) global-alpha)))
        (push (list :type :scrubber-current
                    :cx cx :cy track-y
                    :radius *scrubber-current-radius*
                    :color cc)
              commands)))
    ;; 4. Text label: "N/M snapshots  B branches"
    (let ((label (format nil "~D/~D snapshots  ~D branch~:P"
                         (or current 0) (or total 0)
                         (or (scrubber-branch-count scrubber) 1)))
          (tc (copy-list *hud-text-color*)))
      (when (fourth tc)
        (setf (fourth tc) (* (fourth tc) global-alpha)))
      (push (list :type :text
                  :text label
                  :x (+ (panel-x panel) *hud-text-padding*)
                  :y (+ (panel-y panel) *scrubber-track-y-offset*
                        *scrubber-current-radius* 8)
                  :color tc
                  :size 11
                  :style :normal)
            commands))
    (nreverse commands)))

;;; --- Scrubber Integration with HUD ---

(defun build-scrubber-entries (total current)
  "Build a list of scrubber entry plists for TOTAL snapshots with
   CURRENT as the 1-based selected index."
  (loop for i from 1 to total
        collect (list :index i
                      :type :snapshot
                      :selected-p (= i current))))

(defun update-timeline-scrubber (hud &key total-snapshots current-index branch-count)
  "Update (or create) the timeline scrubber state on the HUD's :timeline panel.
   Stores a timeline-scrubber instance in the HUD's dedicated slot."
  (let ((scrubber (make-timeline-scrubber
                   :total-snapshots (or total-snapshots 0)
                   :current-index (or current-index 0)
                   :branch-count (or branch-count 1)
                   :snapshot-entries (build-scrubber-entries
                                     (or total-snapshots 0)
                                     (or current-index 0)))))
    ;; Store scrubber in the dedicated HUD slot
    (setf (hud-timeline-scrubber-slot hud) scrubber)
    scrubber))

(defun hud-timeline-scrubber (hud)
  "Retrieve the timeline-scrubber object from HUD, or NIL if not set."
  (hud-timeline-scrubber-slot hud))

;;; ===================================================================
;;; Persistent Agent HUD Panel
;;; ===================================================================

(defun find-selected-persistent-entity ()
  "Find the first selected entity that has a persistent-root component.
   Returns the entity ID or NIL."
  (dolist (entity *snapshot-entities*)
    (when (and (entity-valid-p entity)
               (interactive-selected-p entity)
               (gethash entity *persistent-root-table*))
      (return entity))))

(defun update-persistent-agent-panel (hud entity-id)
  "Update the agent HUD panel with persistent agent information.
   Shows agent name, version, generation, thought count, capability count,
   and cognitive phase."
  (let ((panel (hud-panel hud :agent))
        (agent (gethash entity-id *persistent-root-table*)))
    (when (and panel agent)
      (setf (panel-visible-p panel) t)
      (setf (panel-content panel)
            (list (format nil "Agent: ~A"
                          (autopoiesis.agent::persistent-agent-name agent))
                  (format nil "Version: ~D"
                          (autopoiesis.agent::persistent-agent-version agent))
                  (format nil "Generation: ~D"
                          (lineage-binding-generation entity-id))
                  (format nil "Thoughts: ~D"
                          (cognitive-state-thought-count entity-id))
                  (format nil "Capabilities: ~D"
                          (genome-state-capability-count entity-id))
                  (format nil "Phase: ~A"
                          (cognitive-state-phase entity-id)))))))
