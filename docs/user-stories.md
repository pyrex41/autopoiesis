# Autopoiesis User Stories

**Version:** 0.1.0
**Last Updated:** 2026-02-02

This document describes 15 practical user stories showing how humans will interact with Autopoiesis agents in real-world scenarios.

---

## Overview

Autopoiesis enables humans to collaborate with AI agents through:
- **CLI sessions** for real-time interaction
- **Blocking input** for agent-initiated queries
- **Time-travel** through snapshot history
- **Branching** to explore alternatives
- **Tool integration** with Claude API

---

## User Stories

### 1. Starting an Interactive Session with an Agent

**As a** developer
**I want to** start an interactive CLI session with an agent
**So that** I can observe and control the agent's behavior in real-time

**Flow:**
```lisp
;; Create an agent with specific capabilities
(defvar *my-agent*
  (autopoiesis.agent:make-agent
    :name "code-reviewer"
    :capabilities '(read-file analyze-code suggest-fix)))

;; Start interactive CLI session
(autopoiesis.interface:cli-interact *my-agent*)
```

**Human sees:**
```
========================================================================
  AUTOPOIESIS CLI - Agent: code-reviewer (a3f28c91)
  Status: INITIALIZED | Session: 7bc4d2e8
========================================================================

Commands:
  help, h, ?     - Show this help
  status, s      - Show agent status
  start          - Start the agent
  stop           - Stop the agent
  ...

>
```

**Acceptance Criteria:**
- [ ] Session displays agent name and truncated IDs
- [ ] Session shows agent state (initialized/running/paused/stopped)
- [ ] Help command lists all available commands
- [ ] Session persists command history

---

### 2. Injecting Context into a Running Agent

**As a** developer
**I want to** inject an observation into the agent's thought stream
**So that** I can provide information the agent needs without restarting

**Flow:**
```
> start
Agent started.

> inject Review the authentication module for SQL injection vulnerabilities

Injected observation: Review the authentication module for SQL injection vulnerabilities

> thoughts
All Thoughts (1):
  [b7c9a312] :observation: (:human-input "Review the authentication...")
```

**Acceptance Criteria:**
- [ ] Inject command creates observation thought with `:source :human-cli`
- [ ] Thought appears in agent's stream immediately
- [ ] Agent can access injected content in next cognitive cycle

---

### 3. Agent Requests Human Approval Before Dangerous Action

**As an** agent
**I want to** pause and request human approval before executing a destructive operation
**So that** humans maintain control over irreversible actions

**Agent code:**
```lisp
(defun agent-delete-files (files)
  ;; Request human approval before deletion
  (multiple-value-bind (response status)
      (autopoiesis.interface:blocking-human-input
        (format nil "About to delete ~d files. Proceed?" (length files))
        :options '("yes" "no" "show-list")
        :timeout 300)  ; 5 minute timeout
    (case status
      (:responded
        (when (string-equal response "yes")
          (delete-files files)))
      (:timeout
        (log "Timed out waiting for approval, aborting"))
      (:cancelled
        (log "User cancelled the operation")))))
```

**Human sees in CLI:**
```
[AWAITING INPUT] About to delete 15 files. Proceed?
  Options: yes, no, show-list
  Request ID: 8a2b3c4d

> pending
Pending Requests:
  [8a2b3c4d] About to delete 15 files. Proceed?
    Options: yes, no, show-list

> respond 8a2b show-list
Response provided to request 8a2b3c4d
```

**Acceptance Criteria:**
- [ ] Agent blocks until human responds or timeout
- [ ] Human can see pending requests with `pending` command
- [ ] Human can respond by ID prefix match
- [ ] Timeout returns default value with `:timeout` status
- [ ] Thread-safe implementation with condition variables

---

### 4. Stepping Through Agent Cognition One Cycle at a Time

**As a** developer debugging agent behavior
**I want to** execute one cognitive cycle at a time
**So that** I can observe how the agent processes each step

**Flow:**
```
> start
Agent started.

> pause
Agent paused.

> step
Executed one cognitive cycle.

> status
--- Agent State ---
Capabilities: read-file, analyze-code, suggest-fix

--- Recent Thoughts (3 total) ---
  [:observation] (:human-input "Review auth module...")
  [:reasoning ] (analyzing "Checking for SQL injection patterns...")
  [:decision  ] (next-action :read-file "auth/login.py")

> step
Executed one cognitive cycle.

> status
--- Recent Thoughts (4 total) ---
  ...
  [:action    ] (:invoke read-file "auth/login.py" :success t)
```

**Acceptance Criteria:**
- [ ] Pause suspends automatic cognitive loop
- [ ] Step executes exactly one perceive-reason-decide-act-reflect cycle
- [ ] Status shows recent thoughts after each step
- [ ] Agent state transitions correctly through lifecycle

---

### 5. Traveling Back in Time to a Previous State

**As a** developer
**I want to** check out a previous snapshot
**So that** I can inspect what the agent was thinking at that moment

**Flow:**
```lisp
;; List available snapshots
(autopoiesis.snapshot:list-snapshots :root-only t)
;; => ("a1b2c3..." "d4e5f6...")

;; Find snapshots near a timestamp
(autopoiesis.snapshot:find-snapshot-by-timestamp
  (- (get-universal-time) 3600)  ; 1 hour ago
  :direction :nearest)
;; => #<SNAPSHOT abc123>

;; Check out that snapshot
(autopoiesis.snapshot:checkout-snapshot "abc123")
;; => (:agent-state ...)

;; Now *current-snapshot* is set to that point in history
```

**Acceptance Criteria:**
- [ ] Snapshots persist to disk as `.sexpr` files
- [ ] Snapshots can be found by timestamp with :before/:after/:nearest
- [ ] Checkout sets `*current-snapshot*` and returns agent state
- [ ] Parent-child relationships form navigable DAG

---

### 6. Forking to Explore Alternative Approaches

**As a** researcher
**I want to** fork from the current state and explore a different approach
**So that** I can compare outcomes without losing my original work

**Flow:**
```lisp
;; Create a branch from current position
(autopoiesis.snapshot:create-branch "experimental"
  :from-snapshot (autopoiesis.snapshot:snapshot-id
                   autopoiesis.snapshot:*current-snapshot*))

;; Switch to the new branch
(autopoiesis.snapshot:switch-branch "experimental")

;; Agent continues on this branch...
;; Any new snapshots are children of the fork point

;; Later, switch back to main
(autopoiesis.snapshot:switch-branch "main")

;; Compare the two approaches
(autopoiesis.snapshot:snapshot-diff
  (autopoiesis.snapshot:branch-head (autopoiesis.snapshot:current-branch))
  experimental-final-snapshot)
```

**Acceptance Criteria:**
- [ ] Branches created with name and optional starting snapshot
- [ ] Switching branches updates `*current-branch*`
- [ ] New snapshots are added to current branch's head
- [ ] Diff shows edit operations between any two snapshots

---

### 7. Agent Spawns Specialized Child Agent

**As a** coordinator agent
**I want to** spawn a specialized child agent for a subtask
**So that** complex work can be parallelized with clear lineage

**Agent code:**
```lisp
;; From within an agent (with *current-agent* bound)
(autopoiesis.agent:with-current-agent (*coordinator*)
  ;; Spawn a child for code analysis
  (let ((analyzer (autopoiesis.agent:capability-spawn
                    "security-analyzer"
                    :capabilities '(code-read pattern-match))))

    ;; Send work to the child
    (autopoiesis.agent:capability-communicate
      analyzer
      '(:task :analyze-file "auth/login.py" :focus :sql-injection))

    ;; Later, check for results
    (let ((messages (autopoiesis.agent:capability-receive :clear t)))
      (dolist (msg messages)
        (process-result (autopoiesis.agent:message-content msg))))))
```

**Acceptance Criteria:**
- [ ] Child agent inherits parent's capabilities by default
- [ ] Parent-child relationship tracked in agent registry
- [ ] Message passing via `capability-communicate` and `capability-receive`
- [ ] Messages queued in per-agent mailbox until read

---

### 8. Integrating Agent with Claude API

**As a** developer
**I want to** connect my agent to Claude for LLM-powered reasoning
**So that** the agent can use natural language understanding

**Flow:**
```lisp
;; Create a Claude session for the agent
(let ((session (autopoiesis.integration:create-session-for-agent *my-agent*)))

  ;; Add user input to conversation
  (autopoiesis.integration:session-add-message session "user"
    "Analyze this code for security issues: ...")

  ;; Get completion from Claude (tools auto-included from capabilities)
  (let* ((client (autopoiesis.integration:make-claude-client))
         (response (autopoiesis.integration:claude-complete
                     client
                     (autopoiesis.integration:session-messages session)
                     :system (autopoiesis.integration:session-system-prompt session)
                     :tools (autopoiesis.integration:session-tools session))))

    ;; If Claude wants to use tools, execute them
    (when (autopoiesis.integration:response-tool-calls response)
      (let ((results-msg (autopoiesis.integration:handle-tool-use-response
                           response
                           (agent-capabilities *my-agent*))))
        ;; Add results to session for continuation
        (autopoiesis.integration:session-add-tool-results session results-msg)))))
```

**Acceptance Criteria:**
- [ ] Session auto-generates system prompt from agent context
- [ ] Agent capabilities auto-convert to Claude tool format
- [ ] Tool names convert between kebab-case and snake_case
- [ ] Tool call results format correctly for continuation

---

### 9. Human Overrides Agent Decision

**As a** supervisor
**I want to** override an agent's decision before it acts
**So that** I can correct mistakes before they have impact

**Flow:**
```
> status
--- Recent Thoughts (5 total) ---
  ...
  [:decision  ] (:decided :delete-all-logs :from (:archive-logs :delete-all-logs))

> inject Override: Do NOT delete logs. Archive them to S3 instead.

> status
--- Recent Thoughts (6 total) ---
  ...
  [:decision  ] (:decided :delete-all-logs :from ...)
  [:observation] (:human-override :new-state "Do NOT delete logs...")
```

**Or programmatically:**
```lisp
(autopoiesis.interface:human-reject
  last-decision
  :reason "Logs required for compliance audit")

(autopoiesis.interface:human-override
  *my-agent*
  '(:redirect :action :archive-to-s3 :target "logs/*"))
```

**Acceptance Criteria:**
- [ ] `human-reject` sets decision confidence to 0.0
- [ ] `human-override` creates observation with `:source :human-override`
- [ ] Override thought appears in agent's stream
- [ ] Agent processes override in next cognitive cycle

---

### 10. Defining Custom Capabilities with defcapability

**As a** developer
**I want to** define new capabilities that agents can use
**So that** I can extend agent functionality without modifying core code

**Flow:**
```lisp
(autopoiesis.agent:defcapability web-search (query &key (max-results 10))
  "Search the web for QUERY and return up to MAX-RESULTS"
  :permissions (:network)
  :body
  (let ((results (external-search-api query :limit max-results)))
    (mapcar #'extract-snippet results)))

;; Capability is now registered globally
(autopoiesis.agent:find-capability 'web-search)
;; => #<CAPABILITY web-search>

;; Agent can use it
(autopoiesis.agent:invoke-capability 'web-search "lisp macros" :max-results 5)
```

**Acceptance Criteria:**
- [ ] `defcapability` registers capability in global registry
- [ ] Supports docstring, `:permissions`, and `:body` marker
- [ ] Parses lambda list into parameter specifications
- [ ] Capability converts to Claude tool format correctly

---

### 11. Managing Agent's Context Window (Working Memory)

**As an** agent
**I want to** prioritize what stays in my working memory
**So that** I can focus on relevant information within token limits

**Agent code:**
```lisp
;; Create context window with 100k token limit
(let ((ctx (autopoiesis.agent:make-context-window :max-size 100000)))

  ;; Add items with different priorities
  (autopoiesis.agent:context-add ctx '(task "analyze security") :priority 3.0)
  (autopoiesis.agent:context-add ctx '(file-content "1000 lines...") :priority 1.0)
  (autopoiesis.agent:context-add ctx '(observation "user is waiting") :priority 2.0)

  ;; Boost priority of task-related items
  (autopoiesis.agent:context-focus ctx
    (lambda (item) (eq (first item) 'task))
    :boost 2.0)

  ;; Get current content (highest priority items that fit)
  (autopoiesis.agent:context-content ctx)
  ;; => ((task "analyze security") (observation "user is waiting"))

  ;; Lower priority items excluded if they exceed max-size
  (autopoiesis.agent:context-size ctx)
  ;; => 87432
  )
```

**Acceptance Criteria:**
- [ ] Items ordered by priority in context content
- [ ] Max-size limit enforced (lower priority items excluded)
- [ ] `context-focus` multiplies matching items' priorities
- [ ] `context-defocus` divides matching items' priorities
- [ ] Context serializable via `context-to-sexpr`

---

### 12. Annotating Agent History for Later Reference

**As a** researcher
**I want to** add annotations to specific snapshots or thoughts
**So that** I can document insights for future analysis

**Flow:**
```lisp
;; Find an interesting snapshot
(let ((snap (autopoiesis.snapshot:find-snapshot-by-timestamp
              interesting-timestamp :direction :nearest)))

  ;; Add annotation
  (autopoiesis.interface:add-annotation
    (autopoiesis.interface:make-annotation
      (autopoiesis.snapshot:snapshot-id snap)
      "This is where the agent figured out the recursive pattern"
      :author "researcher-1"))

  ;; Later, find all annotations on this snapshot
  (autopoiesis.interface:find-annotations
    (autopoiesis.snapshot:snapshot-id snap))
  ;; => (#<ANNOTATION ...>)
  )
```

**Acceptance Criteria:**
- [ ] Annotations stored by ID and indexed by target
- [ ] Multiple annotations can exist per target
- [ ] Annotations preserve author and timestamp
- [ ] Annotations can be removed by ID

---

### 13. Navigating Agent History with Navigator

**As a** debugger
**I want to** navigate through agent history with back/forward
**So that** I can explore the sequence of agent decisions

**Flow:**
```lisp
;; Get session navigator
(let ((nav (autopoiesis.interface:session-navigator *current-session*)))

  ;; Jump to a specific snapshot
  (autopoiesis.interface:navigate-to nav "snapshot-abc123")

  ;; History is now: (previous-position)
  ;; Position is now: "snapshot-abc123"

  ;; Go back to previous
  (autopoiesis.interface:navigate-back nav)
  ;; Now back at original position

  ;; Jump to branch head
  (autopoiesis.interface:navigate-to-branch nav "experimental")
  ;; Now at head of experimental branch
  )
```

**Or via CLI:**
```
> back
Navigated back.
```

**Acceptance Criteria:**
- [ ] Navigator maintains position and history stack
- [ ] `navigate-to` pushes current position to history
- [ ] `navigate-back` pops from history
- [ ] `navigate-to-branch` switches branch and goes to head

---

### 14. Compacting Event Log with Checkpoints

**As a** system administrator
**I want to** compact the event log periodically
**So that** storage doesn't grow unbounded while maintaining recovery capability

**Flow:**
```lisp
;; Check current event log size
(autopoiesis.snapshot:event-log-count)
;; => 15000

;; Compact events into a checkpoint, keeping last 1000
(let ((checkpoint (autopoiesis.snapshot:compact-events
                    autopoiesis.snapshot:*event-log*
                    (lambda () (get-current-agent-state))
                    :keep-recent 1000)))

  ;; Checkpoint captured 14000 events
  (autopoiesis.snapshot:checkpoint-event-count checkpoint)
  ;; => 14000

  ;; State at compaction time preserved
  (autopoiesis.snapshot:checkpoint-state checkpoint)
  ;; => (:full-agent-state ...)

  ;; Log now has only recent events
  (autopoiesis.snapshot:event-log-count)
  ;; => 1000
  )
```

**Acceptance Criteria:**
- [ ] Checkpoint captures current state from callback
- [ ] Event count recorded in checkpoint
- [ ] Recent events preserved if `:keep-recent` specified
- [ ] Empty log returns nil (no checkpoint needed)

---

### 15. Finding Common Ancestor for Branch Merge Planning

**As a** developer planning to merge branches
**I want to** find the common ancestor of two branch heads
**So that** I can understand what changed in each branch

**Flow:**
```lisp
;; Get the two branch heads
(let* ((main-head (autopoiesis.snapshot:branch-head
                    (gethash "main" autopoiesis.snapshot:*branch-registry*)))
       (exp-head (autopoiesis.snapshot:branch-head
                   (gethash "experimental" autopoiesis.snapshot:*branch-registry*)))

       ;; Find where they diverged
       (ancestor (autopoiesis.snapshot:find-common-ancestor
                   main-head exp-head *snapshot-store*)))

  ;; See what changed in each branch
  (autopoiesis.snapshot:dag-distance
    (autopoiesis.snapshot:snapshot-id ancestor) main-head *snapshot-store*)
  ;; => 5 (5 commits on main since divergence)

  (autopoiesis.snapshot:dag-distance
    (autopoiesis.snapshot:snapshot-id ancestor) exp-head *snapshot-store*)
  ;; => 8 (8 commits on experimental since divergence)

  ;; Get the path through the DAG
  (autopoiesis.snapshot:find-path main-head exp-head *snapshot-store*)
  ;; => ("main-head" ... "ancestor" ... "exp-head")
  )
```

**Acceptance Criteria:**
- [ ] `find-common-ancestor` returns snapshot where branches diverged
- [ ] `dag-distance` counts edges (commits) between snapshots
- [ ] `find-path` returns sequence of snapshot IDs through DAG
- [ ] Works with linear chains and branched histories

---

## Implementation Status

| Story | Core | Agent | Snapshot | Interface | Integration |
|-------|------|-------|----------|-----------|-------------|
| 1. CLI Session | - | ✓ | - | ✓ | - |
| 2. Inject Context | - | ✓ | - | ✓ | - |
| 3. Blocking Approval | - | - | - | ✓ | - |
| 4. Step Debugging | - | ✓ | - | ✓ | - |
| 5. Time Travel | - | - | ✓ | - | - |
| 6. Branching | - | - | ✓ | - | - |
| 7. Spawn Child | - | ✓ | - | - | - |
| 8. Claude Integration | - | ✓ | - | - | ✓ |
| 9. Human Override | - | - | - | ✓ | - |
| 10. defcapability | - | ✓ | - | - | - |
| 11. Context Window | - | ✓ | - | - | - |
| 12. Annotations | - | - | - | ✓ | - |
| 13. Navigator | - | - | ✓ | ✓ | - |
| 14. Event Compaction | - | - | ✓ | - | - |
| 15. DAG Traversal | - | - | ✓ | - | - |

**Legend:**
- ✓ = Implemented
- ~ = Partially implemented
- ✗ = Not implemented
- `-` = Not applicable to this layer

---

## Testing Approach

For each user story:

1. **Unit Tests**: Test individual functions in isolation
2. **Integration Tests**: Test cross-layer interactions
3. **E2E Tests**: Run complete user story flows (`test/e2e-tests.lisp`)
4. **Manual Testing**: CLI interaction walkthrough

Test files are organized by layer in `/test/`:
- `core-tests.lisp` - Core layer unit tests
- `agent-tests.lisp` - Agent layer unit tests
- `snapshot-tests.lisp` - Snapshot layer unit tests
- `interface-tests.lisp` - Interface layer unit tests
- `integration-tests.lisp` - Integration layer unit tests
- `e2e-tests.lisp` - **End-to-end tests for all 15 user stories**

### Running E2E Tests

```lisp
;; Run all tests including E2E
(autopoiesis.test:run-all-tests)

;; Run only E2E user story tests
(autopoiesis.test:run-e2e-tests)

;; Or use the shorthand
(autopoiesis.test:test-e2e)
```

### E2E Test Coverage

Each user story has one or more E2E tests:

| Story | Test Name | Description |
|-------|-----------|-------------|
| 1 | `e2e-story-1-start-interactive-session` | Session creation and agent state observation |
| 1 | `e2e-story-1-session-lifecycle` | Full session lifecycle from create to end |
| 2 | `e2e-story-2-inject-observation` | Injecting context into thought stream |
| 2 | `e2e-story-2-multiple-injections` | Multiple injections maintain order |
| 3 | `e2e-story-3-blocking-approval-flow` | Blocking request and human response |
| 3 | `e2e-story-3-timeout-returns-default` | Timeout returns default value |
| 3 | `e2e-story-3-threaded-approval` | Thread-safe blocking response |
| 3 | `e2e-story-3-cancel-request` | Request cancellation |
| 4 | `e2e-story-4-step-through-cognition` | Step debugging cognitive cycles |
| 4 | `e2e-story-4-state-transitions` | Agent state transitions |
| 5 | `e2e-story-5-time-travel-checkout` | Checkout previous snapshot |
| 5 | `e2e-story-5-list-snapshots` | List snapshots with filtering |
| 6 | `e2e-story-6-create-branch-from-snapshot` | Fork from snapshot |
| 6 | `e2e-story-6-switch-branches` | Branch switching |
| 7 | `e2e-story-7-spawn-child-agent` | Parent spawns child agent |
| 7 | `e2e-story-7-message-passing` | Inter-agent messaging |
| 8 | `e2e-story-8-claude-session-creation` | Claude session for agent |
| 8 | `e2e-story-8-capability-to-tool-conversion` | Capability to Claude tool |
| 8 | `e2e-story-8-tool-name-conversion` | Name format conversion |
| 9 | `e2e-story-9-inject-override` | Override via injection |
| 9 | `e2e-story-9-decision-rejection` | Decision rejection |
| 10 | `e2e-story-10-defcapability-full-flow` | Define and use capability |
| 10 | `e2e-story-10-defcapability-params-parsing` | Parameter parsing |
| 11 | `e2e-story-11-context-window-priorities` | Priority ordering |
| 11 | `e2e-story-11-context-focus-boost` | Focus boost |
| 11 | `e2e-story-11-max-size-enforcement` | Max size limit |
| 11 | `e2e-story-11-context-serialization` | Context serialization |
| 12 | `e2e-story-12-add-annotation` | Add annotation |
| 12 | `e2e-story-12-multiple-annotations` | Multiple annotations |
| 12 | `e2e-story-12-remove-annotation` | Remove annotation |
| 13 | `e2e-story-13-navigator-navigation` | Back/forward navigation |
| 13 | `e2e-story-13-navigator-history-stack` | History stack |
| 13 | `e2e-story-13-navigate-to-branch` | Navigate to branch |
| 14 | `e2e-story-14-event-compaction` | Event compaction |
| 14 | `e2e-story-14-empty-log-no-checkpoint` | Empty log handling |
| 15 | `e2e-story-15-find-common-ancestor` | Find common ancestor |
| 15 | `e2e-story-15-dag-distance` | DAG distance calculation |
| 15 | `e2e-story-15-linear-and-branched` | Linear and branched histories |

---

## Future Stories (Not Yet Implemented)

- **3D Holodeck Visualization**: Explore agent state in immersive 3D
- **Multi-Agent Collaboration**: Multiple agents with shared context
- **MCP Server Integration**: Connect to external capabilities
- **Self-Modification**: Agents rewriting their own behavior
- **Distributed Agents**: Agents running across multiple machines
