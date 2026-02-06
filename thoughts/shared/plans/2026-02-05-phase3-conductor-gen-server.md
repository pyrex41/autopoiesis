# Phase 3: Conductor Gen_Server — Detailed Implementation Plan

## Parent Plan

`thoughts/shared/plans/2026-02-04-lfe-supervised-agent-platform.md` — Phase 3

## Goal

Create the conductor — a tick-based event loop gen_server that drives the system. It maintains a timer heap for scheduled actions, routes external events through fast-path (direct execution) or slow-path (agent spawn), and reports metrics. The conductor is the central orchestration point that connectors (Phase 4) and project definitions (Phase 5) will plug into.

## Prerequisites

- Phase 2 complete: OTP application boots with `autopoiesis-sup` → `agent-sup` + `connector-sup`
- All Phase 2 tests passing (32 tests, 0 failures)

## Corrections from Master Plan

The master plan (`2026-02-04-lfe-supervised-agent-platform.md`, lines 630–860) has several issues this plan corrects:

### 1. uuid dependency unnecessary

The master plan uses `uuid:get_v4()` for agent IDs. This adds an external dependency for something trivial. Use `erlang:unique_integer([positive, monotonic])` with a prefix string instead. No new dep needed.

### 2. gb_trees key collision

The master plan uses Unix seconds as gb_trees keys. Two actions scheduled for the same second would collide (`gb_trees:insert` fails on duplicate keys). Fix: use `{Time, UniqueRef}` tuple keys. Erlang tuple comparison is lexicographic, so sorting by time still works. Use `gb_trees:take_smallest/1` which returns `{Key, Value, NewTree}` for clean extraction.

### 3. Logging: logger not lager

Consistent with Phase 2 correction. Use OTP `logger` throughout.

### 4. Map access: maps:get/maps:put not mref/mset

Consistent with Phase 2 correction. The `mref` 3-arg default form doesn't exist; `mset` behavior is uncertain across LFE versions. Use `maps:get/2`, `maps:get/3`, and `maps:put/3` explicitly.

### 5. Unused state fields

The master plan defines `agents #m()` in conductor state but never populates it. Agent tracking is `agent-sup`'s job. Removed from conductor state.

### 6. Metrics never incremented

The master plan defines `events-processed` and `cycles-run` metrics but only increments `ticks`. This plan increments all relevant metrics at the point of action.

### 7. Agent spawn failure handling

The CL worker script (Phase 1 task 10.2) isn't wired up yet. `agent-sup:spawn-agent` will fail when there's no SBCL process. The conductor must catch spawn failures, log them, and continue operating. This makes the conductor testable independently.

---

## Desired End State

After Phase 3:

1. `rebar3 lfe compile` succeeds with conductor module
2. Application boots with conductor in the supervisor tree
3. `(conductor:status)` returns metrics and queue sizes
4. `(conductor:schedule Action)` adds timed actions that fire correctly
5. `(conductor:queue-event Event)` queues events for next tick processing
6. Fast-path events execute directly; slow-path events attempt agent spawn (with graceful failure handling)
7. Tick counter increments at ~10/second
8. All existing tests still pass; new conductor tests pass

### Verification

```lfe
;; In rebar3 lfe repl:
(application:ensure_all_started 'autopoiesis)
;; => #(ok (...))

(erlang:whereis 'conductor)
;; => <0.xxx.0>

(conductor:status)
;; => #M(timer-count 0 event-queue-length 0 metrics #M(ticks N ...))

;; Schedule a fast-path action that fires in 1 second
(conductor:schedule #M(id test-1 interval 1 recurring false requires-llm false
                       action (lambda () (logger:info "Timer fired!"))))
;; Wait 2 seconds...
(conductor:status)
;; => metrics show timers-fired >= 1
```

---

## What We're NOT Doing in Phase 3

- **Connectors**: No webhook server, no MCP server — that's Phase 4
- **Project loader**: No config-driven agent spawning — that's Phase 5
- **Cron parsing**: Scheduled actions use interval-based timing only (no cron expressions)
- **Agent result tracking**: Conductor doesn't track individual agent outcomes
- **Process monitoring**: Conductor doesn't `erlang:monitor` spawned agents (supervisor handles restarts)
- **Persistent timers**: Timer heap is in-memory only; lost on restart (acceptable for now)

---

## Directory Changes

```
lfe/apps/autopoiesis/src/
├── autopoiesis.app.src           # MODIFIED: add conductor to registered list
├── autopoiesis-app.lfe           # unchanged
├── autopoiesis-sup.lfe           # MODIFIED: add conductor child spec
├── agent-sup.lfe                 # unchanged
├── agent-worker.lfe              # unchanged
├── connector-sup.lfe             # unchanged
└── conductor.lfe                 # NEW: conductor gen_server

lfe/apps/autopoiesis/test/
├── agent-worker-tests.lfe        # unchanged
├── boot-tests.lfe                # MODIFIED: expect conductor in supervisor
└── conductor-tests.lfe           # NEW: conductor unit + integration tests
```

---

## Task Breakdown

### Task 1: Create conductor.lfe gen_server skeleton

**Why**: Everything else depends on the core module existing.

**File**: `lfe/apps/autopoiesis/src/conductor.lfe` (new)

```lfe
(defmodule conductor
  (behaviour gen_server)
  (export (start_link 0) (init 1)
          (handle_call 3) (handle_cast 2) (handle_info 2)
          (terminate 2) (code_change 3))
  ;; Client API
  (export (schedule 1) (queue-event 1) (status 0))
  ;; Exported for testing
  (export (classify-event 1) (compute-next-run 1)))

;;; ============================================================
;;; Client API
;;; ============================================================

(defun start_link ()
  (gen_server:start_link #(local conductor) 'conductor '() '()))

(defun schedule (action)
  "Schedule a timer-based action.
   Action is a map with keys: id, interval, recurring, requires-llm, action."
  (gen_server:cast 'conductor `#(schedule ,action)))

(defun queue-event (event)
  "Queue an external event for next tick processing.
   Event is a map with at minimum a 'type key."
  (gen_server:cast 'conductor `#(event ,event)))

(defun status ()
  "Get conductor status: timer count, queue length, metrics."
  (gen_server:call 'conductor 'status 5000))

;;; ============================================================
;;; gen_server callbacks
;;; ============================================================

(defun init (_args)
  ;; Start the tick timer
  (erlang:send_after 100 (self) 'tick)
  `#(ok #M(timer-heap ,(gb_trees:empty)
           event-queue ()
           metrics #M(ticks 0
                      events-processed 0
                      timers-fired 0))))

(defun handle_call
  (('status _from state)
   `#(reply ,(build-status state) ,state))
  ((msg _from state)
   `#(reply #(error #(unknown-call ,msg)) ,state)))

(defun handle_cast
  ;; Schedule a timer-based action
  ((`#(schedule ,action) state)
   (let* ((next-time (compute-next-run action))
          (ref (erlang:unique_integer '(positive monotonic)))
          (key `#(,next-time ,ref))
          (heap (maps:get 'timer-heap state))
          (new-heap (gb_trees:insert key action heap)))
     `#(noreply ,(maps:put 'timer-heap new-heap state))))

  ;; Queue an external event
  ((`#(event ,event) state)
   (let ((queue (maps:get 'event-queue state)))
     `#(noreply ,(maps:put 'event-queue (++ queue (list event)) state))))

  ((_msg state)
   `#(noreply ,state)))

(defun handle_info
  ;; Main tick — the heartbeat of the system
  (('tick state)
   (let* ((state2 (process-due-timers state))
          (state3 (process-events state2))
          (state4 (increment-metric 'ticks state3)))
     ;; Schedule next tick
     (erlang:send_after 100 (self) 'tick)
     `#(noreply ,state4)))

  ((_msg state)
   `#(noreply ,state)))

(defun terminate (_reason _state)
  'ok)

(defun code_change (_old-vsn state _extra)
  `#(ok ,state))

;;; ============================================================
;;; Timer heap processing
;;; ============================================================

(defun process-due-timers (state)
  "Pop and execute all timers whose time has come."
  (let ((now (erlang:system_time 'second))
        (heap (maps:get 'timer-heap state)))
    (process-due-timers-loop now heap state)))

(defun process-due-timers-loop (now heap state)
  (case (gb_trees:is_empty heap)
    ('true
     (maps:put 'timer-heap heap state))
    ('false
     (let ((`#(#(,time ,_ref) ,action) (gb_trees:smallest heap)))
       (if (=< time now)
           (let* ((`#(,_key ,_val ,heap2) (gb_trees:take_smallest heap))
                  (state2 (execute-timer-action action state))
                  (heap3 (maybe-reschedule action heap2))
                  (state3 (increment-metric 'timers-fired state2)))
             (process-due-timers-loop now heap3 state3))
           ;; Next timer is in the future — done for this tick
           (maps:put 'timer-heap heap state))))))

(defun execute-timer-action (action state)
  "Execute a scheduled action. Fast-path runs directly; slow-path spawns agent."
  (case (maps:get 'requires-llm action 'false)
    ('true
     (spawn-agent-for-work action)
     state)
    ('false
     (case (maps:get 'action action 'undefined)
       ('undefined state)
       (func
        (try (funcall func)
          (catch
            (`#(,type ,reason ,_stack)
             (logger:warning "Timer action ~p failed: ~p:~p"
                             (list (maps:get 'id action 'unknown)
                                   type reason)))))
        state)))))

(defun compute-next-run (action)
  "Compute the next Unix timestamp when this action should fire."
  (let ((now (erlang:system_time 'second))
        (interval (maps:get 'interval action 60)))
    (+ now interval)))

(defun maybe-reschedule (action heap)
  "If the action is recurring, re-insert it into the heap."
  (case (maps:get 'recurring action 'false)
    ('true
     (let* ((next-time (compute-next-run action))
            (ref (erlang:unique_integer '(positive monotonic)))
            (key `#(,next-time ,ref)))
       (gb_trees:insert key action heap)))
    (_
     heap)))

;;; ============================================================
;;; Event processing
;;; ============================================================

(defun process-events (state)
  "Drain the event queue, processing each event."
  (let ((events (maps:get 'event-queue state)))
    (process-events-loop events state)))

(defun process-events-loop (events state)
  (case events
    ('()
     (maps:put 'event-queue '() state))
    ((cons event rest)
     (let ((state2 (process-single-event event state)))
       (process-events-loop rest state2)))))

(defun process-single-event (event state)
  "Classify and process a single event."
  (let ((work-item (classify-event event)))
    (case (maps:get 'requires-llm work-item)
      ('true
       (spawn-agent-for-work work-item)
       (increment-metric 'events-processed state))
      ('false
       (execute-fast-path work-item)
       (increment-metric 'events-processed state)))))

(defun classify-event (event)
  "Classify an event as fast-path or slow-path based on its type."
  (let ((event-type (maps:get 'type event 'unknown)))
    (case event-type
      ('health-check
       #M(type health-check requires-llm false payload event))
      ('metric-update
       #M(type metric-update requires-llm false payload event))
      ('ping
       #M(type ping requires-llm false payload event))
      ;; Unknown or complex events go to slow path
      (_
       #M(type event-type requires-llm true payload event)))))

(defun execute-fast-path (work-item)
  "Execute a fast-path work item synchronously."
  (case (maps:get 'type work-item)
    ('health-check
     (logger:debug "Health check processed"))
    ('metric-update
     (logger:debug "Metric update processed"))
    ('ping
     (logger:debug "Ping processed"))
    (type
     (logger:warning "Unknown fast-path type: ~p" (list type))))
  'ok)

;;; ============================================================
;;; Agent spawning (slow path)
;;; ============================================================

(defun spawn-agent-for-work (work-item)
  "Attempt to spawn an agent worker for slow-path work.
   Handles failure gracefully since the CL worker may not be available."
  (let ((agent-id (make-agent-id)))
    (case (catch (agent-sup:spawn-agent
                   #M(agent-id agent-id
                      name agent-id
                      task work-item)))
      (`#(ok ,pid)
       (logger:info "Spawned agent ~s (pid ~p) for ~p"
                    (list agent-id pid (maps:get 'type work-item)))
       `#(ok ,pid))
      (`#(EXIT ,reason)
       (logger:warning "Failed to spawn agent for ~p: ~p"
                       (list (maps:get 'type work-item) reason))
       `#(error ,reason))
      (`#(error ,reason)
       (logger:warning "Failed to spawn agent for ~p: ~p"
                       (list (maps:get 'type work-item) reason))
       `#(error ,reason)))))

(defun make-agent-id ()
  "Generate a unique agent ID string."
  (let ((n (erlang:unique_integer '(positive))))
    (lists:flatten (io_lib:format "agent-~B" (list n)))))

;;; ============================================================
;;; Metrics and status
;;; ============================================================

(defun increment-metric (name state)
  "Increment a named metric counter by 1."
  (let* ((metrics (maps:get 'metrics state))
         (current (maps:get name metrics 0))
         (new-metrics (maps:put name (+ current 1) metrics)))
    (maps:put 'metrics new-metrics state)))

(defun build-status (state)
  "Build a status map for monitoring."
  #M(timer-count (gb_trees:size (maps:get 'timer-heap state))
     event-queue-length (length (maps:get 'event-queue state))
     metrics (maps:get 'metrics state)))
```

**Depends on**: Nothing (new file)

**Success**: `rebar3 lfe compile` succeeds with conductor module.

---

### Task 2: Add conductor to supervisor tree

**Why**: The conductor must be supervised to run as part of the application.

#### File: `lfe/apps/autopoiesis/src/autopoiesis-sup.lfe`

**Changes**: Add conductor-spec child and include it in children list.

The conductor starts **before** agent-sup and connector-sup in the children list. This is intentional: if agent-sup or connector-sup need to send events to the conductor, it must already be running. Children start in list order.

```lfe
(defun init (_args)
  (let* ((sup-flags #M(strategy one_for_one
                       intensity 5
                       period 10))
         (children (list (conductor-spec)
                         (agent-sup-spec)
                         (connector-sup-spec))))
    `#(ok #(,sup-flags ,children))))

;; Add this function:
(defun conductor-spec ()
  #M(id conductor
     start #(conductor start_link ())
     restart permanent
     shutdown 5000
     type worker
     modules (conductor)))
```

#### File: `lfe/apps/autopoiesis/src/autopoiesis.app.src`

**Changes**: Add `conductor` to the `registered` list.

```erlang
{application,autopoiesis,
             [{description,"Autopoiesis - Self-configuring agent platform"},
              {vsn,"0.1.0"},
              {registered,[conductor]},
              {applications,[kernel,stdlib,lfe]},
              {mod,{'autopoiesis-app',[]}},
              {env,[]}]}.
```

**Depends on**: Task 1

**Success**: Application boots with conductor in the supervisor tree. `(erlang:whereis 'conductor)` returns a pid.

---

### Task 3: Write conductor unit tests

**Why**: Validate conductor behavior in isolation before integration testing.

**File**: `lfe/apps/autopoiesis/test/conductor-tests.lfe` (new)

Tests are organized into groups:

#### Pure function tests (no application needed)
- `classify_event_health_check_test` — health-check → fast-path
- `classify_event_metric_update_test` — metric-update → fast-path
- `classify_event_ping_test` — ping → fast-path
- `classify_event_unknown_test` — unknown type → slow-path
- `classify_event_missing_type_test` — no type key → slow-path
- `compute_next_run_interval_test` — interval added to current time
- `compute_next_run_default_test` — missing interval defaults to 60s

#### Gen_server behavior tests (application running)
- `conductor_registered_test` — conductor process is registered
- `conductor_status_test` — status returns valid map with expected keys
- `conductor_ticks_test` — tick counter increments over time
- `schedule_action_test` — scheduling adds to timer count
- `schedule_and_fire_test` — action with interval=0 fires within 1 tick
- `queue_event_test` — queuing event adds to queue (processed next tick)
- `event_processed_test` — fast-path event increments events-processed metric
- `recurring_action_test` — recurring action fires multiple times
- `fast_path_no_spawn_test` — fast-path events don't increase agent count
- `slow_path_graceful_failure_test` — slow-path spawn failure doesn't crash conductor

```lfe
(defmodule conductor-tests
  (export all))

;;; EUnit tests for conductor gen_server.
;;; Run with: rebar3 eunit --module=conductor-tests

;;; ============================================================
;;; Pure function tests (no application needed)
;;; ============================================================

(defun classify_event_health_check_test ()
  "Health check events should be fast-path."
  (let ((result (conductor:classify-event #M(type health-check))))
    (assert-equal 'false (maps:get 'requires-llm result))
    (assert-equal 'health-check (maps:get 'type result))))

(defun classify_event_metric_update_test ()
  "Metric update events should be fast-path."
  (let ((result (conductor:classify-event #M(type metric-update))))
    (assert-equal 'false (maps:get 'requires-llm result))))

(defun classify_event_ping_test ()
  "Ping events should be fast-path."
  (let ((result (conductor:classify-event #M(type ping))))
    (assert-equal 'false (maps:get 'requires-llm result))))

(defun classify_event_unknown_test ()
  "Unknown event types should be slow-path."
  (let ((result (conductor:classify-event #M(type something-complex))))
    (assert-equal 'true (maps:get 'requires-llm result))))

(defun classify_event_missing_type_test ()
  "Events without a type key should be slow-path."
  (let ((result (conductor:classify-event #M(data some-payload))))
    (assert-equal 'true (maps:get 'requires-llm result))))

(defun compute_next_run_interval_test ()
  "compute-next-run should add interval to current time."
  (let* ((now (erlang:system_time 'second))
         (result (conductor:compute-next-run #M(interval 30))))
    ;; Result should be approximately now + 30 (allow 2 second tolerance)
    (assert-truthy (>= result (+ now 29)))
    (assert-truthy (=< result (+ now 32)))))

(defun compute_next_run_default_test ()
  "compute-next-run should default to 60 seconds if no interval."
  (let* ((now (erlang:system_time 'second))
         (result (conductor:compute-next-run #M(id no-interval))))
    (assert-truthy (>= result (+ now 59)))
    (assert-truthy (=< result (+ now 62)))))

;;; ============================================================
;;; Gen_server behavior tests (require application running)
;;; ============================================================

(defun conductor_registered_test ()
  "Conductor should be registered after app boot."
  (with-application
    (lambda ()
      (let ((pid (erlang:whereis 'conductor)))
        (assert-truthy (is_pid pid))
        (assert-truthy (is_process_alive pid))))))

(defun conductor_status_test ()
  "Status should return a map with expected keys."
  (with-application
    (lambda ()
      (let ((status (conductor:status)))
        (assert-truthy (is_map status))
        (assert-truthy (is_integer (maps:get 'timer-count status)))
        (assert-truthy (is_integer (maps:get 'event-queue-length status)))
        (assert-truthy (is_map (maps:get 'metrics status)))))))

(defun conductor_initial_state_test ()
  "Initial state should have zero timers, empty queue, zero metrics."
  (with-application
    (lambda ()
      (let ((status (conductor:status)))
        (assert-equal 0 (maps:get 'timer-count status))
        (assert-equal 0 (maps:get 'event-queue-length status))
        (let ((metrics (maps:get 'metrics status)))
          (assert-equal 0 (maps:get 'events-processed metrics))
          (assert-equal 0 (maps:get 'timers-fired metrics)))))))

(defun conductor_ticks_test ()
  "Tick counter should increment over time."
  (with-application
    (lambda ()
      (let* ((status1 (conductor:status))
             (ticks1 (maps:get 'ticks (maps:get 'metrics status1))))
        ;; Wait 250ms (~2 ticks at 100ms interval)
        (timer:sleep 250)
        (let* ((status2 (conductor:status))
               (ticks2 (maps:get 'ticks (maps:get 'metrics status2))))
          (assert-truthy (> ticks2 ticks1)))))))

(defun schedule_action_test ()
  "Scheduling an action should increase timer count."
  (with-application
    (lambda ()
      (let ((status1 (conductor:status)))
        (assert-equal 0 (maps:get 'timer-count status1))
        ;; Schedule a future action (10 seconds from now)
        (conductor:schedule #M(id test-timer
                               interval 10
                               recurring false
                               requires-llm false))
        ;; Small delay for cast to process
        (timer:sleep 50)
        (let ((status2 (conductor:status)))
          (assert-equal 1 (maps:get 'timer-count status2)))))))

(defun schedule_and_fire_test ()
  "Action with interval=0 should fire within one tick cycle."
  (with-application
    (lambda ()
      ;; Use a process dictionary flag to detect firing
      (let ((test-pid (self)))
        (conductor:schedule
          #M(id fire-now
             interval 0
             recurring false
             requires-llm false
             action (lambda () (erlang:send test-pid 'timer-fired))))
        ;; Wait for up to 500ms for the timer to fire
        (receive
          ('timer-fired (assert-truthy 'true))
          (after 500
            (error 'timer-did-not-fire)))))))

(defun queue_event_test ()
  "Queuing a fast-path event should process it on next tick."
  (with-application
    (lambda ()
      (conductor:queue-event #M(type health-check))
      ;; Wait for tick to process
      (timer:sleep 200)
      (let* ((status (conductor:status))
             (metrics (maps:get 'metrics status)))
        (assert-truthy (>= (maps:get 'events-processed metrics) 1))))))

(defun recurring_action_test ()
  "Recurring action should fire multiple times."
  (with-application
    (lambda ()
      (let ((test-pid (self))
            (counter (erlang:make_ref)))
        ;; Schedule recurring action every 0 seconds (fires each tick)
        (conductor:schedule
          #M(id recurring-test
             interval 0
             recurring true
             requires-llm false
             action (lambda () (erlang:send test-pid 'recurring-tick))))
        ;; Collect at least 2 firings within 500ms
        (receive ('recurring-tick 'ok) (after 500 (error 'first-tick-timeout)))
        (receive ('recurring-tick 'ok) (after 500 (error 'second-tick-timeout)))
        ;; If we got here, recurring works
        (assert-truthy 'true)))))

(defun slow_path_graceful_failure_test ()
  "Slow-path spawn failure should not crash conductor."
  (with-application
    (lambda ()
      (let ((conductor-pid (erlang:whereis 'conductor)))
        ;; Queue an event that triggers slow-path (unknown type)
        (conductor:queue-event #M(type needs-llm-processing data test))
        ;; Wait for processing
        (timer:sleep 200)
        ;; Conductor should still be alive (spawn failure was caught)
        (assert-truthy (is_process_alive conductor-pid))
        ;; And still responding
        (let ((status (conductor:status)))
          (assert-truthy (is_map status)))))))

(defun multiple_timers_ordering_test ()
  "Multiple timers should fire in chronological order."
  (with-application
    (lambda ()
      (let ((test-pid (self)))
        ;; Schedule two timers: one at 0s, one at 0s (both immediate)
        ;; Both should fire, proving no key collision
        (conductor:schedule
          #M(id timer-a interval 0 recurring false requires-llm false
             action (lambda () (erlang:send test-pid #(fired a)))))
        (conductor:schedule
          #M(id timer-b interval 0 recurring false requires-llm false
             action (lambda () (erlang:send test-pid #(fired b)))))
        ;; Both should fire within 500ms
        (let ((results (collect-messages test-pid 500)))
          (assert-truthy (>= (length results) 2)))))))

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun with-application (test-fn)
  "Execute a test function with the application running, ensuring cleanup."
  (try
    (progn
      (application:stop 'autopoiesis)
      (case (application:ensure_all_started 'autopoiesis)
        (`#(ok ,_apps)
         (funcall test-fn))
        (`#(error ,reason)
         (error `#(setup-failed ,reason))))
      (application:stop 'autopoiesis))
    (catch
      (`#(,type ,reason ,_stack)
       (application:stop 'autopoiesis)
       (error `#(test-exception ,type ,reason))))))

(defun assert-truthy (val)
  "Assert value is truthy."
  (case val
    ('false (error 'assertion-failed))
    ('undefined (error 'assertion-failed))
    (_ 'ok)))

(defun assert-equal (expected actual)
  "Assert expected equals actual."
  (case (== expected actual)
    ('true 'ok)
    ('false (error `#(assertion-failed expected ,expected actual ,actual)))))

(defun collect-messages (pid timeout)
  "Collect all messages sent to pid within timeout."
  (collect-messages-loop '() timeout))

(defun collect-messages-loop (acc timeout)
  (receive
    (msg (collect-messages-loop (++ acc (list msg)) timeout))
    (after timeout
      acc)))
```

**Depends on**: Task 1

**Success**: `rebar3 eunit --module=conductor-tests` passes all tests.

---

### Task 4: Update boot-tests for conductor in supervisor tree

**Why**: The existing boot tests verify the supervisor structure. After adding conductor, they need updating.

**File**: `lfe/apps/autopoiesis/test/boot-tests.lfe`

**Changes**:

1. `supervisors_running_test` — add conductor check: `(assert-supervisor-running 'conductor)` → actually conductor is a worker not a supervisor. Need a new assertion or just check `whereis`.

2. `all_supervisors_registered_test` (if it exists) — add `conductor` to expected list. Note: conductor is a worker, not a supervisor. Rename or adjust the test.

3. `supervisor_children_test` — expect 3 children (conductor, agent-sup, connector-sup) instead of 2.

4. `supervisor_strategy_test` — optionally verify conductor is a worker (not supervisor).

Specific modifications:

- In `supervisors_running_test`: add `(assert-process-running 'conductor)` where `assert-process-running` checks `whereis` + `is_process_alive` (conductor is a worker, not a supervisor, so `supervisor:which_children` won't work on it)
- In `all_supervisors_registered_test`: add conductor to expected names
- In `supervisor_children_test`: change `(assert-equal 2 (length children))` to `(assert-equal 3 (length children))` and add `(assert-truthy (has-child-id 'conductor children))`

Add a new helper:
```lfe
(defun assert-process-running (name)
  "Assert a process with given name is running and registered."
  (case (whereis name)
    ('undefined
     (error `#(process-not-registered ,name)))
    (pid
     (assert-truthy (is_process_alive pid)))))
```

**Depends on**: Task 2

**Success**: `rebar3 eunit --module=boot-tests` passes with updated expectations.

---

### Task 5: Integration test — conductor in running system

**Why**: Verify the conductor works correctly as part of the full application.

This is covered by the gen_server behavior tests in Task 3 (conductor-tests.lfe). Those tests use `with-application` to boot the full app. No separate test file needed.

The integration aspects verified:
- Conductor starts as part of application boot
- Status API works through gen_server call
- Timer scheduling works end-to-end
- Event processing works end-to-end
- Spawn failure doesn't cascade
- Conductor survives across multiple ticks

**Depends on**: Tasks 2, 3, 4

**Success**: All conductor-tests and boot-tests pass together:
```bash
rebar3 eunit --dir=apps/autopoiesis/test
```

---

## Task Dependency Graph

```
Task 1: conductor.lfe (new module)
  ├──► Task 2: Add to supervisor tree ──► Task 4: Update boot-tests
  └──► Task 3: Conductor unit tests       │
                │                          │
                └──────────┬───────────────┘
                           ▼
                    Task 5: Full integration
                    (all tests pass together)
```

## SCUD Waves

- **Wave 1**: Task 1 (create conductor.lfe) — must be first
- **Wave 2**: Tasks 2 + 3 (supervisor integration + unit tests) — parallel, both depend only on Task 1
- **Wave 3**: Task 4 (update boot-tests) — depends on Task 2
- **Wave 4**: Task 5 (full integration verification) — depends on everything

## SCUD Task Definitions

For import into `.scud/tasks/tasks.scg` as a new tag or appended to lfe2:

```
# Phase 3 tasks
11 | Create conductor.lfe gen_server | P | 5 | H
12 | Add conductor to supervisor tree | P | 2 | H
13 | Write conductor unit tests | P | 3 | H
14 | Update boot-tests for conductor | P | 2 | M
15 | Integration test: all tests pass | P | 1 | H

# Edges
12 -> 11
13 -> 11
14 -> 12
15 -> 13
15 -> 14

# Agents
11 | builder
12 | fast-builder
13 | tester
14 | tester
15 | tester
```

---

## Testing Strategy

### Unit Tests (conductor-tests.lfe)
- Pure function tests: classify-event, compute-next-run (no app needed)
- Gen_server tests: status, scheduling, event processing (app running)
- Edge cases: missing keys, unknown types, spawn failures, key collision

### Updated Tests (boot-tests.lfe)
- Supervisor tree now includes conductor
- 3 children instead of 2
- Conductor is registered and alive

### Integration Verification
```bash
# All tests together
rebar3 eunit --dir=apps/autopoiesis/test

# Just conductor
rebar3 eunit --module=conductor-tests

# Just boot verification
rebar3 eunit --module=boot-tests
```

### Manual Verification
```lfe
;; In rebar3 lfe repl:
(application:ensure_all_started 'autopoiesis)

;; Check conductor is running
(erlang:whereis 'conductor)

;; Check status
(conductor:status)

;; Schedule an action
(conductor:schedule #M(id test interval 2 recurring false requires-llm false
                       action (lambda () (logger:info "Fired!"))))

;; Wait 3 seconds, check metrics
(conductor:status)
;; timers-fired should be >= 1

;; Queue events
(conductor:queue-event #M(type health-check))
(conductor:queue-event #M(type needs-llm data test))

;; Wait 1 second, check metrics
(conductor:status)
;; events-processed should be >= 2
```

## Performance Considerations

- **Tick interval**: 100ms = 10 ticks/second. On BEAM this is negligible overhead.
- **Timer heap**: gb_trees is O(log n) for all operations. Fine for hundreds of timers.
- **Event queue**: List append is O(n). For thousands of events per tick, consider a queue module. For Phase 3 this is fine.
- **Spawn overhead**: Each slow-path event spawns a process. OTP processes are cheap (~300 bytes). The real cost is the SBCL port startup (~2-3 seconds). But since spawns fail gracefully in Phase 3, this isn't an issue yet.

## References

- Master plan: `thoughts/shared/plans/2026-02-04-lfe-supervised-agent-platform.md` (Phase 3, lines 630–860)
- Phase 2 plan: `thoughts/shared/plans/2026-02-05-phase2-lfe-project-skeleton.md`
- Research: `thoughts/shared/research/2026-02-04-lfe-beam-agent-supervision.md`
- OTP gb_trees docs: https://www.erlang.org/doc/apps/stdlib/gb_trees.html
