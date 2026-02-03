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
  (declare (ignore ui key))
  nil)

(defmethod refresh-display ((ui terminal-ui))
  (clear-screen)
  (when (ui-timeline ui)
    (render-timeline (ui-timeline ui)))
  (render-status-bar ui)
  (force-output))

(defun run-terminal-ui (ui)
  (setf (ui-running-p ui) t)
  (with-terminal
    (setf (status-bar-message ui) "Autopoiesis 2D Timeline Visualization")
    (loop while (ui-running-p ui)
          do (sleep 0.1)
             (update ui)
             (refresh-display ui))))

(defun stop-terminal-ui (ui)
  (setf (ui-running-p ui) nil))