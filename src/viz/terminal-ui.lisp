(in-package #:autopoiesis.viz)

(defclass terminal-ui ()
  ((timeline :initarg :timeline :accessor ui-timeline :initform nil
             :documentation "Timeline data for visualization.")
   (navigator :initarg :navigator :accessor ui-navigator :initform nil
              :documentation "Navigator for cursor movement.")
   (detail-panel :initarg :detail-panel :accessor ui-detail-panel :initform nil
                 :documentation "Detail panel for selected snapshot.")
   (session :initarg :session :accessor ui-session :initform nil
            :documentation "Associated interface session, if launched from one.")
   (terminal-width :accessor ui-terminal-width :initform 0
                   :documentation "Detected terminal width.")
   (terminal-height :accessor ui-terminal-height :initform 0
                    :documentation "Detected terminal height.")
   (needs-resize-p :accessor ui-needs-resize-p :initform nil
                   :documentation "Flag set when terminal dimensions have changed.")
   (status-message :accessor status-bar-message :initform ""
                   :documentation "Current status message for bottom status bar.")
   (running-p :accessor ui-running-p :initform nil
              :documentation "Whether the UI main loop is running."))
  (:documentation "Main terminal UI class managing screen layout, input, and rendering."))

(defun make-terminal-ui (&key timeline navigator detail-panel session)
  "Create and initialize a terminal UI instance.
   If SESSION is provided, links the UI back to the interface session."
  (let* ((tl (or timeline (make-timeline)))
         (ui (make-instance 'terminal-ui)))
    (setf (ui-timeline ui) tl
          (ui-navigator ui) (or navigator (make-timeline-navigator :timeline tl))
          (ui-detail-panel ui) (or detail-panel (make-detail-panel))
          (ui-session ui) session)
    (update ui)
    ;; Perform initial layout based on detected terminal size
    (handle-resize ui)
    ui))

(defun available-branches (ui)
  "Return sorted list of available branch names."
  (let ((branches nil))
    (maphash (lambda (name _) (push name branches)) (timeline-branches (ui-timeline ui)))
    (sort branches #'string<)))

(defun branch-head-snapshot (ui branch-name)
  "Get head snapshot for BRANCH-NAME."
  (let ((snap-ids (gethash branch-name (timeline-branches (ui-timeline ui)))))
    (when snap-ids
      (find-snapshot (ui-timeline ui) (car (last snap-ids))))))

(defun switch-to-branch (ui branch-name)
  "Switch to head of BRANCH-NAME."
  (let ((head-snap (branch-head-snapshot ui branch-name)))
    (when head-snap
      (jump-to-snapshot (ui-navigator ui) (snapshot-id head-snap))
      (setf (status-bar-message ui) (format nil "Switched to branch ~A" branch-name)))))

(defmethod update ((ui terminal-ui))
  "Update UI state: detect terminal size changes and adjust layout."
  (let ((old-w (ui-terminal-width ui))
        (old-h (ui-terminal-height ui)))
    (multiple-value-bind (w h)
        (get-terminal-size)
      (setf (ui-terminal-width ui) w
            (ui-terminal-height ui) h)
      (when (and (or (/= old-w w) (/= old-h h))
                 (not (and (zerop old-w) (zerop old-h))))
        (setf (ui-needs-resize-p ui) t))))
  nil)

(defgeneric handle-resize (ui)
  (:documentation "Handle terminal resize by adjusting viewport and panel dimensions."))

(defmethod handle-resize ((ui terminal-ui))
  "Adjust viewport and panel dimensions to match new terminal size."
  (let* ((w (ui-terminal-width ui))
         (h (ui-terminal-height ui))
         (status-height (getf (config-dimensions) :status-bar-height 3))
         (border-pad (getf (config-dimensions) :border-padding 1))
         (detail-width (min (getf (config-dimensions) :detail-panel-width 40)
                            (max 20 (floor w 3))))
         (timeline-width (- w detail-width (* border-pad 2)))
         (timeline-height (- h status-height (* border-pad 2))))
    ;; Adjust timeline viewport
    (when (ui-timeline ui)
      (let ((vp (timeline-viewport (ui-timeline ui))))
        (setf (viewport-width vp) (max 10 timeline-width)
              (viewport-height vp) (max 5 timeline-height))))
    ;; Adjust detail panel dimensions
    (when (ui-detail-panel ui)
      (setf (panel-width (ui-detail-panel ui)) (max 20 detail-width)
            (panel-height (ui-detail-panel ui)) (max 5 (- h status-height 2)))))
  (setf (ui-needs-resize-p ui) nil))

(defun render-status-bar (ui)
  "Render the bottom status bar with current position, branch name, status message, and help hints."
  (let* ((height (ui-terminal-height ui))
         (width (ui-terminal-width ui))
         (row (- height 3 1))
         (cursor-pos (navigator-cursor (ui-navigator ui)))
         (current-snap (current-snapshot-at-cursor (ui-navigator ui)))
         (branch (if current-snap
                     (getf (snapshot-metadata current-snap) :branch "main")
                     "main"))
         (msg (status-bar-message ui)))
    (draw-box row 1 width 3)
    (move-cursor (+ row 1) 3)
    (princ (format nil "Pos: ~D  Branch: ~A  ~A" cursor-pos branch msg))
    (move-cursor (+ row 2) 3)
    (set-color +color-dim+)
    (princ "h j k l navigate  ↑↓ branches  Enter select  / search  q quit  ? help")
    (reset-color)
    (force-output)))

(defmethod handle-input ((ui terminal-ui) key)
  (cond
    ((char= key #\h)
     (when (cursor-left (ui-navigator ui))
       (setf (status-bar-message ui) "Moved left")))
    ((char= key #\l)
     (when (cursor-right (ui-navigator ui))
       (setf (status-bar-message ui) "Moved right")))
    ((char= key #\k)
     (when (cursor-up-branch (ui-navigator ui))
       (setf (status-bar-message ui) "Moved up branch")))
    ((char= key #\j)
     (when (cursor-down-branch (ui-navigator ui))
       (setf (status-bar-message ui) "Moved down branch")))
    ((char= key #\q)
     (setf (status-bar-message ui) "Quitting...")
     (stop-terminal-ui ui)
     t)
    ((char= key #\/)
     (setf (status-bar-message ui) "Search mode (not implemented)"))
    ((char= key #\Tab)
     (let* ((branches (available-branches ui))
            (curr-snap (current-snapshot-at-cursor (ui-navigator ui)))
            (curr-branch (if curr-snap (snapshot-branch curr-snap) "main"))
            (curr-idx (position curr-branch branches :test #'string-equal))
            (next-idx (mod (1+ (or curr-idx 0)) (length branches)))
            (next-branch (elt branches next-idx)))
       (switch-to-branch ui next-branch)))
    ((and (char<= #\1 key) (char<= key #\9))
     (let* ((branches (available-branches ui))
            (idx (- (char-code key) (char-code #\1)))
            (branch (when (< idx (length branches)) (elt branches idx))))
       (when branch
         (switch-to-branch ui branch))))
    ((char= key #\Return)
     (setf (status-bar-message ui) "Snapshot selected"))
    (t nil)))

(defmethod refresh-display ((ui terminal-ui))
  ;; Handle pending resize before rendering
  (when (ui-needs-resize-p ui)
    (handle-resize ui))
  (clear-screen)
  (when (ui-timeline ui)
    (render-timeline (ui-timeline ui)))

  ;; Render detail panel if current snapshot
  (let ((snap (current-snapshot-at-cursor (ui-navigator ui))))
    (when snap
      (setf (panel-content (ui-detail-panel ui)) (render-snapshot-summary snap))
      (let ((detail-col (+ (viewport-width (timeline-viewport (ui-timeline ui))) 2)))
        (render-detail-panel (ui-detail-panel ui)
                             detail-col
                             2))))

  (render-status-bar ui)
  (force-output))

(defun run-terminal-ui (ui)
  (setf (ui-running-p ui) t)
  (with-terminal
    (setf (status-bar-message ui) "Autopoiesis 2D Timeline Visualization")
    (loop while (ui-running-p ui) do
       (let ((key (read-char)))
         (handle-input ui key))
       (update ui)
        (refresh-display ui)
        )))

(defun stop-terminal-ui (ui)
  (setf (ui-running-p ui) nil))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Integration
;;; ═══════════════════════════════════════════════════════════════════

(defun session-to-timeline (session)
  "Build a timeline from an interface SESSION's agent thought stream.
   Each thought becomes a snapshot in the timeline, enabling visualization
   of the agent's cognitive history."
  (let* ((agent (autopoiesis.interface:session-agent session))
         (ts (autopoiesis.agent:agent-thought-stream agent))
         (thoughts (autopoiesis.core:stream-thoughts ts))
         (snapshots nil)
         (prev-id nil))
    ;; Convert each thought to a snapshot for timeline display
    (loop for thought across thoughts
          for i from 0
          for snap = (make-instance 'autopoiesis.snapshot:snapshot
                       :id (autopoiesis.core:thought-id thought)
                       :timestamp (autopoiesis.core:thought-timestamp thought)
                       :parent prev-id
                       :agent-state (autopoiesis.core:thought-content thought)
                       :metadata (list :type (autopoiesis.core:thought-type thought)
                                       :branch "main"))
          do (push snap snapshots)
             (setf prev-id (autopoiesis.core:thought-id thought)))
    (let* ((snaps (nreverse snapshots))
           (timeline (make-timeline
                      :snapshots snaps
                      :current (when prev-id prev-id))))
      ;; Set up the main branch
      (setf (gethash "main" (timeline-branches timeline))
            (mapcar #'autopoiesis.snapshot:snapshot-id snaps))
      timeline)))

(defun launch-session-viz (session)
  "Launch the terminal visualization UI for an interface SESSION.
   Builds a timeline from the session's agent thought stream and runs
   the interactive terminal UI. Returns the UI instance when done."
  (let* ((timeline (session-to-timeline session))
         (navigator (make-timeline-navigator :timeline timeline))
         (ui (make-terminal-ui :timeline timeline
                               :navigator navigator
                               :session session)))
    (run-terminal-ui ui)
    ui))