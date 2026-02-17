;;;; conversation-tests.lisp - Tests for the conversation module
;;;;
;;;; Tests for Phase 6: Turn/Context DAG model built on the substrate.

(in-package #:autopoiesis.test)

(def-suite conversation-tests
  :description "Conversation turn/context tests")

(in-suite conversation-tests)

;;; ===================================================================
;;; Context creation
;;; ===================================================================

(test make-context-basic
  "make-context creates a context entity with name and type."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let ((ctx (autopoiesis.conversation:make-context "test-conversation")))
      (is (integerp ctx))
      (is (equal "test-conversation"
                 (autopoiesis.substrate:entity-attr ctx :context/name)))
      (is (eq :context
              (autopoiesis.substrate:entity-attr ctx :entity/type)))
      (is (integerp (autopoiesis.substrate:entity-attr ctx :context/created-at))))))

(test make-context-with-agent
  "make-context with agent-eid links context to an agent."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((agent-eid (autopoiesis.substrate:intern-id :test-agent))
           (ctx (autopoiesis.conversation:make-context "agent-conv"
                                                        :agent-eid agent-eid)))
      (is (= agent-eid
             (autopoiesis.substrate:entity-attr ctx :context/agent))))))

(test make-context-no-head-initially
  "New context has no head turn."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let ((ctx (autopoiesis.conversation:make-context "empty")))
      (is (null (autopoiesis.conversation:context-head ctx))))))

;;; ===================================================================
;;; Turn operations
;;; ===================================================================

(test append-turn-stores-datoms
  "append-turn stores turn datoms and updates context head."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "test"))
           (turn (autopoiesis.conversation:append-turn ctx :user "Hello, world!")))
      (is (integerp turn))
      ;; Turn entity type
      (is (eq :turn (autopoiesis.substrate:entity-attr turn :entity/type)))
      ;; Turn role
      (is (eq :user (autopoiesis.substrate:entity-attr turn :turn/role)))
      ;; Content hash stored
      (is (stringp (autopoiesis.substrate:entity-attr turn :turn/content-hash)))
      ;; Context reference
      (is (= ctx (autopoiesis.substrate:entity-attr turn :turn/context)))
      ;; Timestamp
      (is (integerp (autopoiesis.substrate:entity-attr turn :turn/timestamp)))
      ;; Context head updated
      (is (= turn (autopoiesis.conversation:context-head ctx))))))

(test turn-content-loads-from-blob
  "turn-content loads full text from blob store."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "test"))
           (turn (autopoiesis.conversation:append-turn ctx :user "Hello from blob!")))
      (is (equal "Hello from blob!"
                 (autopoiesis.conversation:turn-content turn))))))

(test append-turn-with-optional-fields
  "append-turn stores model, tokens, tool-use, and metadata."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "test"))
           (turn (autopoiesis.conversation:append-turn
                  ctx :assistant "Response"
                  :model :claude-opus-4-6
                  :tokens 500
                  :tool-use '((:name "read_file" :input "/tmp/foo"))
                  :metadata "extra-info")))
      (is (eq :claude-opus-4-6 (autopoiesis.substrate:entity-attr turn :turn/model)))
      (is (= 500 (autopoiesis.substrate:entity-attr turn :turn/tokens)))
      (is (stringp (autopoiesis.substrate:entity-attr turn :turn/tool-use)))
      (is (equal "extra-info" (autopoiesis.substrate:entity-attr turn :turn/metadata))))))

(test append-turn-parent-chain
  "Multiple turns form a parent chain."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "test"))
           (t1 (autopoiesis.conversation:append-turn ctx :user "First"))
           (t2 (autopoiesis.conversation:append-turn ctx :assistant "Second"))
           (t3 (autopoiesis.conversation:append-turn ctx :user "Third")))
      ;; First turn has no parent
      (is (null (autopoiesis.substrate:entity-attr t1 :turn/parent)))
      ;; Second's parent is first
      (is (= t1 (autopoiesis.substrate:entity-attr t2 :turn/parent)))
      ;; Third's parent is second
      (is (= t2 (autopoiesis.substrate:entity-attr t3 :turn/parent)))
      ;; Head is the last turn
      (is (= t3 (autopoiesis.conversation:context-head ctx))))))

;;; ===================================================================
;;; Context history
;;; ===================================================================

(test context-history-chronological
  "context-history returns turns in chronological order."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "test"))
           (t1 (autopoiesis.conversation:append-turn ctx :user "First"))
           (t2 (autopoiesis.conversation:append-turn ctx :assistant "Second"))
           (t3 (autopoiesis.conversation:append-turn ctx :user "Third")))
      (let ((history (autopoiesis.conversation:context-history ctx)))
        (is (= 3 (length history)))
        (is (= t1 (first history)))
        (is (= t2 (second history)))
        (is (= t3 (third history)))))))

(test context-history-respects-limit
  "context-history respects the limit parameter."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let ((ctx (autopoiesis.conversation:make-context "test")))
      (dotimes (i 5)
        (autopoiesis.conversation:append-turn
         ctx :user (format nil "Turn ~D" i)))
      ;; Limit to 3 -- should get the most recent 3
      (let ((history (autopoiesis.conversation:context-history ctx :limit 3)))
        (is (= 3 (length history)))))))

(test context-history-empty
  "context-history returns nil for context with no turns."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let ((ctx (autopoiesis.conversation:make-context "empty")))
      (is (null (autopoiesis.conversation:context-history ctx))))))

;;; ===================================================================
;;; Fork context
;;; ===================================================================

(test fork-context-independent
  "fork-context creates independent context pointing to same head."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "original"))
           (t1 (autopoiesis.conversation:append-turn ctx :user "Shared"))
           (fork (autopoiesis.conversation:fork-context ctx)))
      ;; Fork points to same head as original
      (is (= t1 (autopoiesis.conversation:context-head fork)))
      (is (= t1 (autopoiesis.conversation:context-head ctx)))
      ;; Fork has forked-from pointer
      (is (= ctx (autopoiesis.substrate:entity-attr fork :context/forked-from)))
      ;; Fork has its own name
      (is (equal "fork-original"
                 (autopoiesis.substrate:entity-attr fork :context/name)))
      ;; Fork has entity type
      (is (eq :context
              (autopoiesis.substrate:entity-attr fork :entity/type))))))

(test fork-context-custom-name
  "fork-context accepts a custom name."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "original"))
           (fork (autopoiesis.conversation:fork-context ctx :name "my-branch")))
      (is (equal "my-branch"
                 (autopoiesis.substrate:entity-attr fork :context/name))))))

(test fork-append-doesnt-affect-original
  "Appending to forked context doesn't affect original."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "original"))
           (shared (autopoiesis.conversation:append-turn ctx :user "Shared turn"))
           (fork (autopoiesis.conversation:fork-context ctx)))
      ;; Append to fork only
      (autopoiesis.conversation:append-turn fork :assistant "Fork-only response")
      ;; Original still points to shared turn
      (is (= shared (autopoiesis.conversation:context-head ctx)))
      ;; Fork has moved forward
      (is (/= shared (autopoiesis.conversation:context-head fork)))
      ;; Original history is 1 turn
      (is (= 1 (length (autopoiesis.conversation:context-history ctx))))
      ;; Fork history is 2 turns
      (is (= 2 (length (autopoiesis.conversation:context-history fork)))))))

(test fork-empty-context
  "Forking an empty context works (no head)."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "empty"))
           (fork (autopoiesis.conversation:fork-context ctx)))
      (is (null (autopoiesis.conversation:context-head fork)))
      (is (null (autopoiesis.conversation:context-history fork))))))

;;; ===================================================================
;;; Query helpers
;;; ===================================================================

(test find-turns-by-role-filters
  "find-turns-by-role returns only turns matching the given role."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "test"))
           (u1 (autopoiesis.conversation:append-turn ctx :user "Q1"))
           (a1 (autopoiesis.conversation:append-turn ctx :assistant "A1"))
           (u2 (autopoiesis.conversation:append-turn ctx :user "Q2")))
      (declare (ignore a1))
      (let ((user-turns (autopoiesis.conversation:find-turns-by-role ctx :user)))
        (is (= 2 (length user-turns)))
        (is (= u1 (first user-turns)))
        (is (= u2 (second user-turns))))
      (let ((asst-turns (autopoiesis.conversation:find-turns-by-role ctx :assistant)))
        (is (= 1 (length asst-turns)))))))

(test find-turns-by-time-range
  "find-turns-by-time-range returns turns within the time window."
  (autopoiesis.substrate:with-store ()
    (autopoiesis.substrate::reset-memory-blobs)
    (let* ((ctx (autopoiesis.conversation:make-context "test"))
           (now (get-universal-time)))
      (autopoiesis.conversation:append-turn ctx :user "Turn 1")
      (autopoiesis.conversation:append-turn ctx :user "Turn 2")
      ;; All turns should be within a 10-second window around now
      (let ((found (autopoiesis.conversation:find-turns-by-time-range
                    ctx (- now 5) (+ now 5))))
        (is (= 2 (length found)))))))
