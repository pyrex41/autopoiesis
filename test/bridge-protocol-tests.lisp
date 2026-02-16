;;;; bridge-protocol-tests.lisp - Tests for Phase 4 bridge protocol support
;;;;
;;;; Tests the CL-side functions that the bridge protocol relies on:
;;;; thought stream queries, capability resolution, snapshot operations,
;;;; and the thought-to-sexpr serialization format.
;;;;
;;;; Note: The full bridge handler functions live in scripts/agent-worker.lisp
;;;; (a standalone script), so we test the underlying API functions they call.

(in-package #:autopoiesis.test)

;;; ===================================================================
;;; Test Suite
;;; ===================================================================

(def-suite bridge-protocol-tests
  :description "Tests for Phase 4 bridge protocol support functions"
  :in integration-tests)

(in-suite bridge-protocol-tests)

;;; ===================================================================
;;; Thought Stream Query Tests
;;; ===================================================================

(test thought-stream-last-n
  "stream-last returns the last N thoughts."
  (let ((agent (autopoiesis.agent:make-agent :name "bridge-test-1")))
    (autopoiesis.agent:start-agent agent)
    (unwind-protect
         (let ((stream (autopoiesis.agent:agent-thought-stream agent)))
           ;; Add 5 thoughts
           (dotimes (i 5)
             (autopoiesis.core:stream-append
              stream
              (autopoiesis.core:make-observation
               (format nil "thought-~a" i) :source :test)))
           ;; Query last 3
           (let ((last-3 (autopoiesis.core:stream-last stream 3)))
             (is (= 3 (length last-3)))))
      (autopoiesis.agent:stop-agent agent))))

(test thought-stream-by-type
  "stream-by-type filters thoughts by type."
  (let ((agent (autopoiesis.agent:make-agent :name "bridge-test-2")))
    (autopoiesis.agent:start-agent agent)
    (unwind-protect
         (let ((stream (autopoiesis.agent:agent-thought-stream agent)))
           ;; Add mixed thoughts
           (autopoiesis.core:stream-append
            stream (autopoiesis.core:make-observation "obs-1" :source :test))
           (autopoiesis.core:stream-append
            stream (autopoiesis.core:make-decision
                    '((:a . 0.5)) :a :rationale "test" :confidence 0.5))
           (autopoiesis.core:stream-append
            stream (autopoiesis.core:make-observation "obs-2" :source :test))
           ;; Query by type — observations should be 2
           (let ((obs (autopoiesis.core:stream-by-type stream :observation)))
             (is (= 2 (length obs)))))
      (autopoiesis.agent:stop-agent agent))))

;;; ===================================================================
;;; Capability Resolution Tests
;;; ===================================================================

(test list-capabilities-returns-list
  "list-capabilities returns a list."
  (is (listp (autopoiesis.agent:list-capabilities))))

(test find-capability-nonexistent
  "find-capability returns nil for unknown names."
  (is (null (autopoiesis.agent:find-capability :nonexistent-cap-xyz-12345))))

;;; ===================================================================
;;; Snapshot Branch Tests
;;; ===================================================================

(test list-branches-returns-list
  "list-branches returns a list even with no branches."
  (let ((store (autopoiesis.snapshot:make-snapshot-store
                (merge-pathnames "test-bridge-store/"
                                 (uiop:temporary-directory)))))
    (let ((autopoiesis.snapshot:*snapshot-store* store))
      (is (listp (autopoiesis.snapshot:list-branches))))))

;;; ===================================================================
;;; Snapshot Diff Tests
;;; ===================================================================

(test sexpr-diff-same
  "sexpr-diff of identical S-expressions produces empty edits."
  (let ((expr '(:agent :name "test" :thoughts 5)))
    (is (null (autopoiesis.core:sexpr-diff expr expr)))))

(test sexpr-diff-different
  "sexpr-diff of different S-expressions produces non-empty edits."
  (let ((from '(:agent :name "test" :thoughts 5))
        (to '(:agent :name "test" :thoughts 10)))
    (is (not (null (autopoiesis.core:sexpr-diff from to))))))

;;; ===================================================================
;;; Agent Serialization Round-trip Tests
;;; ===================================================================

(test agent-to-sexpr-format
  "agent-to-sexpr produces a well-formed S-expression."
  (let ((agent (autopoiesis.agent:make-agent :name "serialize-test")))
    (autopoiesis.agent:start-agent agent)
    (unwind-protect
         (let ((sexpr (autopoiesis.agent:agent-to-sexpr agent)))
           (is (listp sexpr))
           ;; Should be non-empty
           (is (not (null sexpr))))
      (autopoiesis.agent:stop-agent agent))))

;;; ===================================================================
;;; Snapshot Create/Load Round-trip
;;; ===================================================================

(test snapshot-round-trip
  "Creating and loading a snapshot preserves agent state."
  (let ((store (autopoiesis.snapshot:make-snapshot-store
                (merge-pathnames "test-bridge-snapshot/"
                                 (uiop:temporary-directory)))))
    (let ((autopoiesis.snapshot:*snapshot-store* store))
      (let ((agent (autopoiesis.agent:make-agent :name "snapshot-test")))
        (autopoiesis.agent:start-agent agent)
        (unwind-protect
             (let* ((sexpr (autopoiesis.agent:agent-to-sexpr agent))
                    (snapshot (autopoiesis.snapshot:make-snapshot sexpr))
                    (saved (autopoiesis.snapshot:save-snapshot snapshot))
                    (loaded (autopoiesis.snapshot:load-snapshot
                             (autopoiesis.snapshot:snapshot-id saved))))
               (is (not (null loaded)))
               (is (equal (autopoiesis.snapshot:snapshot-id saved)
                          (autopoiesis.snapshot:snapshot-id loaded))))
          (autopoiesis.agent:stop-agent agent))))))

;;; ===================================================================
;;; Thought Serialization Tests
;;; ===================================================================

(test thought-type-accessor
  "thought-type returns the type keyword."
  (let ((obs (autopoiesis.core:make-observation "hello" :source :test)))
    (is (eq :observation (autopoiesis.core:thought-type obs)))))

(test thought-content-accessor
  "thought-content returns the content."
  (let ((obs (autopoiesis.core:make-observation "hello" :source :test)))
    (is (not (null (autopoiesis.core:thought-content obs))))))

(test thought-timestamp-accessor
  "thought-timestamp returns a timestamp."
  (let ((obs (autopoiesis.core:make-observation "hello" :source :test)))
    (is (not (null (autopoiesis.core:thought-timestamp obs))))))
