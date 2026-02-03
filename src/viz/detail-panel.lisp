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
