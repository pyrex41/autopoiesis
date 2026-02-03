;;;; timeline.lisp - Timeline data structure for terminal visualization
;;;;
;;;; Defines `timeline` and `timeline-viewport` classes for holding snapshot
;;;; references and viewport state for ASCII timeline rendering.

(in-package #:autopoiesis.viz)

;;; ═══════════════════════════════════════════════════════════════════
;;; Timeline Viewport Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass timeline-viewport ()
  ((start :initarg :start
          :accessor viewport-start
          :initform 0
          :documentation "Starting snapshot index or time for viewport.")
   (end :initarg :end
        :accessor viewport-end
        :initform nil
        :documentation "Ending snapshot index or time (nil for current).")
   (width :initarg :width
          :accessor viewport-width
          :initform 80
          :documentation "Viewport width in characters.")
   (height :initarg :height
           :accessor viewport-height
           :initform 20
           :documentation "Viewport height in rows.")
   (scroll :initarg :scroll
           :accessor viewport-scroll
           :initform 0
           :documentation "Horizontal scroll offset in characters."))
  (:documentation "Viewport state for timeline rendering."))

;;; ═══════════════════════════════════════════════════════════════════
;;; Timeline Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass timeline ()
  ((snapshots :initarg :snapshots
              :accessor timeline-snapshots
              :initform nil
              :documentation "Chronologically sorted list of snapshot IDs (strings).")
   (branches :initarg :branches
             :accessor timeline-branches
             :initform (make-hash-table :test #'equal)
             :documentation "Hash table: branch-name (string) -> list of snapshot IDs.")
   (current :initarg :current
            :accessor timeline-current
            :initform nil
            :documentation "ID of the current/head snapshot.")
   (viewport :initarg :viewport
             :accessor timeline-viewport
             :initform (make-instance 'timeline-viewport)
             :documentation "Associated viewport state."))
  (:documentation "Timeline holding snapshot references for visualization."))

(defmethod make-timeline (&key (snapshots nil) branches current viewport)
  "Create a new timeline instance."
  (make-instance 'timeline
                 :snapshots snapshots
                 :branches (or branches (make-hash-table :test #'equal))
                 :current current
                 :viewport (or viewport (make-instance 'timeline-viewport))))
