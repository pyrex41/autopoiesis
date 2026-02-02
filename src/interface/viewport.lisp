;;;; viewport.lisp - Focused view of agent state
;;;;
;;;; Controls what part of agent state is visible.

(in-package #:autopoiesis.interface)

;;; ═══════════════════════════════════════════════════════════════════
;;; Viewport Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass viewport ()
  ((focus :initarg :focus
          :accessor viewport-focus
          :initform nil
          :documentation "Path into the state tree")
   (filter :initarg :filter
           :accessor viewport-filter
           :initform nil
           :documentation "Filter predicate")
   (detail-level :initarg :detail-level
                 :accessor viewport-detail-level
                 :initform :summary
                 :documentation ":summary :normal :detailed"))
  (:documentation "A focused view into agent state"))

(defun make-viewport (&key focus filter detail-level)
  "Create a new viewport."
  (make-instance 'viewport
                 :focus focus
                 :filter filter
                 :detail-level (or detail-level :summary)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Viewport Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun set-focus (viewport path)
  "Set the focus path into state."
  (setf (viewport-focus viewport) path))

(defun apply-filter (viewport predicate)
  "Apply a filter predicate."
  (setf (viewport-filter viewport) predicate))

(defun expand-detail (viewport)
  "Increase detail level."
  (setf (viewport-detail-level viewport)
        (case (viewport-detail-level viewport)
          (:summary :normal)
          (:normal :detailed)
          (:detailed :detailed))))

(defun collapse-detail (viewport)
  "Decrease detail level."
  (setf (viewport-detail-level viewport)
        (case (viewport-detail-level viewport)
          (:detailed :normal)
          (:normal :summary)
          (:summary :summary))))

(defun viewport-render (viewport state)
  "Render STATE through the viewport."
  (let ((focused (if (viewport-focus viewport)
                     (follow-path state (viewport-focus viewport))
                     state)))
    (if (viewport-filter viewport)
        (filter-state focused (viewport-filter viewport))
        focused)))

(defun follow-path (state path)
  "Follow PATH into STATE."
  (reduce (lambda (s key)
            (cond
              ((and (listp s) (numberp key)) (nth key s))
              ((and (listp s) (symbolp key)) (getf s key))
              (t s)))
          path
          :initial-value state))

(defun filter-state (state predicate)
  "Filter STATE with PREDICATE."
  (typecase state
    (list (remove-if-not predicate state))
    (t state)))
