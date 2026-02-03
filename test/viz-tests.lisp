;;;; test/viz-tests.lisp - Visualization tests

(in-package #:autopoiesis.test)

(def-suite viz-tests
    :description "Autopoiesis visualization tests")

(in-suite viz-tests)

(test render-timeline-row-basic
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap1"
                               :metadata '(:type :snapshot)
                               :timestamp 1.0d0))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap2"
                               :metadata '(:type :decision)
                               :timestamp 2.0d0))
         (current-snap (make-instance 'autopoiesis.snapshot:snapshot
                               :id "current"
                               :metadata '(:type :action)
                               :timestamp 3.0d0))
         (timeline (autopoiesis.viz:make-timeline
                    :snapshots (list snap1 snap2 current-snap)
                    :current "current"))
         (viewport (make-instance 'autopoiesis.viz:timeline-viewport))
         (out (make-string-output-stream)))
    (let ((*standard-output* out))
      (autopoiesis.viz:render-timeline-row timeline 10)
      (let ((output (get-output-stream-string out)))
        ;; Backbone (uses ASCII dashes)
        (is-true (search "--------------------" output))
        ;; Glyphs
        (is-true (search "○" output))
        (is-true (search "◆" output))
        (is-true (search "●" output))
        ;; Length reasonable
        (is (>= (length output) 100))))))

(test render-branch-connections-main
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap1"
                               :timestamp 1.0d0
                               :metadata '(:type :snapshot)))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap2"
                               :timestamp 3.0d0
                               :metadata '(:type :decision)))
         (branch-snap (make-instance 'autopoiesis.snapshot:snapshot
                                     :id "branch1-snap"
                                     :timestamp 1.5d0
                                     :parent "snap1")))
    (let* ((timeline (autopoiesis.viz:make-timeline
                      :snapshots (list snap1 snap2 branch-snap)
                      :current "snap2"))
           (branches (autopoiesis.viz:timeline-branches timeline)))
      (setf (gethash "main" branches) (list "snap1" "snap2"))
      (setf (gethash "branch1" branches) (list "branch1-snap"))
      (let ((*standard-output* (make-string-output-stream)))
        (autopoiesis.viz:render-branch-connections timeline 10)
        (let ((output (get-output-stream-string *standard-output*)))
          (is-true (search "┬" output)))))))

(test render-branch-connections-vertical
  (let* ((snap1 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap1"
                               :timestamp 1.0d0
                               :metadata '(:type :snapshot)))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                               :id "snap2"
                               :timestamp 3.0d0
                               :metadata '(:type :decision)))
         (branch-snap (make-instance 'autopoiesis.snapshot:snapshot
                                     :id "branch1-snap"
                                     :timestamp 1.5d0
                                     :parent "snap1")))
    (let* ((timeline (autopoiesis.viz:make-timeline
                      :snapshots (list snap1 snap2 branch-snap)
                      :current "snap2"))
           (branches (autopoiesis.viz:timeline-branches timeline)))
      (setf (gethash "main" branches) (list "snap1" "snap2"))
      (setf (gethash "branch1" branches) (list "branch1-snap"))
      (let ((*standard-output* (make-string-output-stream)))
        (autopoiesis.viz:render-branch-connections timeline 11 10)
        (let ((output (get-output-stream-string *standard-output*)))
          (is-true (search "|" output)))))))

(test render-snapshot-summary
  (let ((snap (make-instance 'autopoiesis.snapshot:snapshot
                             :id "test-id-12345678901234567890"
                             :timestamp 1699123456.789
                             :metadata '(:type :decision)
                             :parent "parent-test-id")))
    (let* ((summary (autopoiesis.viz:render-snapshot-summary snap)))
      (is (= 4 (length summary)))
      (is (search "ID:       test-id-1234567890" (first summary)))
      (is (search "Type:      decision" (third summary)))
      (is (search "Parent:    parent-test-id" (fourth summary))))))

(test render-thought-preview-collapsed
  (let ((thought (autopoiesis.core:make-thought
                  '(:action :reasoning :about :something :very :long :that :will :be :truncated :because :it :is :too :long :for :the :panel :width))))
    (let ((preview (autopoiesis.viz:render-thought-preview thought :expanded nil :max-lines 2 :width 20)))
      (is (<= (length preview) 3))  ; max-lines + possible truncation indicator
      (is (some #'(lambda (line) (search "..." line)) preview)))))

(test render-thought-preview-expanded
  (let ((thought (autopoiesis.core:make-thought '(:short :content))))
    (let ((preview (autopoiesis.viz:render-thought-preview thought :expanded t :width 20)))
      (is (> (length preview) 0))
      (is (every #'(lambda (line) (<= (length line) 20)) preview)))))

(test compute-branch-layout-basic
  (let* ((main-snap1 (make-instance 'autopoiesis.snapshot:snapshot
                                    :id "main1" :timestamp 1.0d0
                                    :metadata '(:branch "main")))
         (fork-snap (make-instance 'autopoiesis.snapshot:snapshot
                                   :id "fork1" :timestamp 1.5d0
                                   :parent "main1"
                                   :metadata '(:branch "branch1")))
         (main-snap2 (make-instance 'autopoiesis.snapshot:snapshot
                                    :id "main2" :timestamp 2.0d0
                                    :metadata '(:branch "main")))
         (timeline (autopoiesis.viz:make-timeline
                    :snapshots (list main-snap1 fork-snap main-snap2)
                    :current "main2")))
    (let ((branches (autopoiesis.viz:timeline-branches timeline)))
      (setf (gethash "main" branches) (list "main1" "main2")
            (gethash "branch1" branches) (list "fork1")))
    (let ((layout (autopoiesis.viz:compute-branch-layout timeline)))
      (is (= 10 (cdr (assoc "main" layout :test #'string=))))
      (is (= 6 (cdr (assoc "branch1" layout :test #'string=))))))

(test render-branch-labels-basic
  (let* ((main-snap1 (make-instance 'autopoiesis.snapshot:snapshot
                                    :id "main1" :timestamp 1.0d0
                                    :metadata '(:branch \"main\")))
         (fork-snap (make-instance 'autopoiesis.snapshot:snapshot
                                   :id "fork1" :timestamp 1.5d0
                                   :parent "main1"
                                   :metadata '(:branch "branch1")))
         (main-snap2 (make-instance 'autopoiesis.snapshot:snapshot
                                    :id "main2" :timestamp 2.0d0
                                    :metadata '(:branch \"main\")))
         (timeline (autopoiesis.viz:make-timeline
                    :snapshots (list main-snap1 fork-snap main-snap2)
                    :current "main2"))
         (branches (autopoiesis.viz:timeline-branches timeline)))
    (setf (gethash "main" branches) (list "main1" "main2")
          (gethash "branch1" branches) (list "fork1"))
    (let ((*standard-output* (make-string-output-stream)))
      (autopoiesis.viz:render-branch-labels timeline 10 5)
      (let ((output (get-output-stream-string *standard-output*)))
        (is-true (search \"bran\" output)))))))
