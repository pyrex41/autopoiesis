# Super Agent Implementation Plan

## Overview

Build a long-running infrastructure monitoring agent ("Super Agent") that combines the LFE/BEAM conductor as a Ralph loop orchestrator with Claude Code agent teams for investigation/reasoning and Cortex MCP tools for infrastructure perception. The system runs indefinitely via OTP supervision, with back pressure from health checks and tests, and gets smarter over time via the CL self-extension compiler.

## Current State Analysis

### What Works
- **LFE Orchestration** (`lfe/apps/autopoiesis/src/`): 9 modules, ~730 LOC, 59/59 tests passing. Conductor with 100ms tick loop, gb_trees timer heap, event queue, async agent spawning, HTTP endpoints on :4007
- **CL Cognitive Engine** (`src/`): 2,400+ assertions, agent CLOS class with full serialization (`agent-to-sexpr`/`sexpr-to-agent`), snapshot DAG with content-addressable storage, extension compiler with sandbox validation, MCP client, 14 built-in tools, event bus, security layer
- **Cortex** (separate system): MCP tools available (`cortex_query`, `cortex_schema`, `cortex_entity_detail`, `cortex_start_ecs_adapter`, `cortex_start_kubernetes_adapter`, `cortex_start_git_adapter`), LMDB-based event store, adapters for ECS/K8s/Git

### What's Broken
- **CL Worker Loading**: `scripts/agent-worker.lisp:4` calls `(asdf:load-system :autopoiesis)` without Quicklisp or ASDF registry setup. SBCL crashes immediately.

### What's Missing
- **Claude Worker**: No gen_server to manage Claude Code CLI subprocesses
- **Work Directory**: No file structure for task I/O between conductor and Claude
- **Result Processing**: Conductor can dispatch work but can't process results from Claude
- **Project Config**: No way to define agent profiles, triggers, capabilities declaratively
- **Cortex Bridge**: No connection between conductor events and Cortex perception

### Key Discoveries
- Claude Agent SDK exists: `@anthropic-ai/claude-agent-sdk` (TS) and `claude-agent-sdk` (Python) — `src/integration/mcp-client.lisp:196-285`
- Claude CLI supports `--output-format stream-json` for streaming JSON lines — perfect for Erlang port communication
- Claude CLI supports `--mcp-config ./mcp.json` to pass MCP server configs
- Claude CLI supports `--dangerously-skip-permissions` for unattended execution
- Erlang ports with `{line, N}`, `binary`, `exit_status` are production-proven for long-running processes
- The existing `agent-worker.lfe` is a solid template — same gen_server pattern, different subprocess and protocol

## Desired End State

A running system where:

1. The LFE conductor schedules a periodic infra-watcher timer (e.g., every 5 minutes)
2. When the timer fires, conductor spawns a `claude-worker` via `agent-sup`
3. The worker invokes `claude -p` with a structured prompt and Cortex MCP config
4. Claude queries Cortex for recent infrastructure events via MCP tools
5. Claude writes a structured report (JSON) to stdout
6. The worker parses the report, stores it, and reports back to conductor
7. If anomalies are found, conductor can escalate (log, webhook, blocking request)
8. The whole thing runs forever, surviving crashes via OTP supervision
9. Results accumulate as git commits and/or snapshot DAG entries

### Verification

- `cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests,claude-worker-tests` — all pass
- `cd lfe && rebar3 lfe repl` → `(application:ensure_all_started 'autopoiesis)` → system starts with Claude worker support
- `curl http://localhost:4007/health` → 200 with status including claude worker info
- `conductor:schedule` an infra-watcher timer → Claude invokes, queries Cortex, produces report
- Kill the claude subprocess → supervisor restarts worker → loop continues

## What We're NOT Doing

- **Not replacing the CL worker** — it stays as-is, to be fixed separately. Claude worker is additive.
- **Not building a full agent teams framework** — we're using Claude CLI in single-agent mode first. Teams come later.
- **Not building a web UI** — terminal/REPL interaction only
- **Not implementing the self-extension loop** — that's Phase C, after the basic loop works
- **Not building project config loading** — hardcoded agent profile for now
- **Not using the Claude Agent SDK** — would require Node.js/Python runtime. We use the CLI directly via Erlang port, keeping the stack LFE-only.

## Implementation Approach

Port-based architecture, same pattern as `agent-worker.lfe` but adapted for Claude CLI:

```
conductor → agent-sup:spawn-agent → claude-worker:start_link
                                          ↓
                                    open_port("claude -p ...")
                                          ↓
                                    stream-json lines over stdout
                                          ↓
                                    parse JSON, extract result
                                          ↓
                                    report to conductor via cast
```

Key design decisions:
1. **Port-based, not file-based** — Claude CLI's `--output-format stream-json` gives us streaming JSON lines over stdout, which maps perfectly to Erlang's `{line, N}` port option. No filesystem polling needed.
2. **One-shot, not long-lived** — Each Claude invocation is a single prompt that runs to completion. The conductor schedules new invocations periodically. This matches the Ralph loop pattern: stateless iterations, progress in results not context.
3. **JSON protocol** — Claude outputs JSON, not S-expressions. We parse with `jsx` (already a dependency).
4. **Configurable timeout** — Claude invocations can take 30 seconds to several minutes. Default 5 minutes, configurable per task.

---

## Phase 1: Fix CL Worker Loading

### Overview
Unblock the existing CL cognitive engine by fixing `scripts/agent-worker.lisp` to properly load Quicklisp and register the ASDF source.

### Changes Required

#### 1. Fix agent-worker.lisp startup
**File**: `scripts/agent-worker.lisp`
**Changes**: Add Quicklisp loading and ASDF registry setup before `(asdf:load-system :autopoiesis)`

```lisp
#!/usr/bin/env sbcl --script

(require :asdf)

;; Load Quicklisp for dependency resolution
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp"
                                        (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

;; Add project root to ASDF search path
;; Script is at <project>/scripts/agent-worker.lisp
;; Project root is one level up
(let ((project-root (make-pathname
                      :directory (butlast
                                  (pathname-directory
                                    (or *load-truename*
                                        *default-pathname-defaults*))))))
  (push project-root asdf:*central-registry*))

(asdf:load-system :autopoiesis)
```

#### 2. Verify port protocol round-trip
No code changes — manual verification via REPL.

### Success Criteria

#### Automated Verification:
- [ ] `sbcl --script scripts/agent-worker.lisp` starts without errors (within 10s)
- [ ] Existing CL tests still pass: `./scripts/test.sh`
- [ ] LFE tests still pass: `cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests`

#### Manual Verification:
- [ ] In LFE REPL: spawn an agent worker, send `:init`, receive `:ok` response
- [ ] Send `:cognitive-cycle`, receive `:ok` with cycle result
- [ ] Send `:snapshot`, verify snapshot file created
- [ ] Kill SBCL process, verify supervisor detects death

**Implementation Note**: After completing this phase and all automated verification passes, pause here for confirmation before proceeding.

---

## Phase 2: Claude Worker Gen_Server

### Overview
Create `claude-worker.lfe` — a gen_server that manages a Claude Code CLI subprocess via Erlang port, using streaming JSON output for communication.

### Changes Required

#### 1. Claude Worker Module
**File**: `lfe/apps/autopoiesis/src/claude-worker.lfe`
**Changes**: New file, ~200 LOC

The module mirrors `agent-worker.lfe` structure but adapted for Claude CLI:

```lfe
(defmodule claude-worker
  (behaviour gen_server)
  (export
    ;; gen_server callbacks
    (start_link 1) (init 1)
    (handle_call 3) (handle_cast 2) (handle_info 2)
    (terminate 2) (code_change 3)
    ;; Client API
    (get-status 1)
    ;; Internal — exported for testing
    (build-claude-command 1) (parse-result 1)))
```

**State map:**
```lfe
#M(port <port>                    ; Erlang port to claude process
   task-id <string>               ; Unique task identifier
   config <map>                   ; Task configuration
   started <integer>              ; System time when started
   output-buffer <list>           ; Accumulated JSON messages
   status <atom>                  ; running | complete | failed
   caller <from>                  ; gen_server:call From for async reply
   timeout <integer>)             ; Max runtime in ms (default 300000)
```

**Key functions:**

`build-claude-command/1`:
```lfe
(defun build-claude-command (config)
  "Build claude CLI command for non-interactive execution."
  (let* ((claude-path (maps:get 'claude-path config
                        (application:get_env 'autopoiesis 'claude_path "claude")))
         (prompt (maps:get 'prompt config ""))
         (mcp-config (maps:get 'mcp-config config 'undefined))
         (allowed-tools (maps:get 'allowed-tools config ""))
         (max-turns (maps:get 'max-turns config 50))
         (args (list "-p" prompt
                     "--output-format" "stream-json"
                     "--max-turns" (integer_to_list max-turns)
                     "--dangerously-skip-permissions")))
    ;; Add MCP config if specified
    (let ((args2 (case mcp-config
                   ('undefined args)
                   (path (++ args (list "--mcp-config" path))))))
      ;; Add allowed tools if specified
      (let ((args3 (case allowed-tools
                     ("" args2)
                     (tools (++ args2 (list "--allowedTools" tools))))))
        `#(,claude-path ,args3)))))
```

`init/1`:
```lfe
(defun init
  (((list task-config))
   (let* ((task-id (maps:get 'task-id task-config
                     (make-task-id)))
          (`#(,cmd ,args) (build-claude-command task-config))
          (timeout (maps:get 'timeout task-config 300000))
          (port (erlang:open_port
                  `#(spawn_executable ,cmd)
                  `(#(args ,args)
                    #(line 65536)
                    binary
                    exit_status
                    use_stdio
                    stderr_to_stdout))))
     ;; Set a timer for max runtime
     (let ((timer-ref (erlang:send_after timeout (self) 'timeout)))
       `#(ok #M(port ,port
                task-id ,task-id
                config ,task-config
                started ,(erlang:system_time 'second)
                output-buffer ()
                status running
                timer-ref ,timer-ref
                timeout ,timeout))))))
```

`handle_info/2` for port data:
```lfe
(defun handle_info
  ;; Streaming JSON line from Claude
  ((`#(,_port #(data #(eol ,line))) state)
   (when (=:= (maps:get 'status state) 'running))
   (let ((parsed (parse-json-line line)))
     (case parsed
       ;; Accumulate assistant messages
       (`#(ok ,msg)
        `#(noreply ,(maps:update 'output-buffer
                      (++ (maps:get 'output-buffer state) (list msg))
                      state)))
       ;; Parse error — log and continue
       (`#(error ,_reason)
        `#(noreply ,state)))))

  ;; Claude process exited successfully
  ((`#(,_port #(exit_status 0)) state)
   (let ((result (extract-final-result (maps:get 'output-buffer state))))
     ;; Report result to conductor
     (report-result (maps:get 'task-id state) result)
     `#(stop normal ,(maps:update 'status 'complete state))))

  ;; Claude process exited with error
  ((`#(,_port #(exit_status ,code)) state)
   (logger:warning "Claude worker ~s exited with code ~p"
                   (list (maps:get 'task-id state) code))
   (report-error (maps:get 'task-id state) code
                 (maps:get 'output-buffer state))
   `#(stop #(claude-exit ,code) ,(maps:update 'status 'failed state)))

  ;; Timeout — kill the claude process
  (('timeout state)
   (logger:warning "Claude worker ~s timed out after ~p ms"
                   (list (maps:get 'task-id state)
                         (maps:get 'timeout state)))
   (catch (erlang:port_close (maps:get 'port state)))
   (report-error (maps:get 'task-id state) 'timeout '())
   `#(stop timeout ,(maps:update 'status 'failed state)))

  ((_msg state)
   `#(noreply ,state)))
```

`parse-json-line/1`:
```lfe
(defun parse-json-line (binary)
  "Parse a JSON line from Claude's stream-json output."
  (try
    (let ((json (jsx:decode binary '(return_maps))))
      `#(ok ,json))
    (catch
      (`#(,_type ,reason ,_stack)
       `#(error ,reason)))))
```

`extract-final-result/1`:
```lfe
(defun extract-final-result (messages)
  "Extract the final assistant result from accumulated messages.
   Claude stream-json includes message objects with type and content."
  (let ((assistant-msgs
          (lists:filter
            (lambda (msg)
              (=:= (maps:get <<"type">> msg <<"">>) <<"result">>))
            messages)))
    (case assistant-msgs
      ('() #M(type error message "No result message found"))
      (_ (lists:last assistant-msgs)))))
```

`report-result/2` and `report-error/3`:
```lfe
(defun report-result (task-id result)
  "Report completed result to conductor."
  (catch (gen_server:cast 'conductor
           `#(task-result #M(task-id ,task-id
                              status complete
                              result ,result)))))

(defun report-error (task-id reason output)
  "Report error to conductor."
  (catch (gen_server:cast 'conductor
           `#(task-result #M(task-id ,task-id
                              status failed
                              error ,reason
                              output ,output)))))
```

`terminate/2`:
```lfe
(defun terminate (_reason state)
  (let ((port (maps:get 'port state 'undefined)))
    (when (is_port port)
      (catch (erlang:port_close port))))
  ;; Cancel timeout timer if active
  (let ((timer-ref (maps:get 'timer-ref state 'undefined)))
    (when (is_reference timer-ref)
      (erlang:cancel_timer timer-ref)))
  'ok)
```

#### 2. Update agent-sup for claude workers
**File**: `lfe/apps/autopoiesis/src/agent-sup.lfe`
**Changes**: Add `spawn-claude-agent/1` function and child spec

```lfe
(defun claude-worker-spec ()
  #M(id claude-worker
     start #(claude-worker start_link ())
     restart transient
     shutdown 10000          ; 10s shutdown for claude (longer than CL)
     type worker
     modules (claude-worker)))

(defun spawn-claude-agent (task-config)
  "Spawn a Claude Code agent worker for a task."
  (supervisor:start_child 'agent-sup (list task-config)))
```

**Problem**: `simple_one_for_one` supervisors only support ONE child spec. We need both `agent-worker` and `claude-worker`.

**Solution**: Create a separate `claude-sup.lfe` supervisor, or change `agent-sup` to `one_for_one` and spawn named children. The cleanest approach: **add a new `claude-sup`** under `autopoiesis-sup`.

#### 3. New Claude supervisor
**File**: `lfe/apps/autopoiesis/src/claude-sup.lfe`
**Changes**: New file, ~30 LOC

```lfe
(defmodule claude-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)
          (spawn-claude-agent 1)
          (stop-claude-agent 1)
          (list-claude-agents 0)))

(defun start_link ()
  (supervisor:start_link #(local claude-sup) 'claude-sup '()))

(defun init (_args)
  (let* ((sup-flags #M(strategy simple_one_for_one
                       intensity 3
                       period 60))
         (children (list (claude-worker-spec))))
    `#(ok #(,sup-flags ,children))))

(defun claude-worker-spec ()
  #M(id claude-worker
     start #(claude-worker start_link ())
     restart transient
     shutdown 10000
     type worker
     modules (claude-worker)))

(defun spawn-claude-agent (task-config)
  (supervisor:start_child 'claude-sup (list task-config)))

(defun stop-claude-agent (pid)
  (supervisor:terminate_child 'claude-sup pid))

(defun list-claude-agents ()
  (supervisor:which_children 'claude-sup))
```

#### 4. Update top-level supervisor
**File**: `lfe/apps/autopoiesis/src/autopoiesis-sup.lfe`
**Changes**: Add `claude-sup` as fourth child

Add to children list:
```lfe
(defun claude-sup-spec ()
  #M(id claude-sup
     start #(claude-sup start_link ())
     restart permanent
     shutdown infinity
     type supervisor
     modules (claude-sup)))
```

Add `(claude-sup-spec)` to the children list in `init/1`.

#### 5. Update conductor for task results
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`
**Changes**: Add `handle_cast` clause for `#(task-result ...)`, add `spawn-claude-for-work` function

New cast handler:
```lfe
;; Task result from claude worker
((`#(task-result ,result) state)
 (let ((task-id (maps:get 'task-id result))
       (status (maps:get 'status result)))
   (logger:info "Task ~s completed with status: ~p"
                (list task-id status))
   ;; Store result in state for retrieval
   ;; For now just log — Phase 4 will add result processing
   `#(noreply ,state)))
```

New dispatch function:
```lfe
(defun spawn-claude-for-work (work-item)
  "Spawn a Claude Code agent for slow-path work.
   Runs asynchronously to avoid blocking conductor."
  (let ((task-id (make-agent-id)))
    (spawn
      (lambda ()
        (case (catch (claude-sup:spawn-claude-agent
                       `#M(task-id ,task-id
                           prompt ,(build-prompt-for-work work-item)
                           timeout 300000
                           max-turns 50)))
          (`#(ok ,pid)
           (logger:info "Spawned Claude worker ~s (pid ~p)"
                        (list task-id pid)))
          (`#(EXIT ,reason)
           (logger:warning "Failed to spawn Claude worker: ~p"
                           (list reason)))
          (`#(error ,reason)
           (logger:warning "Failed to spawn Claude worker: ~p"
                           (list reason))))))))

(defun build-prompt-for-work (work-item)
  "Build a Claude prompt from a work item."
  (let ((work-type (maps:get 'type work-item 'unknown))
        (payload (maps:get 'payload work-item #M())))
    (lists:flatten
      (io_lib:format
        "You are an infrastructure monitoring agent. ~n~n"
        "Task type: ~p~n"
        "Payload: ~p~n~n"
        "Analyze the situation and report your findings."
        (list work-type payload)))))
```

### Success Criteria

#### Automated Verification:
- [ ] `cd lfe && rebar3 compile` — compiles without errors
- [ ] `cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests,claude-worker-tests` — all pass
- [ ] New module `claude-worker` exports all documented functions

#### Manual Verification:
- [ ] Start application in REPL, verify `claude-sup` is running in supervisor tree
- [ ] `claude-sup:spawn-claude-agent` with a simple prompt spawns Claude CLI and captures output
- [ ] Claude worker terminates cleanly when Claude exits
- [ ] Claude worker handles timeout (kill Claude after deadline)
- [ ] Killing Claude process triggers supervisor to detect death (no zombie)
- [ ] Conductor receives `#(task-result ...)` cast after Claude completes

**Implementation Note**: After completing this phase and all automated verification passes, pause here for confirmation before proceeding.

---

## Phase 3: Claude Worker Tests

### Overview
Write comprehensive tests for the claude-worker module, following the same patterns as existing LFE tests.

### Changes Required

#### 1. Claude Worker Tests
**File**: `lfe/apps/autopoiesis/test/claude-worker-tests.lfe`
**Changes**: New file, ~200 LOC

```lfe
(defmodule claude-worker-tests
  (export all))

;;; Section 1: Pure function tests

(defun build_claude_command_basic_test ()
  "build-claude-command should construct claude CLI invocation."
  (let ((`#(,cmd ,args) (claude-worker:build-claude-command
                           #M(prompt "hello"))))
    ;; Command should end with "claude" or contain "claude"
    (assert-truthy (is_list args))
    ;; Should include -p flag
    (assert-truthy (lists:member "-p" args))
    ;; Should include prompt
    (assert-truthy (lists:member "hello" args))
    ;; Should include stream-json format
    (assert-truthy (lists:member "--output-format" args))
    (assert-truthy (lists:member "stream-json" args))))

(defun build_claude_command_with_mcp_test ()
  "build-claude-command should include MCP config when specified."
  (let ((`#(,_cmd ,args) (claude-worker:build-claude-command
                            #M(prompt "test"
                               mcp-config "/tmp/mcp.json"))))
    (assert-truthy (lists:member "--mcp-config" args))
    (assert-truthy (lists:member "/tmp/mcp.json" args))))

(defun build_claude_command_with_max_turns_test ()
  "build-claude-command should include max-turns."
  (let ((`#(,_cmd ,args) (claude-worker:build-claude-command
                            #M(prompt "test" max-turns 10))))
    (assert-truthy (lists:member "--max-turns" args))
    (assert-truthy (lists:member "10" args))))

(defun parse_result_valid_json_test ()
  "parse-result should handle valid JSON."
  (let ((result (claude-worker:parse-result
                  <<"[{\"type\":\"result\",\"content\":\"hello\"}]">>)))
    (assert-truthy (is_list result))))

(defun parse_result_empty_test ()
  "parse-result should handle empty buffer."
  (let ((result (claude-worker:parse-result '())))
    (assert-truthy (is_map result))
    (assert-equal <<"error">> (maps:get <<"type">> result))))

;;; Section 2: Integration tests (require claude CLI)

;; Note: These tests only run if claude CLI is available.
;; They use a very short prompt to minimize API cost.

(defun claude_available_p ()
  "Check if claude CLI is available."
  (case (os:find_executable "claude")
    ('false 'false)
    (_ 'true)))

;;; Section 3: Helpers

(defun assert-truthy (val)
  (case val
    ('false (error 'assertion-failed))
    ('undefined (error 'assertion-failed))
    (_ 'ok)))

(defun assert-equal (expected actual)
  (case (== expected actual)
    ('true 'ok)
    ('false (error `#(assertion-failed expected ,expected actual ,actual)))))
```

#### 2. Update test runner
Ensure `claude-worker-tests` is included in the eunit module list.

### Success Criteria

#### Automated Verification:
- [ ] `cd lfe && rebar3 eunit --module=claude-worker-tests` — pure function tests pass
- [ ] `cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests,claude-worker-tests` — all tests pass (60+ total)

---

## Phase 4: Conductor Integration — Infra Watcher Timer

### Overview
Wire up the conductor to schedule a periodic infrastructure monitoring task that spawns Claude workers with Cortex MCP access.

### Changes Required

#### 1. MCP Config File for Cortex
**File**: `lfe/config/cortex-mcp.json`
**Changes**: New file

```json
{
  "mcpServers": {
    "cortex": {
      "command": "uv",
      "args": ["run", "--directory", "/Users/reuben/projects/cortex", "python", "-m", "cortex.mcp_server"],
      "env": {}
    }
  }
}
```

Note: The exact command depends on how Cortex MCP server is invoked. This will be adjusted during implementation.

#### 2. Infra Watcher Prompt
**File**: `lfe/config/infra-watcher-prompt.md`
**Changes**: New file

```markdown
You are an infrastructure monitoring agent running as part of the Autopoiesis platform.

## Your Task

Query the Cortex infrastructure monitoring system for recent events and anomalies.

## Steps

1. Call `cortex_status` to verify Cortex is running
2. Call `cortex_schema` to see what entity types exist
3. Call `cortex_query` with limit=50 to get recent events
4. For any concerning events (task failures, pod restarts, error patterns), call `cortex_entity_detail` to investigate
5. Summarize your findings

## Output Format

Respond with a JSON object:
{
  "status": "clear" | "warning" | "critical",
  "events_reviewed": <number>,
  "anomalies": [
    {
      "entity_type": "...",
      "entity_id": "...",
      "severity": "info" | "warning" | "critical",
      "description": "...",
      "recommendation": "..."
    }
  ],
  "summary": "Human-readable summary"
}
```

#### 3. Conductor Infra Watcher Setup
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`
**Changes**: Add function to schedule infra watcher, add result handling

New function for scheduling the watcher:
```lfe
(defun schedule-infra-watcher ()
  "Schedule the infrastructure watcher to run periodically."
  (let* ((prompt (read-prompt-file "config/infra-watcher-prompt.md"))
         (mcp-config (mcp-config-path "config/cortex-mcp.json")))
    (schedule
      `#M(id infra-watcher
          interval 300            ; every 5 minutes
          recurring true
          requires-llm true
          action-type claude      ; dispatch to claude-worker
          prompt ,prompt
          mcp-config ,mcp-config
          timeout 120000          ; 2 minute timeout
          max-turns 20
          allowed-tools "mcp__cortex__cortex_status,mcp__cortex__cortex_schema,mcp__cortex__cortex_query,mcp__cortex__cortex_entity_detail"))))
```

Update `execute-timer-action` to handle `action-type claude`:
```lfe
(defun execute-timer-action (action state)
  (case (maps:get 'requires-llm action 'false)
    ('true
     (case (maps:get 'action-type action 'cl)
       ('claude (spawn-claude-for-work action))
       (_       (spawn-agent-for-work action)))
     state)
    ('false
     ;; ... existing fast-path code ...
     )))
```

Update `handle_cast` for task results to track infra watcher findings:
```lfe
((`#(task-result ,result) state)
 (let* ((task-id (maps:get 'task-id result "unknown"))
        (task-status (maps:get 'status result 'unknown))
        (new-metrics (increment-metric 'tasks-completed (state-metrics state))))
   (case task-status
     ('complete
      (logger:info "Task ~s completed successfully" (list task-id))
      (process-task-result result))
     ('failed
      (logger:warning "Task ~s failed: ~p"
                      (list task-id (maps:get 'error result 'unknown)))))
   `#(noreply ,(set-state-metrics state new-metrics))))
```

New helper to process results:
```lfe
(defun process-task-result (result)
  "Process a completed task result. Log findings, escalate if needed."
  (let ((data (maps:get 'result result #M())))
    (case (maps:get <<"status">> data <<"unknown">>)
      (<<"critical">>
       (logger:error "CRITICAL: Infrastructure anomaly detected!")
       (logger:error "Details: ~p" (list data)))
      (<<"warning">>
       (logger:warning "Infrastructure warning: ~p"
                       (list (maps:get <<"summary">> data <<"no summary">>))))
      (_
       (logger:info "Infrastructure check: ~p"
                    (list (maps:get <<"summary">> data <<"all clear">>)))))))
```

#### 4. Add helper functions for file reading
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`
**Changes**: Utility functions

```lfe
(defun read-prompt-file (relative-path)
  "Read a prompt file relative to the LFE app directory."
  (let ((path (filename:join (code:priv_dir 'autopoiesis) relative-path)))
    (case (file:read_file path)
      (`#(ok ,content) (binary_to_list content))
      (`#(error ,_reason)
       ;; Fallback: try relative to CWD
       (case (file:read_file relative-path)
         (`#(ok ,content) (binary_to_list content))
         (`#(error ,reason)
          (logger:warning "Could not read prompt file ~s: ~p"
                          (list relative-path reason))
          "Analyze infrastructure and report findings."))))))

(defun mcp-config-path (relative-path)
  "Resolve MCP config path relative to app directory."
  (let ((path (filename:join (code:priv_dir 'autopoiesis) relative-path)))
    (case (filelib:is_file path)
      ('true path)
      ('false
       (case (filelib:is_file relative-path)
         ('true (filename:absname relative-path))
         ('false 'undefined))))))
```

### Success Criteria

#### Automated Verification:
- [ ] `cd lfe && rebar3 compile` — compiles without errors
- [ ] All existing tests still pass
- [ ] New conductor tests for `action-type claude` dispatch pass

#### Manual Verification:
- [ ] Start application, call `conductor:schedule-infra-watcher`
- [ ] Verify timer appears in `conductor:status` timer-heap
- [ ] When timer fires, Claude worker spawns and queries Cortex
- [ ] Result logged by conductor after Claude completes
- [ ] Timer reschedules for next interval
- [ ] If Cortex is not running, Claude reports error gracefully
- [ ] If Claude times out, conductor continues running

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding.

---

## Phase 5: Back Pressure and Robustness

### Overview
Add health monitoring, rate limiting, and error recovery to make the Claude worker loop production-grade.

### Changes Required

#### 1. Update health handler for Claude workers
**File**: `lfe/apps/autopoiesis/src/health-handler.lfe`
**Changes**: Include Claude worker status in health response

Add to health check:
```lfe
;; Add claude worker info to health response
claude-agents ,(length (claude-sup:list-claude-agents))
```

#### 2. Rate limiting in conductor
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`
**Changes**: Don't spawn new Claude worker if one is already running for same task type

```lfe
(defun claude-task-running-p (task-type)
  "Check if a Claude task of this type is already running."
  (let ((agents (claude-sup:list-claude-agents)))
    (lists:any
      (lambda (child)
        (case child
          (`#(,_id ,pid ,worker ,_modules) (when (is_pid pid))
           (try
             (let ((status (claude-worker:get-status pid)))
               (=:= (maps:get 'task-type status 'undefined) task-type))
             (catch (`#(,_ ,_ ,_) 'false))))
          (_ 'false)))
      agents)))
```

#### 3. Consecutive failure tracking
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`
**Changes**: Track failures, back off on repeated failures

Add to metrics:
```lfe
consecutive-failures 0
last-failure-time 0
```

In `process-task-result` failure branch:
```lfe
('failed
 (let* ((failures (+ 1 (maps:get 'consecutive-failures
                         (state-metrics state) 0)))
        (new-metrics (maps:put 'consecutive-failures failures
                      (state-metrics state))))
   (when (> failures 3)
     (logger:error "~p consecutive task failures — backing off"
                   (list failures)))
   ;; Exponential backoff: skip next N intervals
   ))
```

#### 4. Graceful degradation
- If Claude CLI is not installed → log warning, don't crash
- If Cortex MCP is unreachable → Claude reports error, conductor continues
- If Claude exceeds timeout → kill process, log, reschedule
- If too many failures → exponential backoff, then alert

### Success Criteria

#### Automated Verification:
- [ ] All tests pass
- [ ] Health endpoint includes claude worker count

#### Manual Verification:
- [ ] Remove `claude` from PATH, start app → graceful degradation, no crash
- [ ] Trigger rapid task failures → backoff observed in logs
- [ ] Start infra-watcher with Cortex down → Claude reports "cannot connect"
- [ ] Kill Claude mid-execution → supervisor detects, conductor continues

**Implementation Note**: After completing this phase, the system should be robust enough for extended testing.

---

## Testing Strategy

### Unit Tests (claude-worker-tests.lfe)
- `build-claude-command` with various config combinations
- `parse-result` with valid/invalid JSON
- `extract-final-result` with various message sequences

### Integration Tests (require claude CLI)
- Spawn claude-worker with trivial prompt ("echo hello")
- Verify exit status 0 and result parsed
- Test timeout behavior with slow prompt
- Test large output handling

### Conductor Integration Tests
- Schedule `action-type claude` timer, verify dispatch
- Verify `#(task-result ...)` cast received by conductor
- Verify rate limiting (don't double-spawn same task type)

### Manual Testing Steps
1. Start full application: `rebar3 lfe repl` → `(application:ensure_all_started 'autopoiesis)`
2. Schedule infra watcher: `(conductor:schedule-infra-watcher)`
3. Wait for first execution (5 minutes or set interval to 10 seconds for testing)
4. Check logs for Claude output and Cortex queries
5. Check `(conductor:status)` for updated metrics
6. Kill application, restart, verify watcher reschedules

## Performance Considerations

- **Claude API cost**: Each invocation costs API tokens. Default 5-minute interval = ~288 calls/day. Consider longer intervals (15-30 min) for production.
- **Timeout**: 2-minute default for infra checks. Claude usually completes in 30-60 seconds for simple queries.
- **Memory**: Each Claude port process uses ~50MB. With `simple_one_for_one` max 3 restarts/60s, memory is bounded.
- **Concurrent workers**: Rate limiting prevents duplicate tasks. Max 1 infra-watcher at a time.

## References

- Synthesis: `thoughts/shared/research/2026-02-06-super-agent-synthesis.md`
- Roadmap: `thoughts/shared/research/2026-02-06-next-steps-roadmap.md`
- LFE Status: `thoughts/shared/research/2026-02-06-lfe-implementation-status.md`
- Master Plan: `thoughts/shared/plans/2026-02-04-lfe-supervised-agent-platform.md`
- Agent Worker Pattern: `lfe/apps/autopoiesis/src/agent-worker.lfe`
- Conductor: `lfe/apps/autopoiesis/src/conductor.lfe`
- CL Agent Class: `src/agent/agent.lisp:11-40`
- CL Cognitive Loop: `src/agent/cognitive-loop.lisp:50-58`
- CL Snapshot Persistence: `src/snapshot/persistence.lisp:98-151`
- CL Extension Compiler: `src/core/extension-compiler.lisp:389-431`
- Claude CLI Reference: https://code.claude.com/docs/en/cli-reference
- Claude Agent SDK: https://platform.claude.com/docs/en/agent-sdk/overview
- Claude Agent Teams: https://code.claude.com/docs/en/agent-teams
