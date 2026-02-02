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
