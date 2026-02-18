# Phase 4: Rich CL-LFE Bridge Implementation Plan

> **Complete & Superseded**: Implemented at commit 783cd02. The bridge will be removed when LFE is deleted in Phase 5 of the substrate-first plan at `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md`.

## Overview

Expand the CL-LFE bridge protocol so LFE can fully orchestrate CL agents: trigger agentic loops, navigate snapshots, query capabilities, stream thoughts in real-time, and route human-in-the-loop requests. This connects the CL cognitive runtime (Phases 1-3) to BEAM supervision so the full system works end-to-end.

## Current State Analysis

### CL Side (`scripts/agent-worker.lisp`)

The CL worker handles **5 message types** over a stdin/stdout S-expression protocol:

| Message | Handler | Response |
|---------|---------|----------|
| `:init` | `handle-init` (line 67) | `(:ok :type :initialized ...)` |
| `:cognitive-cycle` | `handle-cognitive-cycle` (line 90) | `(:ok :type :cycle-complete ...)` |
| `:snapshot` | `handle-snapshot` (line 106) | `(:ok :type :snapshot-complete ...)` |
| `:inject-observation` | `handle-inject-observation` (line 60) | `(:ok :type :observation-injected)` |
| `:shutdown` | `handle-shutdown` (line 115) | `(:ok :type :shutdown)` then exit |

The heartbeat thread (`start-heartbeat-thread`, line 135) is **defined but never called**.

### LFE Side (`agent-worker.lfe`)

The LFE agent-worker is a gen_server that:
- Opens an SBCL port with line-based S-expression protocol
- Sends messages via `port-send/2` (line 172) using `lfe_io:print1`
- Receives responses via `port-receive/2` (line 177) with configurable timeouts
- Parses responses into tagged tuples: `#(ok ...)`, `#(error ...)`, `#(heartbeat ...)`, `#(blocking-request ...)`
- Has a TODO at `handle-unsolicited-message` (line 217) for routing `:blocking-request`

### Conductor (`conductor.lfe`)

The conductor dispatches work via:
- `execute-action` (line 184): Checks `requires-llm` and `action-type`
- CL agents: spawns via `agent-sup:spawn-agent/1` (line 321)
- Claude agents: spawns via `claude-sup:spawn-claude-agent/1` (line 350)
- Only handles `action-type: claude` — no `agentic` type yet
- Receives results via `handle_cast(#(task-result, Result), State)` (line 100)

### What Exists But Isn't Bridged

| CL Capability | Module | Key Functions |
|---------------|--------|---------------|
| Agentic loop | `claude-bridge.lisp:174` | `agentic-loop`, `agentic-complete` |
| Self-extension | `builtin-tools.lisp:272-376` | `define-capability-tool`, `test-capability-tool`, `promote-capability-tool` |
| Capability listing | `builtin-tools.lisp:382` | `list-capabilities-tool` |
| Thought queries | `thought-stream.lisp:47-68` | `stream-last`, `stream-by-type`, `stream-since` |
| Snapshot branches | `branch.lisp:39-57` | `create-branch`, `switch-branch`, `list-branches` |
| Snapshot diffing | `diff-engine.lisp:11` | `snapshot-diff` |
| Learning | `learning.lisp:398-462` | `extract-patterns`, `list-heuristics` |
| Agent serialization | `agentic-agent.lisp:213` | `agentic-agent-to-sexpr` |
| Provider switching | `provider-inference.lisp` | `make-inference-provider` |

## Desired End State

After Phase 4:

1. **LFE can trigger agentic loops** via `:agentic-prompt` — CL runs the full multi-turn tool loop and streams thoughts back to LFE as they happen
2. **LFE can inspect agent state** — query thought stream, list capabilities, check snapshot history
3. **LFE can navigate snapshots** — checkout, diff, branch, list branches through the bridge
4. **Human-in-the-loop works** — CL `:blocking-request` messages are routed through LFE to an external handler
5. **Conductor has `agentic` dispatch** — schedules and manages agentic tasks alongside existing `cl` and `claude` types
6. **Heartbeat is active** — CL worker sends periodic heartbeats, LFE monitors liveness
7. **All 75 LFE tests still pass**, plus new tests for the expanded protocol

### Verification

```bash
# CL tests (existing + new bridge protocol tests)
./scripts/test.sh

# LFE tests
cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests,claude-worker-tests
```

## What We're NOT Doing

- **Streaming from Claude API** (SSE parsing) — separate concern, not blocking
- **Branch merging** — `merge-branches` is a placeholder, leave it
- **Learning system activation** — the 1,032-line system exists but needs real data; Phase 5 territory
- **CLI entry point** (`bin/jarvis`) — Phase 5
- **Agent spawning from CL** (meta-agent orchestration) — Phase 5
- **Fixing CL worker ASDF loading** — already works (the script has Quicklisp setup at lines 1-21)
- **Provider switching at runtime** — the infrastructure exists from Phase 3, but exposing it over the bridge is Phase 5 scope

## Implementation Approach

**Hybrid strategy**: High-level `:agentic-prompt` for the main workflow (CL owns the loop, streams thoughts back), plus targeted query messages for inspection. LFE doesn't micromanage individual agentic turns — that's CL's job. But LFE can inspect snapshots, list capabilities, and query thoughts for orchestration decisions.

All new messages follow the existing pattern:
- LFE sends S-expression command via port
- CL dispatches in `handle-command`, calls handler
- Handler sends `(:ok ...)` or `(:error ...)` response
- For streaming (agentic loop), CL sends multiple `(:thought ...)` messages before the final `(:ok ...)`

---

## Phase 4.1: Activate Heartbeat Thread

### Overview
Start the heartbeat thread during `:init` so LFE can monitor CL worker liveness. Wire the LFE side to track heartbeats and detect stale workers.

### Changes Required

#### 1. CL Worker: Start heartbeat on init
**File**: `scripts/agent-worker.lisp`

In `handle-init`, after setting `*agent*` and `*start-time*` (line 82), call `(start-heartbeat-thread)`.

```lisp
;; After line 82: (setf *start-time* (get-universal-time))
(start-heartbeat-thread)
```

#### 2. LFE Worker: Track heartbeat timestamps
**File**: `lfe/apps/autopoiesis/src/agent-worker.lfe`

Add `last-heartbeat` key to state map (initialized to current time in `init`). In `handle-unsolicited-message` for `:heartbeat` (line 214-216), update the timestamp.

Add `get-status/1` to include `last-heartbeat` and a `healthy` flag (true if heartbeat within last 30s).

#### 3. LFE Worker: Heartbeat timeout detection
**File**: `lfe/apps/autopoiesis/src/agent-worker.lfe`

Add a periodic `check-heartbeat` timer (every 30s via `erlang:send_after`). If no heartbeat received in 30s after init is complete, log a warning. If no heartbeat in 60s, consider the worker stale and stop with `{heartbeat_timeout}`.

### Success Criteria

#### Automated Verification:
- [ ] CL tests pass: `./scripts/test.sh`
- [ ] LFE tests pass: `cd lfe && rebar3 eunit --module=agent-worker-tests`
- [ ] New test: heartbeat appears in `get-status` response

#### Manual Verification:
- [ ] Start full app, spawn agent, verify heartbeat messages appear in logs

---

## Phase 4.2: Expand CL Bridge Protocol

### Overview
Add 8 new message handlers to the CL worker for agentic prompts, thought queries, capability listing, and snapshot operations.

### Changes Required

#### 1. New message: `:agentic-prompt`
**File**: `scripts/agent-worker.lisp`

```lisp
(defun handle-agentic-prompt (msg)
  "Run an agentic loop with streaming thoughts.
   Message: (:agentic-prompt :prompt \"...\" :capabilities (:tool1 :tool2) :max-turns 25)
   Streams: (:thought :type <type> :content <content> :turn <n>)
   Final:   (:ok :type :agentic-complete :result <text> :turns <n> :snapshot-id <id>)"
  (let* ((prompt (getf (cdr msg) :prompt))
         (cap-names (getf (cdr msg) :capabilities))
         (max-turns (or (getf (cdr msg) :max-turns) 25))
         (capabilities (resolve-capabilities cap-names))
         (messages (list (list (cons "role" "user") (cons "content" prompt))))
         (turn-count 0))
    (handler-case
        (let ((on-thought (lambda (type data)
                            (send-response `(:thought :type ,type
                                                      :content ,(princ-to-string data)
                                                      :turn ,turn-count)))))
          (multiple-value-bind (response all-messages turns)
              (agentic-loop (agent-client *agent*) messages capabilities
                            :system (agent-system-prompt *agent*)
                            :max-turns max-turns
                            :on-thought on-thought)
            ;; Update agent conversation history
            (setf (agent-conversation-history *agent*) all-messages)
            ;; Auto-snapshot after agentic loop
            (let* ((snapshot (make-snapshot (agent-to-sexpr *agent*)))
                   (saved (save-snapshot snapshot)))
              (send-response `(:ok :type :agentic-complete
                                   :result ,(response-text response)
                                   :turns ,turns
                                   :snapshot-id ,(snapshot-id snapshot))))))
      (error (e)
        (send-response `(:error :type :agentic-failed
                                :message ,(format nil "~A" e)))))))
```

Helper to resolve capability names to instances:

```lisp
(defun resolve-capabilities (names)
  "Resolve capability name keywords to capability instances."
  (if names
      (loop for name in names
            for cap = (find-capability name)
            when cap collect cap
            else do (warn "Capability not found: ~A" name))
      ;; Default: all registered capabilities
      (list-capabilities)))
```

#### 2. New message: `:query-thoughts`
**File**: `scripts/agent-worker.lisp`

```lisp
(defun handle-query-thoughts (msg)
  "Query the agent's thought stream.
   Message: (:query-thoughts :last-n 10 :type :decision)
   Response: (:ok :type :thoughts :count <n> :thoughts (<thought-sexpr> ...))"
  (let* ((last-n (or (getf (cdr msg) :last-n) 10))
         (type-filter (getf (cdr msg) :type))
         (stream (agent-thought-stream *agent*))
         (thoughts (if type-filter
                       (stream-by-type stream type-filter)
                       (stream-last stream last-n))))
    (send-response `(:ok :type :thoughts
                         :count ,(length thoughts)
                         :thoughts ,(mapcar #'thought-to-sexpr thoughts)))))
```

#### 3. New message: `:list-capabilities`
**File**: `scripts/agent-worker.lisp`

```lisp
(defun handle-list-capabilities (msg)
  "List available capabilities.
   Message: (:list-capabilities :filter \"search\")
   Response: (:ok :type :capabilities :count <n> :capabilities (...))"
  (let* ((filter (getf (cdr msg) :filter))
         (all-caps (list-capabilities))
         (filtered (if filter
                       (remove-if-not
                        (lambda (cap)
                          (search filter (string (capability-name cap))
                                  :test #'char-equal))
                        all-caps)
                       all-caps)))
    (send-response
     `(:ok :type :capabilities
           :count ,(length filtered)
           :capabilities ,(mapcar (lambda (cap)
                                    (list :name (capability-name cap)
                                          :description (capability-description cap)))
                                  filtered)))))
```

#### 4. New message: `:checkout`
**File**: `scripts/agent-worker.lisp`

```lisp
(defun handle-checkout (msg)
  "Restore agent state from a snapshot.
   Message: (:checkout :snapshot-id \"abc123\")
   Response: (:ok :type :checked-out :snapshot-id <id>)"
  (let* ((snapshot-id (getf (cdr msg) :snapshot-id))
         (snapshot (load-snapshot snapshot-id)))
    (if snapshot
        (let ((restored (sexpr-to-agent (snapshot-agent-state snapshot))))
          (setf *agent* restored)
          (start-agent *agent*)
          (send-response `(:ok :type :checked-out :snapshot-id ,snapshot-id)))
        (send-response `(:error :type :snapshot-not-found
                                :snapshot-id ,snapshot-id)))))
```

#### 5. New message: `:diff`
**File**: `scripts/agent-worker.lisp`

```lisp
(defun handle-diff (msg)
  "Diff two snapshots.
   Message: (:diff :from \"id1\" :to \"id2\")
   Response: (:ok :type :diff :edits (...))"
  (let* ((from-id (getf (cdr msg) :from))
         (to-id (getf (cdr msg) :to))
         (from-snap (load-snapshot from-id))
         (to-snap (load-snapshot to-id)))
    (if (and from-snap to-snap)
        (let ((edits (snapshot-diff from-snap to-snap)))
          (send-response `(:ok :type :diff
                               :from ,from-id :to ,to-id
                               :edit-count ,(length edits)
                               :edits ,(mapcar #'sexpr-edit-to-sexpr edits))))
        (send-response `(:error :type :snapshot-not-found
                                :message "One or both snapshots not found")))))
```

#### 6. New message: `:create-branch`
**File**: `scripts/agent-worker.lisp`

```lisp
(defun handle-create-branch (msg)
  "Create a snapshot branch.
   Message: (:create-branch :name \"experiment\" :from \"snapshot-id\")
   Response: (:ok :type :branch-created :name <name>)"
  (let* ((name (getf (cdr msg) :name))
         (from (getf (cdr msg) :from)))
    (create-branch name :from-snapshot from)
    (send-response `(:ok :type :branch-created :name ,name :from ,from))))
```

#### 7. New message: `:list-branches`
**File**: `scripts/agent-worker.lisp`

```lisp
(defun handle-list-branches (msg)
  "List all branches.
   Message: (:list-branches)
   Response: (:ok :type :branches :branches ((:name ... :head ...) ...))"
  (declare (ignore msg))
  (let ((branches (list-branches)))
    (send-response
     `(:ok :type :branches
           :count ,(length branches)
           :branches ,(mapcar (lambda (b)
                                (list :name (branch-name b)
                                      :head (branch-head b)))
                              branches)))))
```

#### 8. New message: `:switch-branch`
**File**: `scripts/agent-worker.lisp`

```lisp
(defun handle-switch-branch (msg)
  "Switch to a branch and checkout its head.
   Message: (:switch-branch :name \"experiment\")
   Response: (:ok :type :branch-switched :name <name> :head <snapshot-id>)"
  (let* ((name (getf (cdr msg) :name))
         (branch (switch-branch name)))
    (when (branch-head branch)
      (let ((snapshot (load-snapshot (branch-head branch))))
        (when snapshot
          (setf *agent* (sexpr-to-agent (snapshot-agent-state snapshot)))
          (start-agent *agent*))))
    (send-response `(:ok :type :branch-switched
                         :name ,name
                         :head ,(branch-head branch)))))
```

#### 9. Update `handle-command` dispatch
**File**: `scripts/agent-worker.lisp`

Add new cases to the `case` form in `handle-command` (line 144):

```lisp
(:agentic-prompt (handle-agentic-prompt command))
(:query-thoughts (handle-query-thoughts command))
(:list-capabilities (handle-list-capabilities command))
(:checkout (handle-checkout command))
(:diff (handle-diff command))
(:create-branch (handle-create-branch command))
(:list-branches (handle-list-branches command))
(:switch-branch (handle-switch-branch command))
```

### Success Criteria

#### Automated Verification:
- [ ] CL tests pass: `./scripts/test.sh`
- [ ] New CL unit tests for each handler using mock agent state

#### Manual Verification:
- [ ] Can send `:agentic-prompt` via port and receive streaming thoughts followed by completion

---

## Phase 4.3: Expand LFE Bridge Client

### Overview
Add LFE-side client functions in `agent-worker.lfe` for all new CL message types, with appropriate timeouts and response parsing.

### Changes Required

#### 1. Agentic prompt with streaming
**File**: `lfe/apps/autopoiesis/src/agent-worker.lfe`

New public API function and gen_server call:

```lfe
;; Client API
(defun agentic-prompt (pid prompt)
  "Run agentic loop on agent, returns result after streaming."
  (gen_server:call pid `#(agentic-prompt ,prompt) 600000))  ; 10 min timeout

(defun agentic-prompt (pid prompt opts)
  "Run agentic loop with options map (capabilities, max-turns)."
  (gen_server:call pid `#(agentic-prompt ,prompt ,opts) 600000))
```

New `handle_call` clause that sends the message, then collects streaming `:thought` messages until the final `:ok` response:

```lfe
(defun handle_call
  ;; Agentic prompt with streaming thought collection
  ((`#(agentic-prompt ,prompt) ,from ,state)
   (handle-agentic-call prompt #M() from state))
  ((`#(agentic-prompt ,prompt ,opts) ,from ,state)
   (handle-agentic-call prompt opts from state)))

(defun handle-agentic-call (prompt opts from state)
  "Send agentic-prompt and collect streaming thoughts."
  (let* ((caps (maps:get 'capabilities opts '()))
         (max-turns (maps:get 'max-turns opts 25))
         (msg `(:agentic-prompt :prompt ,prompt
                                :capabilities ,caps
                                :max-turns ,max-turns)))
    (port-send (maps:get 'port state) msg)
    ;; Collect streaming thoughts with 300s total timeout
    (let ((result (collect-agentic-response
                   (maps:get 'port state) 300000 '())))
      (gen_server:reply from result)
      `#(noreply ,state))))
```

Helper that loops reading port lines, accumulating `:thought` messages until `:ok` or `:error`:

```lfe
(defun collect-agentic-response (port timeout thoughts)
  "Collect streaming thoughts until final response."
  (case (port-receive port timeout)
    (`#(ok (:thought . ,rest))
     ;; Accumulate thought, continue collecting
     (collect-agentic-response port timeout (cons rest thoughts)))
    (`#(ok (:ok . ,rest))
     ;; Final response
     `#(ok #M(result ,rest thoughts ,(lists:reverse thoughts))))
    (`#(ok (:error . ,rest))
     `#(error ,rest))
    (`timeout
     `#(error #(timeout ,(length thoughts) thoughts-collected)))
    (other
     ;; Unexpected message, continue
     (collect-agentic-response port timeout thoughts))))
```

#### 2. Query functions (synchronous)
**File**: `lfe/apps/autopoiesis/src/agent-worker.lfe`

```lfe
;; Client API
(defun query-thoughts (pid last-n)
  "Query agent's recent thoughts."
  (gen_server:call pid `#(query-thoughts ,last-n) 5000))

(defun list-capabilities (pid)
  "List agent's available capabilities."
  (gen_server:call pid #(list-capabilities) 5000))

(defun checkout-snapshot (pid snapshot-id)
  "Restore agent to a snapshot."
  (gen_server:call pid `#(checkout ,snapshot-id) 10000))

(defun diff-snapshots (pid from-id to-id)
  "Diff two snapshots."
  (gen_server:call pid `#(diff ,from-id ,to-id) 10000))

(defun create-branch (pid name)
  "Create a snapshot branch."
  (gen_server:call pid `#(create-branch ,name) 5000))

(defun create-branch (pid name from-snapshot)
  "Create a branch from a specific snapshot."
  (gen_server:call pid `#(create-branch ,name ,from-snapshot) 5000))

(defun list-branches (pid)
  "List all snapshot branches."
  (gen_server:call pid #(list-branches) 5000))

(defun switch-branch (pid name)
  "Switch to a branch."
  (gen_server:call pid `#(switch-branch ,name) 10000))
```

New `handle_call` clauses for each:

```lfe
;; Query thoughts
((`#(query-thoughts ,n) ,_from ,state)
 (port-send (maps:get 'port state) `(:query-thoughts :last-n ,n))
 (let ((response (port-receive (maps:get 'port state) 5000)))
   `#(reply ,response ,state)))

;; List capabilities
((#(list-capabilities) ,_from ,state)
 (port-send (maps:get 'port state) '(:list-capabilities))
 (let ((response (port-receive (maps:get 'port state) 5000)))
   `#(reply ,response ,state)))

;; Checkout snapshot
((`#(checkout ,id) ,_from ,state)
 (port-send (maps:get 'port state) `(:checkout :snapshot-id ,id))
 (let ((response (port-receive (maps:get 'port state) 10000)))
   `#(reply ,response ,state)))

;; Diff snapshots
((`#(diff ,from ,to) ,_from ,state)
 (port-send (maps:get 'port state) `(:diff :from ,from :to ,to))
 (let ((response (port-receive (maps:get 'port state) 10000)))
   `#(reply ,response ,state)))

;; Create branch
((`#(create-branch ,name) ,_from ,state)
 (port-send (maps:get 'port state) `(:create-branch :name ,name))
 (let ((response (port-receive (maps:get 'port state) 5000)))
   `#(reply ,response ,state)))
((`#(create-branch ,name ,from) ,_from ,state)
 (port-send (maps:get 'port state) `(:create-branch :name ,name :from ,from))
 (let ((response (port-receive (maps:get 'port state) 5000)))
   `#(reply ,response ,state)))

;; List branches
((#(list-branches) ,_from ,state)
 (port-send (maps:get 'port state) '(:list-branches))
 (let ((response (port-receive (maps:get 'port state) 5000)))
   `#(reply ,response ,state)))

;; Switch branch
((`#(switch-branch ,name) ,_from ,state)
 (port-send (maps:get 'port state) `(:switch-branch :name ,name))
 (let ((response (port-receive (maps:get 'port state) 10000)))
   `#(reply ,response ,state)))
```

### Success Criteria

#### Automated Verification:
- [ ] LFE tests pass: `cd lfe && rebar3 eunit --module=agent-worker-tests`
- [ ] New tests for each client function's message formatting
- [ ] New tests for `collect-agentic-response` with mock port data

#### Manual Verification:
- [ ] Full round-trip: LFE sends `:agentic-prompt`, CL streams thoughts, LFE collects result

---

## Phase 4.4: Conductor Agentic Dispatch

### Overview
Add `agentic` action type to the conductor so it can schedule and manage agentic tasks (CL agents running multi-turn API loops).

### Changes Required

#### 1. New action type in conductor
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`

In `execute-action` (line 184), add `agentic` case alongside `claude`:

```lfe
;; In execute-action, after the claude branch (line 190):
(('agentic (dispatch-agentic-agent action state))
```

New dispatch function:

```lfe
(defun dispatch-agentic-agent (action state)
  "Spawn a CL agent and run an agentic prompt on it."
  (let* ((agent-id (list_to_atom
                    (++ "agentic-" (integer_to_list (erlang:unique_integer '(positive))))))
         (prompt (maps:get 'prompt action ""))
         (capabilities (maps:get 'capabilities action '()))
         (max-turns (maps:get 'max-turns action 25))
         (config `#M(agent-id ,agent-id
                     name ,(maps:get 'name action "agentic-worker")
                     capabilities ,capabilities)))
    ;; Spawn asynchronously to avoid blocking tick loop
    (spawn
     (lambda ()
       (case (agent-sup:spawn-agent config)
         (`#(ok ,pid)
          (logger:info "Agentic agent ~p spawned as ~p" (list agent-id pid))
          ;; Run the agentic prompt
          (case (agent-worker:agentic-prompt pid prompt
                  `#M(capabilities ,capabilities max-turns ,max-turns))
            (`#(ok ,result)
             (gen_server:cast 'conductor
               `#(task-result #M(task-id ,agent-id
                                 status complete
                                 result ,result))))
            (`#(error ,reason)
             (gen_server:cast 'conductor
               `#(task-result #M(task-id ,agent-id
                                 status failed
                                 error ,reason))))))
         (`#(error ,reason)
          (logger:warning "Failed to spawn agentic agent ~p: ~p"
                          (list agent-id reason))
          (gen_server:cast 'conductor
            `#(task-result #M(task-id ,agent-id
                              status failed
                              error ,reason)))))))))
```

#### 2. Rate limiting for agentic tasks
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`

Extend the existing `is-duplicate-task/2` (line 429) to also check agent workers, or add a separate rate limiter for agentic tasks. The simplest approach: check `agent-sup:list-agents/0` for active agents with matching task type.

#### 3. Agentic action in infra-watcher scheduling
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`

Add an option in `schedule-infra-watcher` (line 377) to use `action-type: agentic` instead of `claude` when a CL agentic agent is preferred. This can be controlled by a config flag. For now, keep the default as `claude` but document how to switch.

### Success Criteria

#### Automated Verification:
- [ ] LFE tests pass: `cd lfe && rebar3 eunit --module=conductor-tests`
- [ ] New test: schedule agentic action, verify dispatch function called
- [ ] New test: agentic task-result handled by conductor

#### Manual Verification:
- [ ] Full flow: schedule agentic action via conductor → CL agent spawns → agentic loop runs → result reported

---

## Phase 4.5: Human-in-the-Loop Routing

### Overview
Wire the `:blocking-request` unsolicited message from CL through LFE to an external handler (initially just logging + conductor notification).

### Changes Required

#### 1. Route blocking requests in agent-worker
**File**: `lfe/apps/autopoiesis/src/agent-worker.lfe`

Replace the TODO at `handle-unsolicited-message` (line 217-221):

```lfe
;; Replace the blocking-request handler:
((`(:blocking-request . ,details) ,state)
 (let* ((agent-id (maps:get 'agent-id state))
        (request-type (proplists:get_value ':type details))
        (prompt (proplists:get_value ':prompt details))
        (request-id (proplists:get_value ':id details)))
   (logger:notice "Blocking request from agent ~p: type=~p prompt=~p"
                  (list agent-id request-type prompt))
   ;; Notify conductor of the blocking request
   (gen_server:cast 'conductor
     `#(blocking-request #M(agent-id ,agent-id
                            request-id ,request-id
                            request-type ,request-type
                            prompt ,prompt
                            worker-pid ,(self))))
   state))
```

#### 2. Handle blocking requests in conductor
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`

New `handle_cast` clause:

```lfe
(defun handle_cast
  ;; ... existing clauses ...
  ((`#(blocking-request ,request) ,state)
   (logger:notice "Agent blocking request: ~p" (list request))
   ;; Store in pending-requests for external handler
   (let ((pending (maps:get 'pending-requests state '())))
     `#(noreply ,(maps:put 'pending-requests
                           (cons request pending)
                           state))))
  ;; Resolution from external handler
  ((`#(resolve-request ,request-id ,response) ,state)
   (let ((pending (maps:get 'pending-requests state '())))
     ;; Find the request and send response to worker
     (case (lists:keyfind request-id 'request-id pending)
       ('false
        (logger:warning "No pending request ~p" (list request-id)))
       (request
        (let ((worker-pid (maps:get 'worker-pid request)))
          ;; Send response back to CL via agent-worker
          (gen_server:cast worker-pid `#(resolve-blocking ,request-id ,response)))))
     `#(noreply ,(maps:put 'pending-requests
                           (lists:keydelete request-id 'request-id pending)
                           state)))))
```

#### 3. Agent worker receives resolution
**File**: `lfe/apps/autopoiesis/src/agent-worker.lfe`

New `handle_cast` clause:

```lfe
(defun handle_cast
  ((`#(resolve-blocking ,request-id ,response) ,state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:blocking-response :id ,request-id :response ,response)))
   `#(noreply ,state)))
```

#### 4. CL worker receives blocking response
**File**: `scripts/agent-worker.lisp`

The CL side needs to handle `:blocking-response` as an unsolicited message during agentic loop execution. This requires the agentic loop's `on-thought` callback or a separate mechanism. For now, add it as a recognized command:

```lisp
(:blocking-response (handle-blocking-response command))
```

```lisp
(defun handle-blocking-response (msg)
  "Receive response to a blocking request.
   Message: (:blocking-response :id <id> :response <response>)
   Sets a condition variable that the blocking request is waiting on."
  (let ((id (getf (cdr msg) :id))
        (response (getf (cdr msg) :response)))
    ;; Store in a global pending-responses table
    ;; The blocking request handler checks this
    (setf (gethash id *pending-responses*) response)))
```

Note: Full blocking request integration with `autopoiesis.interface:request-input` requires threading coordination. For Phase 4, we route the message and store the response. Full integration with the human interface layer's blocking protocol is Phase 5.

### Success Criteria

#### Automated Verification:
- [ ] LFE tests pass: `cd lfe && rebar3 eunit --module=agent-worker-tests,conductor-tests`
- [ ] New test: blocking-request unsolicited message parsed and forwarded
- [ ] New test: conductor stores and resolves pending requests

#### Manual Verification:
- [ ] CL agent sends blocking-request → appears in conductor pending-requests

---

## Phase 4.6: Tests

### Overview
Comprehensive tests for the expanded protocol on both sides.

### Changes Required

#### 1. CL bridge protocol tests
**File**: `test/bridge-protocol-tests.lisp` (new)

Test each new handler with a mock agent:

```lisp
;; Test handle-agentic-prompt with mock complete function
;; Test handle-query-thoughts with pre-populated thought stream
;; Test handle-list-capabilities with registered capabilities
;; Test handle-checkout with saved snapshot
;; Test handle-diff with two snapshots
;; Test handle-create-branch, handle-list-branches, handle-switch-branch
;; Test handle-command dispatch for all new message types
;; Test error cases: unknown snapshot, missing capabilities, etc.
```

~15 new test cases, ~40 checks.

#### 2. LFE agent-worker protocol tests
**File**: `lfe/apps/autopoiesis/test/agent-worker-tests.lfe`

Add tests for new client message formatting:

```lfe
;; Test agentic-prompt message format
;; Test query-thoughts message format
;; Test list-capabilities message format
;; Test checkout-snapshot message format
;; Test diff-snapshots message format
;; Test create-branch message format
;; Test list-branches message format
;; Test switch-branch message format
;; Test collect-agentic-response with mock streaming data
;; Test heartbeat tracking in state
;; Test blocking-request forwarding
```

~12 new test cases.

#### 3. LFE conductor tests
**File**: `lfe/apps/autopoiesis/test/conductor-tests.lfe`

```lfe
;; Test agentic action dispatch (classify event with action-type agentic)
;; Test blocking-request storage in conductor state
;; Test resolve-request removes from pending
```

~5 new test cases.

### Success Criteria

#### Automated Verification:
- [ ] All CL tests pass: `./scripts/test.sh` — 2,400+ existing checks + ~40 new
- [ ] All LFE tests pass: 75 existing + ~17 new = ~92 tests, 0 failures
- [ ] No regressions in any existing test suite

---

## Testing Strategy

### Unit Tests (CL)
- Mock `*claude-complete-function*` to avoid real API calls
- Pre-populate agent state for thought/snapshot queries
- Verify S-expression response format for each handler
- Test error paths (missing snapshots, unknown capabilities)

### Unit Tests (LFE)
- Test message formatting (what gets sent to port)
- Test response parsing (what comes back from port)
- Test `collect-agentic-response` state machine with synthetic port data
- Test heartbeat tracking with timer mocks

### Integration Tests
- Full round-trip requires running SBCL with `:autopoiesis` loaded
- Mark these as slow/optional (similar to existing `slow-path` tests)
- Test: spawn agent → agentic-prompt → collect result → verify snapshot created

### Manual Testing Steps
1. Start full LFE app: `cd lfe && rebar3 shell`
2. Spawn agent: `(agent-sup:spawn-agent #M(agent-id test-1 name "test"))`
3. Verify heartbeats: check logs for `:heartbeat` messages
4. Query thoughts: `(agent-worker:query-thoughts Pid 5)`
5. List capabilities: `(agent-worker:list-capabilities Pid)`
6. Schedule agentic action via conductor

## File Summary

| File | Change Type | Estimated Lines |
|------|-------------|----------------|
| `scripts/agent-worker.lisp` | Modified | +200 (8 handlers + heartbeat activation) |
| `lfe/apps/autopoiesis/src/agent-worker.lfe` | Modified | +150 (client API + handle_call + heartbeat + streaming) |
| `lfe/apps/autopoiesis/src/conductor.lfe` | Modified | +60 (agentic dispatch + blocking-request handling) |
| `test/bridge-protocol-tests.lisp` | New | ~120 (CL bridge tests) |
| `lfe/apps/autopoiesis/test/agent-worker-tests.lfe` | Modified | +80 (new protocol tests) |
| `lfe/apps/autopoiesis/test/conductor-tests.lfe` | Modified | +30 (agentic dispatch tests) |
| **Total** | | **~640 lines** |

## References

- Jarvis implementation plan: `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md`
- Next steps roadmap: `thoughts/shared/research/2026-02-06-next-steps-roadmap.md`
- Super Agent implementation record: `thoughts/shared/plans/2026-02-06-super-agent-implementation-record.md`
- CL bridge: `scripts/agent-worker.lisp`
- LFE bridge: `lfe/apps/autopoiesis/src/agent-worker.lfe`
- Conductor: `lfe/apps/autopoiesis/src/conductor.lfe`
- Agentic loop: `src/integration/claude-bridge.lisp:174`
- Agentic agent: `src/integration/agentic-agent.lisp`
