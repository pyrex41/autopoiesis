;;;; snapshot-tests.lisp - Tests for snapshot layer
;;;;
;;;; Tests snapshot creation and navigation.

(in-package #:autopoiesis.test)

(def-suite snapshot-tests
  :description "Snapshot layer tests")

(in-suite snapshot-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Tests
;;; ═══════════════════════════════════════════════════════════════════

(test snapshot-creation
  "Test basic snapshot creation"
  (let* ((state '(:agent-data (thoughts ((id . 1) (content . test)))))
         (snap (autopoiesis.snapshot:make-snapshot state)))
    (is (not (null (autopoiesis.snapshot:snapshot-id snap))))
    (is (not (null (autopoiesis.snapshot:snapshot-hash snap))))
    (is (equal state (autopoiesis.snapshot:snapshot-agent-state snap)))))

(test snapshot-hash-dedup
  "Test that identical states produce same hash"
  (let* ((state '(a b c))
         (snap1 (autopoiesis.snapshot:make-snapshot state))
         (snap2 (autopoiesis.snapshot:make-snapshot state)))
    (is (string= (autopoiesis.snapshot:snapshot-hash snap1)
                 (autopoiesis.snapshot:snapshot-hash snap2)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Content Store Tests
;;; ═══════════════════════════════════════════════════════════════════

(test content-store-basic
  "Test content store operations"
  (let ((store (autopoiesis.snapshot:make-content-store))
        (content '(some data here)))
    (let ((hash (autopoiesis.snapshot:store-put store content)))
      (is (stringp hash))
      (is (autopoiesis.snapshot:store-exists-p store hash))
      (is (equal content (autopoiesis.snapshot:store-get store hash)))
      (autopoiesis.snapshot:store-delete store hash)
      (is (not (autopoiesis.snapshot:store-exists-p store hash))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Branch Tests
;;; ═══════════════════════════════════════════════════════════════════

(test branch-operations
  "Test branch creation and switching"
  (let ((registry (make-hash-table :test 'equal)))
    (let ((branch (autopoiesis.snapshot:create-branch "main" :registry registry)))
      (is (string= "main" (autopoiesis.snapshot:branch-name branch)))
      (is (eq branch (gethash "main" registry))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Log Tests
;;; ═══════════════════════════════════════════════════════════════════

(test event-log-append
  "Test event log append and replay"
  (let ((log (make-array 0 :adjustable t :fill-pointer 0))
        (events nil))
    (autopoiesis.snapshot:append-event
     (autopoiesis.snapshot:make-event :thought-added '(content test))
     :log log)
    (autopoiesis.snapshot:append-event
     (autopoiesis.snapshot:make-event :action-taken '(action data))
     :log log)
    (autopoiesis.snapshot:replay-events
     (lambda (e) (push e events))
     :log log)
    (is (= 2 (length events)))))
