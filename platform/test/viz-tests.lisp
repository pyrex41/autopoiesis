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
        (is-true (search "bra" output))))))

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

;;; ═══════════════════════════════════════════════════════════════════
;;; Resize Handling Tests
;;; ═══════════════════════════════════════════════════════════════════

(test handle-resize-adjusts-viewport
  "Test that handle-resize adjusts viewport dimensions."
  (let* ((timeline (autopoiesis.viz:make-timeline))
         (ui (autopoiesis.viz:make-terminal-ui :timeline timeline)))
    ;; Simulate a terminal size of 120x40
    (setf (autopoiesis.viz:ui-terminal-width ui) 120
          (autopoiesis.viz:ui-terminal-height ui) 40)
    (autopoiesis.viz:handle-resize ui)
    (let ((vp (autopoiesis.viz:timeline-viewport timeline)))
      ;; Viewport width should be positive and bounded by terminal width
      (is (> (autopoiesis.viz:viewport-width vp) 0))
      (is (<= (autopoiesis.viz:viewport-width vp) 120))
      ;; Viewport height should be reduced by status bar
      (is (> (autopoiesis.viz:viewport-height vp) 0))
      (is (< (autopoiesis.viz:viewport-height vp) 40)))))

(test handle-resize-adjusts-detail-panel
  "Test that handle-resize adjusts detail panel dimensions."
  (let* ((timeline (autopoiesis.viz:make-timeline))
         (ui (autopoiesis.viz:make-terminal-ui :timeline timeline)))
    ;; Simulate a terminal size of 120x40
    (setf (autopoiesis.viz:ui-terminal-width ui) 120
          (autopoiesis.viz:ui-terminal-height ui) 40)
    (autopoiesis.viz:handle-resize ui)
    (let ((panel (autopoiesis.viz:ui-detail-panel ui)))
      (is (>= (autopoiesis.viz:panel-width panel) 20))
      (is (> (autopoiesis.viz:panel-height panel) 0))
      (is (< (autopoiesis.viz:panel-height panel) 40)))))

(test handle-resize-small-terminal
  "Test that handle-resize enforces minimum dimensions."
  (let* ((timeline (autopoiesis.viz:make-timeline))
         (ui (autopoiesis.viz:make-terminal-ui :timeline timeline)))
    ;; Simulate a very small terminal
    (setf (autopoiesis.viz:ui-terminal-width ui) 30
          (autopoiesis.viz:ui-terminal-height ui) 10)
    (autopoiesis.viz:handle-resize ui)
    (let ((vp (autopoiesis.viz:timeline-viewport timeline)))
      ;; Viewport dimensions should respect minimums
      (is (>= (autopoiesis.viz:viewport-width vp) 10))
      (is (>= (autopoiesis.viz:viewport-height vp) 5)))
    (let ((panel (autopoiesis.viz:ui-detail-panel ui)))
      (is (>= (autopoiesis.viz:panel-width panel) 20))
      (is (>= (autopoiesis.viz:panel-height panel) 5)))))

(test update-detects-size-change
  "Test that update sets needs-resize-p when terminal size changes."
  (let* ((timeline (autopoiesis.viz:make-timeline))
         (ui (autopoiesis.viz:make-terminal-ui :timeline timeline)))
    ;; After initial make, needs-resize-p should be nil (handled in constructor)
    (is (null (autopoiesis.viz:ui-needs-resize-p ui)))
    ;; Manually set dimensions to something different from what get-terminal-size returns
    (setf (autopoiesis.viz:ui-terminal-width ui) 999
          (autopoiesis.viz:ui-terminal-height ui) 999)
    ;; Update should detect the change
    (autopoiesis.viz:update ui)
    ;; Width/height should now match actual terminal, and resize should be flagged
    (is (not (= 999 (autopoiesis.viz:ui-terminal-width ui))))
    (is-true (autopoiesis.viz:ui-needs-resize-p ui))))

(test needs-resize-cleared-after-handle
  "Test that needs-resize-p is cleared after handle-resize."
  (let* ((timeline (autopoiesis.viz:make-timeline))
         (ui (autopoiesis.viz:make-terminal-ui :timeline timeline)))
    (setf (autopoiesis.viz:ui-needs-resize-p ui) t)
    (autopoiesis.viz:handle-resize ui)
    (is (null (autopoiesis.viz:ui-needs-resize-p ui)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Integration Tests
;;; ═══════════════════════════════════════════════════════════════════

(test session-to-timeline-basic
  "Test building a timeline from a session with thoughts."
  (let* ((agent (autopoiesis.agent:make-agent :name "viz-test-agent"))
         (session (autopoiesis.interface:make-session "test-user" agent)))
    ;; Add some thoughts to the agent's thought stream
    (autopoiesis.core:stream-append
     (autopoiesis.agent:agent-thought-stream agent)
     (autopoiesis.core:make-observation "first event" :source :test))
    (autopoiesis.core:stream-append
     (autopoiesis.agent:agent-thought-stream agent)
     (autopoiesis.core:make-observation "second event" :source :test))
    (autopoiesis.core:stream-append
     (autopoiesis.agent:agent-thought-stream agent)
     (autopoiesis.core:make-decision '((:a . 0.8) (:b . 0.2)) :a :rationale "chose a"))
    ;; Build timeline
    (let ((timeline (autopoiesis.viz:session-to-timeline session)))
      ;; Should have 3 snapshots
      (is (= 3 (length (autopoiesis.viz:timeline-snapshots timeline))))
      ;; Should have a current snapshot set
      (is (not (null (autopoiesis.viz:timeline-current timeline))))
      ;; Main branch should exist
      (is (= 3 (length (gethash "main" (autopoiesis.viz:timeline-branches timeline)))))
      ;; Snapshots should be chained via parent
      (let ((snaps (autopoiesis.viz:timeline-snapshots timeline)))
        (is (null (autopoiesis.snapshot:snapshot-parent (first snaps))))
        (is (string= (autopoiesis.snapshot:snapshot-id (first snaps))
                      (autopoiesis.snapshot:snapshot-parent (second snaps))))
        (is (string= (autopoiesis.snapshot:snapshot-id (second snaps))
                      (autopoiesis.snapshot:snapshot-parent (third snaps))))))))

(test session-to-timeline-empty
  "Test building a timeline from a session with no thoughts."
  (let* ((agent (autopoiesis.agent:make-agent :name "empty-agent"))
         (session (autopoiesis.interface:make-session "test-user" agent)))
    (let ((timeline (autopoiesis.viz:session-to-timeline session)))
      (is (= 0 (length (autopoiesis.viz:timeline-snapshots timeline))))
      (is (null (autopoiesis.viz:timeline-current timeline))))))

(test session-to-timeline-preserves-types
  "Test that thought types are preserved as snapshot metadata types."
  (let* ((agent (autopoiesis.agent:make-agent :name "type-test-agent"))
         (session (autopoiesis.interface:make-session "test-user" agent)))
    (autopoiesis.core:stream-append
     (autopoiesis.agent:agent-thought-stream agent)
     (autopoiesis.core:make-observation "saw something" :source :test))
    (autopoiesis.core:stream-append
     (autopoiesis.agent:agent-thought-stream agent)
     (autopoiesis.core:make-decision '((:x . 0.7) (:y . 0.3)) :x :rationale "picked x"))
    (autopoiesis.core:stream-append
     (autopoiesis.agent:agent-thought-stream agent)
     (autopoiesis.core:make-reflection "previous thought" "learned something"))
    (let* ((timeline (autopoiesis.viz:session-to-timeline session))
           (snaps (autopoiesis.viz:timeline-snapshots timeline)))
      (is (eq :observation
              (getf (autopoiesis.snapshot:snapshot-metadata (first snaps)) :type)))
      (is (eq :decision
              (getf (autopoiesis.snapshot:snapshot-metadata (second snaps)) :type)))
      (is (eq :reflection
              (getf (autopoiesis.snapshot:snapshot-metadata (third snaps)) :type))))))

(test terminal-ui-session-slot
  "Test that terminal-ui can hold a session reference."
  (let* ((agent (autopoiesis.agent:make-agent :name "ui-session-agent"))
         (session (autopoiesis.interface:make-session "test-user" agent))
         (ui (autopoiesis.viz:make-terminal-ui :session session)))
    (is (eq session (autopoiesis.viz:ui-session ui)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Help Overlay Tests
;;; ═══════════════════════════════════════════════════════════════════

(test toggle-help-on-off
  "Test that toggle-help toggles the help overlay state."
  (let ((ui (autopoiesis.viz:make-terminal-ui)))
    ;; Initially off
    (is (null (autopoiesis.viz:ui-show-help-p ui)))
    ;; Toggle on
    (autopoiesis.viz:toggle-help ui)
    (is-true (autopoiesis.viz:ui-show-help-p ui))
    ;; Toggle off
    (autopoiesis.viz:toggle-help ui)
    (is (null (autopoiesis.viz:ui-show-help-p ui)))))

(test render-help-overlay-output
  "Test that render-help-overlay produces output with keybinding info."
  (let* ((ui (autopoiesis.viz:make-terminal-ui)))
    (setf (autopoiesis.viz:ui-terminal-width ui) 80
          (autopoiesis.viz:ui-terminal-height ui) 24)
    (let ((*standard-output* (make-string-output-stream)))
      (autopoiesis.viz:render-help-overlay ui)
      (let ((output (get-output-stream-string *standard-output*)))
        ;; Should contain the title
        (is-true (search "Keybindings" output))
        ;; Should contain key descriptions
        (is-true (search "Move cursor left" output))
        (is-true (search "Quit" output))
        ;; Should contain the close hint
        (is-true (search "Press ? to close" output))))))

(test handle-input-question-mark-toggles-help
  "Test that ? key toggles help overlay via handle-input."
  (let ((ui (autopoiesis.viz:make-terminal-ui)))
    ;; Initially off
    (is (null (autopoiesis.viz:ui-show-help-p ui)))
    ;; Press ?
    (autopoiesis.viz:handle-input ui #\?)
    (is-true (autopoiesis.viz:ui-show-help-p ui))
    ;; Press ? again
    (autopoiesis.viz:handle-input ui #\?)
    (is (null (autopoiesis.viz:ui-show-help-p ui)))))
