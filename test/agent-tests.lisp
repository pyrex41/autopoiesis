;;;; agent-tests.lisp - Tests for agent layer
;;;;
;;;; Tests agent lifecycle and capabilities.

(in-package #:autopoiesis.test)

(def-suite agent-tests
  :description "Agent layer tests")

(in-suite agent-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Lifecycle Tests
;;; ═══════════════════════════════════════════════════════════════════

(test agent-creation
  "Test basic agent creation"
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (is (not (null (autopoiesis.agent:agent-id agent))))
    (is (string= "test-agent" (autopoiesis.agent:agent-name agent)))
    (is (eq :initialized (autopoiesis.agent:agent-state agent)))))

(test agent-lifecycle
  "Test agent state transitions"
  (let ((agent (autopoiesis.agent:make-agent)))
    (is (not (autopoiesis.agent:agent-running-p agent)))
    (autopoiesis.agent:start-agent agent)
    (is (autopoiesis.agent:agent-running-p agent))
    (autopoiesis.agent:pause-agent agent)
    (is (eq :paused (autopoiesis.agent:agent-state agent)))
    (autopoiesis.agent:resume-agent agent)
    (is (autopoiesis.agent:agent-running-p agent))
    (autopoiesis.agent:stop-agent agent)
    (is (eq :stopped (autopoiesis.agent:agent-state agent)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Capability Tests
;;; ═══════════════════════════════════════════════════════════════════

(test capability-registration
  "Test capability registration and lookup"
  (let ((registry (make-hash-table :test 'equal))
        (cap (autopoiesis.agent:make-capability
              "test-cap"
              (lambda () "result")
              :description "A test capability")))
    (autopoiesis.agent:register-capability cap :registry registry)
    (is (eq cap (autopoiesis.agent:find-capability "test-cap" :registry registry)))
    (autopoiesis.agent:unregister-capability "test-cap" :registry registry)
    (is (null (autopoiesis.agent:find-capability "test-cap" :registry registry)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Spawning Tests
;;; ═══════════════════════════════════════════════════════════════════

(test agent-spawning
  "Test spawning child agents"
  (let ((parent (autopoiesis.agent:make-agent :name "parent")))
    (let ((child (autopoiesis.agent:spawn-agent parent :name "child")))
      (is (equal (autopoiesis.agent:agent-id parent)
                 (autopoiesis.agent:agent-parent child)))
      (is (member (autopoiesis.agent:agent-id child)
                  (autopoiesis.agent:agent-children parent)
                  :test #'equal)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; defcapability Macro Tests
;;; ═══════════════════════════════════════════════════════════════════

(test parse-defcapability-body-docstring-only
  "Test parsing body with just a docstring and implementation"
  (multiple-value-bind (doc options body)
      (autopoiesis.agent:parse-defcapability-body '("A docstring" (+ 1 2)))
    (is (string= "A docstring" doc))
    (is (null options))
    (is (equal '((+ 1 2)) body))))

(test parse-defcapability-body-with-options
  "Test parsing body with options and :body marker"
  (multiple-value-bind (doc options body)
      (autopoiesis.agent:parse-defcapability-body
       '("Search the web" :permissions (:network) :body (search query)))
    (is (string= "Search the web" doc))
    (is (equal '(:permissions (:network)) options))
    (is (equal '((search query)) body))))

(test parse-defcapability-body-no-docstring
  "Test parsing body without docstring"
  (multiple-value-bind (doc options body)
      (autopoiesis.agent:parse-defcapability-body '(:permissions (:io) :body (read-file path)))
    (is (string= "" doc))
    (is (equal '(:permissions (:io)) options))
    (is (equal '((read-file path)) body))))

(test parse-capability-params-required
  "Test parsing required parameters"
  (let ((params (autopoiesis.agent:parse-capability-params '(a b c))))
    (is (equal '((a t :required t) (b t :required t) (c t :required t)) params))))

(test parse-capability-params-optional
  "Test parsing optional parameters"
  (let ((params (autopoiesis.agent:parse-capability-params '(a &optional b (c 10)))))
    (is (equal '((a t :required t) (b t) (c t :default 10)) params))))

(test parse-capability-params-keyword
  "Test parsing keyword parameters"
  (let ((params (autopoiesis.agent:parse-capability-params '(query &key (limit 10) verbose))))
    (is (equal '((query t :required t) (limit t :default 10) (verbose t)) params))))

(test defcapability-simple
  "Test defcapability with simple body"
  (let ((registry (make-hash-table :test 'equal)))
    ;; Clear any existing registration and use a fresh registry
    (let ((autopoiesis.agent::*capability-registry* registry))
      (eval '(autopoiesis.agent:defcapability test-add (a b)
               "Add two numbers"
               (+ a b)))
      (let ((cap (autopoiesis.agent:find-capability 'test-add :registry registry)))
        (is (not (null cap)))
        (is (string= "Add two numbers" (autopoiesis.agent:capability-description cap)))
        (is (= 5 (funcall (autopoiesis.agent:capability-function cap) 2 3)))))))

(test defcapability-with-options
  "Test defcapability with options and :body marker"
  (let ((registry (make-hash-table :test 'equal)))
    (let ((autopoiesis.agent::*capability-registry* registry))
      (eval '(autopoiesis.agent:defcapability test-multiply (x y)
               "Multiply two numbers"
               :permissions (:math)
               :body
               (* x y)))
      (let ((cap (autopoiesis.agent:find-capability 'test-multiply :registry registry)))
        (is (not (null cap)))
        (is (equal '(:math) (autopoiesis.agent:capability-permissions cap)))
        (is (= 12 (funcall (autopoiesis.agent:capability-function cap) 3 4)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Priority Queue Tests
;;; ═══════════════════════════════════════════════════════════════════

(test priority-queue-basic
  "Test basic priority queue operations"
  (let ((pq (autopoiesis.agent:make-priority-queue)))
    (is (autopoiesis.agent:pqueue-empty-p pq))
    (is (= 0 (autopoiesis.agent:pqueue-size pq)))
    ;; Add items with different priorities
    (autopoiesis.agent:pqueue-push pq :low 1.0)
    (autopoiesis.agent:pqueue-push pq :high 3.0)
    (autopoiesis.agent:pqueue-push pq :medium 2.0)
    (is (not (autopoiesis.agent:pqueue-empty-p pq)))
    (is (= 3 (autopoiesis.agent:pqueue-size pq)))
    ;; Peek should return highest priority
    (multiple-value-bind (item priority)
        (autopoiesis.agent:pqueue-peek pq)
      (is (eq :high item))
      (is (= 3.0 priority)))
    ;; Pop should return in priority order
    (is (eq :high (autopoiesis.agent:pqueue-pop pq)))
    (is (eq :medium (autopoiesis.agent:pqueue-pop pq)))
    (is (eq :low (autopoiesis.agent:pqueue-pop pq)))
    (is (autopoiesis.agent:pqueue-empty-p pq))))

(test priority-queue-remove
  "Test removing items from priority queue"
  (let ((pq (autopoiesis.agent:make-priority-queue)))
    (autopoiesis.agent:pqueue-push pq :a 1.0)
    (autopoiesis.agent:pqueue-push pq :b 2.0)
    (autopoiesis.agent:pqueue-push pq :c 3.0)
    (autopoiesis.agent:pqueue-remove pq :b)
    (is (= 2 (autopoiesis.agent:pqueue-size pq)))
    (is (eq :c (autopoiesis.agent:pqueue-pop pq)))
    (is (eq :a (autopoiesis.agent:pqueue-pop pq)))))

(test priority-queue-map
  "Test mapping over priority queue to update priorities"
  (let ((pq (autopoiesis.agent:make-priority-queue)))
    (autopoiesis.agent:pqueue-push pq :a 1.0)
    (autopoiesis.agent:pqueue-push pq :b 2.0)
    ;; Double all priorities
    (autopoiesis.agent:pqueue-map pq (lambda (item priority)
                                       (declare (ignore item))
                                       (* priority 2)))
    ;; Should still be in same order
    (multiple-value-bind (item priority)
        (autopoiesis.agent:pqueue-peek pq)
      (is (eq :b item))
      (is (= 4.0 priority)))))

(test priority-queue-items
  "Test getting all items from priority queue"
  (let ((pq (autopoiesis.agent:make-priority-queue)))
    (autopoiesis.agent:pqueue-push pq :low 1.0)
    (autopoiesis.agent:pqueue-push pq :high 3.0)
    (autopoiesis.agent:pqueue-push pq :medium 2.0)
    (is (equal '(:high :medium :low) (autopoiesis.agent:pqueue-items pq)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Context Window Tests
;;; ═══════════════════════════════════════════════════════════════════

(test context-window-creation
  "Test context window creation"
  (let ((ctx (autopoiesis.agent:make-context-window)))
    (is (= 100000 (autopoiesis.agent:context-max-size ctx)))
    (is (null (autopoiesis.agent:context-content ctx)))
    (is (= 0 (autopoiesis.agent:context-item-count ctx))))
  ;; With custom max-size
  (let ((ctx (autopoiesis.agent:make-context-window :max-size 1000)))
    (is (= 1000 (autopoiesis.agent:context-max-size ctx)))))

(test context-window-add-remove
  "Test adding and removing items from context"
  (let ((ctx (autopoiesis.agent:make-context-window)))
    (autopoiesis.agent:context-add ctx '(task "do something") :priority 2.0)
    (autopoiesis.agent:context-add ctx '(observation "saw something") :priority 1.0)
    (is (= 2 (autopoiesis.agent:context-item-count ctx)))
    ;; Higher priority item should be first in content
    (is (equal '(task "do something") (first (autopoiesis.agent:context-content ctx))))
    ;; Remove an item
    (autopoiesis.agent:context-remove ctx '(task "do something") :test #'equal)
    (is (= 1 (autopoiesis.agent:context-item-count ctx)))
    (is (equal '(observation "saw something")
               (first (autopoiesis.agent:context-content ctx))))))

(test context-window-priority-ordering
  "Test that items are ordered by priority"
  (let ((ctx (autopoiesis.agent:make-context-window)))
    (autopoiesis.agent:context-add ctx :low :priority 1.0)
    (autopoiesis.agent:context-add ctx :high :priority 3.0)
    (autopoiesis.agent:context-add ctx :medium :priority 2.0)
    (is (equal '(:high :medium :low) (autopoiesis.agent:context-content ctx)))))

(test context-window-focus
  "Test focusing (boosting priority) of items"
  (let ((ctx (autopoiesis.agent:make-context-window)))
    (autopoiesis.agent:context-add ctx '(type-a 1) :priority 1.0)
    (autopoiesis.agent:context-add ctx '(type-b 2) :priority 2.0)
    (autopoiesis.agent:context-add ctx '(type-a 3) :priority 1.5)
    ;; Initially type-b is first
    (is (equal '(type-b 2) (first (autopoiesis.agent:context-content ctx))))
    ;; Focus on type-a items (boost by 2x)
    (autopoiesis.agent:context-focus ctx
                                     (lambda (item) (eq (first item) 'type-a))
                                     :boost 2.0)
    ;; Now a type-a item should be first (1.5 * 2 = 3.0 > 2.0)
    (is (equal '(type-a 3) (first (autopoiesis.agent:context-content ctx))))))

(test context-window-max-size
  "Test that context respects max-size limit"
  (let ((ctx (autopoiesis.agent:make-context-window :max-size 10)))
    ;; Add items that exceed max-size
    (autopoiesis.agent:context-add ctx '(big item with lots of data) :priority 1.0)
    (autopoiesis.agent:context-add ctx '(small) :priority 2.0)
    (autopoiesis.agent:context-add ctx '(another big item here) :priority 0.5)
    ;; Should only include items that fit
    (is (<= (autopoiesis.agent:context-size ctx) 10))
    ;; Higher priority items should be included first
    (is (member '(small) (autopoiesis.agent:context-content ctx) :test #'equal))))

(test context-window-clear
  "Test clearing context window"
  (let ((ctx (autopoiesis.agent:make-context-window)))
    (autopoiesis.agent:context-add ctx :a :priority 1.0)
    (autopoiesis.agent:context-add ctx :b :priority 2.0)
    (is (= 2 (autopoiesis.agent:context-item-count ctx)))
    (autopoiesis.agent:context-clear ctx)
    (is (= 0 (autopoiesis.agent:context-item-count ctx)))
    (is (null (autopoiesis.agent:context-content ctx)))))

(test context-window-serialization
  "Test context window serialization and deserialization"
  (let ((ctx (autopoiesis.agent:make-context-window :max-size 50000)))
    (autopoiesis.agent:context-add ctx '(task "test") :priority 2.0)
    (autopoiesis.agent:context-add ctx '(note "important") :priority 1.5)
    (let* ((sexpr (autopoiesis.agent:context-to-sexpr ctx))
           (restored (autopoiesis.agent:sexpr-to-context sexpr)))
      (is (= (autopoiesis.agent:context-max-size ctx)
             (autopoiesis.agent:context-max-size restored)))
      (is (= (autopoiesis.agent:context-item-count ctx)
             (autopoiesis.agent:context-item-count restored)))
      ;; Content should be the same (order preserved)
      (is (equal (autopoiesis.agent:context-content ctx)
                 (autopoiesis.agent:context-content restored))))))
