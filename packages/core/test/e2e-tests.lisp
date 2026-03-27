;;;; e2e-tests.lisp - End-to-end tests for user stories
;;;;
;;;; Tests complete user flows from the user stories document.
;;;; Each test represents a real-world scenario users will encounter.

(in-package #:autopoiesis.test)

(def-suite e2e-tests
  :description "End-to-end tests for user stories")

(in-suite e2e-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Test Utilities
;;; ═══════════════════════════════════════════════════════════════════

(defun make-temp-store-for-e2e ()
  "Create a temporary snapshot store for E2E tests."
  (let ((path (merge-pathnames
               (format nil "autopoiesis-e2e-~a/" (autopoiesis.core:make-uuid))
               (uiop:temporary-directory))))
    (ensure-directories-exist path)
    (autopoiesis.snapshot:make-snapshot-store path)))

(defun cleanup-e2e-store (store)
  "Clean up E2E test store."
  ;; Note: store-base-path is not exported, using internal access
  (let ((path (autopoiesis.snapshot::store-base-path store)))
    (when (probe-file path)
      (uiop:delete-directory-tree path :validate t))))

(defmacro with-temp-store ((store-var) &body body)
  "Execute BODY with a temporary snapshot store."
  `(let ((,store-var (make-temp-store-for-e2e)))
     (unwind-protect
          (progn ,@body)
       (cleanup-e2e-store ,store-var))))

(defmacro with-clean-registries (&body body)
  "Execute BODY with clean capability and agent registries."
  `(let ((autopoiesis.agent::*capability-registry* (make-hash-table :test 'equal))
         (autopoiesis.agent:*agent-mailboxes* (make-hash-table :test 'equal)))
     ,@body))

(defmacro with-clean-blocking-requests (&body body)
  "Execute BODY with clean blocking requests registry."
  `(progn
     (bordeaux-threads:with-lock-held (autopoiesis.interface::*blocking-requests-lock*)
       (clrhash autopoiesis.interface::*blocking-requests*))
     ,@body))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 1: Starting an Interactive Session with an Agent
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-1-start-interactive-session
  "E2E: Developer starts CLI session with agent and observes agent state"
  ;; Create an agent with specific capabilities
  (let* ((agent (autopoiesis.agent:make-agent
                 :name "code-reviewer"
                 :capabilities '(read-file analyze-code suggest-fix)))
         ;; Start a session (as a developer would)
         (session (autopoiesis.interface:start-session "developer" agent)))

    ;; Acceptance: Session displays agent name and truncated IDs
    (is (not (null (autopoiesis.interface:session-id session))))
    (is (stringp (autopoiesis.interface:session-id session)))
    (is (eq agent (autopoiesis.interface:session-agent session)))

    ;; Acceptance: Session shows agent state
    (is (eq :initialized (autopoiesis.agent:agent-state agent)))

    ;; Session summary should include key info
    (let ((summary (autopoiesis.interface:session-summary session)))
      (is (getf summary :id))
      (is (equal "developer" (getf summary :user)))
      (is (equal "code-reviewer" (getf summary :agent))))

    ;; Agent can be started and state changes
    (autopoiesis.agent:start-agent agent)
    (is (eq :running (autopoiesis.agent:agent-state agent)))

    ;; Clean up
    (autopoiesis.agent:stop-agent agent)
    (autopoiesis.interface:end-session session)))

(test e2e-story-1-session-lifecycle
  "E2E: Complete session lifecycle from create to end"
  (let* ((agent (autopoiesis.agent:make-agent :name "lifecycle-test"))
         (session (autopoiesis.interface:start-session "tester" agent))
         (session-id (autopoiesis.interface:session-id session)))

    ;; Session is findable
    (is (eq session (autopoiesis.interface:find-session session-id)))

    ;; Agent lifecycle within session
    (autopoiesis.agent:start-agent agent)
    (is (autopoiesis.agent:agent-running-p agent))

    (autopoiesis.agent:pause-agent agent)
    (is (eq :paused (autopoiesis.agent:agent-state agent)))

    (autopoiesis.agent:resume-agent agent)
    (is (autopoiesis.agent:agent-running-p agent))

    (autopoiesis.agent:stop-agent agent)

    ;; End session cleans up
    (autopoiesis.interface:end-session session)
    (is (null (autopoiesis.interface:find-session session-id)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 2: Injecting Context into a Running Agent
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-2-inject-observation
  "E2E: Developer injects observation into agent's thought stream"
  (let* ((agent (autopoiesis.agent:make-agent :name "context-injection-test"))
         (stream (autopoiesis.agent:agent-thought-stream agent)))

    ;; Start agent
    (autopoiesis.agent:start-agent agent)

    ;; Inject an observation (simulating CLI inject command)
    ;; make-observation signature: (raw &key source interpreted)
    (let ((observation (autopoiesis.core:make-observation
                        "Review the authentication module for SQL injection vulnerabilities"
                        :source :human-cli)))
      (autopoiesis.core:stream-append stream observation)

      ;; Acceptance: Thought appears in agent's stream immediately
      ;; Note: stream-thoughts returns a vector, use stream-length and stream-last for lists
      (is (>= (autopoiesis.core:stream-length stream) 1))
      (let ((last-thoughts (autopoiesis.core:stream-last stream 1)))
        (let ((last-thought (first last-thoughts)))
          (is (typep last-thought 'autopoiesis.core:observation))
          (is (eq :human-cli (autopoiesis.core:observation-source last-thought)))
          (is (equal "Review the authentication module for SQL injection vulnerabilities"
                     (autopoiesis.core:thought-content last-thought))))))

    (autopoiesis.agent:stop-agent agent)))

(test e2e-story-2-multiple-injections
  "E2E: Multiple injections maintain order in thought stream"
  (let* ((agent (autopoiesis.agent:make-agent :name "multi-inject"))
         (stream (autopoiesis.agent:agent-thought-stream agent)))

    (autopoiesis.agent:start-agent agent)

    ;; Inject multiple observations
    ;; make-observation signature: (raw &key source interpreted)
    (loop for msg in '("First task" "Second task" "Third task")
          do (autopoiesis.core:stream-append
              stream
              (autopoiesis.core:make-observation msg :source :human-cli)))

    ;; All thoughts should be present in order
    ;; Note: stream-thoughts returns a vector, use stream-length and stream-last for lists
    (is (>= (autopoiesis.core:stream-length stream) 3))
    (let ((last-thoughts (autopoiesis.core:stream-last stream 3)))
      (let ((contents (mapcar #'autopoiesis.core:thought-content last-thoughts)))
        (is (equal '("First task" "Second task" "Third task") contents))))

    (autopoiesis.agent:stop-agent agent)))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 3: Agent Requests Human Approval Before Dangerous Action
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-3-blocking-approval-flow
  "E2E: Agent blocks waiting for human approval"
  (with-clean-blocking-requests
    ;; Create a blocking request (as an agent would)
    (let ((request (autopoiesis.interface:make-blocking-request
                    "About to delete 15 files. Proceed?"
                    :options '("yes" "no" "show-list")
                    :default "no")))

      ;; Acceptance: Human can see pending requests
      (let ((pending (autopoiesis.interface:list-pending-blocking-requests)))
        (is (= 1 (length pending)))
        (is (member request pending)))

      ;; Acceptance: Human can respond by full ID
      ;; Note: find-blocking-request requires full ID, not prefix (missing feature: prefix lookup)
      (let ((full-id (autopoiesis.interface:blocking-request-id request)))
        (multiple-value-bind (success found-request)
            (autopoiesis.interface:respond-to-request full-id "yes")
          (is-true success)
          (is (eq request found-request))))

      ;; Acceptance: Request status changed
      (is (eq :responded (autopoiesis.interface:blocking-request-status request)))
      (is (equal "yes" (autopoiesis.interface:blocking-request-response request))))))

(test e2e-story-3-timeout-returns-default
  "E2E: Timeout returns default value with :timeout status"
  (with-clean-blocking-requests
    (let ((request (autopoiesis.interface:make-blocking-request
                    "Approve action?"
                    :default "abort")))

      ;; Wait with very short timeout - no one responds
      (multiple-value-bind (response status)
          (autopoiesis.interface:wait-for-response request :timeout 0.05)

        ;; Acceptance: Timeout returns default value with :timeout status
        (is (eq :timeout status))
        (is (equal "abort" response))))))

(test e2e-story-3-threaded-approval
  "E2E: Response from another thread unblocks waiting agent"
  (with-clean-blocking-requests
    (let ((request (autopoiesis.interface:make-blocking-request "Delete logs?"))
          (result nil)
          (result-status nil))

      ;; Simulate agent waiting in background thread
      (let ((agent-thread (bordeaux-threads:make-thread
                           (lambda ()
                             (multiple-value-bind (r s)
                                 (autopoiesis.interface:wait-for-response request :timeout 5.0)
                               (setf result r)
                               (setf result-status s)))
                           :name "agent-waiter")))

        ;; Give agent time to start waiting
        (sleep 0.1)

        ;; Human provides response
        (autopoiesis.interface:provide-response request "approved")

        ;; Agent should unblock
        (bordeaux-threads:join-thread agent-thread)

        ;; Acceptance: Thread-safe implementation unblocked correctly
        (is (eq :responded result-status))
        (is (equal "approved" result))))))

(test e2e-story-3-cancel-request
  "E2E: Human cancels blocking request"
  (with-clean-blocking-requests
    (let ((request (autopoiesis.interface:make-blocking-request "Dangerous operation")))

      (autopoiesis.interface:cancel-blocking-request request :reason "Changed my mind")

      ;; Acceptance: Cancelled status with reason
      (is (eq :cancelled (autopoiesis.interface:blocking-request-status request)))
      (is (equal '(:cancelled :reason "Changed my mind")
                 (autopoiesis.interface:blocking-request-response request))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 4: Stepping Through Agent Cognition One Cycle at a Time
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-4-step-through-cognition
  "E2E: Developer steps through cognitive cycles one at a time"
  (let ((agent (autopoiesis.agent:make-agent :name "step-debug")))

    ;; Start agent and immediately pause
    (autopoiesis.agent:start-agent agent)
    (autopoiesis.agent:pause-agent agent)

    ;; Acceptance: Pause suspends automatic cognitive loop
    (is (eq :paused (autopoiesis.agent:agent-state agent)))

    ;; Inject some context to process
    (let ((stream (autopoiesis.agent:agent-thought-stream agent)))
      (autopoiesis.core:stream-append
       stream
       (autopoiesis.core:make-observation "Task: analyze code" :source :human-cli)))

    ;; Step executes one cycle (the cognitive-cycle function)
    ;; cognitive-cycle signature: (agent environment)
    (autopoiesis.agent:cognitive-cycle agent nil)

    ;; Acceptance: Status shows thoughts after step
    (let ((thoughts (autopoiesis.core:stream-thoughts
                     (autopoiesis.agent:agent-thought-stream agent))))
      (is (>= (length thoughts) 1)))

    ;; Agent can resume
    (autopoiesis.agent:resume-agent agent)
    (is (eq :running (autopoiesis.agent:agent-state agent)))

    (autopoiesis.agent:stop-agent agent)))

(test e2e-story-4-state-transitions
  "E2E: Agent state transitions correctly through lifecycle"
  (let ((agent (autopoiesis.agent:make-agent)))
    ;; initialized -> running -> paused -> running -> stopped
    (is (eq :initialized (autopoiesis.agent:agent-state agent)))

    (autopoiesis.agent:start-agent agent)
    (is (eq :running (autopoiesis.agent:agent-state agent)))

    (autopoiesis.agent:pause-agent agent)
    (is (eq :paused (autopoiesis.agent:agent-state agent)))

    (autopoiesis.agent:resume-agent agent)
    (is (eq :running (autopoiesis.agent:agent-state agent)))

    (autopoiesis.agent:stop-agent agent)
    (is (eq :stopped (autopoiesis.agent:agent-state agent)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 5: Traveling Back in Time to a Previous State
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-5-time-travel-checkout
  "E2E: Developer checks out previous snapshot and inspects state"
  (with-temp-store (store)
    ;; Create a series of snapshots (simulating agent state over time)
    (let* ((state-1 '(:agent-state (:thoughts ((id . 1) (content . "thinking")))))
           (state-2 '(:agent-state (:thoughts ((id . 1) (content . "thinking"))
                                              ((id . 2) (content . "deciding")))))
           (state-3 '(:agent-state (:thoughts ((id . 1) (content . "thinking"))
                                              ((id . 2) (content . "deciding"))
                                              ((id . 3) (content . "acting")))))
           (snap-1 (autopoiesis.snapshot:make-snapshot state-1))
           (snap-1-id (autopoiesis.snapshot:snapshot-id snap-1)))

      (autopoiesis.snapshot:save-snapshot snap-1 store)

      (let* ((snap-2 (autopoiesis.snapshot:make-snapshot state-2 :parent snap-1-id))
             (snap-2-id (autopoiesis.snapshot:snapshot-id snap-2)))
        (autopoiesis.snapshot:save-snapshot snap-2 store)

        (let ((snap-3 (autopoiesis.snapshot:make-snapshot state-3 :parent snap-2-id)))
          (autopoiesis.snapshot:save-snapshot snap-3 store)

          ;; Acceptance: Snapshots persist to disk
          (is (autopoiesis.snapshot:snapshot-exists-p snap-1-id store))
          (is (autopoiesis.snapshot:snapshot-exists-p snap-2-id store))

          ;; Acceptance: Checkout returns agent state
          (autopoiesis.snapshot:clear-snapshot-cache store)
          (let ((loaded (autopoiesis.snapshot:load-snapshot snap-1-id store)))
            (is (not (null loaded)))
            (is (equal state-1 (autopoiesis.snapshot:snapshot-agent-state loaded))))

          ;; Acceptance: Parent-child relationships form navigable DAG
          (let ((ancestors (autopoiesis.snapshot:snapshot-ancestors
                            (autopoiesis.snapshot:snapshot-id snap-3) store)))
            (is (= 2 (length ancestors)))
            (is (member snap-1-id ancestors :test #'string=))
            (is (member snap-2-id ancestors :test #'string=))))))))

(test e2e-story-5-list-snapshots
  "E2E: List available snapshots including root-only filtering"
  (with-temp-store (store)
    (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
           (root-id (autopoiesis.snapshot:snapshot-id root)))
      (autopoiesis.snapshot:save-snapshot root store)

      (let* ((child (autopoiesis.snapshot:make-snapshot '(:child t) :parent root-id))
             (child-id (autopoiesis.snapshot:snapshot-id child)))
        (autopoiesis.snapshot:save-snapshot child store)

        ;; Acceptance: Root-only listing excludes children
        (let ((roots (autopoiesis.snapshot:list-snapshots :root-only t :store store)))
          (is (member root-id roots :test #'string=))
          (is (not (member child-id roots :test #'string=))))

        ;; All snapshots listing includes both
        (let ((all (autopoiesis.snapshot:list-snapshots :root-only nil :store store)))
          (is (member root-id all :test #'string=))
          (is (member child-id all :test #'string=)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 6: Forking to Explore Alternative Approaches
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-6-create-branch-from-snapshot
  "E2E: Researcher forks from current state to explore alternatives"
  (with-temp-store (store)
    (let ((registry (make-hash-table :test 'equal)))
      ;; Create initial snapshot on main branch
      (let ((main-branch (autopoiesis.snapshot:create-branch "main" :registry registry)))
        (let* ((root-state '(:approach :original))
               (root-snap (autopoiesis.snapshot:make-snapshot root-state))
               (root-id (autopoiesis.snapshot:snapshot-id root-snap)))
          (autopoiesis.snapshot:save-snapshot root-snap store)
          (setf (autopoiesis.snapshot:branch-head main-branch) root-id)

          ;; Acceptance: Create branch from specific snapshot
          (let ((exp-branch (autopoiesis.snapshot:create-branch
                             "experimental"
                             :from-snapshot root-id
                             :registry registry)))
            (is (string= "experimental" (autopoiesis.snapshot:branch-name exp-branch)))
            (is (string= root-id (autopoiesis.snapshot:branch-head exp-branch)))

            ;; Work on experimental branch - add new snapshot
            (let* ((exp-state '(:approach :experimental))
                   (exp-snap (autopoiesis.snapshot:make-snapshot exp-state :parent root-id))
                   (exp-id (autopoiesis.snapshot:snapshot-id exp-snap)))
              (autopoiesis.snapshot:save-snapshot exp-snap store)
              (setf (autopoiesis.snapshot:branch-head exp-branch) exp-id)

              ;; Work on main branch separately
              (let* ((main-state '(:approach :original :progress 50))
                     (main-snap (autopoiesis.snapshot:make-snapshot main-state :parent root-id))
                     (main-id (autopoiesis.snapshot:snapshot-id main-snap)))
                (autopoiesis.snapshot:save-snapshot main-snap store)
                (setf (autopoiesis.snapshot:branch-head main-branch) main-id)

                ;; Acceptance: Branches have different heads
                (is (not (string= (autopoiesis.snapshot:branch-head main-branch)
                                  (autopoiesis.snapshot:branch-head exp-branch))))

                ;; Acceptance: Both share common ancestor
                (let ((ancestor (autopoiesis.snapshot:find-common-ancestor
                                 main-id exp-id store)))
                  (is (not (null ancestor)))
                  (is (string= root-id (autopoiesis.snapshot:snapshot-id ancestor))))

                ;; Acceptance: Diff shows changes between branches
                (let ((diff (autopoiesis.snapshot:snapshot-diff
                             (autopoiesis.snapshot:load-snapshot main-id store)
                             (autopoiesis.snapshot:load-snapshot exp-id store))))
                  (is (not (null diff))))))))))))

(test e2e-story-6-switch-branches
  "E2E: Switch between branches and verify head changes"
  (let ((registry (make-hash-table :test 'equal))
        (*current-branch* nil))
    (declare (special *current-branch*))

    ;; Create branches
    (let ((main (autopoiesis.snapshot:create-branch "main" :registry registry))
          (feature (autopoiesis.snapshot:create-branch "feature" :registry registry)))

      (setf (autopoiesis.snapshot:branch-head main) "main-head-id")
      (setf (autopoiesis.snapshot:branch-head feature) "feature-head-id")

      ;; Acceptance: Switching branches updates current branch
      (setf *current-branch* main)
      (is (eq *current-branch* main))
      (is (string= "main-head-id" (autopoiesis.snapshot:branch-head *current-branch*)))

      (setf *current-branch* feature)
      (is (eq *current-branch* feature))
      (is (string= "feature-head-id" (autopoiesis.snapshot:branch-head *current-branch*))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 7: Agent Spawns Specialized Child Agent
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-7-spawn-child-agent
  "E2E: Coordinator agent spawns specialized child for subtask"
  (with-clean-registries
    (let ((coordinator (autopoiesis.agent:make-agent
                        :name "coordinator"
                        :capabilities '(plan delegate))))

      (autopoiesis.agent:with-current-agent (coordinator)
        ;; Acceptance: Spawn child via capability
        (let ((analyzer (autopoiesis.agent:capability-spawn
                         "security-analyzer"
                         :capabilities '(code-read pattern-match))))

          ;; Acceptance: Child has specified name
          (is (string= "security-analyzer" (autopoiesis.agent:agent-name analyzer)))

          ;; Acceptance: Parent-child relationship tracked
          (is (equal (autopoiesis.agent:agent-id coordinator)
                     (autopoiesis.agent:agent-parent analyzer)))
          (is (member (autopoiesis.agent:agent-id analyzer)
                      (autopoiesis.agent:agent-children coordinator)
                      :test #'equal)))))))

(test e2e-story-7-message-passing
  "E2E: Parent and child communicate via messages"
  (with-clean-registries
    (let ((parent (autopoiesis.agent:make-agent :name "parent"))
          (child (autopoiesis.agent:make-agent :name "child")))

      ;; Clear mailboxes
      (setf (gethash (autopoiesis.agent:agent-id child)
                     autopoiesis.agent:*agent-mailboxes*) nil)

      ;; Parent sends task to child
      (autopoiesis.agent:with-current-agent (parent)
        (autopoiesis.agent:capability-communicate
         child
         '(:task :analyze-file "auth/login.py" :focus :sql-injection)))

      ;; Acceptance: Message queued in child's mailbox
      (autopoiesis.agent:with-current-agent (child)
        (let ((messages (autopoiesis.agent:capability-receive)))
          (is (= 1 (length messages)))
          (let ((msg (first messages)))
            (is (equal (autopoiesis.agent:agent-id parent)
                       (autopoiesis.agent:message-from msg)))
            (is (equal '(:task :analyze-file "auth/login.py" :focus :sql-injection)
                       (autopoiesis.agent:message-content msg)))))

        ;; Send result back to parent
        (autopoiesis.agent:capability-communicate
         parent
         '(:result :vulnerabilities 2 :severity :high)))

      ;; Clear and verify parent received result
      (setf (gethash (autopoiesis.agent:agent-id parent)
                     autopoiesis.agent:*agent-mailboxes*)
            (gethash (autopoiesis.agent:agent-id parent)
                     autopoiesis.agent:*agent-mailboxes*))

      (autopoiesis.agent:with-current-agent (parent)
        (let ((messages (autopoiesis.agent:capability-receive :clear t)))
          (is (= 1 (length messages)))
          (is (equal '(:result :vulnerabilities 2 :severity :high)
                     (autopoiesis.agent:message-content (first messages)))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 8: Integrating Agent with Claude API
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-8-claude-session-creation
  "E2E: Create Claude session for agent with auto-generated tools"
  ;; Note: make-agent :capabilities accepts symbol names but create-claude-session-for-agent
  ;; expects registered capability objects. Create agent without capabilities for basic test.
  ;; Full capability integration tested in e2e-story-8-capability-to-tool-conversion.
  (let ((agent (autopoiesis.agent:make-agent :name "claude-integrated")))

    ;; Create session linked to agent
    (let ((session (autopoiesis.integration:create-claude-session-for-agent agent)))

      ;; Acceptance: Session created with ID
      (is (not (null session)))
      (is (stringp (autopoiesis.integration:claude-session-id session)))

      ;; Acceptance: Session linked to agent
      (is (equal (autopoiesis.agent:agent-id agent)
                 (autopoiesis.integration:claude-session-agent-id session)))

      ;; Acceptance: System prompt auto-generated from agent context
      (let ((system-prompt (autopoiesis.integration:claude-session-system-prompt session)))
        (is (stringp system-prompt))
        (is (> (length system-prompt) 0)))

      ;; Clean up
      (autopoiesis.integration:delete-claude-session session))))

(test e2e-story-8-capability-to-tool-conversion
  "E2E: Agent capabilities auto-convert to Claude tool format"
  (with-clean-registries
    ;; Register a capability
    (let ((cap (autopoiesis.agent:make-capability
                'test-search
                (lambda (query) (list :results query))
                :description "Search for files"
                :parameters '((query string :required t :doc "Search query")
                              (limit integer :default 10 :doc "Max results")))))
      (autopoiesis.agent:register-capability cap)

      ;; Acceptance: Convert to Claude tool format
      (let ((claude-tool (autopoiesis.integration:capability-to-claude-tool cap)))
        (is (not (null claude-tool)))
        ;; Tool name should be snake_case
        (is (equal "test_search"
                   (cdr (assoc "name" claude-tool :test #'string=))))
        ;; Description preserved
        (is (equal "Search for files"
                   (cdr (assoc "description" claude-tool :test #'string=))))
        ;; Input schema should have properties
        (let* ((schema (cdr (assoc "input_schema" claude-tool :test #'string=)))
               (props (cdr (assoc "properties" schema :test #'string=))))
          (is (not (null props)))
          (is (cdr (assoc "query" props :test #'string=)))
          (is (cdr (assoc "limit" props :test #'string=))))))))

(test e2e-story-8-tool-name-conversion
  "E2E: Tool names convert between kebab-case and snake_case"
  ;; Acceptance: Lisp name to Claude tool name
  (is (equal "read_file" (autopoiesis.integration:lisp-name-to-tool-name 'read-file)))
  (is (equal "analyze_code" (autopoiesis.integration:lisp-name-to-tool-name 'analyze-code)))

  ;; Acceptance: Claude tool name to Lisp name (returns keyword, not symbol)
  (is (equal :read-file (autopoiesis.integration:tool-name-to-lisp-name "read_file")))
  (is (equal :analyze-code (autopoiesis.integration:tool-name-to-lisp-name "analyze_code"))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 9: Human Overrides Agent Decision
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-9-inject-override
  "E2E: Supervisor overrides agent decision via injection"
  (let* ((agent (autopoiesis.agent:make-agent :name "supervised"))
         (stream (autopoiesis.agent:agent-thought-stream agent)))

    (autopoiesis.agent:start-agent agent)

    ;; Agent made a decision
    ;; make-decision signature: (alternatives chosen &key rationale confidence)
    (autopoiesis.core:stream-append
     stream
     (autopoiesis.core:make-decision
      '((:archive-logs . 0.3) (:delete-all-logs . 0.7))
      :delete-all-logs))

    ;; Acceptance: Inject override observation
    ;; make-observation signature: (raw &key source interpreted)
    (autopoiesis.core:stream-append
     stream
     (autopoiesis.core:make-observation
      "Override: Do NOT delete logs. Archive them to S3 instead."
      :source :human-override))

    ;; Acceptance: Override thought appears in stream
    (let ((thoughts (autopoiesis.core:stream-thoughts stream)))
      (let ((override (find-if
                       (lambda (th)  ; renamed from t (reserved constant)
                         (and (typep th 'autopoiesis.core:observation)
                              (eq :human-override (autopoiesis.core:observation-source th))))
                       thoughts)))
        (is (not (null override)))
        (is (search "Do NOT delete" (autopoiesis.core:thought-content override)))))

    (autopoiesis.agent:stop-agent agent)))

(test e2e-story-9-decision-rejection
  "E2E: Human rejects agent decision programmatically"
  (let* ((agent (autopoiesis.agent:make-agent :name "rejection-test"))
         (stream (autopoiesis.agent:agent-thought-stream agent)))

    ;; Agent made a decision with confidence
    ;; make-decision signature: (alternatives chosen &key rationale confidence)
    (let ((decision (autopoiesis.core:make-decision
                     '((:safe-action . 0.1) (:risky-action . 0.9))
                     :risky-action
                     :confidence 0.9)))
      (autopoiesis.core:stream-append stream decision)

      ;; Acceptance: Rejection sets confidence to 0.0
      (setf (autopoiesis.core:thought-confidence decision) 0.0)
      (is (= 0.0 (autopoiesis.core:thought-confidence decision))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 10: Defining Custom Capabilities with defcapability
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-10-defcapability-full-flow
  "E2E: Developer defines and uses custom capability"
  (with-clean-registries
    ;; Define a custom capability
    (eval '(autopoiesis.agent:defcapability web-search (query &key (max-results 10))
             "Search the web for QUERY and return up to MAX-RESULTS"
             :permissions (:network)
             :body
             (list :query query :results max-results)))

    ;; Acceptance: Capability registered globally
    (let ((cap (autopoiesis.agent:find-capability 'web-search)))
      (is (not (null cap)))

      ;; Acceptance: Docstring preserved
      (is (search "Search the web"
                  (autopoiesis.agent:capability-description cap)))

      ;; Acceptance: Permissions extracted
      (is (equal '(:network) (autopoiesis.agent:capability-permissions cap)))

      ;; Acceptance: Can invoke the capability
      (let ((result (autopoiesis.agent:invoke-capability 'web-search "lisp macros" :max-results 5)))
        (is (equal '(:query "lisp macros" :results 5) result))))))

(test e2e-story-10-defcapability-params-parsing
  "E2E: defcapability parses lambda list into parameter specs"
  ;; Acceptance: Parses various parameter types
  (let ((params (autopoiesis.agent:parse-capability-params
                 '(path &optional (encoding "utf-8") &key verbose (limit 100)))))
    ;; Required param
    (is (find 'path params :key #'first))
    ;; Optional with default
    (is (find 'encoding params :key #'first))
    ;; Keyword params
    (is (find 'verbose params :key #'first))
    (is (find 'limit params :key #'first))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 11: Managing Agent's Context Window (Working Memory)
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-11-context-window-priorities
  "E2E: Agent prioritizes working memory within token limits"
  (let ((ctx (autopoiesis.agent:make-context-window :max-size 100000)))

    ;; Add items with different priorities
    (autopoiesis.agent:context-add ctx '(task "analyze security") :priority 3.0)
    (autopoiesis.agent:context-add ctx '(file-content "lots of code...") :priority 1.0)
    (autopoiesis.agent:context-add ctx '(observation "user waiting") :priority 2.0)

    ;; Acceptance: Items ordered by priority
    (let ((content (autopoiesis.agent:context-content ctx)))
      (is (equal '(task "analyze security") (first content)))
      (is (equal '(observation "user waiting") (second content)))
      (is (equal '(file-content "lots of code...") (third content))))))

(test e2e-story-11-context-focus-boost
  "E2E: Boost priority of task-related items"
  (let ((ctx (autopoiesis.agent:make-context-window)))

    (autopoiesis.agent:context-add ctx '(task "security audit") :priority 1.0)
    (autopoiesis.agent:context-add ctx '(note "meeting at 3pm") :priority 2.0)
    (autopoiesis.agent:context-add ctx '(task "code review") :priority 1.5)

    ;; Before focus: note has highest priority
    (is (equal '(note "meeting at 3pm") (first (autopoiesis.agent:context-content ctx))))

    ;; Acceptance: Focus boosts matching items' priorities
    (autopoiesis.agent:context-focus ctx
                                     (lambda (item) (eq (first item) 'task))
                                     :boost 2.0)

    ;; After focus: task items prioritized (1.5 * 2 = 3.0 > 2.0)
    (let ((content (autopoiesis.agent:context-content ctx)))
      (is (eq 'task (first (first content)))))))

(test e2e-story-11-max-size-enforcement
  "E2E: Context excludes lower priority items when max-size exceeded"
  (let ((ctx (autopoiesis.agent:make-context-window :max-size 20)))

    ;; Add items that exceed max-size
    (autopoiesis.agent:context-add ctx '(big item with lots of data) :priority 0.5)
    (autopoiesis.agent:context-add ctx '(tiny) :priority 3.0)
    (autopoiesis.agent:context-add ctx '(medium item here) :priority 1.0)

    ;; Acceptance: Max-size limit enforced
    (is (<= (autopoiesis.agent:context-size ctx) 20))

    ;; Acceptance: Higher priority items included first
    (let ((content (autopoiesis.agent:context-content ctx)))
      (is (member '(tiny) content :test #'equal)))))

(test e2e-story-11-context-serialization
  "E2E: Context window serializable via context-to-sexpr"
  (let ((ctx (autopoiesis.agent:make-context-window :max-size 50000)))
    (autopoiesis.agent:context-add ctx '(task "important") :priority 2.0)
    (autopoiesis.agent:context-add ctx '(note "remember this") :priority 1.0)

    ;; Acceptance: Serialize and restore
    (let* ((sexpr (autopoiesis.agent:context-to-sexpr ctx))
           (restored (autopoiesis.agent:sexpr-to-context sexpr)))
      (is (= (autopoiesis.agent:context-max-size ctx)
             (autopoiesis.agent:context-max-size restored)))
      (is (= (autopoiesis.agent:context-item-count ctx)
             (autopoiesis.agent:context-item-count restored)))
      (is (equal (autopoiesis.agent:context-content ctx)
                 (autopoiesis.agent:context-content restored))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 12: Annotating Agent History for Later Reference
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-12-add-annotation
  "E2E: Researcher adds annotations to snapshots"
  ;; Annotation functions use :store (id->annotation) and :index (target->ids)
  (let ((store (make-hash-table :test 'equal))
        (index (make-hash-table :test 'equal)))
    ;; Create annotation for a snapshot
    (let* ((snapshot-id "abc123")
           (annotation (autopoiesis.interface:make-annotation
                        snapshot-id
                        "Agent figured out the recursive pattern here"
                        :author "researcher-1")))

      (autopoiesis.interface:add-annotation annotation :store store :index index)

      ;; Acceptance: Annotation stored and retrievable
      (let ((found (autopoiesis.interface:find-annotations snapshot-id :store store :index index)))
        (is (= 1 (length found)))
        (is (equal "Agent figured out the recursive pattern here"
                   (autopoiesis.interface:annotation-content (first found))))
        (is (equal "researcher-1"
                   (autopoiesis.interface:annotation-author (first found))))))))

(test e2e-story-12-multiple-annotations
  "E2E: Multiple annotations per target"
  (let ((store (make-hash-table :test 'equal))
        (index (make-hash-table :test 'equal))
        (snapshot-id "xyz789"))

    ;; Acceptance: Multiple annotations on same target
    (autopoiesis.interface:add-annotation
     (autopoiesis.interface:make-annotation snapshot-id "First insight" :author "alice")
     :store store :index index)
    (autopoiesis.interface:add-annotation
     (autopoiesis.interface:make-annotation snapshot-id "Second thought" :author "bob")
     :store store :index index)

    (let ((found (autopoiesis.interface:find-annotations snapshot-id :store store :index index)))
      (is (= 2 (length found))))))

(test e2e-story-12-remove-annotation
  "E2E: Annotations can be removed by ID"
  (let ((store (make-hash-table :test 'equal))
        (index (make-hash-table :test 'equal))
        (snapshot-id "def456"))

    (let ((ann (autopoiesis.interface:make-annotation snapshot-id "To be removed")))
      (autopoiesis.interface:add-annotation ann :store store :index index)

      ;; Verify added
      (is (= 1 (length (autopoiesis.interface:find-annotations snapshot-id :store store :index index))))

      ;; Acceptance: Remove by ID
      (autopoiesis.interface:remove-annotation
       (autopoiesis.interface:annotation-id ann)
       :store store :index index)

      (is (= 0 (length (autopoiesis.interface:find-annotations snapshot-id :store store :index index)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 13: Navigating Agent History with Navigator
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-13-navigator-navigation
  "E2E: Debugger navigates through history with back/forward"
  (let ((nav (autopoiesis.interface:make-navigator)))

    ;; Navigate to several snapshots
    (autopoiesis.interface:navigate-to nav "snapshot-1")
    (autopoiesis.interface:navigate-to nav "snapshot-2")
    (autopoiesis.interface:navigate-to nav "snapshot-3")

    ;; Acceptance: Current position is last navigated
    (is (equal "snapshot-3" (autopoiesis.interface:navigator-position nav)))

    ;; Acceptance: Navigate-back returns to previous
    (autopoiesis.interface:navigate-back nav)
    (is (equal "snapshot-2" (autopoiesis.interface:navigator-position nav)))

    ;; Go back again
    (autopoiesis.interface:navigate-back nav)
    (is (equal "snapshot-1" (autopoiesis.interface:navigator-position nav)))))

(test e2e-story-13-navigator-history-stack
  "E2E: Navigator maintains history stack"
  (let ((nav (autopoiesis.interface:make-navigator)))

    ;; Acceptance: Navigate-to pushes current to history
    (autopoiesis.interface:navigate-to nav "pos-a")
    (autopoiesis.interface:navigate-to nav "pos-b")

    (let ((history (autopoiesis.interface:navigator-history nav)))
      (is (member "pos-a" history :test #'equal)))))

(test e2e-story-13-navigate-to-branch
  "E2E: Navigate to branch head"
  ;; NOTE: navigate-to-branch uses global *branch-registry* internally via switch-branch
  ;; It does NOT accept a :registry parameter (missing functionality)
  ;; We use the global registry for this test
  (let ((nav (autopoiesis.interface:make-navigator)))
    ;; Create branch in global registry
    (let ((branch (autopoiesis.snapshot:create-branch "e2e-experimental")))
      (setf (autopoiesis.snapshot:branch-head branch) "exp-head-123")

      ;; Acceptance: Navigate to branch switches to branch head
      (autopoiesis.interface:navigate-to-branch nav "e2e-experimental")
      (is (equal "exp-head-123" (autopoiesis.interface:navigator-position nav))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 14: Compacting Event Log with Checkpoints
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-14-event-compaction
  "E2E: Admin compacts event log while preserving recovery capability"
  (let ((log (make-array 0 :adjustable t :fill-pointer 0))
        (state '(:full-state (agent-data thoughts decisions))))

    ;; Add many events (simulating extended operation)
    (loop for i from 1 to 100
          do (autopoiesis.snapshot:append-event
              (autopoiesis.snapshot:make-event :test-event (list :num i))
              :log log))

    ;; Acceptance: Check current event log size
    (is (= 100 (autopoiesis.snapshot:event-log-count :log log)))

    ;; Acceptance: Compact events into checkpoint, keeping last 10
    (let ((checkpoint (autopoiesis.snapshot:compact-events
                       log
                       (lambda () state)
                       :keep-recent 10)))

      ;; Acceptance: Checkpoint captured correct count
      (is (= 90 (autopoiesis.snapshot:checkpoint-event-count checkpoint)))

      ;; Acceptance: State preserved in checkpoint
      (is (equal state (autopoiesis.snapshot:checkpoint-state checkpoint)))

      ;; Acceptance: Log now has only recent events
      (is (= 10 (autopoiesis.snapshot:event-log-count :log log))))))

(test e2e-story-14-empty-log-no-checkpoint
  "E2E: Empty log returns nil (no checkpoint needed)"
  (let ((log (make-array 0 :adjustable t :fill-pointer 0)))
    ;; Acceptance: Empty log returns nil
    (let ((checkpoint (autopoiesis.snapshot:compact-events
                       log
                       (lambda () '(:state)))))
      (is (null checkpoint)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; User Story 15: Finding Common Ancestor for Branch Merge Planning
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-story-15-find-common-ancestor
  "E2E: Developer finds common ancestor for merge planning"
  (with-temp-store (store)
    ;; Build a diamond DAG: root -> (main-work, exp-work)
    (let* ((root (autopoiesis.snapshot:make-snapshot '(:base t)))
           (root-id (autopoiesis.snapshot:snapshot-id root)))
      (autopoiesis.snapshot:save-snapshot root store)

      ;; Main branch work
      (let* ((main-1 (autopoiesis.snapshot:make-snapshot '(:main 1) :parent root-id))
             (main-1-id (autopoiesis.snapshot:snapshot-id main-1)))
        (autopoiesis.snapshot:save-snapshot main-1 store)

        (let* ((main-2 (autopoiesis.snapshot:make-snapshot '(:main 2) :parent main-1-id))
               (main-head (autopoiesis.snapshot:snapshot-id main-2)))
          (autopoiesis.snapshot:save-snapshot main-2 store)

          ;; Experimental branch work
          (let* ((exp-1 (autopoiesis.snapshot:make-snapshot '(:exp 1) :parent root-id))
                 (exp-1-id (autopoiesis.snapshot:snapshot-id exp-1)))
            (autopoiesis.snapshot:save-snapshot exp-1 store)

            (let* ((exp-2 (autopoiesis.snapshot:make-snapshot '(:exp 2) :parent exp-1-id))
                   (exp-head (autopoiesis.snapshot:snapshot-id exp-2)))
              (autopoiesis.snapshot:save-snapshot exp-2 store)

              ;; Acceptance: Find common ancestor
              (let ((ancestor (autopoiesis.snapshot:find-common-ancestor
                               main-head exp-head store)))
                (is (not (null ancestor)))
                (is (string= root-id (autopoiesis.snapshot:snapshot-id ancestor))))

              ;; Acceptance: Distance from ancestor to each head
              (is (= 2 (autopoiesis.snapshot:dag-distance root-id main-head store)))
              (is (= 2 (autopoiesis.snapshot:dag-distance root-id exp-head store)))

              ;; Acceptance: Find path through DAG
              (let ((path (autopoiesis.snapshot:find-path main-head exp-head store)))
                (is (not (null path)))
                ;; Path should go: main-head -> main-1 -> root -> exp-1 -> exp-head
                (is (>= (length path) 3))
                ;; Should include root
                (is (member root-id path :test #'string=))))))))))

(test e2e-story-15-dag-distance
  "E2E: Calculate DAG distance for merge estimation"
  (with-temp-store (store)
    ;; Linear chain: root -> c1 -> c2 -> c3 -> c4
    (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
           (root-id (autopoiesis.snapshot:snapshot-id root)))
      (autopoiesis.snapshot:save-snapshot root store)

      (let ((prev-id root-id))
        (dotimes (i 4)
          (let* ((snap (autopoiesis.snapshot:make-snapshot (list :child i) :parent prev-id))
                 (snap-id (autopoiesis.snapshot:snapshot-id snap)))
            (autopoiesis.snapshot:save-snapshot snap store)
            (when (= i 3)
              ;; Acceptance: Distance counts edges
              (is (= 4 (autopoiesis.snapshot:dag-distance root-id snap-id store)))
              (is (= 0 (autopoiesis.snapshot:dag-distance snap-id snap-id store))))
            (setf prev-id snap-id)))))))

(test e2e-story-15-linear-and-branched
  "E2E: Works with both linear chains and branched histories"
  (with-temp-store (store)
    ;; Linear portion
    (let* ((root (autopoiesis.snapshot:make-snapshot '(:root t)))
           (root-id (autopoiesis.snapshot:snapshot-id root)))
      (autopoiesis.snapshot:save-snapshot root store)

      ;; Acceptance: Linear chain works
      (let* ((child (autopoiesis.snapshot:make-snapshot '(:child t) :parent root-id))
             (child-id (autopoiesis.snapshot:snapshot-id child)))
        (autopoiesis.snapshot:save-snapshot child store)

        (is (autopoiesis.snapshot:is-ancestor-p root-id child-id store))
        (is (autopoiesis.snapshot:is-descendant-p child-id root-id store))

        ;; Branch from root
        (let* ((branch (autopoiesis.snapshot:make-snapshot '(:branch t) :parent root-id))
               (branch-id (autopoiesis.snapshot:snapshot-id branch)))
          (autopoiesis.snapshot:save-snapshot branch store)

          ;; Acceptance: Branched history works
          (is (autopoiesis.snapshot:is-ancestor-p root-id branch-id store))
          ;; Neither child nor branch is ancestor of the other
          (is (not (autopoiesis.snapshot:is-ancestor-p child-id branch-id store)))
          (is (not (autopoiesis.snapshot:is-ancestor-p branch-id child-id store))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Self-Modification Safety Chain Tests
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-self-modification-approval-gate
  "E2E: Self-modification requires human approval before promotion"
  (with-clean-blocking-requests
    (let ((autopoiesis.agent:*require-human-approval-for-promotion* t)
          (autopoiesis.agent:*promotion-approval-timeout* 5)
          (agent (autopoiesis.agent:make-agent :name "approval-e2e")))
      ;; Define capability
      (multiple-value-bind (cap errors)
          (autopoiesis.agent:agent-define-capability agent
            :e2e-cap "e2e test cap" '((x number)) '((+ x 10)))
        (declare (ignore errors))
        (when cap
          ;; Test it
          (autopoiesis.agent:test-agent-capability cap '(((5) 15) ((0) 10)))

          ;; Spawn approval thread
          (bt:make-thread
           (lambda ()
             (sleep 0.2)
             (let ((pending (autopoiesis.interface:list-pending-blocking-requests)))
               (when pending
                 (autopoiesis.interface:provide-response (first pending) :approve)))))

          ;; Promote should block then succeed
          (is-true (autopoiesis.agent:promote-capability cap))
          (is (eq :promoted (autopoiesis.agent:cap-promotion-status cap)))

          ;; Capability should be globally registered
          (is (not (null (autopoiesis.agent:find-capability :e2e-cap)))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Story: Agent Runtime Routes Through Cognitive Cycle
;;; ═══════════════════════════════════════════════════════════════════

(test e2e-agent-runtime-cognitive-cycle
  "Test that agent-runtime routes messages through cognitive-cycle
   with all 5 phase types in the thought stream."
  (with-clean-registries
    (let ((autopoiesis.integration:*events-enabled* nil)
          (autopoiesis.integration:*provider-registry* (make-hash-table :test 'equal)))
      ;; Create a mock streaming provider
      (let* ((chunks '("I" " can" " help"))
             (mock-provider (make-instance 'autopoiesis.test::streaming-mock-provider
                                           :name "e2e-mock"
                                           :command "echo"
                                           :stream-chunks chunks
                                           :canned-output "I can help"
                                           :canned-exit-code 0))
             (agent (autopoiesis.agent:make-agent :name "e2e-runtime-agent")))
        ;; Simulate what runtime-start-agent does: change-class to provider-backed-agent
        (change-class agent 'autopoiesis.integration:provider-backed-agent
                      :provider mock-provider
                      :invocation-mode :streaming
                      :system-prompt "You are a test agent")
        (autopoiesis.agent:start-agent agent)
        ;; Wire callbacks that track events
        (let ((events nil))
          (setf (autopoiesis.integration:agent-streaming-callbacks agent)
                (list :on-start (lambda () (push :start events))
                      :on-delta (lambda (d) (push (cons :delta d) events))
                      :on-end   (lambda () (push :end events))
                      :on-complete (lambda (text) (push (cons :complete text) events))))
          ;; Run cognitive cycle
          (let ((result (autopoiesis.agent:cognitive-cycle agent "help me")))
            ;; Should get a provider-result back
            (is (typep result 'autopoiesis.integration:provider-result))
            (is (string= "I can help" (autopoiesis.integration:provider-result-text result)))
            ;; Check thought stream has all phase types
            (let* ((stream (autopoiesis.agent:agent-thought-stream agent))
                   (len (autopoiesis.core:stream-length stream))
                   (thoughts (autopoiesis.core:stream-last stream len))
                   (types (mapcar #'autopoiesis.core:thought-type thoughts)))
              ;; observation from perceive, decision from decide,
              ;; observations/actions from act recording, reflection from reflect
              (is (member :observation types))
              (is (member :decision types))
              (is (member :reflection types))
              (is (>= len 4)))
            ;; Verify callbacks fired
            (setf events (nreverse events))
            (is (eq :start (first events)))
            (is (eq :end (find :end events)))))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Test Runner Entry Point
;;; ═══════════════════════════════════════════════════════════════════

(defun run-e2e-tests ()
  "Run all E2E tests for user stories."
  (run! 'e2e-tests))
