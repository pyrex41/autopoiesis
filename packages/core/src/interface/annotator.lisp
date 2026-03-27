;;;; annotator.lisp - Human annotations
;;;;
;;;; Attach human commentary to agent state.

(in-package #:autopoiesis.interface)

;;; ═══════════════════════════════════════════════════════════════════
;;; Annotation Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass annotation ()
  ((id :initarg :id
       :accessor annotation-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique ID")
   (target :initarg :target
           :accessor annotation-target
           :documentation "What this annotates (snapshot ID, thought ID, etc.)")
   (content :initarg :content
            :accessor annotation-content
            :documentation "The annotation text or data")
   (author :initarg :author
           :accessor annotation-author
           :initform nil
           :documentation "Who created this annotation")
   (timestamp :initarg :timestamp
              :accessor annotation-timestamp
              :initform (autopoiesis.core:get-precise-time)
              :documentation "When created"))
  (:documentation "A human annotation attached to state"))

(defun make-annotation (target content &key author)
  "Create a new annotation."
  (make-instance 'annotation
                 :target target
                 :content content
                 :author author))

;;; ═══════════════════════════════════════════════════════════════════
;;; Annotation Store
;;; ═══════════════════════════════════════════════════════════════════

(defvar *annotation-store* (make-hash-table :test 'equal)
  "Store of annotations by ID.")

(defvar *annotation-index* (make-hash-table :test 'equal)
  "Index: target -> list of annotation IDs.")

(defun add-annotation (annotation &key (store *annotation-store*) (index *annotation-index*))
  "Add an annotation."
  (setf (gethash (annotation-id annotation) store) annotation)
  (push (annotation-id annotation)
        (gethash (annotation-target annotation) index))
  annotation)

(defun remove-annotation (annotation-id &key (store *annotation-store*) (index *annotation-index*))
  "Remove an annotation."
  (let ((ann (gethash annotation-id store)))
    (when ann
      (setf (gethash (annotation-target ann) index)
            (remove annotation-id (gethash (annotation-target ann) index)
                    :test #'equal))
      (remhash annotation-id store))))

(defun find-annotations (target &key (index *annotation-index*) (store *annotation-store*))
  "Find all annotations for TARGET."
  (mapcar (lambda (id) (gethash id store))
          (gethash target index)))
