;;;; detail-panel.lisp - Detail panel for terminal visualization
;;;;
;;;; Defines the `detail-panel` class for holding panel dimensions and content buffer.

(in-package #:autopoiesis.viz)

;;; ═══════════════════════════════════════════════════════════════════
;;; Detail Panel Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass detail-panel ()
  ((width :initarg :width
          :accessor panel-width
          :initform 40
          :documentation "Width of the detail panel in characters.")
   (height :initarg :height
           :accessor panel-height
           :initform 15
           :documentation "Height of the detail panel in characters.")
   (content :initarg :content
            :accessor panel-content
            :initform '()
            :documentation "Content buffer: list of strings, one per line."))
  (:documentation "Panel for displaying detailed snapshot information in the terminal UI."))

(defmethod make-detail-panel (&key ((:width w) 40) ((:height h) 15) content)
  "Create a new detail panel."
  (make-instance 'detail-panel
                 :width w
                 :height h
                 :content (or content '())))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Summary Rendering
;;; ═══════════════════════════════════════════════════════════════════

(defun render-snapshot-summary (snapshot)
  "Generate list of strings summarizing the SNAPSHOT for detail panel display."
  (list (format nil "ID:       ~A"
                (truncate-string (snapshot-id snapshot) 32))
        (format nil "Timestamp: ~F"
                (snapshot-timestamp snapshot))
        (format nil "Type:      ~A"
                (string-downcase (symbol-name (or (getf (snapshot-metadata snapshot) :type) :snapshot))))
        (format nil "Parent:    ~A"
                (or (snapshot-parent snapshot) "none"))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Preview Rendering
;;; ═══════════════════════════════════════════════════════════════════

(defun render-thought-preview (thought &key (expanded nil) (max-lines 5) (width 38))
  "Render a preview of THOUGHT's content with truncation and expand/collapse.
   Returns a list of strings suitable for detail panel display.
   EXPANDED: if true, show full content; if false, truncate to MAX-LINES.
   WIDTH: maximum width of each line."
  (let* ((content (thought-content thought))
         (serialized (autopoiesis.core:sexpr-serialize content))
         (lines (split-string-by-lines serialized width)))
    (if expanded
        ;; Show all lines
        lines
        ;; Show truncated preview
        (let ((preview-lines (subseq lines 0 (min max-lines (length lines)))))
          (if (> (length lines) max-lines)
              ;; Add truncation indicator
              (append preview-lines (list (format nil "... (~d more lines)" (- (length lines) max-lines))))
              ;; No truncation needed
              preview-lines)))))

(defun split-string-by-lines (string max-width)
  "Split STRING into lines, each no longer than MAX-WIDTH.
   Attempts to break at word boundaries when possible."
  (let ((result '())
        (remaining string))
    (loop while (> (length remaining) max-width)
          do (let ((break-pos (find-line-break remaining max-width)))
               (push (subseq remaining 0 break-pos) result)
               (setf remaining (subseq remaining break-pos))))
    (when (> (length remaining) 0)
      (push remaining result))
    (nreverse result)))

(defun find-line-break (string max-width)
  "Find the best position to break STRING within MAX-WIDTH.
   Prefers word boundaries (spaces)."
  (let ((space-pos (position #\Space string :from-end t :end max-width)))
    (if space-pos
        (1+ space-pos)  ; Include the space
        max-width)))

(defun render-detail-panel (panel col row)
  "Render detail panel at COL, ROW."
  (draw-box row col (panel-width panel) (panel-height panel))
  (let ((content-row (+ row 1)))
    (move-cursor content-row (+ col 2))
    (princ "Detail:")
    (loop for line in (panel-content panel)
          for i from 0
          do (move-cursor (+ content-row 1 i) (+ col 2))
             (princ (pad-string line (- (panel-width panel) 3)))))
  (force-output *standard-output*))
