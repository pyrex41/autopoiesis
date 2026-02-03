;;;; test/viz-tests.lisp - Visualization tests

(in-package #:autopoiesis.test)

(def-suite viz-tests
    :description \"Autopoiesis visualization tests\")

(in-suite viz-tests)

(test render-timeline-row-basic
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id \"snap1\"
                               :metadata '(:type :snapshot)
                               :timestamp 1.0d0))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id \"snap2\"
                               :metadata '(:type :decision)
                               :timestamp 2.0d0))
         (current-snap (make-instance 'autopoiesis.snapshot:snapshot
                               :id \"current\"
                               :metadata '(:type :action)
                               :timestamp 3.0d0))
         (timeline (autopoiesis.viz:make-timeline
                    :snapshots (list snap1 snap2 current-snap)
                    :current \"current\"))
         (viewport (make-instance 'autopoiesis.viz:timeline-viewport))
         (out (make-string-output-stream)))
    (let ((*standard-output* out))
      (autopoiesis.viz:render-timeline-row timeline 10)
      (let ((output (get-output-to-string out)))
        ;; Backbone
        (is-true (search \"────────────────────\" output))
        ;; Glyphs
        (is-true (search \"○\" output))
        (is-true (search \"◆\" output))
        (is-true (search \"●\" output))
        ;; Length reasonable
        (is (>= (length output) 100))))

(test render-branch-connections-main
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id \"snap1\"
                               :timestamp 1.0d0
                               :metadata '(:type :snapshot)))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id \"snap2\"
                               :timestamp 3.0d0
                               :metadata '(:type :decision)))
         (branch-snap (make-instance 'autopoiesis.snapshot:snapshot
                                     :id \"branch1-snap\"
                                     :timestamp 1.5d0
                                     :parent \"snap1\")))
    (let* ((timeline (autopoiesis.viz:make-timeline
                      :snapshots (list snap1 snap2 branch-snap)
                      :current \"snap2\"))
           (branches (autopoiesis.viz:timeline-branches timeline)))
      (setf (gethash \"main\" branches) (list \"snap1\" \"snap2\"))
      (setf (gethash \"branch1\" branches) (list \"branch1-snap\"))
      (let ((*standard-output* (make-string-output-stream)))
        (autopoiesis.viz:render-branch-connections timeline 10)
        (let ((output (get-output-to-string *standard-output*)))
          (is-true (search \"┬\" output)))))))

(test render-branch-connections-vertical
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id \"snap1\"
                               :timestamp 1.0d0
                               :metadata '(:type :snapshot)))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id \"snap2\"
                               :timestamp 3.0d0
                               :metadata '(:type :decision)))
         (branch-snap (make-instance 'autopoiesis.snapshot:snapshot
                                     :id \"branch1-snap\"
                                     :timestamp 1.5d0
                                     :parent \"snap1\")))
    (let* ((timeline (autopoiesis.viz:make-timeline
                      :snapshots (list snap1 snap2 branch-snap)
                      :current \"snap2\"))
           (branches (autopoiesis.viz:timeline-branches timeline)))
      (setf (gethash \"main\" branches) (list \"snap1\" \"snap2\"))
      (setf (gethash \"branch1\" branches) (list \"branch1-snap\"))
      (let ((*standard-output* (make-string-output-stream)))
        (autopoiesis.viz:render-branch-connections timeline 11 :main-row 10)
        (let ((output (get-output-to-string *standard-output*)))
          (is-true (search \"│\" output)))))))