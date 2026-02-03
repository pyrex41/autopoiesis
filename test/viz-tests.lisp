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
      (is (= 6 (cdr (assoc "branch1" layout :test #'string=)))))))

(test render-branch-labels-basic
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
                    :current "main2"))
         (branches (autopoiesis.viz:timeline-branches timeline)))
    (setf (gethash "main" branches) (list "main1" "main2")
          (gethash "branch1" branches) (list "fork1"))
    (let ((*standard-output* (make-string-output-stream)))
      (autopoiesis.viz:render-branch-labels timeline 10 5)
      (let ((output (get-output-stream-string *standard-output*)))
        (is-true (search "bran" output))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Navigation Tests
;;; ═══════════════════════════════════════════════════════════════════

(test cursor-left-right
  "Test cursor-left and cursor-right movement along timeline."
  (let* ((snap0 (make-instance 'autopoiesis.snapshot:snapshot :id "snap0"))
         (snap1 (make-instance 'autopoiesis.snapshot:snapshot :id "snap1"))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot :id "snap2"))
         (timeline (autopoiesis.viz:make-timeline :snapshots (list snap0 snap1 snap2)))
         (nav (autopoiesis.viz:make-timeline-navigator :timeline timeline :cursor 1)))
    ;; Start at cursor 1
    (is (= 1 (autopoiesis.viz:navigator-cursor nav)))
    ;; Move left to 0
    (is-true (autopoiesis.viz:cursor-left nav))
    (is (= 0 (autopoiesis.viz:navigator-cursor nav)))
    ;; Cannot move left past beginning
    (is-false (autopoiesis.viz:cursor-left nav))
    ;; Move right from 0 to 1
    (is-true (autopoiesis.viz:cursor-right nav))
    (is (= 1 (autopoiesis.viz:navigator-cursor nav)))
    ;; Move right from 1 to 2
    (is-true (autopoiesis.viz:cursor-right nav))
    (is (= 2 (autopoiesis.viz:navigator-cursor nav)))
    ;; Cannot move right past end
    (is-false (autopoiesis.viz:cursor-right nav))))

(test cursor-up-down-branch
  "Test cursor-up-branch and cursor-down-branch for parent/child traversal."
  (let* ((snap0 (make-instance 'autopoiesis.snapshot:snapshot :id "snap0"))
         (snap1 (make-instance 'autopoiesis.snapshot:snapshot :id "snap1" :parent "snap0"))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot :id "snap2" :parent "snap1"))
         (snapb (make-instance 'autopoiesis.snapshot:snapshot :id "snapb" :parent "snap1"))
         (timeline (autopoiesis.viz:make-timeline :snapshots (list snap0 snap1 snap2 snapb)))
         (nav (autopoiesis.viz:make-timeline-navigator :timeline timeline)))
    ;; From snap2 (idx 2) up to parent snap1 (idx 1)
    (setf (autopoiesis.viz:navigator-cursor nav) 2)
    (is-true (autopoiesis.viz:cursor-up-branch nav))
    (is (= 1 (autopoiesis.viz:navigator-cursor nav)))
    ;; From snap1 up to parent snap0
    (is-true (autopoiesis.viz:cursor-up-branch nav))
    (is (= 0 (autopoiesis.viz:navigator-cursor nav)))
    ;; snap0 has no parent - cannot go up
    (is-false (autopoiesis.viz:cursor-up-branch nav))
    ;; From snap0 down to first child snap1
    (setf (autopoiesis.viz:navigator-cursor nav) 0)
    (is-true (autopoiesis.viz:cursor-down-branch nav))
    (is (= 1 (autopoiesis.viz:navigator-cursor nav)))
    ;; From snap1 down to first child snap2
    (setf (autopoiesis.viz:navigator-cursor nav) 1)
    (is-true (autopoiesis.viz:cursor-down-branch nav))
    (is (= 2 (autopoiesis.viz:navigator-cursor nav)))
    ;; From snap2 down - snap2 has no children after it with parent snap2
    ;; But snapb is at idx 3 with parent snap1, not snap2
    (is-false (autopoiesis.viz:cursor-down-branch nav))))

(test jump-to-snapshot-test
  "Test jumping cursor to a specific snapshot by ID."
  (let* ((snap0 (make-instance 'autopoiesis.snapshot:snapshot :id "snap0"))
         (snap1 (make-instance 'autopoiesis.snapshot:snapshot :id "snap1"))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot :id "snap2"))
         (timeline (autopoiesis.viz:make-timeline :snapshots (list snap0 snap1 snap2)))
         (nav (autopoiesis.viz:make-timeline-navigator :timeline timeline)))
    ;; Jump to first snapshot
    (is-true (autopoiesis.viz:jump-to-snapshot nav "snap0"))
    (is (= 0 (autopoiesis.viz:navigator-cursor nav)))
    ;; Jump to last snapshot
    (is-true (autopoiesis.viz:jump-to-snapshot nav "snap2"))
    (is (= 2 (autopoiesis.viz:navigator-cursor nav)))
    ;; Jump to middle snapshot
    (is-true (autopoiesis.viz:jump-to-snapshot nav "snap1"))
    (is (= 1 (autopoiesis.viz:navigator-cursor nav)))
    ;; Jump to nonexistent snapshot returns nil
    (is-false (autopoiesis.viz:jump-to-snapshot nav "missing"))))

(test current-snapshot-at-cursor-test
  "Test getting the snapshot at current cursor position."
  (let* ((snap0 (make-instance 'autopoiesis.snapshot:snapshot :id "snap0"))
         (snap1 (make-instance 'autopoiesis.snapshot:snapshot :id "snap1"))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot :id "snap2"))
         (timeline (autopoiesis.viz:make-timeline :snapshots (list snap0 snap1 snap2)))
         (nav (autopoiesis.viz:make-timeline-navigator :timeline timeline :cursor 0)))
    ;; At cursor 0, get snap0
    (is (eq snap0 (autopoiesis.viz:current-snapshot-at-cursor nav)))
    ;; Move to cursor 1
    (setf (autopoiesis.viz:navigator-cursor nav) 1)
    (is (eq snap1 (autopoiesis.viz:current-snapshot-at-cursor nav)))
    ;; Move to cursor 2
    (setf (autopoiesis.viz:navigator-cursor nav) 2)
    (is (eq snap2 (autopoiesis.viz:current-snapshot-at-cursor nav)))))

(test search-snapshots-test
  "Test searching snapshots by ID or type."
  (let* ((snap0 (make-instance 'autopoiesis.snapshot:snapshot
                                :id "genesis-001"
                                :metadata '(:type :genesis)))
         (snap1 (make-instance 'autopoiesis.snapshot:snapshot
                                :id "decision-001"
                                :metadata '(:type :decision)))
         (snap2 (make-instance 'autopoiesis.snapshot:snapshot
                                :id "action-002"
                                :metadata '(:type :action)))
         (snap3 (make-instance 'autopoiesis.snapshot:snapshot
                                :id "decision-002"
                                :metadata '(:type :decision)))
         (timeline (autopoiesis.viz:make-timeline
                    :snapshots (list snap0 snap1 snap2 snap3)))
         (nav (autopoiesis.viz:make-timeline-navigator :timeline timeline)))
    ;; Search by ID substring
    (let ((results (autopoiesis.viz:search-snapshots nav "decision")))
      (is (= 2 (length results)))
      (is (member snap1 results))
      (is (member snap3 results)))
    ;; Search by type
    (let ((results (autopoiesis.viz:search-snapshots nav "action")))
      (is (= 1 (length results)))
      (is (member snap2 results)))
    ;; Search with no matches
    (let ((results (autopoiesis.viz:search-snapshots nav "nonexistent")))
      (is (= 0 (length results))))
    ;; Case-insensitive search
    (let ((results (autopoiesis.viz:search-snapshots nav "GENESIS")))
      (is (= 1 (length results)))
      (is (member snap0 results)))))
