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
              :documentation "Chronologically sorted list of snapshot objects (loaded for viz).")
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

(defun render-timeline-row (timeline row)
  \"Render basic ASCII timeline row at screen ROW for TIMELINE.\"
  (let* ((snaps (timeline-snapshots timeline))
         (sorted-snaps (sort (copy-seq snaps) #'< :key #'snapshot-timestamp))
         (current-id (timeline-current timeline))
         (num-slots 20)
         (slot-width 4)
         (total-width (* num-slots slot-width)))
    ;; Draw horizontal backbone
    (move-cursor row 1)
    (set-color +color-border+)
    (dotimes (i total-width)
      (princ #\- *standard-output*))
    (reset-color)
    ;; Draw snapshot nodes
    (loop for slot from 0 below num-slots
          for fraction = (if (= num-slots 1) 0 (/ slot (1- num-slots)))
for snap-idx = (min (1- (length sorted-snaps)) (round (* fraction (1- (length sorted-snaps)))))
          for snap = (elt sorted-snaps snap-idx)
          for col = (+ 2 (* slot slot-width))
          do
             (move-cursor row col)
(render-snapshot-node timeline row col snap)
    (force-output *standard-output*))))

(defun find-snapshot (timeline id)
  \"Find snapshot by ID in TIMELINE.\"
  (find id (timeline-snapshots timeline)
        :key #'snapshot-id :test #'string-equal))

(defun compute-fork-cols (timeline)
  \"Compute column positions for fork points.\"
  (let (fork-cols)
    (maphash (lambda (bname branch-ids)
               (unless (string-equal bname "main")
                 (let ((first-id (first branch-ids)))
                   (when first-id
                     (let ((branch-snap (find-snapshot timeline first-id)))
                       (when branch-snap
                         (let ((parent-id (snapshot-parent branch-snap)))
                           (when parent-id
                             (let ((parent-snap (find-snapshot timeline parent-id)))
                               (when parent-snap
                                 (let* ((sorted (sort (copy-list (timeline-snapshots timeline)) #'< :key #'snapshot-timestamp))
                                        (max-t (reduce #'max (mapcar #'snapshot-timestamp sorted)
                                                       :initial-value 0d0))
                                        (fraction (if (zerop max-t) 0 (/ (snapshot-timestamp parent-snap) max-t)))
                                        (num-slots 20)
                                        (slot-width 4)
                                        (slot (max 0 (min (1- num-slots)
                                                          (round (* fraction (1- num-slots))))))
                                        (col (+ 2 (* slot slot-width))))
                                   (push col fork-cols)))))))))))
              (timeline-branches timeline))
    (remove-duplicates fork-cols)))

(defun render-branch-connections (timeline row &optional (main-row 10))
  "Render branch connections on ROW, main timeline on MAIN-ROW."
  (let* ((fork-cols (compute-fork-cols timeline))
         (vp (timeline-viewport timeline))
         (scroll (viewport-scroll vp))
         (width (viewport-width vp)))
    (dolist (col fork-cols)
      (let ((rel-col (- col scroll)))
        (when (and (>= rel-col 0) (< rel-col width))
          (move-cursor row rel-col)
(cond ((= row main-row)
                  (with-color (+color-fork+)
                    (princ "T")))
                 ((<= (+ main-row 1) row (+ main-row 5))
                  (with-color (+color-border+)
                    (princ "|")))
                 (t nil))))
  (defun render-snapshot-node (timeline row col snapshot)
    (let* ((current-id (timeline-current timeline))
           (meta-type (getf (snapshot-metadata snapshot) :type))
           (type (or meta-type :snapshot))
           (glyph (if (string= (snapshot-id snapshot) current-id)
                      +glyph-current+
                      (snapshot-glyph type)))
           (color (snapshot-type-color type)))
      (move-cursor row col)
      (set-color color)
(princ glyph *standard-output*)
(reset-color)))

(defun render-legend (start-row)
  "Render timeline legend at START-ROW."
  (let ((row start-row)
        (types '(:snapshot :decision :fork :merge :current :genesis :human :action)))
    (move-cursor row 1)
    (with-color (+color-border+)
      (princ " Legend "))
    (loop for type in types
          for col from 10 by 12
          do
             (move-cursor row (+ col 1))
             (with-color (snapshot-type-color type))
               (princ (snapshot-glyph type))
             (reset-color)
             (move-cursor row (+ col 3))
             (with-color (+color-text+))
               (princ (subseq (string-downcase (symbol-name type)) 0 6)))
    (force-output)))

(defun render-timeline (timeline)
  "Render full timeline: legend, rows, branches, legend."
  (let* ((vp (timeline-viewport timeline))
         (legend-row 1)
         (main-row 5)
         (branch-rows 6))
    (render-legend legend-row)
    (render-timeline-row timeline main-row)
    (dotimes (i branch-rows)
      (render-branch-connections timeline (+ main-row i 1) main-row))
    (force-output)))
