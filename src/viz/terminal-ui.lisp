;;;; terminal-ui.lisp - Terminal UI class for Autopoiesis visualization
;;;;
;;;; Implements the main terminal UI class using cl-charms (ncurses bindings)
;;;; for interactive timeline visualization and navigation.

(in-package #:autopoiesis.viz)

;;; ═══════════════════════════════════════════════════════════════════
;;; Terminal UI Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass terminal-ui ()
  ((timeline :initarg :timeline
             :accessor ui-timeline
             :initform nil
             :documentation "Timeline object to visualize")
   (detail-panel :initarg :detail-panel
                 :accessor ui-detail-panel
                 :initform nil
                 :documentation "Detail panel for showing snapshot information")
   (status-bar :initarg :status-bar
               :accessor ui-status-bar
               :initform nil
               :documentation "Status bar showing current position and hints")
   (navigator :initarg :navigator
              :accessor ui-navigator
              :initform nil
              :documentation "Timeline navigator for cursor movement")
   (running-p :initarg :running-p
              :accessor ui-running-p
              :initform nil
              :documentation "Flag indicating if UI loop is running")
   (screen :initarg :screen
           :accessor ui-screen
           :initform nil
           :documentation "Ncurses screen object")
   (terminal-width :initarg :terminal-width
                   :accessor ui-terminal-width
                   :initform 80
                   :documentation "Terminal width in characters")
   (terminal-height :initarg :terminal-height
                    :accessor ui-terminal-height
                    :initform 24
                    :documentation "Terminal height in characters")
   (help-visible-p :initarg :help-visible-p
                   :accessor ui-help-visible-p
                   :initform nil
                   :documentation "Flag for showing help overlay"))
   (:documentation "Main terminal UI class for interactive timeline visualization"))

(defmethod print-object ((ui terminal-ui) stream)
  (print-unreadable-object (ui stream :type t)
    (format stream "~:[stopped~;running~]" (ui-running-p ui))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Constructor and Initialization
;;; ═══════════════════════════════════════════════════════════════════

(defun make-terminal-ui (&key timeline navigator)
  "Create a new terminal UI instance.
   TIMELINE: Timeline object to visualize
   NAVIGATOR: Navigator for cursor movement"
  (make-instance 'terminal-ui
                 :timeline timeline
                 :navigator navigator
                 :detail-panel (make-detail-panel)
                 :status-bar (make-hash-table :test #'equal)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Ncurses Screen Management
;;; ═══════════════════════════════════════════════════════════════════

(defmethod init-screen ((ui terminal-ui))
  "Initialize ncurses screen for the UI."
  (with-accessors ((screen ui-screen)
                   (width ui-terminal-width)
                   (height ui-terminal-height)) ui
    ;; Initialize ncurses screen
    (uiop:run-program "stty raw -echo")
    ;; Set up terminal modes
    
    
    
    
    ;; Hide cursor
    (hide-cursor)
    ;; Get terminal dimensions
    (multiple-value-bind (w h) (get-terminal-size)
      (setf width w
            height h))
    ;; Clear screen
    (clear-screen)
    (finish-output *standard-output*)))

(defmethod cleanup-screen ((ui terminal-ui))
  "Clean up ncurses screen and restore terminal state."
  (with-accessors ((screen ui-screen)) ui
    (when screen
      ;; Restore cursor
      (show-cursor)
      ;; Clear screen
      (clear-screen)
      (finish-output *standard-output*)
      ;; End ncurses
      
      (setf screen nil))))

;;; ═══════════════════════════════════════════════════════════════════
;;; UI Layout Management
;;; ═══════════════════════════════════════════════════════════════════

(defmethod calculate-layout ((ui terminal-ui))
  "Calculate the layout dimensions for UI components."
  (with-accessors ((width ui-terminal-width)
                   (height ui-terminal-height)) ui
    ;; Timeline takes most of the screen
    (let* ((timeline-height (- height 3)) ; Leave space for status bar
           (detail-width (max 40 (floor width 3))) ; Detail panel on right
           (timeline-width (- width detail-width 1))) ; Timeline on left
      (values timeline-width timeline-height detail-width))))

(defmethod get-timeline-region ((ui terminal-ui))
  "Return the screen region for the timeline (x y width height)."
  (multiple-value-bind (timeline-width timeline-height detail-width)
      (calculate-layout ui)
    (declare (ignore detail-width))
    (values 0 0 timeline-width timeline-height)))

(defmethod get-detail-region ((ui terminal-ui))
  "Return the screen region for the detail panel (x y width height)."
  (multiple-value-bind (timeline-width timeline-height detail-width)
      (calculate-layout ui)
    (let ((detail-x (+ timeline-width 1)))
      (values detail-x 0 detail-width timeline-height))))

(defmethod get-status-region ((ui terminal-ui))
  "Return the screen region for the status bar (x y width height)."
  (with-accessors ((width ui-terminal-width)
                   (height ui-terminal-height)) ui
    (values 0 (- height 2) width 2)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Rendering Methods
;;; ═══════════════════════════════════════════════════════════════════

(defmethod render ((ui terminal-ui))
  "Render the entire UI to the screen."
  (clear-screen)
  (render-timeline ui)
  (render-detail-panel ui)
  (render-status-bar ui)
  (when (ui-help-visible-p ui)
    (render-help-overlay ui))
  (finish-output *standard-output*))




(defmethod render-detail-panel ((ui terminal-ui))
  "Render the detail panel component."
  (multiple-value-bind (x y width height) (get-detail-region ui)
    ;; Draw detail panel border
    (draw-box y x width height)
    ;; Render detail content
    (let ((content-x (1+ x))
          (content-y (1+ y))
          (content-width (- width 2))
          (content-height (- height 2)))
      (render-detail-content ui content-x content-y content-width content-height))))

(defmethod render-detail-content ((ui terminal-ui) x y width height)
  "Render detail panel content in the specified region."
  (when-let (navigator (ui-navigator ui))
    ;; Show current snapshot details
    (let ((current-pos (navigator-cursor navigator)))
      (move-cursor y x)
      (format t "Position: ~d" current-pos)
      ;; TODO: Implement full detail panel rendering
      )))

(defmethod render-status-bar ((ui terminal-ui))
  "Render the status bar at the bottom."
  (multiple-value-bind (x y width height) (get-status-region ui)
    (declare (ignore height))
    ;; Draw status bar line
    (draw-horizontal-line y x width)
    ;; Render status content below the line
    (let ((status-y (1+ y)))
      (move-cursor status-y x)
      (format t "Autopoiesis Timeline | Branch: main | Position: 0/0")
      (move-cursor status-y (+ x 50))
      (format t "Press 'h' for help, 'q' to quit"))))

(defmethod render-help-overlay ((ui terminal-ui))
  "Render help overlay with key bindings."
  (let ((help-text '("Autopoiesis Timeline Help"
                     "Navigation:"
                     "  h,j,k,l    Move cursor left/down/up/right"
                     "  H,J,K,L    Move to branch boundaries"
                     "  0, $        Go to start/end"
                     "  Enter       Select snapshot"
                     "  /           Search snapshots"
                     ""
                     "Actions:"
                     "  f           Fork from current"
                     "  m           Merge branches"
                     "  Space       Follow agent"
                     "  o           Overview"
                     ""
                     "View:"
                     "  ?           Toggle this help"
                     "  q           Quit"
                     ""
                     "Press any key to close")))
    ;; Draw help box in center
    (let* ((max-line-length (apply #'max (mapcar #'length help-text)))
           (box-width (+ max-line-length 4))
           (box-height (+ (length help-text) 2))
           (box-x (floor (- (ui-terminal-width ui) box-width) 2))
           (box-y (floor (- (ui-terminal-height ui) box-height) 2)))
      ;; Draw background box
      (draw-box box-y box-x box-width box-height)
      ;; Render help text
      (loop for i from 0
            for line in help-text
            do (move-cursor (+ box-y 1 i) (+ box-x 2))
               (format t "~a" line)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Input Handling
;;; ═══════════════════════════════════════════════════════════════════

(defmethod handle-input ((ui terminal-ui) input)
  "Handle a single input character."
  (case input
    (#\q (stop-terminal-ui ui))
    (#\h (when (ui-navigator ui)
           (cursor-left (ui-navigator ui))))
    (#\j (when (ui-navigator ui)
           (cursor-down-branch (ui-navigator ui))))
    (#\k (when (ui-navigator ui)
           (cursor-up-branch (ui-navigator ui))))
    (#\l (when (ui-navigator ui)
           (cursor-right (ui-navigator ui))))
    (#\? (setf (ui-help-visible-p ui) (not (ui-help-visible-p ui))))
    (otherwise
     ;; Handle other keys or ignore
     nil)))

(defmethod read-input ((ui terminal-ui))
  "Read a single character from input."
  (read-char-no-hang *standard-input* nil nil))

;;; ═══════════════════════════════════════════════════════════════════
;;; Main UI Loop
;;; ═══════════════════════════════════════════════════════════════════

(defmethod run-terminal-ui ((ui terminal-ui))
  "Run the main terminal UI loop."
  (unwind-protect
       (progn
         (init-screen ui)
         (setf (ui-running-p ui) t)
         (render ui)
         (loop while (ui-running-p ui) do
           (let ((input (read-input ui)))
             (handle-input ui input)
             (render ui))))
    (cleanup-screen ui)))

(defmethod stop-terminal-ui ((ui terminal-ui))
  "Stop the terminal UI loop."
  (setf (ui-running-p ui) nil))

;;; ═══════════════════════════════════════════════════════════════════
;;; Utility Methods
;;; ═══════════════════════════════════════════════════════════════════

(defmethod refresh-display ((ui terminal-ui))
  "Refresh the display by re-rendering everything."
  (render ui))

(defmethod update-terminal-size ((ui terminal-ui))
  "Update stored terminal dimensions."
  (multiple-value-bind (width height) (get-terminal-size)
    (setf (ui-terminal-width ui) width
          (ui-terminal-height ui) height)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Helper Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun toggle-help (ui)
  "Toggle help overlay visibility."
  (setf (ui-help-visible-p ui) (not (ui-help-visible-p ui))))

(defun status-bar-message (ui message)
  "Set a temporary status bar message."
  (when-let (status (ui-status-bar ui))
    (setf (gethash :message status) message)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Integration with Existing Components
;;; ═══════════════════════════════════════════════════════════════════

;; TODO: Integrate with timeline-navigator for cursor movement
;; TODO: Integrate with detail-panel for snapshot display
;; TODO: Add keyboard input handling for search, etc.