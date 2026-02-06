# Combine Best of LFE Implementations

## Overview

Merge the best design decisions from the scud-lfe45 worktree into the main implementation, which serves as the base (complete, 56/56 tests passing, has agent-worker). The main changes are: `defrecord` for conductor state, richer scheduling API with cancel support, `erlang:monotonic_time` for timers, improved HTTP handlers, expanded metrics, and a combined test strategy using both standalone and full-app test patterns.

## Current State Analysis

### Main (`ap/lfe/`) - The Base
- 1,758 LOC (727 src, 1,037 test), **56/56 tests passing**
- Complete: agent-worker with SBCL port communication, boot tests, HTTP tests
- Conductor uses plain maps for state, minimal API (`schedule/1`, `queue-event/1`, `status/0`)
- Uses `erlang:system_time` for timer scheduling
- 3 metrics: `ticks`, `events-processed`, `timers-fired`
- Status returns nested map: `#M(timer-count N event-queue-length N metrics #M(...))`
- Idiomatic LFE hyphenated naming throughout

### scud-lfe45 (`ap-worktrees/scud-lfe45/lfe/`) - Cherry-pick Source
- 1,103 LOC, 19/19 passing (connector-tests broken, no boot/agent-worker tests)
- Conductor uses `defrecord` with generated accessors
- Richer API: `schedule/2,3`, `schedule_recurring/3`, `cancel/1`
- `cancel_action` with heap scan by name
- `format_status/2` and `handle_continue/2` callbacks
- 7 metrics (adds `timers-scheduled`, `timers-cancelled`)
- Flat status map with all fields at top level
- Tests use standalone `conductor:start_link` (no full app boot)

### Key Discoveries
- Main's `maybe-reschedule` in timer-fire loop is cleaner than scud-lfe45's self-rescheduling lambda wrapping (confirmed by user preference)
- `erlang:monotonic_time` is immune to clock adjustments -- better for timer scheduling
- scud-lfe45's standalone conductor tests are faster and better for unit testing; main's `with-application` tests are needed for integration coverage
- scud-lfe45's connector-tests.lfe uses Erlang `{...}` tuple syntax in `?assertMatch` macros -- fatal LFE parse error, must be rewritten from scratch
- scud-lfe45's `5am.lfe` assertion library lives in `src/` (ships in production) -- discard
- scud-lfe45's `agent-sup.lfe` uses `one_for_one` with empty children (stub) -- discard, keep main's `simple_one_for_one` with agent-worker template

## Desired End State

A single refined LFE implementation in `ap/lfe/` that:
- Uses `defrecord` for conductor state with LFE-idiomatic hyphenated naming
- Provides both convenience API (`schedule/2,3`, `cancel/1`) and full-map API (`schedule/1`)
- Uses `erlang:monotonic_time` for timer scheduling
- Has `maybe-reschedule` for recurring timers (main's approach)
- Reports 7 flat metrics in status
- HTTP handlers have body-size limits, proper error codes (503), `reply-json` helpers
- Tests use both standalone and with-application patterns
- All tests pass: existing 56 + new cancel/recurring/lifecycle/metrics tests

### Verification
```bash
cd lfe && rebar3 compile  # clean compile
cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests  # all pass, 0 failures
```

## What We're NOT Doing

- Not changing agent-worker.lfe or agent-worker-tests.lfe (they work fine)
- Not adopting scud-lfe45's Erlang-style underscored naming
- Not adopting scud-lfe45's tuple-based event model (maps are more flexible for JSON webhooks)
- Not adopting scud-lfe45's `schedule_recurring` self-rescheduling lambda approach
- Not porting scud-lfe45's `5am.lfe` or `conductor-test.lfe` (wrong directory, unnecessary)
- Not porting scud-lfe45's `conductor_eunit.lfe` (duplicate coverage)

## Implementation Approach

Work through 3 phases: conductor rewrite, HTTP handler upgrade, test rewrite. Each phase should compile and the next phase depends on the previous.

---

## Phase 1: Conductor Rewrite

### Overview
Rewrite `conductor.lfe` to adopt `defrecord`, richer API, `monotonic_time`, expanded metrics, and flat status -- while preserving all existing functionality (event classification, agent spawning, `maybe-reschedule`).

### Changes Required:

#### 1. `conductor.lfe` - Full rewrite
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`

**Module declaration changes:**
- Add `defrecord` for state (from scud-lfe45)
- Add exports: `(schedule 2)`, `(schedule 3)`, `(cancel 1)`
- Add exports: `(handle_continue 2)`, `(format_status 2)`
- Keep exports: `(classify-event 1)`, `(compute-next-run 1)` for testing
- Keep existing `(schedule 1)` for backward compatibility with map-based scheduling

```lfe
(defmodule conductor
  (behaviour gen_server)
  (export (start_link 0) (init 1)
          (handle_call 3) (handle_cast 2) (handle_info 2)
          (handle_continue 2) (terminate 2) (format_status 2)
          (code_change 3))
  ;; Client API
  (export (schedule 1) (schedule 2) (schedule 3)
          (cancel 1) (queue-event 1) (status 0))
  ;; Exported for testing
  (export (classify-event 1) (compute-next-run 1)))

;; State record — replaces plain maps
(defrecord state
  timer-heap     ; gb_trees with #(monotonic-time unique-ref) keys
  event-queue    ; list of event maps
  metrics)       ; map of metric counters
```

**Client API changes:**
- `schedule/1` (map) -- keep existing, for full flexibility
- `schedule/2` (name, action-fun) -- new convenience, 60s default interval, non-recurring, fast-path
- `schedule/3` (name, action-fun, interval) -- new convenience with custom interval
- `cancel/1` (name) -- new, cancel scheduled action by name/id
- `queue-event/1` -- keep as-is
- `status/0` -- keep as-is, but return flat map now

```lfe
(defun schedule (name action-fun)
  "Schedule a non-recurring fast-path action with default 60s interval."
  (schedule `#M(id ,name interval 60 recurring false requires-llm false action ,action-fun)))

(defun schedule (name action-fun interval)
  "Schedule a non-recurring fast-path action with custom interval."
  (schedule `#M(id ,name interval ,interval recurring false requires-llm false action ,action-fun)))

(defun cancel (name)
  "Cancel a scheduled action by its id/name."
  (gen_server:cast 'conductor `#(cancel ,name)))
```

**init/1 changes:**
- Use `make-state` record constructor
- Use `erlang:monotonic_time 'second` consistently
- Initialize 5 metric counters (add `timers-scheduled`, `timers-cancelled`)

```lfe
(defun init (_args)
  (logger:info "Starting conductor gen_server")
  (erlang:send_after 100 (self) 'tick)
  (let ((initial (make-state
                   timer-heap (gb_trees:empty)
                   event-queue '()
                   metrics #M(tick-count 0
                              events-processed 0
                              timers-fired 0
                              timers-scheduled 0
                              timers-cancelled 0))))
    `#(ok ,initial)))
```

**handle_cast changes:**
- Use record accessors (`state-timer-heap`, `set-state-timer-heap`, etc.)
- Add `#(cancel ,name)` clause
- Update `#(schedule ,action)` to also increment `timers-scheduled` metric

```lfe
(defun handle_cast
  ;; Schedule a timer-based action (map API)
  ((`#(schedule ,action) state)
   (let* ((next-time (compute-next-run action))
          (ref (erlang:unique_integer '(positive monotonic)))
          (key `#(,next-time ,ref))
          (new-heap (gb_trees:insert key action (state-timer-heap state)))
          (new-metrics (increment-metric 'timers-scheduled (state-metrics state))))
     `#(noreply ,(set-state-metrics
                   (set-state-timer-heap state new-heap)
                   new-metrics))))

  ;; Cancel a scheduled action by name
  ((`#(cancel ,name) state)
   `#(noreply ,(cancel-action name state)))

  ;; Queue an external event
  ((`#(event ,event) state)
   (let ((new-queue (++ (state-event-queue state) (list event))))
     `#(noreply ,(set-state-event-queue state new-queue))))

  ((_msg state)
   `#(noreply ,state)))
```

**handle_info tick changes:**
- Use record accessors throughout
- Rename metric from `ticks` to `tick-count` for consistency

```lfe
(defun handle_info
  (('tick state)
   (let* ((state2 (process-due-timers state))
          (state3 (process-events state2))
          (new-metrics (increment-metric 'tick-count (state-metrics state3))))
     (erlang:send_after 100 (self) 'tick)
     `#(noreply ,(set-state-metrics state3 new-metrics))))
  ((_msg state)
   `#(noreply ,state)))
```

**New callbacks:**

```lfe
(defun handle_continue (_continue state)
  `#(noreply ,state))

(defun format_status (_opt state)
  `#(data ((#(state ,state)))))

(defun terminate (reason _state)
  (logger:info "Conductor terminating: ~p" (list reason))
  'ok)
```

**Timer processing changes:**
- `compute-next-run/1` uses `erlang:monotonic_time 'second` instead of `system_time`
- `process-due-timers/1` uses `erlang:monotonic_time 'second`
- Keep `maybe-reschedule` (main's approach, user confirmed)
- Use record accessors for state

```lfe
(defun compute-next-run (action)
  "Compute the next monotonic timestamp when this action should fire."
  (let ((now (erlang:monotonic_time 'second))
        (interval (maps:get 'interval action 60)))
    (+ now interval)))
```

**New cancel-action function** (adapted from scud-lfe45, using hyphenated naming):

```lfe
(defun cancel-action (name state)
  "Cancel a scheduled action by id/name. Scans heap, removes matching entries."
  (let* ((heap (state-timer-heap state))
         (old-size (gb_trees:size heap))
         (entries (gb_trees:to_list heap))
         (filtered (lists:filter
                     (lambda (entry)
                       (let ((action (element 2 entry)))
                         (/= (maps:get 'id action 'undefined) name)))
                     entries))
         (new-heap (gb_trees:from_orddict filtered)))
    (if (< (gb_trees:size new-heap) old-size)
        (let ((new-metrics (increment-metric 'timers-cancelled (state-metrics state))))
          (set-state-metrics
            (set-state-timer-heap state new-heap)
            new-metrics))
        state)))
```

**Metrics/status changes:**
- `increment-metric` now takes metrics map directly (not full state) -- cleaner
- Wait, actually, let's keep it taking full state for consistency with main's pattern. Actually let me reconsider. Main's `increment-metric` takes `(name state)` and returns a new state. scud-lfe45's `increment_metric` takes `(key metrics)` and returns new metrics. With defrecord, the scud-lfe45 approach is cleaner since we can compose with `set-state-metrics`.

Let me use a hybrid: `increment-metric` takes `(name metrics-map)` returns new metrics-map. Callers compose with `set-state-metrics`.

```lfe
(defun increment-metric (name metrics)
  "Increment a named metric counter by 1."
  (let ((current (maps:get name metrics 0)))
    (maps:put name (+ current 1) metrics)))
```

- `build-status` returns flat map (7 fields, no nesting):

```lfe
(defun build-status (state)
  "Build a flat status map for monitoring."
  (let ((metrics (state-metrics state)))
    `#M(timer-heap-size ,(gb_trees:size (state-timer-heap state))
        event-queue-length ,(length (state-event-queue state))
        tick-count ,(maps:get 'tick-count metrics 0)
        events-processed ,(maps:get 'events-processed metrics 0)
        timers-fired ,(maps:get 'timers-fired metrics 0)
        timers-scheduled ,(maps:get 'timers-scheduled metrics 0)
        timers-cancelled ,(maps:get 'timers-cancelled metrics 0))))
```

**Event processing / agent spawning:** Keep main's implementation wholesale, just update to use record accessors and new `increment-metric` signature.

### Success Criteria:

#### Automated Verification:
- [ ] `cd lfe && rebar3 compile` succeeds with no warnings
- [ ] Conductor starts in repl: `(conductor:start_link)` returns `#(ok <pid>)`
- [ ] `(conductor:status)` returns flat map with 7 keys
- [ ] `(conductor:schedule 'test (lambda () 'ok) 5)` succeeds
- [ ] `(conductor:cancel 'test)` succeeds

**Implementation Note**: After completing this phase, verify compilation and basic REPL smoke test before proceeding.

---

## Phase 2: HTTP Handler Upgrades

### Overview
Upgrade webhook-handler and health-handler with body-size limits, proper error codes, and helper functions. Keep webhook-server.lfe's retry logic from main.

### Changes Required:

#### 1. `webhook-handler.lfe`
**File**: `lfe/apps/autopoiesis/src/webhook-handler.lfe`

Adopt scud-lfe45's improvements while keeping main's event normalization:

- Add body-size check (1MB limit, return 413)
- Add `reply-json` and `reply-error` helper functions
- Handle `#(more ...)` partial body reads
- Keep `normalize-event` (converts JSON binary keys to atom-keyed map)
- Keep `conductor:queue-event` call (not `queue_event`)

```lfe
(defmodule webhook-handler
  (export (init 2)))

(defun init (req0 state)
  (case (cowboy_req:method req0)
    (#"POST" (handle-post req0 state))
    (_ (reply-error 405 #"method_not_allowed" req0 state))))

(defun handle-post (req0 state)
  (case (cowboy_req:read_body req0)
    (`#(ok ,body ,req1)
     (if (> (byte_size body) 1048576)
         (reply-error 413 #"payload_too_large" req1 state)
         (case (catch (jsx:decode body '(return_maps)))
           (`#(EXIT ,_reason)
            (reply-error 400 #"invalid_json" req1 state))
           (decoded
            (conductor:queue-event (normalize-event decoded))
            (reply-json 200 (jsx:encode `#M(status #"accepted")) req1 state)))))
    (`#(more ,_body ,req1)
     (reply-error 413 #"payload_too_large" req1 state))))

(defun normalize-event (json-map)
  "Convert JSON map (binary keys) to atom-keyed map for conductor."
  (let ((event-type (maps:get #"type" json-map #"unknown")))
    `#M(type ,(binary_to_atom event-type 'utf8)
        payload ,json-map)))

(defun reply-json (status body req state)
  (let ((req2 (cowboy_req:reply status
                #M(#"content-type" #"application/json")
                body req)))
    `#(ok ,req2 ,state)))

(defun reply-error (status error-key req state)
  (let ((body (iolist_to_binary
                (list #"{\"error\":\"" error-key #"\"}"))))
    (reply-json status body req state)))
```

#### 2. `health-handler.lfe`
**File**: `lfe/apps/autopoiesis/src/health-handler.lfe`

Adopt scud-lfe45's improvements:
- Return 503 (not 200) when conductor is unavailable
- Add degradation logic: "degraded" when tick-count is 0 or queue too large
- Use flat status keys (matching Phase 1's new `build-status`)
- Add `reply-json` helper

```lfe
(defmodule health-handler
  (export (init 2)))

(defun init (req0 state)
  (case (cowboy_req:method req0)
    (#"GET" (handle-get req0 state))
    (_ (reply-error 405 #"method_not_allowed" req0 state))))

(defun handle-get (req0 state)
  (try
    (let* ((cond-status (conductor:status))
           (tick-count (maps:get 'tick-count cond-status 0))
           (queue-length (maps:get 'event-queue-length cond-status 0))
           (health-status (if (and (> tick-count 0) (< queue-length 1000))
                              #"ok"
                              #"degraded"))
           (body (jsx:encode
                   `#M(status ,health-status
                       tick_count ,tick-count
                       event_queue_length ,queue-length
                       events_processed ,(maps:get 'events-processed cond-status 0)
                       timers_fired ,(maps:get 'timers-fired cond-status 0)))))
      (reply-json 200 body req0 state))
    (catch
      (`#(,_type ,_reason ,_stack)
       (let ((body (jsx:encode `#M(status #"error" message #"conductor unavailable"))))
         (reply-json 503 body req0 state))))))

(defun reply-json (status body req state)
  (let ((req2 (cowboy_req:reply status
                #M(#"content-type" #"application/json")
                body req)))
    `#(ok ,req2 ,state)))

(defun reply-error (status error-key req state)
  (let ((body (iolist_to_binary
                (list #"{\"error\":\"" error-key #"\"}"))))
    (reply-json status body req state)))
```

#### 3. `webhook-server.lfe` - Minor touch
**File**: `lfe/apps/autopoiesis/src/webhook-server.lfe`

Keep main's implementation as-is (retry logic on eaddrinuse is good). No changes needed.

### Success Criteria:

#### Automated Verification:
- [ ] `cd lfe && rebar3 compile` succeeds
- [ ] In REPL with app running: `curl http://localhost:4007/health` returns 200 with JSON containing `"status":"ok"`
- [ ] `curl -X POST http://localhost:4007/webhook -d '{"type":"test"}' -H 'Content-Type: application/json'` returns 200
- [ ] `curl -X POST http://localhost:4007/webhook -d 'bad json'` returns 400
- [ ] `curl -X GET http://localhost:4007/webhook` returns 405
- [ ] `curl -X POST http://localhost:4007/health` returns 405

**Implementation Note**: Verify compilation and manual curl tests before proceeding to test rewrite.

---

## Phase 3: Test Rewrite

### Overview
Rewrite conductor-tests.lfe to combine both approaches: standalone `conductor:start_link` for unit tests (faster, isolated) and `with-application` for integration tests. Update connector-tests and boot-tests for new flat status format. Keep agent-worker-tests unchanged.

### Changes Required:

#### 1. `conductor-tests.lfe` - Major rewrite
**File**: `lfe/apps/autopoiesis/test/conductor-tests.lfe`

Structure:
1. **Pure function tests** (no process needed) -- kept from main, updated for new compute-next-run
2. **Standalone conductor tests** (start_link/stop, no full app) -- adapted from scud-lfe45
3. **Integration tests** (`with-application`, full app) -- kept from main, updated for new status format

```
;; Section 1: Pure function tests (no process)
;;   classify_event_* tests -- keep from main as-is
;;   compute_next_run_* tests -- update to use monotonic_time expectations

;; Section 2: Standalone conductor tests (start_link/stop)
;;   conductor_start_stop_test -- from scud-lfe45
;;   conductor_initial_status_test -- verify 7 flat status keys at zero
;;   schedule_convenience_api_test -- test schedule/2 and schedule/3
;;   cancel_action_test -- test cancel/1 with ETS verification
;;   recurring_action_test -- test maybe-reschedule with ETS counter
;;   metrics_status_test -- verify all 7 metrics update correctly
;;   tick_processing_test -- verify tick-count increments

;; Section 3: Integration tests (with-application)
;;   conductor_registered_test -- from main
;;   schedule_and_fire_test -- from main (tests message-passing with full app)
;;   multiple_timers_ordering_test -- from main (tests key collision avoidance)
;;   queue_event_test -- from main
;;   slow_path_graceful_failure_test -- from main

;; Section 4: Helpers
;;   with-conductor/1 -- new: starts/stops conductor only
;;   with-application/1 -- from main: starts/stops full app
;;   assert-truthy/1, assert-equal/1 -- from main
;;   collect-messages/1 -- from main
```

Key changes to existing main tests:
- `conductor_status_test` → rewrite as `conductor_initial_status_test` in standalone section, check 7 flat keys
- `conductor_initial_state_test` → merge into `conductor_initial_status_test`
- `conductor_ticks_test` → rewrite as `tick_processing_test` in standalone section, check `tick-count` (not nested `ticks`)
- `schedule_action_test` → rewrite as `schedule_convenience_api_test` in standalone section, test both `schedule/2` and `schedule/3`, check `timer-heap-size` (not `timer-count`)
- `compute_next_run_*` tests → update: `compute-next-run` now uses monotonic_time, so test against `erlang:monotonic_time 'second` not `erlang:system_time 'second`

New tests from scud-lfe45 patterns (adapted to LFE naming + main's event model):
- `cancel_action_test` -- schedule a 2s timer, cancel immediately, verify it doesn't fire after 2.5s, verify `timers-cancelled >= 1`
- `recurring_action_test` (standalone) -- schedule recurring via map API with `recurring true`, verify fires multiple times via ETS counter
- `metrics_status_test` -- perform schedule + cancel + queue-event, verify all 7 status fields update

New `with-conductor` helper:
```lfe
(defun with-conductor (test-fn)
  "Start/stop conductor in isolation (no full app)."
  (case (conductor:start_link)
    (`#(ok ,pid)
     (try (funcall test-fn)
       (after (gen_server:stop pid)
              (timer:sleep 50))))
    (`#(error ,reason)
     (error `#(conductor-start-failed ,reason)))))
```

#### 2. `boot-tests.lfe` - Update status assertions
**File**: `lfe/apps/autopoiesis/test/boot-tests.lfe`

Minimal changes -- only update tests that inspect conductor status format:
- Any test checking `timer-count` → `timer-heap-size`
- Any test checking nested `metrics` → use flat top-level keys

(Looking at the current boot-tests, they don't actually inspect conductor status -- they check supervisor hierarchy, process registration, and children counts. So **no changes needed** to boot-tests.)

#### 3. `connector-tests.lfe` - Update health response assertions
**File**: `lfe/apps/autopoiesis/test/connector-tests.lfe`

Update `health_endpoint_test` to check for the new response format:
- Status is `#"ok"` (unchanged)
- Response now includes `tick_count`, `event_queue_length`, etc. (just verify status key exists, don't over-assert)

Also add test for 413 payload too large on webhook:

```lfe
(defun webhook_large_payload_test ()
  "POST /webhook with >1MB body should return 413."
  (with-running-app
    (lambda ()
      (let ((big-body (binary_to_list (binary:copy #"x" 1048577))))
        (case (httpc:request 'post
                `#("http://localhost:4007/webhook"
                   ()
                   "application/json"
                   ,big-body) "" '())
          (`#(ok #(,status-line ,_headers ,_body))
           (let ((`#(,_ver ,code ,_reason) status-line))
             (assert-equal 413 code)))
          (`#(error ,reason)
           (error `#(http-request-failed ,reason))))))))
```

#### 4. `agent-worker-tests.lfe` - No changes
Already works correctly, 23 tests.

### Success Criteria:

#### Automated Verification:
- [ ] `cd lfe && rebar3 compile` succeeds
- [ ] `cd lfe && rebar3 eunit --module=conductor-tests` -- all pass, 0 failures
- [ ] `cd lfe && rebar3 eunit --module=boot-tests` -- all pass, 0 failures
- [ ] `cd lfe && rebar3 eunit --module=connector-tests` -- all pass, 0 failures
- [ ] `cd lfe && rebar3 eunit --module=agent-worker-tests` -- all pass, 0 failures
- [ ] `cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests` -- all pass, 0 failures, total should be >= 56 tests (likely ~65+ with new cancel/recurring/metrics tests)

#### Manual Verification:
- [ ] Review that all conductor-tests follow both patterns: some use `with-conductor` (standalone), some use `with-application` (full app)
- [ ] Verify no tests have timing flakiness (adequate sleep durations, reasonable timeouts)

---

## Testing Strategy

### Unit Tests (standalone conductor):
- Pure function tests: classify-event, compute-next-run
- Standalone lifecycle: start/stop, initial status, tick processing
- Scheduling: convenience API (schedule/2, schedule/3), cancel, recurring
- Metrics: all 7 counters update correctly

### Integration Tests (with-application):
- Conductor registration in supervision tree
- Timer firing with message passing
- Multiple timer key collision avoidance
- Event queue processing (fast-path)
- Slow-path graceful failure (agent spawn)
- HTTP health endpoint (200 ok, 405 wrong method)
- HTTP webhook endpoint (200 accepted, 400 bad json, 405 wrong method, 413 too large)
- Application boot, supervisor hierarchy, double-boot resilience

### Unchanged:
- agent-worker-tests: 23 pure function tests for build-cl-command, parse-cl-response
- boot-tests: 11 integration tests for app lifecycle, supervisor tree

## References

- Main implementation: `lfe/apps/autopoiesis/src/` (9 modules, 727 LOC)
- scud-lfe45 implementation: `../ap-worktrees/scud-lfe45/lfe/apps/autopoiesis/src/` (11 modules, 546 LOC)
- Previous plan: `thoughts/shared/plans/2026-02-05-phase3-phase4-conductor-connectors.md`
