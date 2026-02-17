;;;; navigator.lisp - Timeline navigation for terminal visualization
;;;;
;;;; Defines `timeline-navigator` class that wraps the snapshot navigator
;;;; and provides cursor-based navigation in the timeline context.

(in-package #:autopoiesis.viz)

;;; ═══════════════════════════════════════════════════════════════════
;;; Timeline Navigator Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass timeline-navigator ()
  ((timeline :initarg :timeline
             :accessor navigator-timeline
             :initform nil
             :documentation "Associated timeline instance.")
   (navigator :initarg :navigator
              :accessor navigator-navigator
              :initform (autopoiesis.interface:make-navigator)
              :documentation "Underlying snapshot navigator.")
   (cursor :initarg :cursor
           :accessor navigator-cursor
           :initform 0
           :documentation "Current cursor position (index into timeline snapshots)."))
  (:documentation "Navigator for timeline-based cursor movement."))

(defun make-timeline-navigator (&key timeline navigator cursor)
  "Create a new timeline navigator."
  (make-instance 'timeline-navigator
                 :timeline timeline
                 :navigator (or navigator (autopoiesis.interface:make-navigator))
                 :cursor (or cursor 0)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cursor Movement Functions
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric cursor-left (navigator)
  (:documentation "Move cursor to previous snapshot in timeline.")
  (:method ((nav timeline-navigator))
    (with-slots (cursor timeline) nav
      (when (> cursor 0)
        (decf cursor)
        (update-navigator-position nav)
        t))))

(defgeneric cursor-right (navigator)
  (:documentation "Move cursor to next snapshot in timeline.")
  (:method ((nav timeline-navigator))
    (with-slots (cursor timeline) nav
      (let ((max-cursor (1- (length (timeline-snapshots timeline)))))
        (when (< cursor max-cursor)
          (incf cursor)
          (update-navigator-position nav)
          t)))))

(defgeneric cursor-up-branch (navigator)
  (:documentation "Move cursor up to parent branch or earlier fork point.")
  (:method ((nav timeline-navigator))
    (with-slots (cursor timeline) nav
      (let* ((snaps (timeline-snapshots timeline))
             (current-snap (when (< cursor (length snaps))
                             (elt snaps cursor))))
        (when current-snap
          (let ((parent-id (snapshot-parent current-snap)))
            (when parent-id
              (let ((parent-idx (position parent-id snaps
                                          :key #'snapshot-id
                                          :test #'string-equal)))
                (when parent-idx
                  (setf cursor parent-idx)
                  (update-navigator-position nav)
                  t)))))))))

(defgeneric cursor-down-branch (navigator)
  (:documentation "Move cursor down to child branch or later merge point.")
  (:method ((nav timeline-navigator))
    (with-slots (cursor timeline) nav
      (let* ((snaps (timeline-snapshots timeline))
             (current-snap (when (< cursor (length snaps))
                             (elt snaps cursor))))
        (when current-snap
          ;; Find first child snapshot
          (let ((current-id (snapshot-id current-snap)))
            (let ((child-idx (position current-id snaps
                                       :key #'snapshot-parent
                                       :test #'string-equal
                                       :start (1+ cursor))))
              (when child-idx
                (setf cursor child-idx)
                (update-navigator-position nav)
                t))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Jump and Search Functions
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric jump-to-snapshot (navigator snapshot-id)
  (:documentation "Jump cursor to specific snapshot by ID.")
  (:method ((nav timeline-navigator) snapshot-id)
    (with-slots (cursor timeline) nav
      (let* ((snaps (timeline-snapshots timeline))
             (idx (position snapshot-id snaps
                            :key #'snapshot-id
                            :test #'string-equal)))
        (when idx
          (setf cursor idx)
          (update-navigator-position nav)
          t)))))

(defgeneric search-snapshots (navigator query)
  (:documentation "Search for snapshots matching QUERY and return list of IDs.")
  (:method ((nav timeline-navigator) query)
    (with-slots (timeline) nav
      (let ((snaps (timeline-snapshots timeline)))
        (remove-if-not
         (lambda (snap)
           (or (search query (snapshot-id snap) :test #'char-equal)
               (let ((snap-type (getf (snapshot-metadata snap) :type)))
                 (and snap-type
                      (search query (princ-to-string snap-type) :test #'char-equal)))))
         snaps)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Helper Functions
;;; ═══════════════════════════════════════════════════════════════════

(defun update-navigator-position (navigator)
  "Update the underlying navigator position to match cursor."
  (with-slots (cursor timeline navigator) navigator
    (let* ((snaps (timeline-snapshots timeline))
           (current-snap (when (< cursor (length snaps))
                           (elt snaps cursor))))
      (when current-snap
        (autopoiesis.interface:navigate-to navigator (snapshot-id current-snap))))))

(defun current-snapshot-at-cursor (navigator)
  "Get the snapshot at current cursor position."
  (with-slots (cursor timeline) navigator
    (let ((snaps (timeline-snapshots timeline)))
      (when (< cursor (length snaps))
        (elt snaps cursor)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Navigation State
;;; ═══════════════════════════════════════════════════════════════════

(defmethod initialize-instance :after ((nav timeline-navigator) &key)
  "Initialize navigator state after creation."
  (update-navigator-position nav))</content>
<parameter name="filePath">src/viz/navigator.lisp