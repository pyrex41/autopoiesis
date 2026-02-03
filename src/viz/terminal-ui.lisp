(in-package #:autopoiesis.viz)

(defclass terminal-ui ()
  ((timeline :initarg :timeline :accessor ui-timeline :initform nil
             :documentation "Timeline data for visualization.")
   (navigator :initarg :navigator :accessor ui-navigator :initform nil
              :documentation "Navigator for cursor movement.")
   (detail-panel :initarg :detail-panel :accessor ui-detail-panel :initform nil
                 :documentation "Detail panel for selected snapshot.")
   (terminal-width :accessor ui-terminal-width :initform 0
                   :documentation "Detected terminal width.")
   (terminal-height :accessor ui-terminal-height :initform 0
                    :documentation "Detected terminal height.")
   (status-message :accessor status-bar-message :initform ""
                   :documentation "Current status message for bottom status bar.")
   (running-p :accessor ui-running-p :initform nil
              :documentation "Whether the UI main loop is running."))
  (:documentation "Main terminal UI class managing screen layout, input, and rendering."))

(defun make-terminal-ui (&key timeline navigator detail-panel)
  "Create and initialize a terminal UI instance."
  (let ((ui (make-instance 'terminal-ui)))
    (setf (ui-timeline ui) (or timeline (make-timeline))
          (ui-navigator ui) (or navigator (make-timeline-navigator))
          (ui-detail-panel ui) (or detail-panel (make-detail-panel)))
    (update ui)
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
  "Update UI state: terminal size, sync navigator with timeline, etc."
  (multiple-value-bind (w h)
      (get-terminal-size)
    (setf (ui-terminal-width ui) w
          (ui-terminal-height ui) h))
  nil)

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
  (clear-screen)
  (when (ui-timeline ui)
    (render-timeline (ui-timeline ui)))

  ;; Render detail panel if current snapshot
  (let ((snap (current-snapshot-at-cursor (ui-navigator ui))))
    (when snap
      (setf (panel-content (ui-detail-panel ui)) (render-snapshot-summary snap))
      (render-detail-panel (ui-detail-panel ui)
                           (+ (getf (config-dimensions) :timeline-width 80) 2)
                           2)))

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