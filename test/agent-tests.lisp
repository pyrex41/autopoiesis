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

;;; ═══════════════════════════════════════════════════════════════════
;;; Built-in Capabilities Tests
;;; ═══════════════════════════════════════════════════════════════════

(test builtin-capabilities-registered
  "Test that built-in capabilities are registered"
  ;; The capabilities are registered when builtin-capabilities.lisp loads
  ;; Use package-qualified symbols since registry uses EQUAL test
  (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.agent::introspect))))
  (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.agent::spawn))))
  (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.agent::communicate))))
  (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.agent::receive)))))

(test introspect-requires-current-agent
  "Test that introspect errors without *current-agent*"
  (let ((autopoiesis.agent:*current-agent* nil))
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.agent:capability-introspect :state))))

(test introspect-capabilities
  "Test introspecting agent capabilities"
  (let ((agent (autopoiesis.agent:make-agent
                :name "test-agent"
                :capabilities '(cap-a cap-b))))
    (autopoiesis.agent:with-current-agent (agent)
      (let ((caps (autopoiesis.agent:capability-introspect :capabilities)))
        (is (equal '(cap-a cap-b) caps))))))

(test introspect-state
  "Test introspecting agent state"
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (autopoiesis.agent:with-current-agent (agent)
      (is (eq :initialized (autopoiesis.agent:capability-introspect :state)))
      (autopoiesis.agent:start-agent agent)
      (is (eq :running (autopoiesis.agent:capability-introspect :state))))))

(test introspect-identity
  "Test introspecting agent identity"
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (autopoiesis.agent:with-current-agent (agent)
      (let ((identity (autopoiesis.agent:capability-introspect :identity)))
        (is (equal (autopoiesis.agent:agent-id agent) (getf identity :id)))
        (is (string= "test-agent" (getf identity :name)))))))

(test introspect-all
  "Test introspecting all agent info"
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (autopoiesis.agent:with-current-agent (agent)
      (let ((all (autopoiesis.agent:capability-introspect :all)))
        (is (not (null (getf all :identity))))
        (is (not (null (member :state all))))
        (is (not (null (member :capabilities all))))
        (is (not (null (member :thoughts all))))))))

(test spawn-capability
  "Test spawning child agents via capability"
  (let ((parent (autopoiesis.agent:make-agent :name "parent")))
    (autopoiesis.agent:with-current-agent (parent)
      (let ((child (autopoiesis.agent:capability-spawn "child")))
        (is (not (null child)))
        (is (string= "child" (autopoiesis.agent:agent-name child)))
        (is (equal (autopoiesis.agent:agent-id parent)
                   (autopoiesis.agent:agent-parent child)))
        (is (member (autopoiesis.agent:agent-id child)
                    (autopoiesis.agent:agent-children parent)
                    :test #'equal))))))

(test spawn-requires-current-agent
  "Test that spawn errors without *current-agent*"
  (let ((autopoiesis.agent:*current-agent* nil))
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.agent:capability-spawn "child"))))

(test message-creation
  "Test message creation"
  (let ((msg (autopoiesis.agent:make-message "sender-id" "receiver-id" '(hello world))))
    (is (not (null (autopoiesis.agent:message-id msg))))
    (is (string= "sender-id" (autopoiesis.agent:message-from msg)))
    (is (string= "receiver-id" (autopoiesis.agent:message-to msg)))
    (is (equal '(hello world) (autopoiesis.agent:message-content msg)))))

(test communicate-and-receive
  "Test sending and receiving messages between agents"
  (let ((sender (autopoiesis.agent:make-agent :name "sender"))
        (receiver (autopoiesis.agent:make-agent :name "receiver")))
    ;; Clear any existing messages
    (setf (gethash (autopoiesis.agent:agent-id receiver)
                   autopoiesis.agent:*agent-mailboxes*)
          nil)
    ;; Send message from sender
    (autopoiesis.agent:with-current-agent (sender)
      (autopoiesis.agent:capability-communicate receiver '(hello from sender)))
    ;; Receive as receiver
    (autopoiesis.agent:with-current-agent (receiver)
      (let ((messages (autopoiesis.agent:capability-receive :clear t)))
        (is (= 1 (length messages)))
        (is (equal '(hello from sender) (autopoiesis.agent:message-content (first messages))))
        (is (equal (autopoiesis.agent:agent-id sender)
                   (autopoiesis.agent:message-from (first messages))))
        ;; Messages should be cleared
        (is (null (autopoiesis.agent:capability-receive)))))))

(test communicate-requires-current-agent
  "Test that communicate errors without *current-agent*"
  (let ((autopoiesis.agent:*current-agent* nil))
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.agent:capability-communicate "target" '(message)))))

(test receive-requires-current-agent
  "Test that receive errors without *current-agent*"
  (let ((autopoiesis.agent:*current-agent* nil))
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.agent:capability-receive))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent-Defined Capability Tests
;;; ═══════════════════════════════════════════════════════════════════

(test agent-capability-creation
  "Test creating an agent-capability directly"
  (let ((cap (autopoiesis.agent:make-agent-capability
              :test-cap
              "A test capability"
              '((x number) (y number))
              "agent-123"
              '(lambda (x y) (+ x y)))))
    (is (eq :test-cap (autopoiesis.agent:capability-name cap)))
    (is (string= "A test capability" (autopoiesis.agent:capability-description cap)))
    (is (string= "agent-123" (autopoiesis.agent:cap-source-agent cap)))
    (is (eq :draft (autopoiesis.agent:cap-promotion-status cap)))
    (is (autopoiesis.agent:agent-capability-p cap))))

(test agent-capability-p-predicate
  "Test agent-capability-p predicate"
  (let ((agent-cap (autopoiesis.agent:make-agent-capability
                    :test-cap "desc" nil "agent-1" nil))
        (regular-cap (autopoiesis.agent:make-capability
                      :regular-cap (lambda () t))))
    (is (autopoiesis.agent:agent-capability-p agent-cap))
    (is (not (autopoiesis.agent:agent-capability-p regular-cap)))
    (is (not (autopoiesis.agent:agent-capability-p "not a capability")))))

(test agent-define-capability-valid
  "Test agent defining a valid capability"
  ;; Clear extension registry for clean test
  (autopoiesis.core:clear-extension-registry)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (multiple-value-bind (cap errors)
        (autopoiesis.agent:agent-define-capability
         agent
         :add-numbers
         "Add two numbers together"
         '((a number) (b number))
         '((+ a b)))
      (is (not (null cap)))
      (is (null errors))
      (is (eq :add-numbers (autopoiesis.agent:capability-name cap)))
      (is (eq :draft (autopoiesis.agent:cap-promotion-status cap)))
      (is (equal (autopoiesis.agent:agent-id agent)
                 (autopoiesis.agent:cap-source-agent cap)))
      ;; Should be added to agent's capabilities
      (is (member cap (autopoiesis.agent:agent-capabilities agent))))))

(test agent-define-capability-invalid
  "Test agent defining an invalid capability (forbidden code)"
  (autopoiesis.core:clear-extension-registry)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (multiple-value-bind (cap errors)
        (autopoiesis.agent:agent-define-capability
         agent
         :bad-cap
         "A bad capability"
         '((path string))
         '((delete-file path)))  ; Forbidden operation
      (is (null cap))
      (is (not (null errors)))
      ;; Should NOT be added to agent's capabilities
      (is (not (find :bad-cap (autopoiesis.agent:agent-capabilities agent)
                     :key #'autopoiesis.agent:capability-name))))))

(test test-agent-capability-all-pass
  "Test testing an agent capability where all tests pass"
  (autopoiesis.core:clear-extension-registry)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (multiple-value-bind (cap errors)
        (autopoiesis.agent:agent-define-capability
         agent
         :multiply
         "Multiply two numbers"
         '((a number) (b number))
         '((* a b)))
      (declare (ignore errors))
      (is (not (null cap)))
      ;; Run tests - format is ((args...) expected)
      (multiple-value-bind (passed-p results)
          (autopoiesis.agent:test-agent-capability
           cap
           '(((2 3) 6)
             ((4 5) 20)
             ((0 100) 0)))
        (is-true passed-p)
        (is (= 3 (length results)))
        (is (every (lambda (r) (eq (getf r :status) :pass)) results))
        ;; Status should be :testing
        (is (eq :testing (autopoiesis.agent:cap-promotion-status cap)))))))

(test test-agent-capability-with-failure
  "Test testing an agent capability where some tests fail"
  (autopoiesis.core:clear-extension-registry)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (multiple-value-bind (cap errors)
        (autopoiesis.agent:agent-define-capability
         agent
         :always-ten
         "Always return 10"
         '((x number))
         '((declare (ignore x)) 10))
      (declare (ignore errors))
      (is (not (null cap)))
      ;; Run tests - some will fail. Format is ((args...) expected)
      (multiple-value-bind (passed-p results)
          (autopoiesis.agent:test-agent-capability
           cap
           '(((5) 10)     ; pass
             ((3) 10)     ; pass
             ((7) 7)))    ; fail - expects 7 but gets 10
        (is-false passed-p)
        (is (= 3 (length results)))
        ;; Check we have both pass and fail results
        (is (= 2 (count :pass results :key (lambda (r) (getf r :status)))))
        (is (= 1 (count :fail results :key (lambda (r) (getf r :status)))))))))

(test promote-capability-success
  "Test promoting a capability after tests pass"
  (autopoiesis.core:clear-extension-registry)
  (let ((registry (make-hash-table :test 'equal))
        (agent (autopoiesis.agent:make-agent :name "test-agent")))
    (let ((autopoiesis.agent::*capability-registry* registry))
      (multiple-value-bind (cap errors)
          (autopoiesis.agent:agent-define-capability
           agent
           :double
           "Double a number"
           '((x number))
           '((* x 2)))
        (declare (ignore errors))
        (is (not (null cap)))
        ;; Run passing tests - format is ((args...) expected)
        (multiple-value-bind (passed-p results)
            (autopoiesis.agent:test-agent-capability
             cap
             '(((5) 10)
               ((0) 0)
               ((-3) -6)))
          (declare (ignore results))
          (is-true passed-p))
        ;; Promote
        (is-true (autopoiesis.agent:promote-capability cap))
        (is (eq :promoted (autopoiesis.agent:cap-promotion-status cap)))
        ;; Should be in global registry
        (is (eq cap (autopoiesis.agent:find-capability :double :registry registry)))))))

(test promote-capability-failure-no-tests
  "Test that promotion fails if no tests were run"
  (autopoiesis.core:clear-extension-registry)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (multiple-value-bind (cap errors)
        (autopoiesis.agent:agent-define-capability
         agent
         :untested
         "An untested capability"
         '((x number))
         '(x))
      (declare (ignore errors))
      ;; Try to promote without testing
      (setf (autopoiesis.agent:cap-promotion-status cap) :testing)
      (is (not (autopoiesis.agent:promote-capability cap)))
      ;; Status should still be :testing (no test results)
      (is (eq :testing (autopoiesis.agent:cap-promotion-status cap))))))

(test promote-capability-failure-tests-failed
  "Test that promotion fails if tests failed"
  (autopoiesis.core:clear-extension-registry)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (multiple-value-bind (cap errors)
        (autopoiesis.agent:agent-define-capability
         agent
         :bad-math
         "Bad math capability"
         '((x number))
         '((+ x 1)))  ; Always adds 1
      (declare (ignore errors))
      ;; Run failing tests
      (autopoiesis.agent:test-agent-capability
       cap
       '((((5)) 5)))  ; Expects 5 but gets 6
      ;; Try to promote
      (is (not (autopoiesis.agent:promote-capability cap)))
      ;; Status should be :rejected
      (is (eq :rejected (autopoiesis.agent:cap-promotion-status cap))))))

(test reject-capability
  "Test rejecting a capability"
  (autopoiesis.core:clear-extension-registry)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (multiple-value-bind (cap errors)
        (autopoiesis.agent:agent-define-capability
         agent
         :to-reject
         "A capability to reject"
         '((x number))
         '(x))
      (declare (ignore errors))
      (autopoiesis.agent:reject-capability cap "Not useful")
      (is (eq :rejected (autopoiesis.agent:cap-promotion-status cap)))
      ;; Reason should be in test-results
      (is (find :rejected (autopoiesis.agent:cap-test-results cap)
                :key (lambda (r) (getf r :status)))))))

(test list-agent-capabilities
  "Test listing agent-defined capabilities"
  (autopoiesis.core:clear-extension-registry)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    ;; Add a regular capability
    (let ((regular-cap (autopoiesis.agent:make-capability :regular (lambda () t))))
      (push regular-cap (autopoiesis.agent:agent-capabilities agent))
      ;; Verify regular cap is NOT an agent-capability
      (is-false (autopoiesis.agent:agent-capability-p regular-cap)))
    ;; Add agent-defined capabilities
    (multiple-value-bind (cap-a errors-a)
        (autopoiesis.agent:agent-define-capability
         agent :cap-a "Cap A" '((x number)) '(x))
      (declare (ignore errors-a))
      (is-true cap-a)
      (when cap-a
        (is-true (autopoiesis.agent:agent-capability-p cap-a))))
    (multiple-value-bind (cap-b errors-b)
        (autopoiesis.agent:agent-define-capability
         agent :cap-b "Cap B" '((x number)) '(x))
      (declare (ignore errors-b))
      (is-true cap-b)
      (when cap-b
        (is-true (autopoiesis.agent:agent-capability-p cap-b))))
    ;; Total capabilities should be 3
    (is (= 3 (length (autopoiesis.agent:agent-capabilities agent))))
    ;; Test manual filtering
    (let* ((all-caps (autopoiesis.agent:agent-capabilities agent))
           (filtered (remove-if-not #'autopoiesis.agent:agent-capability-p all-caps)))
      (is (= 2 (length filtered))))
    ;; List all agent capabilities (should be 2 agent-capabilities, not 3 total)
    (let ((agent-caps (autopoiesis.agent:list-agent-capabilities agent)))
      (is (= 2 (length agent-caps)))
      (is-true (every #'autopoiesis.agent:agent-capability-p agent-caps)))
    ;; List by status
    (let ((draft-caps (autopoiesis.agent:list-agent-capabilities agent :status :draft)))
      (is (= 2 (length draft-caps))))))

(test find-agent-capability
  "Test finding an agent capability by name"
  (autopoiesis.core:clear-extension-registry)
  (let ((agent (autopoiesis.agent:make-agent :name "test-agent")))
    (autopoiesis.agent:agent-define-capability
     agent :findable "A findable capability" '((x number)) '(x))
    (let ((found (autopoiesis.agent:find-agent-capability agent :findable)))
      (is (not (null found)))
      (is (eq :findable (autopoiesis.agent:capability-name found))))
    ;; Not found case
    (is (null (autopoiesis.agent:find-agent-capability agent :nonexistent)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Learning System Tests - Experience
;;; ═══════════════════════════════════════════════════════════════════

(test experience-creation
  "Test basic experience creation"
  (let ((exp (autopoiesis.agent:make-experience
              :task-type :code-review
              :context '(file "test.lisp")
              :actions '((read-file "test.lisp") (analyze-code))
              :outcome :success
              :agent-id "agent-123"
              :metadata '(:duration 5.0))))
    (is (not (null (autopoiesis.agent:experience-id exp))))
    (is (eq :code-review (autopoiesis.agent:experience-task-type exp)))
    (is (equal '(file "test.lisp") (autopoiesis.agent:experience-context exp)))
    (is (equal '((read-file "test.lisp") (analyze-code))
               (autopoiesis.agent:experience-actions exp)))
    (is (eq :success (autopoiesis.agent:experience-outcome exp)))
    (is (string= "agent-123" (autopoiesis.agent:experience-agent-id exp)))
    (is (equal '(:duration 5.0) (autopoiesis.agent:experience-metadata exp)))
    (is (numberp (autopoiesis.agent:experience-timestamp exp)))))

(test experience-serialization
  "Test experience serialization and deserialization"
  (let* ((exp (autopoiesis.agent:make-experience
               :task-type :debugging
               :context '(error "null pointer")
               :actions '((trace-stack) (fix-bug))
               :outcome :success
               :agent-id "agent-456"))
         (sexpr (autopoiesis.agent:experience-to-sexpr exp))
         (restored (autopoiesis.agent:sexpr-to-experience sexpr)))
    (is (eq :experience (first sexpr)))
    (is (not (null restored)))
    (is (equal (autopoiesis.agent:experience-id exp)
               (autopoiesis.agent:experience-id restored)))
    (is (eq (autopoiesis.agent:experience-task-type exp)
            (autopoiesis.agent:experience-task-type restored)))
    (is (equal (autopoiesis.agent:experience-context exp)
               (autopoiesis.agent:experience-context restored)))
    (is (equal (autopoiesis.agent:experience-actions exp)
               (autopoiesis.agent:experience-actions restored)))
    (is (eq (autopoiesis.agent:experience-outcome exp)
            (autopoiesis.agent:experience-outcome restored)))))

(test experience-storage
  "Test storing and retrieving experiences"
  (let ((store (make-hash-table :test 'equal)))
    (let ((exp1 (autopoiesis.agent:make-experience
                 :task-type :testing
                 :outcome :success
                 :agent-id "agent-1"))
          (exp2 (autopoiesis.agent:make-experience
                 :task-type :testing
                 :outcome :failure
                 :agent-id "agent-2"))
          (exp3 (autopoiesis.agent:make-experience
                 :task-type :coding
                 :outcome :success
                 :agent-id "agent-1")))
      ;; Store experiences
      (autopoiesis.agent:store-experience exp1 :store store)
      (autopoiesis.agent:store-experience exp2 :store store)
      (autopoiesis.agent:store-experience exp3 :store store)
      ;; Find by ID
      (is (eq exp1 (autopoiesis.agent:find-experience
                    (autopoiesis.agent:experience-id exp1)
                    :store store)))
      ;; List all
      (is (= 3 (length (autopoiesis.agent:list-experiences :store store))))
      ;; Filter by task-type
      (is (= 2 (length (autopoiesis.agent:list-experiences
                        :store store :task-type :testing))))
      ;; Filter by outcome
      (is (= 2 (length (autopoiesis.agent:list-experiences
                        :store store :outcome :success))))
      ;; Filter by agent-id
      (is (= 2 (length (autopoiesis.agent:list-experiences
                        :store store :agent-id "agent-1"))))
      ;; Clear
      (autopoiesis.agent:clear-experiences :store store)
      (is (= 0 (length (autopoiesis.agent:list-experiences :store store)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Learning System Tests - Heuristic
;;; ═══════════════════════════════════════════════════════════════════

(test heuristic-creation
  "Test basic heuristic creation"
  (let ((heur (autopoiesis.agent:make-heuristic
               :name "prefer-tests-first"
               :condition '(task-type :coding)
               :recommendation '(:prefer-actions ((run-tests)))
               :confidence 0.8
               :source-pattern '(:pattern ((run-tests) (commit))))))
    (is (not (null (autopoiesis.agent:heuristic-id heur))))
    (is (string= "prefer-tests-first" (autopoiesis.agent:heuristic-name heur)))
    (is (equal '(task-type :coding) (autopoiesis.agent:heuristic-condition heur)))
    (is (equal '(:prefer-actions ((run-tests)))
               (autopoiesis.agent:heuristic-recommendation heur)))
    (is (= 0.8 (autopoiesis.agent:heuristic-confidence heur)))
    (is (= 0 (autopoiesis.agent:heuristic-applications heur)))
    (is (= 0 (autopoiesis.agent:heuristic-successes heur)))))

(test heuristic-confidence-bounds
  "Test that heuristic confidence is bounded between 0 and 1"
  (let ((heur1 (autopoiesis.agent:make-heuristic :confidence 1.5))
        (heur2 (autopoiesis.agent:make-heuristic :confidence -0.5)))
    (is (= 1.0 (autopoiesis.agent:heuristic-confidence heur1)))
    (is (= 0.0 (autopoiesis.agent:heuristic-confidence heur2)))))

(test heuristic-serialization
  "Test heuristic serialization and deserialization"
  (let* ((heur (autopoiesis.agent:make-heuristic
                :name "test-heuristic"
                :condition '(and (task-type :review) (has-tests t))
                :recommendation '(:approve)
                :confidence 0.75))
         (sexpr (autopoiesis.agent:heuristic-to-sexpr heur))
         (restored (autopoiesis.agent:sexpr-to-heuristic sexpr)))
    (is (eq :heuristic (first sexpr)))
    (is (not (null restored)))
    (is (equal (autopoiesis.agent:heuristic-id heur)
               (autopoiesis.agent:heuristic-id restored)))
    (is (string= (autopoiesis.agent:heuristic-name heur)
                 (autopoiesis.agent:heuristic-name restored)))
    (is (equal (autopoiesis.agent:heuristic-condition heur)
               (autopoiesis.agent:heuristic-condition restored)))
    (is (= (autopoiesis.agent:heuristic-confidence heur)
           (autopoiesis.agent:heuristic-confidence restored)))))

(test heuristic-storage
  "Test storing and retrieving heuristics"
  (let ((store (make-hash-table :test 'equal)))
    (let ((heur1 (autopoiesis.agent:make-heuristic
                  :name "high-confidence"
                  :confidence 0.9))
          (heur2 (autopoiesis.agent:make-heuristic
                  :name "low-confidence"
                  :confidence 0.3)))
      ;; Store heuristics
      (autopoiesis.agent:store-heuristic heur1 :store store)
      (autopoiesis.agent:store-heuristic heur2 :store store)
      ;; Find by ID
      (is (eq heur1 (autopoiesis.agent:find-heuristic
                     (autopoiesis.agent:heuristic-id heur1)
                     :store store)))
      ;; List all
      (is (= 2 (length (autopoiesis.agent:list-heuristics :store store))))
      ;; Filter by min-confidence
      (is (= 1 (length (autopoiesis.agent:list-heuristics
                        :store store :min-confidence 0.5))))
      ;; Clear
      (autopoiesis.agent:clear-heuristics :store store)
      (is (= 0 (length (autopoiesis.agent:list-heuristics :store store)))))))

(test heuristic-application-tracking
  "Test tracking heuristic applications and successes"
  (let ((heur (autopoiesis.agent:make-heuristic :confidence 0.5)))
    (is (= 0 (autopoiesis.agent:heuristic-applications heur)))
    (is (= 0 (autopoiesis.agent:heuristic-successes heur)))
    ;; Record successful application
    (autopoiesis.agent:record-heuristic-application heur :success t)
    (is (= 1 (autopoiesis.agent:heuristic-applications heur)))
    (is (= 1 (autopoiesis.agent:heuristic-successes heur)))
    (is (= 1.0 (autopoiesis.agent:heuristic-confidence heur)))
    ;; Record failed application
    (autopoiesis.agent:record-heuristic-application heur :success nil)
    (is (= 2 (autopoiesis.agent:heuristic-applications heur)))
    (is (= 1 (autopoiesis.agent:heuristic-successes heur)))
    (is (= 0.5 (autopoiesis.agent:heuristic-confidence heur)))
    ;; last-applied should be set
    (is (not (null (autopoiesis.agent:heuristic-last-applied heur))))))

(test heuristic-confidence-decay
  "Test decaying heuristic confidence"
  (let ((heur (autopoiesis.agent:make-heuristic :confidence 1.0)))
    (autopoiesis.agent:decay-heuristic-confidence heur :factor 0.9)
    (is (= 0.9 (autopoiesis.agent:heuristic-confidence heur)))
    (autopoiesis.agent:decay-heuristic-confidence heur :factor 0.5)
    (is (= 0.45 (autopoiesis.agent:heuristic-confidence heur)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Learning System Tests - Condition Matching
;;; ═══════════════════════════════════════════════════════════════════

(test condition-matches-literal
  "Test literal value matching"
  (is-true (autopoiesis.agent:condition-matches-p :foo :foo))
  (is-false (autopoiesis.agent:condition-matches-p :foo :bar))
  (is-true (autopoiesis.agent:condition-matches-p 42 42))
  (is-true (autopoiesis.agent:condition-matches-p "hello" "hello"))
  (is-true (autopoiesis.agent:condition-matches-p nil nil)))

(test condition-matches-any
  "Test :any wildcard matching"
  (is-true (autopoiesis.agent:condition-matches-p :any :foo))
  (is-true (autopoiesis.agent:condition-matches-p :any 42))
  (is-true (autopoiesis.agent:condition-matches-p :any nil))
  (is-true (autopoiesis.agent:condition-matches-p :any '(a b c))))

(test condition-matches-type
  "Test type checking in conditions"
  (is-true (autopoiesis.agent:condition-matches-p '(:type number) 42))
  (is-false (autopoiesis.agent:condition-matches-p '(:type number) "hello"))
  (is-true (autopoiesis.agent:condition-matches-p '(:type string) "hello"))
  (is-true (autopoiesis.agent:condition-matches-p '(:type list) '(a b c)))
  (is-true (autopoiesis.agent:condition-matches-p '(:type symbol) :foo)))

(test condition-matches-member
  "Test member checking in conditions"
  (is-true (autopoiesis.agent:condition-matches-p
            '(:member (:a :b :c)) :b))
  (is-false (autopoiesis.agent:condition-matches-p
             '(:member (:a :b :c)) :d))
  (is-true (autopoiesis.agent:condition-matches-p
            '(:member (1 2 3)) 2)))

(test condition-matches-and
  "Test conjunction in conditions"
  (is-true (autopoiesis.agent:condition-matches-p
            '(and (:type number) (:member (1 2 3))) 2))
  (is-false (autopoiesis.agent:condition-matches-p
             '(and (:type number) (:member (1 2 3))) 4))
  (is-false (autopoiesis.agent:condition-matches-p
             '(and (:type number) (:member (1 2 3))) "hello")))

(test condition-matches-or
  "Test disjunction in conditions"
  (is-true (autopoiesis.agent:condition-matches-p
            '(or (:type number) (:type string)) 42))
  (is-true (autopoiesis.agent:condition-matches-p
            '(or (:type number) (:type string)) "hello"))
  (is-false (autopoiesis.agent:condition-matches-p
             '(or (:type number) (:type string)) :symbol)))

(test condition-matches-not
  "Test negation in conditions"
  (is-true (autopoiesis.agent:condition-matches-p
            '(not (:type number)) "hello"))
  (is-false (autopoiesis.agent:condition-matches-p
             '(not (:type number)) 42)))

(test condition-matches-list-pattern
  "Test list pattern matching"
  (is-true (autopoiesis.agent:condition-matches-p
            '(:task :any) '(:task :coding)))
  (is-true (autopoiesis.agent:condition-matches-p
            '(:task :coding :priority (:type number))
            '(:task :coding :priority 5)))
  (is-false (autopoiesis.agent:condition-matches-p
             '(:task :coding) '(:task :testing))))

(test find-applicable-heuristics
  "Test finding heuristics that match a context"
  (let ((store (make-hash-table :test 'equal)))
    (let ((heur1 (autopoiesis.agent:make-heuristic
                  :name "coding-heuristic"
                  :condition '(:task-type :coding)
                  :confidence 0.8))
          (heur2 (autopoiesis.agent:make-heuristic
                  :name "testing-heuristic"
                  :condition '(:task-type :testing)
                  :confidence 0.7))
          (heur3 (autopoiesis.agent:make-heuristic
                  :name "low-confidence"
                  :condition '(:task-type :coding)
                  :confidence 0.2)))
      (autopoiesis.agent:store-heuristic heur1 :store store)
      (autopoiesis.agent:store-heuristic heur2 :store store)
      (autopoiesis.agent:store-heuristic heur3 :store store)
      ;; Find applicable for coding task
      (let ((applicable (autopoiesis.agent:find-applicable-heuristics
                         '(:task-type :coding)
                         :store store
                         :min-confidence 0.3)))
        (is (= 1 (length applicable)))
        (is (string= "coding-heuristic"
                     (autopoiesis.agent:heuristic-name (first applicable)))))
      ;; Find with lower confidence threshold
      (let ((applicable (autopoiesis.agent:find-applicable-heuristics
                         '(:task-type :coding)
                         :store store
                         :min-confidence 0.1)))
        (is (= 2 (length applicable)))
        ;; Should be sorted by confidence (highest first)
        (is (string= "coding-heuristic"
                     (autopoiesis.agent:heuristic-name (first applicable)))))
      ;; No matches
      (let ((applicable (autopoiesis.agent:find-applicable-heuristics
                         '(:task-type :debugging)
                         :store store)))
        (is (= 0 (length applicable)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Learning System Tests - Pattern Extraction
;;; ═══════════════════════════════════════════════════════════════════

(test extract-patterns-empty
  "Test extract-patterns with empty or nil input"
  (is (null (autopoiesis.agent:extract-patterns nil)))
  (is (null (autopoiesis.agent:extract-patterns '()))))

(test extract-patterns-single-experience
  "Test extract-patterns with single experience (needs at least 2)"
  (let ((exp (autopoiesis.agent:make-experience
              :task-type :coding
              :actions '((read-file) (edit-file) (save-file))
              :outcome :success)))
    ;; Single experience should return nil (need at least 2 for patterns)
    (is (null (autopoiesis.agent:extract-patterns (list exp))))))

(test extract-action-sequences-basic
  "Test basic action sequence extraction"
  (let* ((exp1 (autopoiesis.agent:make-experience
                :task-type :coding
                :actions '((read-file) (analyze) (edit) (save))
                :outcome :success))
         (exp2 (autopoiesis.agent:make-experience
                :task-type :coding
                :actions '((read-file) (analyze) (refactor) (save))
                :outcome :success))
         (exp3 (autopoiesis.agent:make-experience
                :task-type :coding
                :actions '((read-file) (analyze) (test) (save))
                :outcome :success))
         (experiences (list exp1 exp2 exp3))
         (patterns (autopoiesis.agent:extract-action-sequences
                    experiences
                    :outcome :success
                    :min-frequency 0.5)))
    ;; Should find common sequences
    (is (not (null patterns)))
    ;; (read-file analyze) should appear in all 3 (100%)
    (let ((read-analyze (find '((read-file) (analyze)) patterns
                              :key (lambda (p) (getf p :pattern))
                              :test #'equal)))
      (is (not (null read-analyze)))
      (is (= 1.0 (getf read-analyze :frequency)))
      (is (= 3 (getf read-analyze :count))))))

(test extract-action-sequences-with-frequency-threshold
  "Test that frequency threshold filters patterns correctly"
  (let* ((exp1 (autopoiesis.agent:make-experience
                :actions '((a) (b) (c) (d))
                :outcome :success))
         (exp2 (autopoiesis.agent:make-experience
                :actions '((a) (b) (x) (y))
                :outcome :success))
         (exp3 (autopoiesis.agent:make-experience
                :actions '((a) (b) (c) (z))
                :outcome :success))
         (exp4 (autopoiesis.agent:make-experience
                :actions '((p) (q) (r) (s))
                :outcome :success))
         (experiences (list exp1 exp2 exp3 exp4)))
    ;; With 50% threshold, (a b) should appear (3/4 = 75%)
    (let ((patterns (autopoiesis.agent:extract-action-sequences
                     experiences :outcome :success :min-frequency 0.5)))
      (is (find '((a) (b)) patterns
                :key (lambda (p) (getf p :pattern))
                :test #'equal)))
    ;; With 80% threshold, (a b) should NOT appear (75% < 80%)
    (let ((patterns (autopoiesis.agent:extract-action-sequences
                     experiences :outcome :success :min-frequency 0.8)))
      (is (null (find '((a) (b)) patterns
                      :key (lambda (p) (getf p :pattern))
                      :test #'equal))))))

(test extract-action-sequences-ngram-sizes
  "Test that different n-gram sizes are extracted"
  (let* ((exp1 (autopoiesis.agent:make-experience
                :actions '((a) (b) (c) (d))
                :outcome :success))
         (exp2 (autopoiesis.agent:make-experience
                :actions '((a) (b) (c) (d))
                :outcome :success))
         (experiences (list exp1 exp2))
         (patterns (autopoiesis.agent:extract-action-sequences
                    experiences :outcome :success :min-frequency 0.5)))
    ;; Should have 2-grams, 3-grams, and 4-grams
    (is (find 2 patterns :key (lambda (p) (getf p :ngram-size))))
    (is (find 3 patterns :key (lambda (p) (getf p :ngram-size))))
    (is (find 4 patterns :key (lambda (p) (getf p :ngram-size))))))

(test extract-patterns-success-and-failure
  "Test that extract-patterns separates success and failure patterns"
  (let* ((success1 (autopoiesis.agent:make-experience
                    :actions '((test) (fix) (commit))
                    :outcome :success))
         (success2 (autopoiesis.agent:make-experience
                    :actions '((test) (fix) (commit))
                    :outcome :success))
         (failure1 (autopoiesis.agent:make-experience
                    :actions '((commit) (test) (revert))
                    :outcome :failure))
         (failure2 (autopoiesis.agent:make-experience
                    :actions '((commit) (test) (revert))
                    :outcome :failure))
         (experiences (list success1 success2 failure1 failure2))
         (patterns (autopoiesis.agent:extract-patterns experiences :min-frequency 0.4)))
    ;; Should have both success and failure patterns
    (is (find :success patterns :key (lambda (p) (getf p :outcome))))
    (is (find :failure patterns :key (lambda (p) (getf p :outcome))))
    ;; Success pattern: (test fix)
    (let ((success-pattern (find-if (lambda (p)
                                      (and (eq (getf p :outcome) :success)
                                           (equal (getf p :pattern) '((test) (fix)))))
                                    patterns)))
      (is (not (null success-pattern))))
    ;; Failure pattern: (commit test)
    (let ((failure-pattern (find-if (lambda (p)
                                      (and (eq (getf p :outcome) :failure)
                                           (equal (getf p :pattern) '((commit) (test)))))
                                    patterns)))
      (is (not (null failure-pattern))))))

(test extract-context-keys-plist
  "Test extracting keys from plist-style context"
  (let ((keys (autopoiesis.agent:extract-context-keys
               '(:file "test.lisp" :language :lisp :size 100))))
    (is (member :file keys))
    (is (member :language keys))
    (is (member :size keys))))

(test extract-context-keys-list
  "Test extracting keys from list-style context"
  (let ((keys (autopoiesis.agent:extract-context-keys '(error "null pointer"))))
    (is (member 'error keys))))

(test extract-context-keys-nil
  "Test extracting keys from nil context"
  (is (null (autopoiesis.agent:extract-context-keys nil))))

(test extract-context-patterns-basic
  "Test basic context pattern extraction"
  (let* ((exp1 (autopoiesis.agent:make-experience
                :context '(:file "a.lisp" :type :source)
                :outcome :success))
         (exp2 (autopoiesis.agent:make-experience
                :context '(:file "b.lisp" :type :source)
                :outcome :success))
         (exp3 (autopoiesis.agent:make-experience
                :context '(:file "c.lisp" :type :test)
                :outcome :success))
         (experiences (list exp1 exp2 exp3))
         (patterns (autopoiesis.agent:extract-context-patterns
                    experiences :min-frequency 0.5)))
    ;; :file should appear in all (100%)
    (is (find :file patterns :key (lambda (p) (getf p :pattern))))
    ;; :type should appear in all (100%)
    (is (find :type patterns :key (lambda (p) (getf p :pattern))))))

(test actions-contain-sequence-p-basic
  "Test basic sequence containment check"
  (is-true (autopoiesis.agent:actions-contain-sequence-p
            '((a) (b) (c) (d))
            '((b) (c))))
  (is-true (autopoiesis.agent:actions-contain-sequence-p
            '((a) (b) (c) (d))
            '((a) (b))))
  (is-true (autopoiesis.agent:actions-contain-sequence-p
            '((a) (b) (c) (d))
            '((c) (d))))
  (is-false (autopoiesis.agent:actions-contain-sequence-p
             '((a) (b) (c) (d))
             '((a) (c))))  ; Not contiguous
  (is-false (autopoiesis.agent:actions-contain-sequence-p
             '((a) (b))
             '((a) (b) (c))))  ; Sequence longer than actions
  (is-false (autopoiesis.agent:actions-contain-sequence-p
             nil
             '((a)))))

(test pattern-to-condition-basic
  "Test converting patterns to heuristic conditions"
  ;; Action pattern with single task type
  (let* ((pattern '(:pattern ((read) (analyze))
                    :outcome :success
                    :task-types (:coding)))
         (condition (autopoiesis.agent:pattern-to-condition pattern)))
    (is (eq 'and (first condition)))
    ;; Check that task-type is somewhere in the condition (using string comparison for package independence)
    (is (find "TASK-TYPE" (flatten condition) 
              :key (lambda (x) (when (symbolp x) (symbol-name x)))
              :test #'string=)))
  
  ;; Context pattern
  (let* ((pattern '(:pattern :file
                    :type :context))
         (condition (autopoiesis.agent:pattern-to-condition pattern)))
    ;; Check using string comparison for package independence
    (is (string= "CONTEXT-HAS-KEY" (symbol-name (first condition))))))

(test extract-patterns-with-task-types
  "Test that patterns track which task types they came from"
  (let* ((exp1 (autopoiesis.agent:make-experience
                :task-type :coding
                :actions '((read) (edit) (save))
                :outcome :success))
         (exp2 (autopoiesis.agent:make-experience
                :task-type :coding
                :actions '((read) (edit) (test))
                :outcome :success))
         (exp3 (autopoiesis.agent:make-experience
                :task-type :review
                :actions '((read) (edit) (comment))
                :outcome :success))
         (experiences (list exp1 exp2 exp3))
         (patterns (autopoiesis.agent:extract-action-sequences
                    experiences :outcome :success :min-frequency 0.5)))
    ;; (read edit) should appear in all 3
    (let ((read-edit (find '((read) (edit)) patterns
                           :key (lambda (p) (getf p :pattern))
                           :test #'equal)))
      (is (not (null read-edit)))
      ;; Should have both task types
      (is (member :coding (getf read-edit :task-types)))
      (is (member :review (getf read-edit :task-types))))))
