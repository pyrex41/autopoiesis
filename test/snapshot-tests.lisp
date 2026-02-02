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

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Persistence Tests
;;; ═══════════════════════════════════════════════════════════════════

(defun make-temp-store-path ()
  "Create a temporary directory path for test store."
  (let ((path (merge-pathnames
               (format nil "autopoiesis-test-~a/" (autopoiesis.core:make-uuid))
               (uiop:temporary-directory))))
    (ensure-directories-exist path)
    path))

(defun cleanup-temp-store (path)
  "Remove temporary test store directory."
  (when (probe-file path)
    (uiop:delete-directory-tree path :validate t)))

(test snapshot-persistence-basic
  "Test basic snapshot save and load"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path))
         (state '(:test-data (foo bar baz)))
         (snap (autopoiesis.snapshot:make-snapshot state)))
    (unwind-protect
         (progn
           ;; Save snapshot
           (autopoiesis.snapshot:save-snapshot snap store)
           (let ((id (autopoiesis.snapshot:snapshot-id snap)))
             ;; Verify it exists
             (is (autopoiesis.snapshot:snapshot-exists-p id store))
             ;; Clear cache to force disk read
             (autopoiesis.snapshot:clear-snapshot-cache store)
             ;; Load and verify
             (let ((loaded (autopoiesis.snapshot:load-snapshot id store)))
               (is (not (null loaded)))
               (is (string= id (autopoiesis.snapshot:snapshot-id loaded)))
               (is (equal state (autopoiesis.snapshot:snapshot-agent-state loaded)))
               (is (string= (autopoiesis.snapshot:snapshot-hash snap)
                            (autopoiesis.snapshot:snapshot-hash loaded))))))
      ;; Cleanup
      (cleanup-temp-store temp-path))))

(test snapshot-persistence-parent-child
  "Test snapshot parent-child relationships"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path))
         (parent-state '(:parent t))
         (child-state '(:child t))
         (parent-snap (autopoiesis.snapshot:make-snapshot parent-state))
         (parent-id (autopoiesis.snapshot:snapshot-id parent-snap))
         (child-snap (autopoiesis.snapshot:make-snapshot child-state :parent parent-id)))
    (unwind-protect
         (progn
           ;; Save both
           (autopoiesis.snapshot:save-snapshot parent-snap store)
           (autopoiesis.snapshot:save-snapshot child-snap store)
           (let ((child-id (autopoiesis.snapshot:snapshot-id child-snap)))
             ;; Verify parent-child relationship
             (let ((children (autopoiesis.snapshot:snapshot-children parent-id store)))
               (is (not (null (member child-id children :test #'string=)))))
             ;; Verify ancestors
             (let ((ancestors (autopoiesis.snapshot:snapshot-ancestors child-id store)))
               (is (not (null (member parent-id ancestors :test #'string=)))))
             ;; Verify root listing
             (let ((roots (autopoiesis.snapshot:list-snapshots :root-only t :store store)))
               (is (not (null (member parent-id roots :test #'string=))))
               (is (null (member child-id roots :test #'string=))))))
      ;; Cleanup
      (cleanup-temp-store temp-path))))

(test snapshot-serialization-roundtrip
  "Test snapshot serialization and deserialization"
  (let* ((state '(:complex-data ((a . 1) (b . 2)) :nested (x y z)))
         (snap (autopoiesis.snapshot:make-snapshot state :parent "parent-id"
                                                   :metadata '(:tag test))))
    (let* ((sexpr (autopoiesis.snapshot:snapshot-to-sexpr snap))
           (restored (autopoiesis.snapshot:sexpr-to-snapshot sexpr)))
      (is (string= (autopoiesis.snapshot:snapshot-id snap)
                   (autopoiesis.snapshot:snapshot-id restored)))
      (is (string= (autopoiesis.snapshot:snapshot-parent snap)
                   (autopoiesis.snapshot:snapshot-parent restored)))
      (is (equal state (autopoiesis.snapshot:snapshot-agent-state restored)))
      (is (equal (autopoiesis.snapshot:snapshot-metadata snap)
                 (autopoiesis.snapshot:snapshot-metadata restored))))))

(test snapshot-delete
  "Test snapshot deletion"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path))
         (snap (autopoiesis.snapshot:make-snapshot '(:to-delete t))))
    (unwind-protect
         (progn
           (autopoiesis.snapshot:save-snapshot snap store)
           (let ((id (autopoiesis.snapshot:snapshot-id snap)))
             ;; Verify exists
             (is (autopoiesis.snapshot:snapshot-exists-p id store))
             ;; Delete
             (autopoiesis.snapshot:delete-snapshot id store)
             ;; Verify gone
             (is (not (autopoiesis.snapshot:snapshot-exists-p id store)))
             (is (null (autopoiesis.snapshot:load-snapshot id store)))))
      (cleanup-temp-store temp-path))))

(test snapshot-index-rebuild
  "Test index rebuild from disk"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path))
         (snaps (loop for i from 1 to 3
                      collect (autopoiesis.snapshot:make-snapshot (list :num i)))))
    (unwind-protect
         (progn
           ;; Save snapshots
           (dolist (snap snaps)
             (autopoiesis.snapshot:save-snapshot snap store))
           (let ((ids (mapcar #'autopoiesis.snapshot:snapshot-id snaps)))
             ;; Close store (saves index)
             (autopoiesis.snapshot:close-store store)
             ;; Create new store from same path - should load index
             (let ((store2 (autopoiesis.snapshot:make-snapshot-store temp-path)))
               (dolist (id ids)
                 (is (autopoiesis.snapshot:snapshot-exists-p id store2))))))
      (cleanup-temp-store temp-path))))
