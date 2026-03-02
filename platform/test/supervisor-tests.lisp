;;;; supervisor-tests.lisp - Tests for supervisor checkpoint-and-revert
;;;;
;;;; Tests checkpoint creation, revert, promotion, with-checkpoint macro,
;;;; and integration with recovery and extension systems.

(in-package #:autopoiesis.test)

(def-suite supervisor-tests
  :description "Supervisor checkpoint-and-revert tests"
  :in all-tests)

(in-suite supervisor-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Test Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun make-test-agent-with-state (&key (name "test-agent")
                                        (state :running)
                                        (capabilities '(:read :write)))
  "Create an agent with known state for testing."
  (let ((agent (make-instance 'autopoiesis.agent:agent
                              :name name
                              :state state
                              :capabilities capabilities)))
    agent))

(defmacro with-supervisor-env (&body body)
  "Run BODY with a fresh supervisor environment and temporary snapshot store."
  (let ((dir (gensym "DIR")))
    `(let ((,dir (merge-pathnames
                  (format nil "sup-test-~a/" (autopoiesis.core:make-uuid))
                  (uiop:temporary-directory))))
       (unwind-protect
            (let ((autopoiesis.snapshot:*snapshot-store*
                    (autopoiesis.snapshot:make-snapshot-store ,dir))
                  (autopoiesis.supervisor:*stable-root* nil)
                  (autopoiesis.supervisor:*checkpoint-stack* nil))
              ,@body)
         (uiop:delete-directory-tree ,dir :validate t :if-does-not-exist :ignore)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Checkpoint Creation Tests
;;; ═══════════════════════════════════════════════════════════════════

(test checkpoint-creates-snapshot
  "checkpoint-agent creates a snapshot with correct metadata"
  (with-supervisor-env
    (let* ((agent (make-test-agent-with-state :name "alpha"))
           (snap (autopoiesis.supervisor:checkpoint-agent agent :operation :test-op)))
      (is (not (null snap)))
      (is (not (null (autopoiesis.snapshot:snapshot-id snap))))
      (is (not (null (autopoiesis.snapshot:snapshot-agent-state snap))))
      ;; Metadata should contain operation and checkpoint-time
      (let ((meta (autopoiesis.snapshot:snapshot-metadata snap)))
        (is (eq :test-op (getf meta :operation)))
        (is (not (null (getf meta :checkpoint-time))))))))

(test checkpoint-preserves-agent-state
  "checkpoint-agent captures the full agent state"
  (with-supervisor-env
    (let* ((agent (make-test-agent-with-state :name "beta" :state :paused
                                              :capabilities '(:a :b :c)))
           (snap (autopoiesis.supervisor:checkpoint-agent agent)))
      (let ((state (autopoiesis.snapshot:snapshot-agent-state snap)))
        ;; State should be a plist starting with :agent
        (is (eq :agent (first state)))
        (is (string= "beta" (getf (rest state) :name)))
        (is (eq :paused (getf (rest state) :state)))
        (is (equal '(:a :b :c) (getf (rest state) :capabilities)))))))

(test checkpoint-pushes-to-stack
  "checkpoint-agent pushes entry onto checkpoint stack"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state)))
      (is (= 0 (length autopoiesis.supervisor:*checkpoint-stack*)))
      (autopoiesis.supervisor:checkpoint-agent agent :operation :op1)
      (is (= 1 (length autopoiesis.supervisor:*checkpoint-stack*)))
      (is (eq :op1 (cdr (first autopoiesis.supervisor:*checkpoint-stack*))))
      (autopoiesis.supervisor:checkpoint-agent agent :operation :op2)
      (is (= 2 (length autopoiesis.supervisor:*checkpoint-stack*)))
      (is (eq :op2 (cdr (first autopoiesis.supervisor:*checkpoint-stack*)))))))

(test checkpoint-persists-to-store
  "checkpoint-agent persists snapshot when store is available"
  (with-supervisor-env
    (let* ((agent (make-test-agent-with-state))
           (snap (autopoiesis.supervisor:checkpoint-agent agent))
           (snap-id (autopoiesis.snapshot:snapshot-id snap)))
      ;; Should be loadable from store
      (let ((loaded (autopoiesis.snapshot:load-snapshot snap-id)))
        (is (not (null loaded)))
        (is (string= snap-id (autopoiesis.snapshot:snapshot-id loaded)))))))

(test checkpoint-without-store
  "checkpoint-agent works without a snapshot store (in-memory only)"
  (let ((autopoiesis.snapshot:*snapshot-store* nil)
        (autopoiesis.supervisor:*stable-root* nil)
        (autopoiesis.supervisor:*checkpoint-stack* nil))
    (let* ((agent (make-test-agent-with-state))
           (snap (autopoiesis.supervisor:checkpoint-agent agent)))
      (is (not (null snap)))
      (is (= 1 (length autopoiesis.supervisor:*checkpoint-stack*))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Revert Tests
;;; ═══════════════════════════════════════════════════════════════════

(test revert-restores-agent-state
  "revert-to-stable restores agent to checkpointed state"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state :name "original" :state :running
                                             :capabilities '(:x :y))))
      ;; Checkpoint
      (autopoiesis.supervisor:checkpoint-agent agent :operation :before-change)
      ;; Modify agent
      (setf (autopoiesis.agent:agent-name agent) "modified")
      (setf (autopoiesis.agent:agent-state agent) :paused)
      (setf (autopoiesis.agent:agent-capabilities agent) '(:z))
      ;; Verify modified
      (is (string= "modified" (autopoiesis.agent:agent-name agent)))
      ;; Revert
      (autopoiesis.supervisor:revert-to-stable agent)
      ;; Verify restored
      (is (string= "original" (autopoiesis.agent:agent-name agent)))
      (is (eq :running (autopoiesis.agent:agent-state agent)))
      (is (equal '(:x :y) (autopoiesis.agent:agent-capabilities agent))))))

(test revert-to-specific-target
  "revert-to-stable can target a specific snapshot ID"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state :name "v1")))
      ;; First checkpoint
      (let ((snap1 (autopoiesis.supervisor:checkpoint-agent agent :operation :v1)))
        ;; Modify and second checkpoint
        (setf (autopoiesis.agent:agent-name agent) "v2")
        (autopoiesis.supervisor:checkpoint-agent agent :operation :v2)
        ;; Modify again
        (setf (autopoiesis.agent:agent-name agent) "v3")
        ;; Revert to first checkpoint specifically
        (autopoiesis.supervisor:revert-to-stable
         agent :target (autopoiesis.snapshot:snapshot-id snap1))
        (is (string= "v1" (autopoiesis.agent:agent-name agent)))))))

(test revert-without-store-errors
  "revert-to-stable signals error when no store available"
  (let ((autopoiesis.snapshot:*snapshot-store* nil)
        (autopoiesis.supervisor:*stable-root* nil)
        (autopoiesis.supervisor:*checkpoint-stack* '(("fake-id" . :test))))
    (let ((agent (make-test-agent-with-state)))
      (signals autopoiesis.core:autopoiesis-error
        (autopoiesis.supervisor:revert-to-stable agent)))))

(test revert-without-checkpoint-errors
  "revert-to-stable signals error when no checkpoint exists"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state)))
      (signals autopoiesis.core:autopoiesis-error
        (autopoiesis.supervisor:revert-to-stable agent)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Promote Tests
;;; ═══════════════════════════════════════════════════════════════════

(test promote-sets-stable-root
  "promote-checkpoint sets *stable-root* to top of stack"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state)))
      (let ((snap (autopoiesis.supervisor:checkpoint-agent agent :operation :promote-test)))
        (is (null autopoiesis.supervisor:*stable-root*))
        (let ((promoted-id (autopoiesis.supervisor:promote-checkpoint)))
          (is (string= (autopoiesis.snapshot:snapshot-id snap) promoted-id))
          (is (string= promoted-id autopoiesis.supervisor:*stable-root*))
          (is (= 0 (length autopoiesis.supervisor:*checkpoint-stack*))))))))

(test promote-pops-stack
  "promote-checkpoint removes top entry from stack"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state)))
      (autopoiesis.supervisor:checkpoint-agent agent :operation :first)
      (autopoiesis.supervisor:checkpoint-agent agent :operation :second)
      (is (= 2 (length autopoiesis.supervisor:*checkpoint-stack*)))
      (autopoiesis.supervisor:promote-checkpoint)
      (is (= 1 (length autopoiesis.supervisor:*checkpoint-stack*)))
      ;; Remaining entry should be :first
      (is (eq :first (cdr (first autopoiesis.supervisor:*checkpoint-stack*)))))))

(test promote-empty-stack-errors
  "promote-checkpoint signals error on empty stack"
  (with-supervisor-env
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.supervisor:promote-checkpoint))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Supervisor Status Tests
;;; ═══════════════════════════════════════════════════════════════════

(test supervisor-status-empty
  "supervisor-status returns correct plist when empty"
  (with-supervisor-env
    (let ((status (autopoiesis.supervisor:supervisor-status)))
      (is (null (getf status :stable-root)))
      (is (= 0 (getf status :checkpoint-depth)))
      (is (null (getf status :stack))))))

(test supervisor-status-with-checkpoints
  "supervisor-status reflects checkpoint stack state"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state)))
      (autopoiesis.supervisor:checkpoint-agent agent :operation :alpha)
      (autopoiesis.supervisor:checkpoint-agent agent :operation :beta)
      (let ((status (autopoiesis.supervisor:supervisor-status)))
        (is (= 2 (getf status :checkpoint-depth)))
        (is (= 2 (length (getf status :stack))))
        ;; Top of stack should be :beta
        (is (eq :beta (getf (first (getf status :stack)) :operation)))))))

(test supervisor-status-after-promote
  "supervisor-status reflects stable-root after promotion"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state)))
      (autopoiesis.supervisor:checkpoint-agent agent :operation :gamma)
      (autopoiesis.supervisor:promote-checkpoint)
      (let ((status (autopoiesis.supervisor:supervisor-status)))
        (is (not (null (getf status :stable-root))))
        (is (= 0 (getf status :checkpoint-depth)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; with-checkpoint Macro Tests
;;; ═══════════════════════════════════════════════════════════════════

(test with-checkpoint-success-promotes
  "with-checkpoint promotes on successful completion"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state :name "before")))
      (let ((result (autopoiesis.supervisor:with-checkpoint
                        (agent :operation :success-test)
                      (setf (autopoiesis.agent:agent-name agent) "after")
                      :done)))
        (is (eq :done result))
        ;; Should have been promoted
        (is (not (null autopoiesis.supervisor:*stable-root*)))
        (is (= 0 (length autopoiesis.supervisor:*checkpoint-stack*)))
        ;; Agent keeps the modification
        (is (string= "after" (autopoiesis.agent:agent-name agent)))))))

(test with-checkpoint-failure-reverts
  "with-checkpoint reverts and re-signals on error"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state :name "safe")))
      (signals error
        (autopoiesis.supervisor:with-checkpoint
            (agent :operation :fail-test)
          (setf (autopoiesis.agent:agent-name agent) "broken")
          (error "deliberate failure")))
      ;; Agent should be reverted
      (is (string= "safe" (autopoiesis.agent:agent-name agent)))
      ;; No promotion should have happened
      (is (null autopoiesis.supervisor:*stable-root*)))))

(test with-checkpoint-failure-calls-on-revert
  "with-checkpoint calls on-revert callback on failure"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state))
          (revert-called nil)
          (revert-error nil))
      (handler-case
          (autopoiesis.supervisor:with-checkpoint
              (agent :operation :revert-callback
                     :on-revert (lambda (e)
                                  (setf revert-called t
                                        revert-error e)))
            (error "test error"))
        (error () nil))
      (is-true revert-called)
      (is (typep revert-error 'error)))))

(test with-checkpoint-nested
  "Nested with-checkpoint works correctly"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state :name "base")))
      (autopoiesis.supervisor:with-checkpoint
          (agent :operation :outer)
        (setf (autopoiesis.agent:agent-name agent) "outer-mod")
        (autopoiesis.supervisor:with-checkpoint
            (agent :operation :inner)
          (setf (autopoiesis.agent:agent-name agent) "inner-mod")))
      ;; Both should have promoted
      (is (string= "inner-mod" (autopoiesis.agent:agent-name agent)))
      (is (not (null autopoiesis.supervisor:*stable-root*))))))

(test with-checkpoint-nested-inner-failure
  "Nested with-checkpoint: inner failure reverts inner, outer succeeds"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state :name "base")))
      (autopoiesis.supervisor:with-checkpoint
          (agent :operation :outer)
        (setf (autopoiesis.agent:agent-name agent) "outer-mod")
        ;; Inner checkpoint fails - catch its error so outer succeeds
        (handler-case
            (autopoiesis.supervisor:with-checkpoint
                (agent :operation :inner)
              (setf (autopoiesis.agent:agent-name agent) "inner-mod")
              (error "inner failure"))
          (error () nil)))
      ;; Inner should have reverted to outer-mod, outer should have promoted
      (is (string= "outer-mod" (autopoiesis.agent:agent-name agent))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Nested Checkpoint Stack Tests
;;; ═══════════════════════════════════════════════════════════════════

(test nested-stack-push-pop
  "Multiple checkpoints maintain correct stack order"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state)))
      (autopoiesis.supervisor:checkpoint-agent agent :operation :a)
      (autopoiesis.supervisor:checkpoint-agent agent :operation :b)
      (autopoiesis.supervisor:checkpoint-agent agent :operation :c)
      (is (= 3 (length autopoiesis.supervisor:*checkpoint-stack*)))
      ;; Top should be :c
      (is (eq :c (cdr (first autopoiesis.supervisor:*checkpoint-stack*))))
      ;; Promote pops :c
      (autopoiesis.supervisor:promote-checkpoint)
      (is (= 2 (length autopoiesis.supervisor:*checkpoint-stack*)))
      (is (eq :b (cdr (first autopoiesis.supervisor:*checkpoint-stack*)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Recovery Integration Tests
;;; ═══════════════════════════════════════════════════════════════════

(test recovery-restart-available
  "revert-to-checkpoint restart is available in recovery context"
  (let ((restart-found nil))
    (handler-bind
        ((error (lambda (c)
                  (declare (ignore c))
                  (let ((restart (find-restart 'autopoiesis.core::revert-to-checkpoint)))
                    (setf restart-found (not (null restart)))
                    ;; Use a different restart to continue
                    (invoke-restart 'autopoiesis.core::abort-operation)))))
      (handler-case
          (autopoiesis.core:establish-recovery-restarts
           (lambda () (error "test"))
           :operation :test)
        (error () nil)))
    (is-true restart-found)))

(test recovery-strategy-registered
  "revert-on-inconsistency strategy is registered for state-inconsistency-error"
  (let ((strategies (autopoiesis.core:find-recovery-strategies
                     (make-condition 'autopoiesis.core:state-inconsistency-error
                                     :message "test"
                                     :expected-state :a
                                     :actual-state :b))))
    ;; Should find at least one strategy
    (is (not (null strategies)))
    ;; Should include the revert-on-inconsistency strategy
    (is (some (lambda (s) (eq (autopoiesis.core::strategy-name s)
                              'autopoiesis.supervisor::revert-on-inconsistency))
              strategies))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Extension Checkpoint Hook Tests
;;; ═══════════════════════════════════════════════════════════════════

(test extension-checkpoint-hook-exists
  "The *checkpoint-on-invoke* variable exists in extension-compiler"
  (is-true (boundp 'autopoiesis.core::*checkpoint-on-invoke*)))

(test extension-invoke-uses-hook
  "invoke-extension uses checkpoint hook when set"
  (let ((hook-called nil)
        (autopoiesis.core::*checkpoint-on-invoke*
          (lambda (thunk)
            (setf hook-called t)
            (funcall thunk)))
        (registry (make-hash-table :test 'equal)))
    ;; Register a simple extension
    (multiple-value-bind (ext errors)
        (autopoiesis.core:register-extension "test-agent" '(+ 1 2) :name "hook-test"
                                             :registry registry)
      (declare (ignore errors))
      (when ext
        (let ((ext-id (autopoiesis.core::extension-id ext)))
          (autopoiesis.core:invoke-extension ext-id :registry registry)
          (is-true hook-called))))))

(test extension-invoke-works-without-hook
  "invoke-extension works normally when hook is nil"
  (let ((autopoiesis.core::*checkpoint-on-invoke* nil)
        (registry (make-hash-table :test 'equal)))
    (multiple-value-bind (ext errors)
        (autopoiesis.core:register-extension "test-agent" '(+ 1 2) :name "no-hook-test"
                                             :registry registry)
      (declare (ignore errors))
      (when ext
        (let ((ext-id (autopoiesis.core::extension-id ext)))
          (let ((result (autopoiesis.core:invoke-extension ext-id :registry registry)))
            (is (= 3 result))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Round-trip Tests
;;; ═══════════════════════════════════════════════════════════════════

(test full-checkpoint-revert-cycle
  "Complete cycle: checkpoint -> modify -> revert -> verify"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state :name "cycle-test"
                                             :state :running
                                             :capabilities '(:alpha :beta))))
      ;; Checkpoint
      (autopoiesis.supervisor:checkpoint-agent agent :operation :full-cycle)
      ;; Modify everything
      (setf (autopoiesis.agent:agent-name agent) "changed")
      (setf (autopoiesis.agent:agent-state agent) :stopped)
      (setf (autopoiesis.agent:agent-capabilities agent) nil)
      (setf (autopoiesis.agent:agent-parent agent) "some-parent")
      (setf (autopoiesis.agent:agent-children agent) '("child-1"))
      ;; Verify modifications took effect
      (is (string= "changed" (autopoiesis.agent:agent-name agent)))
      (is (eq :stopped (autopoiesis.agent:agent-state agent)))
      ;; Revert
      (autopoiesis.supervisor:revert-to-stable agent)
      ;; Verify all fields restored
      (is (string= "cycle-test" (autopoiesis.agent:agent-name agent)))
      (is (eq :running (autopoiesis.agent:agent-state agent)))
      (is (equal '(:alpha :beta) (autopoiesis.agent:agent-capabilities agent)))
      (is (null (autopoiesis.agent:agent-parent agent)))
      (is (null (autopoiesis.agent:agent-children agent))))))

(test checkpoint-revert-preserves-identity
  "Revert returns the same agent object, not a new one"
  (with-supervisor-env
    (let ((agent (make-test-agent-with-state)))
      (autopoiesis.supervisor:checkpoint-agent agent)
      (setf (autopoiesis.agent:agent-name agent) "temp")
      (let ((result (autopoiesis.supervisor:revert-to-stable agent)))
        (is (eq agent result))))))
