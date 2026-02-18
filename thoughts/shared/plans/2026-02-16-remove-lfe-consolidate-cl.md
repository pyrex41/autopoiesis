# Remove LFE Control Plane, Consolidate to CL-Only

> **Superseded**: This plan has been incorporated into the consolidated substrate-first architecture plan at `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md` (Path C). The LFE removal is now Phase 5 of that plan, built on top of the substrate kernel. Refer to the consolidated plan for the current implementation approach.

## Overview

Remove the LFE/BEAM control plane (~1,605 LOC across 11 modules) and consolidate all orchestration into Common Lisp. Port the useful conductor/worker functionality into a new CL `orchestration` module. The CL system already has subprocess management (`provider.lisp`), HTTP server (`hunchentoot`), threading (`bordeaux-threads`), and JSON (`cl-json`) — this plan wires them into a conductor that replaces the LFE layer.

## Current State Analysis

### LFE Layer (to be removed): 11 files, ~1,605 LOC

| Module | LOC | Verdict | Rationale |
|--------|-----|---------|-----------|
| conductor.lfe | 564 | **Port to CL** | Timer heap + tick loop + event queue — real value |
| claude-worker.lfe | 257 | **Port to CL** | Claude CLI subprocess driver — needed |
| autopoiesis-sup.lfe | 49 | **Drop** | OTP supervisor tree — CL uses threads + restart logic |
| agent-worker.lfe | 484 | **Drop** | CL↔CL bridge via subprocess — CL calls itself directly |
| claude-sup.lfe | 37 | **Drop** | simple_one_for_one supervisor — replaced by CL worker pool |
| agent-sup.lfe | 42 | **Drop** | CL agent subprocess supervisor — unnecessary |
| health-handler.lfe | 42 | **Port to CL** | Health endpoint — add to existing Hunchentoot |
| webhook-server.lfe | 60 | **Drop** | Cowboy HTTP lifecycle — Hunchentoot already running |
| webhook-handler.lfe | 39 | **Port to CL** | Webhook event ingestion — add to existing Hunchentoot |
| connector-sup.lfe | 21 | **Drop** | HTTP server supervisor — unnecessary |
| autopoiesis-app.lfe | 10 | **Drop** | OTP application entry — replaced by CL startup |

### CL Capabilities Already Available

- **Subprocess**: `run-provider-subprocess` (`src/integration/provider.lisp:237-318`) — full process lifecycle with timeout, SIGTERM/SIGKILL, threaded I/O
- **HTTP server**: Hunchentoot on port 8081 with /health, /healthz, /readyz, /metrics (`src/monitoring/endpoints.lisp:405-456`)
- **Threading**: `bordeaux-threads` used throughout — locks, threads, joins
- **JSON**: `cl-json` for encode/decode, already used in MCP client and monitoring
- **Agentic loop**: `agentic-loop` (`src/integration/claude-bridge.lisp:174-226`) — multi-turn tool execution without CLI
- **Timer patterns**: Sleep-based loops in heartbeat thread, SSE keep-alive, event polling

## Desired End State

After this plan is complete:

1. The `lfe/` directory is deleted
2. A new `src/orchestration/` module provides:
   - A conductor with timer heap, tick loop, and event queue (ported from LFE)
   - A Claude CLI worker that spawns `claude` subprocesses and parses stream-json
   - Integration with the existing CL agentic-loop for direct API calls (no subprocess needed)
3. The existing Hunchentoot server gains /conductor/status, /conductor/webhook endpoints
4. `scripts/agent-worker.lisp` (the CL-side of the bridge) is deleted since CL calls itself directly
5. All existing CL tests pass
6. New orchestration tests cover conductor and worker functionality
7. CLAUDE.md is updated to reflect the new architecture

### Verification

```bash
# CL tests (existing + new)
./scripts/test.sh

# Verify LFE directory is gone
test ! -d lfe/ && echo "LFE removed"

# Verify conductor starts and ticks
sbcl --load scripts/test-conductor.lisp
```

## What We're NOT Doing

- **Reimplementing OTP supervision trees in CL** — We use simple thread + retry loops. If we need real supervision later, that's a separate project.
- **Changing the agentic-loop or cognitive primitives** — Those are untouched.
- **Adding new features** — This is a pure consolidation. Same functionality, fewer moving parts.
- **Modifying existing test suites** — Existing CL tests should pass unchanged. We add new tests for orchestration.
- **Multi-user/multi-tenant support** — Out of scope. This remains a single-user system.
- **Removing the LFE config/prompt files** — `lfe/config/cortex-mcp.json` and `lfe/config/infra-watcher-prompt.md` move to `config/` at project root.

## Implementation Approach

**Bottom-up**: Build the new CL orchestration module, verify it works, then delete LFE. Each phase is independently testable. We never have a broken intermediate state because the LFE code isn't modified — it's just deleted at the end.

---

## Phase 1: CL Conductor — Timer Heap + Tick Loop

### Overview

Port the conductor's core scheduling logic from LFE to CL. This is the heart of the orchestration — a background thread with a 100ms tick that processes a timer heap and event queue.

### Changes Required

#### 1. New package definition
**File**: `src/orchestration/packages.lisp` (new)

```lisp
(defpackage #:autopoiesis.orchestration
  (:use #:cl #:alexandria)
  (:export
   ;; Conductor
   #:*conductor*
   #:start-conductor
   #:stop-conductor
   #:conductor-running-p
   #:conductor-status
   #:schedule-action
   #:cancel-action
   #:queue-event
   ;; Claude worker
   #:run-claude-cli
   #:build-claude-command
   #:parse-stream-json-output))
```

#### 2. Conductor implementation
**File**: `src/orchestration/conductor.lisp` (new)

Port from `conductor.lfe`. The timer heap uses a sorted list (or priority queue via `alexandria`). Key structures:

```lisp
(defclass conductor ()
  ((timer-heap :initform nil :accessor conductor-timer-heap
               :documentation "List of (fire-time . action) sorted by time")
   (event-queue :initform nil :accessor conductor-event-queue
                :documentation "Pending events to process")
   (metrics :initform (make-hash-table) :accessor conductor-metrics)
   (lock :initform (bt:make-lock "conductor") :accessor conductor-lock)
   (tick-thread :initform nil :accessor conductor-tick-thread)
   (running :initform nil :accessor conductor-running-p))
  (:documentation "Central scheduler — tick loop with timer heap and event queue."))

(defvar *conductor* nil "The global conductor instance.")

(defun start-conductor ()
  "Start the conductor tick loop in a background thread."
  (when *conductor* (stop-conductor))
  (let ((c (make-instance 'conductor)))
    (setf (conductor-running-p c) t)
    (setf (conductor-tick-thread c)
          (bt:make-thread
           (lambda () (conductor-tick-loop c))
           :name "conductor-tick"))
    (setf *conductor* c)
    c))

(defun stop-conductor ()
  "Stop the conductor tick loop."
  (when *conductor*
    (setf (conductor-running-p *conductor*) nil)
    ;; Thread will exit on next tick check
    (when (conductor-tick-thread *conductor*)
      (ignore-errors (bt:join-thread (conductor-tick-thread *conductor*))))
    (setf *conductor* nil)))

(defun conductor-tick-loop (conductor)
  "Main tick loop — runs every 100ms."
  (loop while (conductor-running-p conductor)
        do (handler-case
               (progn
                 (process-due-timers conductor)
                 (process-events conductor)
                 (increment-metric conductor :tick-count))
             (error (e)
               (log:warn "Conductor tick error: ~A" e)))
           (sleep 0.1)))

(defun schedule-action (action)
  "Schedule a timed action. ACTION is a plist:
   :id :interval :recurring :requires-llm :action-type :action (function or config)"
  (bt:with-lock-held ((conductor-lock *conductor*))
    (let* ((interval (getf action :interval 60))
           (fire-time (+ (get-internal-real-time)
                         (* interval internal-time-units-per-second)))
           (entry (cons fire-time action)))
      (push entry (conductor-timer-heap *conductor*))
      (setf (conductor-timer-heap *conductor*)
            (sort (conductor-timer-heap *conductor*) #'< :key #'car))
      (increment-metric *conductor* :timers-scheduled))))

(defun cancel-action (name)
  "Cancel a scheduled action by :id."
  (bt:with-lock-held ((conductor-lock *conductor*))
    (setf (conductor-timer-heap *conductor*)
          (remove name (conductor-timer-heap *conductor*)
                 :key (lambda (entry) (getf (cdr entry) :id))))
    (increment-metric *conductor* :timers-cancelled)))

(defun queue-event (event)
  "Queue an external event (plist with at minimum :type)."
  (bt:with-lock-held ((conductor-lock *conductor*))
    (push event (conductor-event-queue *conductor*))))
```

Timer processing, event classification, metric tracking, and failure handling follow the same logic as the LFE conductor. Port:
- `process-due-timers` → pop entries where fire-time <= now, execute, maybe-reschedule if `:recurring t`
- `process-events` → drain queue, classify each event, dispatch
- `execute-timer-action` → dispatch on `:action-type`: `:claude` → run-claude-cli, `:agentic` → run agentic-loop in thread, `:fast` → funcall directly
- `conductor-status` → return plist of metrics for health endpoint
- Rate limiting: track running workers in a set, check before spawning

### Success Criteria

#### Automated Verification:
- [ ] `./scripts/test.sh` — all existing CL tests pass (no regressions)
- [ ] New test: conductor starts, ticks, and stops cleanly
- [ ] New test: schedule-action fires after interval
- [ ] New test: cancel-action removes from heap
- [ ] New test: queue-event processes through event queue
- [ ] New test: recurring actions reschedule
- [ ] New test: conductor-status returns correct metrics

#### Manual Verification:
- [ ] Start conductor in REPL, verify tick thread is running
- [ ] Schedule a test action, verify it fires

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding.

---

## Phase 2: CL Claude Worker — CLI Subprocess Driver

### Overview

Port the Claude CLI subprocess management from `claude-worker.lfe` into CL using the existing `run-provider-subprocess` pattern from `provider.lisp`.

### Changes Required

#### 1. Claude CLI worker
**File**: `src/orchestration/claude-worker.lisp` (new)

```lisp
(defun build-claude-command (config)
  "Build claude CLI command string.
   CONFIG is a plist: :prompt :mcp-config :allowed-tools :max-turns :claude-path"
  (let* ((claude (or (getf config :claude-path) (find-claude-executable)))
         (prompt (getf config :prompt ""))
         (max-turns (getf config :max-turns 50))
         (parts (list claude
                      "-p" (shell-quote prompt)
                      "--output-format" "stream-json"
                      "--verbose"
                      "--max-turns" (write-to-string max-turns)
                      "--dangerously-skip-permissions")))
    (when (getf config :mcp-config)
      (appendf parts (list "--mcp-config" (getf config :mcp-config))))
    (when (getf config :allowed-tools)
      (appendf parts (list "--allowedTools" (getf config :allowed-tools))))
    (format nil "~{~A~^ ~} </dev/null" parts)))

(defun run-claude-cli (config &key (timeout 300) on-complete on-error)
  "Run Claude CLI as subprocess, parse stream-json output.
   Calls ON-COMPLETE with result plist or ON-ERROR with reason.
   Runs in a new thread — returns the thread."
  (bt:make-thread
   (lambda ()
     (handler-case
         (let* ((command (build-claude-command config))
                (output (make-array 0 :element-type 'character
                                      :adjustable t :fill-pointer 0))
                (messages nil))
           ;; Use sb-ext:run-program with shell
           (let ((process (sb-ext:run-program
                           "/bin/sh" (list "-c" command)
                           :output :stream
                           :error :stream
                           :wait nil)))
             (unwind-protect
                  (let ((stdout (sb-ext:process-output process))
                        (deadline (+ (get-internal-real-time)
                                     (* timeout internal-time-units-per-second))))
                    ;; Read stream-json lines
                    (loop for line = (read-line stdout nil nil)
                          while line
                          do (handler-case
                                 (let ((json (cl-json:decode-json-from-string line)))
                                   (push json messages))
                               (error () nil)) ; skip unparseable lines
                          when (> (get-internal-real-time) deadline)
                            do (sb-ext:process-kill process sb-unix:sigterm)
                               (sleep 2)
                               (when (sb-ext:process-alive-p process)
                                 (sb-ext:process-kill process sb-unix:sigkill))
                               (when on-error
                                 (funcall on-error :timeout))
                               (return))
                    ;; Wait for exit
                    (sb-ext:process-wait process)
                    (let ((exit-code (sb-ext:process-exit-code process)))
                      (if (zerop exit-code)
                          (let ((result (extract-result (nreverse messages))))
                            (when on-complete (funcall on-complete result)))
                          (when on-error
                            (funcall on-error (list :exit-code exit-code))))))
               (ignore-errors (sb-ext:process-close process)))))
       (error (e)
         (when on-error (funcall on-error (format nil "~A" e))))))
   :name "claude-worker"))

(defun extract-result (messages)
  "Extract the result message from stream-json output.
   Messages is a list of decoded JSON alists."
  (let ((result-msgs (remove-if-not
                      (lambda (msg)
                        (string= "result" (cdr (assoc :type msg))))
                      messages)))
    (if result-msgs
        (car (last result-msgs))
        (car (last messages)))))

(defun find-claude-executable ()
  "Find claude in PATH."
  (let ((path (uiop:run-program "which claude"
                                :output '(:string :stripped t)
                                :ignore-error-status t)))
    (if (and path (not (string= "" path))) path "claude")))

(defun shell-quote (str)
  "Single-quote a string for shell safety."
  (format nil "'~A'" (cl-ppcre:regex-replace-all "'" str "'\\''")))
```

#### 2. Wire conductor to Claude worker
**File**: `src/orchestration/conductor.lisp` (addition)

Add to `execute-timer-action`:

```lisp
(defun execute-timer-action (conductor action)
  "Execute a scheduled action."
  (let ((action-type (getf (cdr action) :action-type :fast)))
    (case action-type
      (:claude
       (unless (worker-running-p conductor (getf (cdr action) :id))
         (let ((task-id (format nil "claude-~A" (incf (gethash :task-counter
                                                        (conductor-metrics conductor) 0)))))
           (run-claude-cli
            (list :prompt (getf (cdr action) :prompt)
                  :mcp-config (getf (cdr action) :mcp-config)
                  :allowed-tools (getf (cdr action) :allowed-tools)
                  :max-turns (getf (cdr action) :max-turns 50)
                  :claude-path (getf (cdr action) :claude-path))
            :timeout (or (getf (cdr action) :timeout) 300)
            :on-complete (lambda (result)
                           (handle-task-result conductor task-id :complete result))
            :on-error (lambda (reason)
                        (handle-task-result conductor task-id :failed reason))))))
      (:agentic
       ;; Direct CL agentic loop — no subprocess needed
       (bt:make-thread
        (lambda ()
          (handler-case
              (let ((result (run-agentic-task (cdr action))))
                (handle-task-result conductor "agentic" :complete result))
            (error (e)
              (handle-task-result conductor "agentic" :failed
                                  (format nil "~A" e)))))
        :name "agentic-worker"))
      (:fast
       (let ((fn (getf (cdr action) :action)))
         (when fn (ignore-errors (funcall fn)))))
      (t
       (log:warn "Unknown action type: ~A" action-type)))))
```

#### 3. Schedule infra-watcher (ported from LFE)
**File**: `src/orchestration/conductor.lisp` (addition)

```lisp
(defun schedule-infra-watcher (&key (interval 300) (mcp-config "config/cortex-mcp.json"))
  "Schedule the infrastructure watcher to run periodically."
  (let ((prompt (read-prompt-file "config/infra-watcher-prompt.md")))
    (schedule-action
     (list :id :infra-watcher
           :interval interval
           :recurring t
           :action-type :claude
           :prompt prompt
           :mcp-config (when (probe-file mcp-config) (namestring (truename mcp-config)))
           :timeout 120
           :max-turns 20
           :allowed-tools "mcp__cortex__cortex_status,mcp__cortex__cortex_schema,mcp__cortex__cortex_query,mcp__cortex__cortex_entity_detail"))))

(defun read-prompt-file (path)
  "Read a prompt file, return default string on failure."
  (handler-case
      (uiop:read-file-string path)
    (error ()
      "Analyze infrastructure and report findings.")))
```

### Success Criteria

#### Automated Verification:
- [ ] `./scripts/test.sh` — all existing CL tests pass
- [ ] New test: `build-claude-command` produces correct command string
- [ ] New test: `build-claude-command` handles all config combinations (mcp-config, allowed-tools, custom path)
- [ ] New test: `shell-quote` properly escapes single quotes
- [ ] New test: `extract-result` finds "result" type message
- [ ] New test: `extract-result` falls back to last message
- [ ] New test: `schedule-infra-watcher` adds entry to conductor timer heap

#### Manual Verification:
- [ ] Run `(run-claude-cli '(:prompt "Say PONG" :max-turns 1) :timeout 60 :on-complete #'print)` and verify output
- [ ] Schedule infra-watcher, verify it fires after interval

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding.

---

## Phase 3: HTTP Endpoints — Conductor Status + Webhook

### Overview

Add conductor-specific endpoints to the existing Hunchentoot server. The monitoring server already handles /health, /healthz, /readyz, /metrics on port 8081.

### Changes Required

#### 1. Conductor endpoints
**File**: `src/orchestration/endpoints.lisp` (new)

```lisp
(in-package #:autopoiesis.orchestration)

(defun conductor-status-handler ()
  "GET /conductor/status — return conductor metrics as JSON."
  (if *conductor*
      (autopoiesis.monitoring::json-response (conductor-status *conductor*))
      (autopoiesis.monitoring::json-response
       '(:status "stopped") :status 503)))

(defun conductor-webhook-handler ()
  "POST /conductor/webhook — accept events."
  (let ((body (hunchentoot:raw-post-data :force-text t)))
    (handler-case
        (let ((json (cl-json:decode-json-from-string body)))
          (queue-event (list :type (or (cdr (assoc :type json)) :unknown)
                            :payload json))
          (autopoiesis.monitoring::json-response '(:status "accepted")))
      (error ()
        (autopoiesis.monitoring::json-response
         '(:error "invalid_json") :status 400)))))

(defun register-conductor-endpoints ()
  "Add conductor endpoints to the running Hunchentoot server."
  (push (hunchentoot:create-prefix-dispatcher
         "/conductor/status" #'conductor-status-handler)
        hunchentoot:*dispatch-table*)
  (push (hunchentoot:create-prefix-dispatcher
         "/conductor/webhook" #'conductor-webhook-handler)
        hunchentoot:*dispatch-table*))
```

### Success Criteria

#### Automated Verification:
- [ ] `./scripts/test.sh` — all existing CL tests pass
- [ ] New test: GET /conductor/status returns JSON with metrics
- [ ] New test: POST /conductor/webhook accepts valid JSON
- [ ] New test: POST /conductor/webhook rejects invalid JSON with 400

#### Manual Verification:
- [ ] `curl localhost:8081/conductor/status` returns conductor metrics
- [ ] `curl -X POST localhost:8081/conductor/webhook -d '{"type":"test"}' -H "Content-Type: application/json"` returns 200

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding.

---

## Phase 4: Wire into ASDF + Startup

### Overview

Add the orchestration module to the ASDF system definition and create a unified startup function.

### Changes Required

#### 1. Update ASDF
**File**: `autopoiesis.asd`

Add orchestration module after monitoring:

```lisp
(:module "orchestration"
 :serial t
 :depends-on ("core" "agent" "integration" "monitoring")
 :components
 ((:file "packages")
  (:file "conductor")
  (:file "claude-worker")
  (:file "endpoints")))
```

Update the main autopoiesis file's depends-on to include "orchestration".

#### 2. Startup function
**File**: `src/orchestration/conductor.lisp` (addition)

```lisp
(defun start-system (&key (monitoring-port 8081) (start-conductor t))
  "Start the full Autopoiesis system: monitoring server + conductor."
  (autopoiesis.monitoring:start-monitoring-server :port monitoring-port)
  (register-conductor-endpoints)
  (when start-conductor
    (start-conductor))
  (format t "~&Autopoiesis system started.~%")
  (format t "  Monitoring: http://localhost:~D~%" monitoring-port)
  (format t "  Conductor: ~A~%" (if start-conductor "running" "stopped"))
  t)

(defun stop-system ()
  "Stop the full system."
  (stop-conductor)
  (autopoiesis.monitoring:stop-monitoring-server)
  (format t "~&Autopoiesis system stopped.~%"))
```

#### 3. Move config files
Move `lfe/config/cortex-mcp.json` → `config/cortex-mcp.json`
Move `lfe/config/infra-watcher-prompt.md` → `config/infra-watcher-prompt.md`

### Success Criteria

#### Automated Verification:
- [ ] `(ql:quickload :autopoiesis)` loads without error (includes new module)
- [ ] `./scripts/test.sh` — all tests pass
- [ ] New test: `start-system` and `stop-system` don't error

#### Manual Verification:
- [ ] `(autopoiesis.orchestration:start-system)` starts monitoring + conductor
- [ ] Endpoints respond at http://localhost:8081

---

## Phase 5: Delete LFE, Clean Up

### Overview

Remove the LFE directory, the CL-side bridge script, and update documentation.

### Changes Required

#### 1. Delete LFE directory
```bash
rm -rf lfe/
```

This removes:
- 11 LFE source files (1,605 LOC)
- 5 LFE test files
- rebar.config, rebar.lock
- LFE app configuration

#### 2. Delete CL bridge worker
```bash
rm scripts/agent-worker.lisp
```

This was the CL side of the S-expression bridge protocol. With no LFE to talk to, it's dead code.

#### 3. Remove bridge protocol tests
**File**: `test/bridge-protocol-tests.lisp` — delete or gut

These tests tested the S-expression protocol between LFE and CL. The protocol no longer exists. The functions they test (in `scripts/agent-worker.lisp`) are deleted.

Remove from `autopoiesis.asd` test components:
```lisp
(:file "bridge-protocol-tests")  ; remove this line
```

#### 4. Update CLAUDE.md

Remove:
- References to LFE, BEAM, OTP, supervisor trees
- `rebar3 eunit` test commands
- LFE-specific architecture description
- Reference to 75 LFE tests

Add:
- Orchestration module description
- `(autopoiesis.orchestration:start-system)` as startup command
- Updated architecture (no more 2-runtime split)

#### 5. Update build scripts

**File**: `scripts/test.sh` — remove any LFE test invocation
**File**: `scripts/build.sh` — remove any rebar3/LFE build steps

### Success Criteria

#### Automated Verification:
- [ ] `test ! -d lfe/` — LFE directory gone
- [ ] `test ! -f scripts/agent-worker.lisp` — bridge script gone
- [ ] `./scripts/test.sh` — all CL tests pass
- [ ] `(ql:quickload :autopoiesis)` loads cleanly
- [ ] `(asdf:test-system :autopoiesis)` — all tests pass

#### Manual Verification:
- [ ] Full startup: `(autopoiesis.orchestration:start-system)` works
- [ ] Schedule infra-watcher: `(autopoiesis.orchestration:schedule-infra-watcher)` fires

---

## Testing Strategy

### Unit Tests (`test/orchestration-tests.lisp`, new)

```lisp
;; Conductor tests
- start-conductor / stop-conductor lifecycle
- schedule-action fires at correct time
- cancel-action removes entry
- recurring actions reschedule
- queue-event processes through pipeline
- event classification (fast-path vs slow-path)
- conductor-status returns metrics
- rate limiting prevents duplicate workers
- consecutive failure tracking
- failure backoff after 3 failures

;; Claude worker tests
- build-claude-command basic construction
- build-claude-command with MCP config
- build-claude-command with allowed tools
- build-claude-command with custom max-turns
- shell-quote escapes properly
- extract-result finds result type
- extract-result fallback to last message
- extract-result handles empty list

;; Endpoint tests (mock Hunchentoot)
- GET /conductor/status returns JSON
- POST /conductor/webhook accepts event
- POST /conductor/webhook rejects bad JSON
```

~25 new test cases, ~60 assertions.

### Integration Tests

- Start system → schedule test action → verify fires → stop system
- Run claude-cli with "Say PONG" → verify result extraction (requires Claude CLI installed, mark as optional/slow)

### Manual Testing Steps

1. `(ql:quickload :autopoiesis)`
2. `(autopoiesis.orchestration:start-system)`
3. `curl localhost:8081/conductor/status` — verify JSON response
4. `(autopoiesis.orchestration:schedule-infra-watcher :interval 30)` — verify fires
5. `(autopoiesis.orchestration:stop-system)`

## File Summary

| File | Type | Estimated Lines |
|------|------|----------------|
| `src/orchestration/packages.lisp` | New | ~30 |
| `src/orchestration/conductor.lisp` | New | ~250 |
| `src/orchestration/claude-worker.lisp` | New | ~120 |
| `src/orchestration/endpoints.lisp` | New | ~40 |
| `test/orchestration-tests.lisp` | New | ~200 |
| `autopoiesis.asd` | Modified | ~10 lines changed |
| `CLAUDE.md` | Modified | ~50 lines changed |
| **Total new CL** | | **~650 lines** |
| **Total deleted LFE** | | **~1,605 lines + tests** |
| **Net change** | | **~-950 lines** |

## References

- LFE control plane analysis: `thoughts/shared/research/2026-02-16-lfe-control-plane-analysis.md`
- Super Agent implementation record: `thoughts/shared/plans/2026-02-06-super-agent-implementation-record.md`
- Phase 4 bridge plan (now obsolete): `thoughts/shared/plans/2026-02-15-phase4-rich-cl-lfe-bridge.md`
- Jarvis feasibility research: `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md`
- CL subprocess management: `src/integration/provider.lisp:237-318`
- CL monitoring server: `src/monitoring/endpoints.lisp:405-456`
- CL agentic loop: `src/integration/claude-bridge.lisp:174-226`
