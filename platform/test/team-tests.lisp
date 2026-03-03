;;;; team-tests.lisp - Tests for team coordination layer
;;;;
;;;; Tests mailbox concurrency, CV-based await, team lifecycle,
;;;; workspace coordination, strategy protocol, and team capabilities.

(in-package #:autopoiesis.test)

(def-suite team-tests
  :description "Team coordination layer tests")

(in-suite team-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Thread-Safe Mailbox Tests
;;; ═══════════════════════════════════════════════════════════════════

(test mailbox-ensure-creates
  "Test that ensure-mailbox creates a mailbox struct"
  (let ((autopoiesis.agent:*agent-mailboxes* (make-hash-table :test 'equal)))
    (let ((mbox (autopoiesis.agent:ensure-mailbox "test-agent-1")))
      (is (not (null mbox)))
      ;; Same call returns same mailbox
      (is (eq mbox (autopoiesis.agent:ensure-mailbox "test-agent-1"))))))

(test mailbox-deliver-and-receive
  "Test basic deliver and receive"
  (let ((autopoiesis.agent:*agent-mailboxes* (make-hash-table :test 'equal)))
    (autopoiesis.agent:send-message "sender" "receiver" '(:hello))
    (let ((msgs (autopoiesis.agent:receive-messages "receiver")))
      (is (= 1 (length msgs)))
      (is (equal '(:hello) (autopoiesis.agent:message-content (first msgs)))))))

(test mailbox-receive-clear
  "Test that :clear removes messages"
  (let ((autopoiesis.agent:*agent-mailboxes* (make-hash-table :test 'equal)))
    (autopoiesis.agent:send-message "a" "b" "msg1")
    (autopoiesis.agent:send-message "a" "b" "msg2")
    (let ((msgs (autopoiesis.agent:receive-messages "b" :clear t)))
      (is (= 2 (length msgs))))
    ;; After clear, no messages
    (let ((msgs (autopoiesis.agent:receive-messages "b")))
      (is (= 0 (length msgs))))))

(test mailbox-concurrent-delivery
  "Test concurrent message delivery from multiple threads"
  (let ((autopoiesis.agent:*agent-mailboxes* (make-hash-table :test 'equal))
        (num-threads 10)
        (msgs-per-thread 50))
    (let ((threads
            (loop for i from 0 below num-threads
                  collect (bt:make-thread
                           (lambda ()
                             (dotimes (j msgs-per-thread)
                               (autopoiesis.agent:send-message
                                (format nil "sender-~A" i)
                                "target"
                                (list :msg i j))))
                           :name (format nil "mailbox-test-~A" i)))))
      ;; Wait for all threads
      (dolist (th threads) (bt:join-thread th))
      ;; All messages should have arrived
      (let ((msgs (autopoiesis.agent:receive-messages "target")))
        (is (= (* num-threads msgs-per-thread) (length msgs)))))))

(test mailbox-blocking-receive
  "Test blocking receive with timeout"
  (let ((autopoiesis.agent:*agent-mailboxes* (make-hash-table :test 'equal)))
    ;; Blocking receive with short timeout should return empty
    (let ((msgs (autopoiesis.agent:receive-messages "nobody"
                                                     :block t :timeout 0.1)))
      (is (= 0 (length msgs))))
    ;; Deliver then receive
    (autopoiesis.agent:send-message "a" "blocker" "wake up")
    (let ((msgs (autopoiesis.agent:receive-messages "blocker" :block t :timeout 1)))
      (is (= 1 (length msgs))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; CV-Based Await Tests
;;; ═══════════════════════════════════════════════════════════════════

(test await-agent-already-complete
  "Test await-agent returns immediately for completed agents"
  (autopoiesis.substrate:with-store ()
    (let* ((aid "test-await-done")
           (eid (autopoiesis.substrate:intern-id aid)))
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom eid :agent/status :complete)
             (autopoiesis.substrate:make-datom eid :agent/result "done!")))
      (let ((result (autopoiesis.integration::%await-agent-cv aid :timeout 1)))
        (is (search "complete" result))
        (is (search "done!" result))))))

(test await-agent-timeout
  "Test await-agent times out for running agents"
  (autopoiesis.substrate:with-store ()
    (let* ((aid "test-await-timeout")
           (eid (autopoiesis.substrate:intern-id aid)))
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom eid :agent/status :running)))
      (let ((result (autopoiesis.integration::%await-agent-cv aid :timeout 0.5)))
        (is (search "Timeout" result))))))

(test await-agent-not-found
  "Test await-agent with unknown agent"
  (autopoiesis.substrate:with-store ()
    (let ((result (autopoiesis.integration::%await-agent-cv "nonexistent" :timeout 0.1)))
      (is (search "not found" result)))))

(test await-agent-completes-during-wait
  "Test await-agent detects completion via substrate hook"
  (autopoiesis.substrate:with-store ()
    (let* ((aid "test-await-hook")
           (eid (autopoiesis.substrate:intern-id aid)))
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom eid :agent/status :running)))
      ;; Complete the agent after a short delay
      (bt:make-thread
       (lambda ()
         (sleep 0.2)
         (autopoiesis.substrate:transact!
          (list (autopoiesis.substrate:make-datom eid :agent/status :complete)
                (autopoiesis.substrate:make-datom eid :agent/result "hook-result"))))
       :name "completer")
      (let ((result (autopoiesis.integration::%await-agent-cv aid :timeout 5)))
        (is (search "complete" result))
        (is (search "hook-result" result))))))

(test await-all-agents-mixed
  "Test await-all with mix of pre-completed and delayed agents"
  (autopoiesis.substrate:with-store ()
    (let* ((aid1 "test-all-done")
           (aid2 "test-all-delayed")
           (eid1 (autopoiesis.substrate:intern-id aid1))
           (eid2 (autopoiesis.substrate:intern-id aid2)))
      ;; Agent 1 already complete
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom eid1 :agent/status :complete)
             (autopoiesis.substrate:make-datom eid1 :agent/result "result-1")))
      ;; Agent 2 still running
      (autopoiesis.substrate:transact!
       (list (autopoiesis.substrate:make-datom eid2 :agent/status :running)))
      ;; Complete agent 2 after delay
      (bt:make-thread
       (lambda ()
         (sleep 0.2)
         (autopoiesis.substrate:transact!
          (list (autopoiesis.substrate:make-datom eid2 :agent/status :complete)
                (autopoiesis.substrate:make-datom eid2 :agent/result "result-2"))))
       :name "completer-2")
      (let ((results (autopoiesis.integration::%await-all-agents
                      (list aid1 aid2) :timeout 5)))
        (is (= 2 (length results)))
        (is (search "result-1" (cdr (first results))))
        (is (search "result-2" (cdr (second results))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Team Lifecycle Tests
;;; ═══════════════════════════════════════════════════════════════════

(test team-create-basic
  "Test basic team creation"
  (let ((autopoiesis.team:*team-registry* (make-hash-table :test 'equal)))
    (autopoiesis.substrate:with-store ()
      (let ((team (autopoiesis.team:create-team "test"
                    :strategy :parallel
                    :task "do something"
                    :members '("agent-1" "agent-2"))))
        (is (not (null team)))
        (is (search "test" (autopoiesis.team:team-id team)))
        (is (eq :created (autopoiesis.team:team-status team)))
        (is (equal "do something" (autopoiesis.team:team-task team)))
        (is (= 2 (length (autopoiesis.team:team-members team))))))))

(test team-registry-operations
  "Test team registry find/list/active"
  (let ((autopoiesis.team:*team-registry* (make-hash-table :test 'equal)))
    (autopoiesis.substrate:with-store ()
      (let ((team (autopoiesis.team:create-team "reg-test"
                    :strategy :parallel :task "test")))
        ;; Find by ID
        (is (eq team (autopoiesis.team:find-team (autopoiesis.team:team-id team))))
        ;; List teams
        (is (= 1 (length (autopoiesis.team:list-teams))))
        ;; No active teams yet (status is :created)
        (is (= 0 (length (autopoiesis.team:active-teams))))
        ;; Start the team
        (autopoiesis.team:start-team team)
        (is (eq :active (autopoiesis.team:team-status team)))
        (is (= 1 (length (autopoiesis.team:active-teams))))))))

(test team-lifecycle-transitions
  "Test team state transitions"
  (let ((autopoiesis.team:*team-registry* (make-hash-table :test 'equal)))
    (autopoiesis.substrate:with-store ()
      (let ((team (autopoiesis.team:create-team "lifecycle"
                    :strategy :leader-worker :task "test")))
        (is (eq :created (autopoiesis.team:team-status team)))
        (autopoiesis.team:start-team team)
        (is (eq :active (autopoiesis.team:team-status team)))
        (autopoiesis.team:pause-team team)
        (is (eq :paused (autopoiesis.team:team-status team)))
        (autopoiesis.team:resume-team team)
        (is (eq :active (autopoiesis.team:team-status team)))
        (autopoiesis.team:disband-team team)
        (is (eq :completed (autopoiesis.team:team-status team)))
        ;; Should be removed from registry
        (is (null (autopoiesis.team:find-team (autopoiesis.team:team-id team))))))))

(test team-query-status
  "Test query-team-status returns comprehensive info"
  (let ((autopoiesis.team:*team-registry* (make-hash-table :test 'equal)))
    (autopoiesis.substrate:with-store ()
      (let* ((team (autopoiesis.team:create-team "status-test"
                     :strategy :parallel
                     :task "analyze data"
                     :members '("agent-a" "agent-b")))
             (status (autopoiesis.team:query-team-status team)))
        (is (getf status :id))
        (is (eq :created (getf status :status)))
        (is (equal "analyze data" (getf status :task)))
        (is (= 2 (getf status :member-count)))))))

(test team-member-management
  "Test adding and removing team members"
  (let ((autopoiesis.team:*team-registry* (make-hash-table :test 'equal)))
    (autopoiesis.substrate:with-store ()
      (let ((team (autopoiesis.team:create-team "members"
                    :strategy :parallel :task "test")))
        (autopoiesis.team::add-team-member team "agent-1")
        (is (= 1 (length (autopoiesis.team:team-members team))))
        (autopoiesis.team::add-team-member team "agent-2")
        (is (= 2 (length (autopoiesis.team:team-members team))))
        ;; Duplicate add is idempotent
        (autopoiesis.team::add-team-member team "agent-1")
        (is (= 2 (length (autopoiesis.team:team-members team))))
        ;; Remove
        (autopoiesis.team::remove-team-member team "agent-1")
        (is (= 1 (length (autopoiesis.team:team-members team))))))))

(test team-serialization
  "Test team serialization roundtrip"
  (let ((autopoiesis.team:*team-registry* (make-hash-table :test 'equal)))
    (autopoiesis.substrate:with-store ()
      (let* ((team (autopoiesis.team:create-team "serial"
                     :strategy :parallel
                     :task "serialize me"
                     :members '("a" "b")))
             (plist (autopoiesis.team:team-to-plist team))
             (restored (autopoiesis.team:plist-to-team plist)))
        (is (equal (autopoiesis.team:team-id team)
                   (autopoiesis.team:team-id restored)))
        (is (equal (autopoiesis.team:team-task team)
                   (autopoiesis.team:team-task restored)))
        (is (equal (autopoiesis.team:team-members team)
                   (autopoiesis.team:team-members restored)))))))

(test team-registry-concurrent-creates
  "Test concurrent team creation"
  (let ((autopoiesis.team:*team-registry* (make-hash-table :test 'equal)))
    (autopoiesis.substrate:with-store ()
      (let ((threads
              (loop for i from 0 below 10
                    collect (bt:make-thread
                             (lambda ()
                               (autopoiesis.team:create-team
                                (format nil "concurrent-~A" i)
                                :strategy :parallel
                                :task "test"))
                             :name (format nil "team-create-~A" i)))))
        (dolist (th threads) (bt:join-thread th))
        (is (= 10 (length (autopoiesis.team:list-teams))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Workspace Coordination Tests
;;; ═══════════════════════════════════════════════════════════════════

(test workspace-put-get-roundtrip
  "Test workspace shared memory put/get"
  (autopoiesis.substrate:with-store ()
    (autopoiesis.workspace:workspace-put "ws-1" "mykey" "myvalue")
    (is (equal "myvalue"
               (autopoiesis.workspace:workspace-get "ws-1" "mykey")))))

(test workspace-put-overwrite
  "Test workspace put overwrites existing value"
  (autopoiesis.substrate:with-store ()
    (autopoiesis.workspace:workspace-put "ws-2" "key" "v1")
    (autopoiesis.workspace:workspace-put "ws-2" "key" "v2")
    (is (equal "v2" (autopoiesis.workspace:workspace-get "ws-2" "key")))))

(test workspace-get-missing
  "Test workspace get returns nil for missing key"
  (autopoiesis.substrate:with-store ()
    (is (null (autopoiesis.workspace:workspace-get "ws-none" "nope")))))

(test workspace-task-push-and-list
  "Test pushing tasks and listing them"
  (autopoiesis.substrate:with-store ()
    (let ((ws-id "ws-task-test"))
      (autopoiesis.workspace:workspace-push-task ws-id "task one")
      (autopoiesis.workspace:workspace-push-task ws-id "task two")
      (let ((tasks (autopoiesis.workspace:workspace-list-tasks ws-id)))
        (is (= 2 (length tasks)))
        (is (every (lambda (t) (eq :pending (getf t :status))) tasks))))))

(test workspace-task-submit-result
  "Test submitting a result for a task"
  (autopoiesis.substrate:with-store ()
    (let* ((ws-id "ws-submit-test")
           (task-id (autopoiesis.workspace:workspace-push-task ws-id "do it")))
      (autopoiesis.workspace:workspace-submit-result task-id "done!")
      (let ((tasks (autopoiesis.workspace:workspace-list-tasks ws-id :status :complete)))
        (is (= 1 (length tasks)))
        (is (equal "done!" (getf (first tasks) :result)))))))

(test workspace-log-entry
  "Test coordination log entries"
  (autopoiesis.substrate:with-store ()
    (let ((log-id (autopoiesis.workspace:workspace-log-entry
                   "ws-log" "agent-1" "Starting work")))
      (is (not (null log-id))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Strategy Protocol Tests
;;; ═══════════════════════════════════════════════════════════════════

(test strategy-make-all-types
  "Test that all strategy types can be instantiated"
  (dolist (type '(:leader-worker :parallel :pipeline :debate :consensus))
    (let ((s (autopoiesis.team:make-strategy type)))
      (is (not (null s))
          (format nil "Strategy ~A should be creatable" type)))))

(test leader-worker-strategy-basic
  "Test leader-worker strategy initialization"
  (let ((autopoiesis.team:*team-registry* (make-hash-table :test 'equal)))
    (autopoiesis.substrate:with-store ()
      (let ((team (autopoiesis.team:create-team "lw-test"
                    :strategy :leader-worker
                    :task "build something"
                    :leader "boss"
                    :members '("boss" "worker-1" "worker-2"))))
        (autopoiesis.team:start-team team)
        (is (eq :active (autopoiesis.team:team-status team)))
        (is (equal "boss" (autopoiesis.team:team-leader team)))))))

(test parallel-strategy-assign
  "Test parallel strategy assigns to all members"
  (let ((autopoiesis.team:*team-registry* (make-hash-table :test 'equal))
        (autopoiesis.agent:*agent-mailboxes* (make-hash-table :test 'equal)))
    (autopoiesis.substrate:with-store ()
      (let ((team (autopoiesis.team:create-team "par-test"
                    :strategy :parallel
                    :task "analyze"
                    :members '("agent-1" "agent-2" "agent-3"))))
        (autopoiesis.team:start-team team)
        (let ((result (autopoiesis.team:strategy-assign-work
                       (autopoiesis.team:team-strategy team)
                       team "analyze this")))
          (is (search "3 members" result))
          ;; Each member should have a message
          (dolist (mid '("agent-1" "agent-2" "agent-3"))
            (let ((msgs (autopoiesis.agent:receive-messages mid)))
              (is (= 1 (length msgs))))))))))

(test pipeline-strategy-stages
  "Test pipeline strategy stage advancement"
  (let ((strategy (autopoiesis.team:make-strategy :pipeline)))
    (is (= 0 (autopoiesis.team::pipeline-current-stage strategy)))
    (autopoiesis.team::advance-pipeline strategy "stage-0-result")
    (is (= 1 (autopoiesis.team::pipeline-current-stage strategy)))
    (is (equal '("stage-0-result")
               (autopoiesis.team::pipeline-stage-results strategy)))))

(test debate-strategy-rounds
  "Test debate strategy round tracking"
  (let ((strategy (autopoiesis.team:make-strategy :debate '(:max-rounds 2))))
    (is (= 0 (autopoiesis.team::debate-current-round strategy)))
    (autopoiesis.team::record-debate-argument strategy "agent-1" "I argue X")
    (autopoiesis.team::advance-debate strategy)
    (is (= 1 (autopoiesis.team::debate-current-round strategy)))
    (autopoiesis.team::advance-debate strategy)
    ;; Should be complete after max rounds
    (is (autopoiesis.team:strategy-complete-p
         strategy (make-instance 'autopoiesis.team:team)))))

(test consensus-strategy-convergence
  "Test consensus strategy vote tracking"
  (let ((strategy (autopoiesis.team:make-strategy :consensus '(:threshold 1.0))))
    (autopoiesis.team::record-consensus-vote strategy "agent-1" :approve)
    (autopoiesis.team::record-consensus-vote strategy "agent-2" :approve)
    (let ((votes (autopoiesis.team::consensus-votes strategy)))
      (is (= 1 (length votes)))
      (is (= 2 (length (cdr (first votes))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Team Capability Tests
;;; ═══════════════════════════════════════════════════════════════════

(test team-tools-registered
  "Test that team tools are in the builtin-tool-symbols list"
  (let ((tools (autopoiesis.integration:builtin-tool-symbols)))
    (is (member 'autopoiesis.integration::create-team-tool tools))
    (is (member 'autopoiesis.integration::start-team-work tools))
    (is (member 'autopoiesis.integration::query-team-tool tools))
    (is (member 'autopoiesis.integration::await-team tools))
    (is (member 'autopoiesis.integration::disband-team-tool tools))))

(test workspace-team-capabilities-list
  "Test that workspace capability names include team operations"
  (let ((names (autopoiesis.workspace:workspace-capability-names)))
    (is (member 'autopoiesis.workspace::team-workspace-read names))
    (is (member 'autopoiesis.workspace::team-workspace-write names))
    (is (member 'autopoiesis.workspace::team-claim-task names))
    (is (member 'autopoiesis.workspace::team-submit-result names))
    (is (member 'autopoiesis.workspace::team-broadcast names))))

(test jarvis-with-team-function-exists
  "Test that start-jarvis-with-team is available"
  (is (fboundp 'autopoiesis.jarvis:start-jarvis-with-team)))
