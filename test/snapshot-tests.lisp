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

;;; ═══════════════════════════════════════════════════════════════════
;;; DAG Traversal Tests
;;; ═══════════════════════════════════════════════════════════════════

(test dag-collect-ancestors
  "Test collecting ancestors of a snapshot"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path)))
    (unwind-protect
         (progn
           ;; Create a chain: root -> child1 -> child2
           (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
                  (root-id (autopoiesis.snapshot:snapshot-id root)))
             (autopoiesis.snapshot:save-snapshot root store)
             (let* ((child1 (autopoiesis.snapshot:make-snapshot '(:child1 t) :parent root-id))
                    (child1-id (autopoiesis.snapshot:snapshot-id child1)))
               (autopoiesis.snapshot:save-snapshot child1 store)
               (let* ((child2 (autopoiesis.snapshot:make-snapshot '(:child2 t) :parent child1-id))
                      (child2-id (autopoiesis.snapshot:snapshot-id child2)))
                 (autopoiesis.snapshot:save-snapshot child2 store)
                 ;; Test ancestors of child2
                 (let ((ancestors (autopoiesis.snapshot:collect-ancestor-ids child2-id store)))
                   (is (= 2 (length ancestors)))
                   (is (string= child1-id (first ancestors)))
                   (is (string= root-id (second ancestors))))
                 ;; Root has no ancestors
                 (let ((ancestors (autopoiesis.snapshot:collect-ancestor-ids root-id store)))
                   (is (null ancestors)))))))
      (cleanup-temp-store temp-path))))

(test dag-find-common-ancestor
  "Test finding common ancestor of two snapshots"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path)))
    (unwind-protect
         (progn
           ;; Create a diamond: root -> (branch-a, branch-b)
           (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
                  (root-id (autopoiesis.snapshot:snapshot-id root)))
             (autopoiesis.snapshot:save-snapshot root store)
             (let* ((branch-a (autopoiesis.snapshot:make-snapshot '(:branch-a t) :parent root-id))
                    (branch-a-id (autopoiesis.snapshot:snapshot-id branch-a))
                    (branch-b (autopoiesis.snapshot:make-snapshot '(:branch-b t) :parent root-id))
                    (branch-b-id (autopoiesis.snapshot:snapshot-id branch-b)))
               (autopoiesis.snapshot:save-snapshot branch-a store)
               (autopoiesis.snapshot:save-snapshot branch-b store)
               ;; Common ancestor should be root
               (let ((ancestor (autopoiesis.snapshot:find-common-ancestor branch-a-id branch-b-id store)))
                 (is (not (null ancestor)))
                 (is (string= root-id (autopoiesis.snapshot:snapshot-id ancestor))))
               ;; Same snapshot - common ancestor is itself
               (let ((ancestor (autopoiesis.snapshot:find-common-ancestor branch-a-id branch-a-id store)))
                 (is (not (null ancestor)))
                 (is (string= branch-a-id (autopoiesis.snapshot:snapshot-id ancestor)))))))
      (cleanup-temp-store temp-path))))

(test dag-find-path
  "Test finding path between snapshots"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path)))
    (unwind-protect
         (progn
           ;; Create chain: root -> child1 -> child2
           (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
                  (root-id (autopoiesis.snapshot:snapshot-id root)))
             (autopoiesis.snapshot:save-snapshot root store)
             (let* ((child1 (autopoiesis.snapshot:make-snapshot '(:child1 t) :parent root-id))
                    (child1-id (autopoiesis.snapshot:snapshot-id child1)))
               (autopoiesis.snapshot:save-snapshot child1 store)
               (let* ((child2 (autopoiesis.snapshot:make-snapshot '(:child2 t) :parent child1-id))
                      (child2-id (autopoiesis.snapshot:snapshot-id child2)))
                 (autopoiesis.snapshot:save-snapshot child2 store)
                 ;; Forward path: root -> child2
                 (let ((path (autopoiesis.snapshot:find-path root-id child2-id store)))
                   (is (not (null path)))
                   (is (= 3 (length path)))
                   (is (string= root-id (first path)))
                   (is (string= child2-id (third path))))
                 ;; Backward path: child2 -> root
                 (let ((path (autopoiesis.snapshot:find-path child2-id root-id store)))
                   (is (not (null path)))
                   (is (= 3 (length path)))
                   (is (string= child2-id (first path)))
                   (is (string= root-id (third path))))
                 ;; Same snapshot
                 (let ((path (autopoiesis.snapshot:find-path root-id root-id store)))
                   (is (not (null path)))
                   (is (= 1 (length path))))))))
      (cleanup-temp-store temp-path))))

(test dag-distance
  "Test calculating distance between snapshots"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path)))
    (unwind-protect
         (progn
           ;; Create chain: root -> child1 -> child2
           (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
                  (root-id (autopoiesis.snapshot:snapshot-id root)))
             (autopoiesis.snapshot:save-snapshot root store)
             (let* ((child1 (autopoiesis.snapshot:make-snapshot '(:child1 t) :parent root-id))
                    (child1-id (autopoiesis.snapshot:snapshot-id child1)))
               (autopoiesis.snapshot:save-snapshot child1 store)
               (let* ((child2 (autopoiesis.snapshot:make-snapshot '(:child2 t) :parent child1-id))
                      (child2-id (autopoiesis.snapshot:snapshot-id child2)))
                 (autopoiesis.snapshot:save-snapshot child2 store)
                 (is (= 0 (autopoiesis.snapshot:dag-distance root-id root-id store)))
                 (is (= 1 (autopoiesis.snapshot:dag-distance root-id child1-id store)))
                 (is (= 2 (autopoiesis.snapshot:dag-distance root-id child2-id store)))))))
      (cleanup-temp-store temp-path))))

(test dag-ancestor-predicates
  "Test is-ancestor-p and is-descendant-p"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path)))
    (unwind-protect
         (progn
           (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
                  (root-id (autopoiesis.snapshot:snapshot-id root)))
             (autopoiesis.snapshot:save-snapshot root store)
             (let* ((child (autopoiesis.snapshot:make-snapshot '(:child t) :parent root-id))
                    (child-id (autopoiesis.snapshot:snapshot-id child)))
               (autopoiesis.snapshot:save-snapshot child store)
               (is (autopoiesis.snapshot:is-ancestor-p root-id child-id store))
               (is (not (autopoiesis.snapshot:is-ancestor-p child-id root-id store)))
               (is (autopoiesis.snapshot:is-descendant-p child-id root-id store))
               (is (not (autopoiesis.snapshot:is-descendant-p root-id child-id store))))))
      (cleanup-temp-store temp-path))))

(test dag-depth
  "Test calculating DAG depth"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path)))
    (unwind-protect
         (progn
           (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
                  (root-id (autopoiesis.snapshot:snapshot-id root)))
             (autopoiesis.snapshot:save-snapshot root store)
             (let* ((child1 (autopoiesis.snapshot:make-snapshot '(:child1 t) :parent root-id))
                    (child1-id (autopoiesis.snapshot:snapshot-id child1)))
               (autopoiesis.snapshot:save-snapshot child1 store)
               (let* ((child2 (autopoiesis.snapshot:make-snapshot '(:child2 t) :parent child1-id))
                      (child2-id (autopoiesis.snapshot:snapshot-id child2)))
                 (autopoiesis.snapshot:save-snapshot child2 store)
                 (is (= 0 (autopoiesis.snapshot:dag-depth root-id store)))
                 (is (= 1 (autopoiesis.snapshot:dag-depth child1-id store)))
                 (is (= 2 (autopoiesis.snapshot:dag-depth child2-id store)))))))
      (cleanup-temp-store temp-path))))

(test dag-find-root
  "Test finding root snapshot"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path)))
    (unwind-protect
         (progn
           (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
                  (root-id (autopoiesis.snapshot:snapshot-id root)))
             (autopoiesis.snapshot:save-snapshot root store)
             (let* ((child (autopoiesis.snapshot:make-snapshot '(:child t) :parent root-id))
                    (child-id (autopoiesis.snapshot:snapshot-id child)))
               (autopoiesis.snapshot:save-snapshot child store)
               ;; Find root from child
               (let ((found-root (autopoiesis.snapshot:find-root child-id store)))
                 (is (not (null found-root)))
                 (is (string= root-id (autopoiesis.snapshot:snapshot-id found-root))))
               ;; Find root from root
               (let ((found-root (autopoiesis.snapshot:find-root root-id store)))
                 (is (not (null found-root)))
                 (is (string= root-id (autopoiesis.snapshot:snapshot-id found-root)))))))
      (cleanup-temp-store temp-path))))

(test dag-walk-ancestors
  "Test walking ancestors"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path)))
    (unwind-protect
         (progn
           (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
                  (root-id (autopoiesis.snapshot:snapshot-id root)))
             (autopoiesis.snapshot:save-snapshot root store)
             (let* ((child1 (autopoiesis.snapshot:make-snapshot '(:child1 t) :parent root-id))
                    (child1-id (autopoiesis.snapshot:snapshot-id child1)))
               (autopoiesis.snapshot:save-snapshot child1 store)
               (let* ((child2 (autopoiesis.snapshot:make-snapshot '(:child2 t) :parent child1-id))
                      (child2-id (autopoiesis.snapshot:snapshot-id child2))
                      (visited nil))
                 (autopoiesis.snapshot:save-snapshot child2 store)
                 ;; Walk from child2 up
                 (autopoiesis.snapshot:walk-ancestors
                  child2-id
                  (lambda (snap)
                    (push (autopoiesis.snapshot:snapshot-id snap) visited))
                  store)
                 (is (= 3 (length visited)))
                 ;; Order: child2, child1, root
                 (is (string= child2-id (third visited)))
                 (is (string= root-id (first visited)))))))
      (cleanup-temp-store temp-path))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event Compaction Tests
;;; ═══════════════════════════════════════════════════════════════════

(test event-compaction-basic
  "Test basic event compaction"
  (let ((log (make-array 0 :adjustable t :fill-pointer 0))
        (state '(:current-state (a b c))))
    ;; Add some events
    (autopoiesis.snapshot:append-event
     (autopoiesis.snapshot:make-event :event-1 '(data 1))
     :log log)
    (autopoiesis.snapshot:append-event
     (autopoiesis.snapshot:make-event :event-2 '(data 2))
     :log log)
    (autopoiesis.snapshot:append-event
     (autopoiesis.snapshot:make-event :event-3 '(data 3))
     :log log)
    ;; Verify we have 3 events
    (is (= 3 (autopoiesis.snapshot:event-log-count :log log)))
    ;; Compact all events
    (let ((checkpoint (autopoiesis.snapshot:compact-events
                       log
                       (lambda () state))))
      ;; Checkpoint should exist
      (is (not (null checkpoint)))
      ;; State should be captured
      (is (equal state (autopoiesis.snapshot:checkpoint-state checkpoint)))
      ;; Event count should be recorded
      (is (= 3 (autopoiesis.snapshot:checkpoint-event-count checkpoint)))
      ;; Log should be empty
      (is (= 0 (autopoiesis.snapshot:event-log-count :log log))))))

(test event-compaction-keep-recent
  "Test event compaction with keep-recent"
  (let ((log (make-array 0 :adjustable t :fill-pointer 0))
        (state '(:current-state t)))
    ;; Add 5 events
    (loop for i from 1 to 5
          do (autopoiesis.snapshot:append-event
              (autopoiesis.snapshot:make-event :test-event (list :num i))
              :log log))
    ;; Keep 2 recent events
    (let ((checkpoint (autopoiesis.snapshot:compact-events
                       log
                       (lambda () state)
                       :keep-recent 2)))
      (is (not (null checkpoint)))
      ;; 3 events should have been compacted
      (is (= 3 (autopoiesis.snapshot:checkpoint-event-count checkpoint)))
      ;; 2 events should remain
      (is (= 2 (autopoiesis.snapshot:event-log-count :log log)))
      ;; Remaining events should be the last 2
      (let ((remaining-events nil))
        (autopoiesis.snapshot:replay-events
         (lambda (e) (push e remaining-events))
         :log log)
        (is (= 2 (length remaining-events)))))))

(test event-compaction-empty-log
  "Test compaction of empty log returns nil"
  (let ((log (make-array 0 :adjustable t :fill-pointer 0)))
    (let ((checkpoint (autopoiesis.snapshot:compact-events
                       log
                       (lambda () '(:state)))))
      (is (null checkpoint)))))

(test event-compaction-keep-all
  "Test compaction with keep-recent >= log size"
  (let ((log (make-array 0 :adjustable t :fill-pointer 0)))
    ;; Add 3 events
    (loop for i from 1 to 3
          do (autopoiesis.snapshot:append-event
              (autopoiesis.snapshot:make-event :test i)
              :log log))
    ;; Keep more than we have
    (let ((checkpoint (autopoiesis.snapshot:compact-events
                       log
                       (lambda () '(:state))
                       :keep-recent 10)))
      ;; Should still create checkpoint
      (is (not (null checkpoint)))
      ;; But all events should remain
      (is (= 3 (autopoiesis.snapshot:event-log-count :log log))))))

(test checkpoint-creation
  "Test checkpoint class creation"
  (let ((state '(:full-state (thoughts actions decisions)))
        (checkpoint (autopoiesis.snapshot:make-checkpoint
                     '(:full-state (thoughts actions decisions))
                     :event-count 42)))
    (is (not (null (autopoiesis.snapshot:checkpoint-id checkpoint))))
    (is (not (null (autopoiesis.snapshot:checkpoint-timestamp checkpoint))))
    (is (equal state (autopoiesis.snapshot:checkpoint-state checkpoint)))
    (is (= 42 (autopoiesis.snapshot:checkpoint-event-count checkpoint)))))

(test clear-event-log
  "Test clearing the event log"
  (let ((log (make-array 0 :adjustable t :fill-pointer 0)))
    (loop for i from 1 to 5
          do (autopoiesis.snapshot:append-event
              (autopoiesis.snapshot:make-event :test i)
              :log log))
    (is (= 5 (autopoiesis.snapshot:event-log-count :log log)))
    (autopoiesis.snapshot:clear-event-log :log log)
    (is (= 0 (autopoiesis.snapshot:event-log-count :log log)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; LRU Cache Tests
;;; ═══════════════════════════════════════════════════════════════════

(test lru-cache-basic
  "Test basic LRU cache operations"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 3)))
    ;; Test initial state
    (is (= 0 (autopoiesis.snapshot:cache-size cache)))
    (is (= 3 (autopoiesis.snapshot:cache-capacity cache)))
    ;; Test put and get
    (autopoiesis.snapshot:cache-put cache "key1" "value1")
    (is (= 1 (autopoiesis.snapshot:cache-size cache)))
    (is (string= "value1" (autopoiesis.snapshot:cache-get cache "key1")))
    ;; Test miss
    (is (null (autopoiesis.snapshot:cache-get cache "nonexistent")))))

(test lru-cache-eviction
  "Test LRU cache eviction when at capacity"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 3)))
    ;; Fill cache
    (autopoiesis.snapshot:cache-put cache "key1" "value1")
    (autopoiesis.snapshot:cache-put cache "key2" "value2")
    (autopoiesis.snapshot:cache-put cache "key3" "value3")
    (is (= 3 (autopoiesis.snapshot:cache-size cache)))
    ;; Add fourth item - should evict key1 (LRU)
    (autopoiesis.snapshot:cache-put cache "key4" "value4")
    (is (= 3 (autopoiesis.snapshot:cache-size cache)))
    (is (null (autopoiesis.snapshot:cache-get cache "key1")))
    (is (string= "value2" (autopoiesis.snapshot:cache-get cache "key2")))
    (is (string= "value3" (autopoiesis.snapshot:cache-get cache "key3")))
    (is (string= "value4" (autopoiesis.snapshot:cache-get cache "key4")))))

(test lru-cache-access-updates-order
  "Test that accessing an item updates its LRU position"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 3)))
    ;; Fill cache
    (autopoiesis.snapshot:cache-put cache "key1" "value1")
    (autopoiesis.snapshot:cache-put cache "key2" "value2")
    (autopoiesis.snapshot:cache-put cache "key3" "value3")
    ;; Access key1 to make it most recently used
    (autopoiesis.snapshot:cache-get cache "key1")
    ;; Add fourth item - should evict key2 (now LRU)
    (autopoiesis.snapshot:cache-put cache "key4" "value4")
    (is (string= "value1" (autopoiesis.snapshot:cache-get cache "key1")))
    (is (null (autopoiesis.snapshot:cache-get cache "key2")))
    (is (string= "value3" (autopoiesis.snapshot:cache-get cache "key3")))
    (is (string= "value4" (autopoiesis.snapshot:cache-get cache "key4")))))

(test lru-cache-update-existing
  "Test updating an existing cache entry"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 3)))
    (autopoiesis.snapshot:cache-put cache "key1" "value1")
    (autopoiesis.snapshot:cache-put cache "key1" "updated-value1")
    (is (= 1 (autopoiesis.snapshot:cache-size cache)))
    (is (string= "updated-value1" (autopoiesis.snapshot:cache-get cache "key1")))))

(test lru-cache-remove
  "Test removing items from cache"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 3)))
    (autopoiesis.snapshot:cache-put cache "key1" "value1")
    (autopoiesis.snapshot:cache-put cache "key2" "value2")
    (is (= 2 (autopoiesis.snapshot:cache-size cache)))
    ;; Remove existing key
    (is (autopoiesis.snapshot:cache-remove cache "key1"))
    (is (= 1 (autopoiesis.snapshot:cache-size cache)))
    (is (null (autopoiesis.snapshot:cache-get cache "key1")))
    ;; Remove non-existent key
    (is (not (autopoiesis.snapshot:cache-remove cache "nonexistent")))))

(test lru-cache-clear
  "Test clearing the cache"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 3)))
    (autopoiesis.snapshot:cache-put cache "key1" "value1")
    (autopoiesis.snapshot:cache-put cache "key2" "value2")
    (autopoiesis.snapshot:cache-clear cache)
    (is (= 0 (autopoiesis.snapshot:cache-size cache)))
    (is (null (autopoiesis.snapshot:cache-get cache "key1")))))

(test lru-cache-statistics
  "Test cache hit/miss statistics"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 3)))
    (autopoiesis.snapshot:cache-put cache "key1" "value1")
    ;; Hit
    (autopoiesis.snapshot:cache-get cache "key1")
    ;; Miss
    (autopoiesis.snapshot:cache-get cache "nonexistent")
    (is (= 1 (autopoiesis.snapshot:cache-hits cache)))
    (is (= 1 (autopoiesis.snapshot:cache-misses cache)))
    (is (= 0.5 (autopoiesis.snapshot:cache-hit-rate cache)))
    ;; Test stats plist
    (let ((stats (autopoiesis.snapshot:cache-stats cache)))
      (is (= 3 (getf stats :capacity)))
      (is (= 1 (getf stats :size)))
      (is (= 1 (getf stats :hits)))
      (is (= 1 (getf stats :misses))))))

(test lru-cache-resize
  "Test resizing the cache"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 5)))
    ;; Fill cache
    (loop for i from 1 to 5
          do (autopoiesis.snapshot:cache-put cache
                                             (format nil "key~d" i)
                                             (format nil "value~d" i)))
    (is (= 5 (autopoiesis.snapshot:cache-size cache)))
    ;; Resize down - should evict LRU entries
    (let ((evicted (autopoiesis.snapshot:resize-cache cache 3)))
      (is (= 2 evicted))
      (is (= 3 (autopoiesis.snapshot:cache-size cache)))
      ;; key1 and key2 should be evicted (LRU)
      (is (null (autopoiesis.snapshot:cache-get cache "key1")))
      (is (null (autopoiesis.snapshot:cache-get cache "key2")))
      ;; key3, key4, key5 should remain
      (is (string= "value3" (autopoiesis.snapshot:cache-get cache "key3")))
      (is (string= "value5" (autopoiesis.snapshot:cache-get cache "key5"))))))

(test lru-cache-contains-p
  "Test cache-contains-p without updating LRU order"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 3)))
    (autopoiesis.snapshot:cache-put cache "key1" "value1")
    (autopoiesis.snapshot:cache-put cache "key2" "value2")
    (autopoiesis.snapshot:cache-put cache "key3" "value3")
    ;; Check without updating order
    (is (autopoiesis.snapshot:cache-contains-p cache "key1"))
    (is (not (autopoiesis.snapshot:cache-contains-p cache "nonexistent")))
    ;; Add new item - key1 should still be evicted (contains-p didn't update order)
    (autopoiesis.snapshot:cache-put cache "key4" "value4")
    (is (null (autopoiesis.snapshot:cache-get cache "key1")))))

(test lru-cache-keys
  "Test getting cache keys in LRU order"
  (let ((cache (autopoiesis.snapshot:make-lru-cache :capacity 5)))
    (autopoiesis.snapshot:cache-put cache "key1" "value1")
    (autopoiesis.snapshot:cache-put cache "key2" "value2")
    (autopoiesis.snapshot:cache-put cache "key3" "value3")
    ;; Access key1 to make it most recent
    (autopoiesis.snapshot:cache-get cache "key1")
    (let ((keys (autopoiesis.snapshot:cache-keys cache)))
      ;; Most recent first
      (is (string= "key1" (first keys)))
      (is (string= "key3" (second keys)))
      (is (string= "key2" (third keys))))))

(test snapshot-store-with-lru-cache
  "Test snapshot store uses LRU cache correctly"
  (let* ((temp-path (make-temp-store-path))
         (store (autopoiesis.snapshot:make-snapshot-store temp-path :cache-capacity 3)))
    (unwind-protect
         (progn
           ;; Create and save 5 snapshots
           (let ((snap-ids nil))
             (loop for i from 1 to 5
                   do (let ((snap (autopoiesis.snapshot:make-snapshot (list :num i))))
                        (autopoiesis.snapshot:save-snapshot snap store)
                        (push (autopoiesis.snapshot:snapshot-id snap) snap-ids)))
             (setf snap-ids (nreverse snap-ids))
             ;; Cache should only have last 3 snapshots
             (let ((stats (autopoiesis.snapshot:snapshot-cache-stats store)))
               (is (= 3 (getf stats :size)))
               (is (= 3 (getf stats :capacity))))
             ;; Loading first snapshot should cause cache miss then cache it
             (let ((snap1 (autopoiesis.snapshot:load-snapshot (first snap-ids) store)))
               (is (not (null snap1)))
               ;; Check stats show a miss
               (let ((stats (autopoiesis.snapshot:snapshot-cache-stats store)))
                 (is (>= (getf stats :misses) 1))))))
      (cleanup-temp-store temp-path))))
