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
