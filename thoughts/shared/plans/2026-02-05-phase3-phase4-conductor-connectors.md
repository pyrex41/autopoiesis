# Phase 3 & 4: Conductor Gen_Server and HTTP Connectors — Detailed Implementation Plan

## Parent Plan

`thoughts/shared/plans/2026-02-04-lfe-supervised-agent-platform.md` — Phases 3 & 4

## Goal

Phase 3: Create the conductor gen_server — the always-running event loop that maintains a timer heap, routes events, dispatches work to agents, and drives the whole system with a 100ms tick.

Phase 4: Add HTTP connectors under connector-sup — a cowboy-based webhook server that ingests external events and routes them to the conductor, plus a health endpoint.

## Prerequisites

- Phase 2 complete: LFE project skeleton compiles, OTP application boots with supervision tree
- `autopoiesis-sup` running with `agent-sup` and `connector-sup` children
- `agent-worker` gen_server functional with port communication to CL

## Corrections from Master Plan

The master plan (Phase 3 section) has several inaccuracies corrected here:

### 1. gb_trees:insert crashes on duplicate keys

The master plan uses timestamps as keys: `(gb_trees:insert next-time action timer-heap)`. But `gb_trees:insert/3` **crashes** if the key already exists. Two actions scheduled at the same millisecond would crash the conductor.

**Fix**: Use composite keys `#(timestamp action-id)` where action-id is a monotonic integer. Erlang's term ordering sorts tuples element-by-element, so chronological order is preserved.

### 2. Use erlang:send_after, not timer:send_interval

`timer:send_interval` creates a recurring timer that sends messages at fixed intervals regardless of processing time. If a tick takes >100ms, messages pile up. `erlang:send_after` lets us reschedule after processing, providing natural backpressure.

### 3. uuid:get_v4 doesn't exist

The master plan uses `(binary_to_list (uuid:get_v4))` for agent IDs. There's no `uuid` module in our deps. Use `(erlang:unique_integer '(monotonic positive))` instead.

### 4. logger instead of lager (consistent with Phase 2)

Replace all `lager:info/warning/error` with `logger:info/warning/error`.

### 5. Map syntax: #M(...) uppercase (consistent with Phase 2)

Use `#M(...)` not `#m(...)`.

### 6. maps:get instead of mref (consistent with Phase 2)

Use `(maps:get 'key map)` and `(maps:get 'key map default)`.

### 7. Cowboy version: 2.14.2 (not 2.10.0)

The master plan specifies cowboy 2.10.0. Current stable is 2.14.2.

### 8. No MCP server in Phase 4

The master plan bundles MCP server with webhook server. MCP stdio server is significantly more complex (JSON-RPC protocol, bidirectional communication). Defer to a later phase. Phase 4 focuses only on HTTP webhook + health.

---

## Desired End State

After Phase 3 + 4 are complete:

1. `(application:ensure_all_started 'autopoiesis)` boots the full supervision tree including the conductor
2. `(conductor:status)` returns a map with timer count, event queue length, and metrics
3. `(conductor:schedule ...)` adds a scheduled action to the timer heap
4. `(conductor:queue-event ...)` queues an external event for processing
5. Tick processing runs every ~100ms (observable via metrics counter)
6. Scheduled actions fire at correct times and execute their callbacks
7. `curl -X POST localhost:4007/webhook -d '{"type":"test"}'` returns 200 and the event appears in conductor's queue
8. `curl localhost:4007/health` returns 200 with status JSON
9. Killing the conductor causes `autopoiesis-sup` to restart it
10. Webhook server survives malformed JSON (returns 400, doesn't crash)

### Verification

```bash
# Phase 3
cd lfe && rebar3 lfe compile                  # compiles without errors
cd lfe && rebar3 eunit                         # all tests pass

# Phase 4
curl -s localhost:4007/health | jq .           # returns {"status":"ok",...}
curl -s -X POST localhost:4007/webhook \
  -H 'Content-Type: application/json' \
  -d '{"type":"alert","severity":"warning"}'   # returns {"status":"accepted"}
```

## What We're NOT Doing

- **Not implementing the MCP stdio server** — deferred to a later phase
- **Not implementing the project definition format** — that's Phase 5
- **Not spawning agents from the conductor** — conductor can queue events and fire timers, but agent spawning integration comes in Phase 5 when project definitions specify which agents to run
- **Not implementing cron parsing** — scheduled actions use interval-based scheduling only. Cron expressions are a nice-to-have for later.
- **Not adding Cortex integration** — the conductor's event queue accepts events from any source, but the Cortex ZMQ bridge is a separate effort
- **Not implementing the blackboard** — ephemeral shared state is Phase 5+ when agents need coordination

---

## Phase 3: Conductor Gen_Server

### Overview

The conductor is the event loop driving the system. It's a gen_server that:
- Maintains a **timer heap** (gb_trees) of scheduled actions sorted by execution time
- Maintains an **event queue** (list) of external events waiting to be processed
- **Ticks** every 100ms to process due timers and queued events
- Classifies work items as **fast-path** (execute directly) or **slow-path** (needs agent/LLM)
- Tracks **metrics** (ticks, events processed, actions fired)

### Changes Required

#### 1. Conductor Module

**File**: `lfe/apps/autopoiesis/src/conductor.lfe` (new)

```lfe
(defmodule conductor
  (behaviour gen_server)
  (export
    ;; gen_server callbacks
    (start_link 0) (init 1)
    (handle_call 3) (handle_cast 2) (handle_info 2)
    (terminate 2) (code_change 3)
    ;; Client API
    (schedule 1) (schedule 2) (cancel-action 1)
    (queue-event 1) (status 0)
    ;; Internal — exported for testing
    (classify-event 1) (compute-next-run 1)))

;;; ============================================================
;;; Client API
;;; ============================================================

(defun start_link ()
  (gen_server:start_link #(local conductor) 'conductor '() '()))

(defun schedule (action)
  "Schedule a one-time or recurring action.
   Action is a map with keys:
     name       - atom, human-readable name
     interval   - integer seconds between runs (for recurring)
     action     - fun/0 to execute
     requires-llm - boolean, true if needs LLM reasoning
     recurring  - boolean, true to reschedule after firing"
  (gen_server:call 'conductor `#(schedule ,action)))

(defun schedule (name action-fun)
  "Convenience: schedule a one-shot fast-path action by name and fun."
  (schedule #M(name ,name
               action ,action-fun
               requires-llm false
               recurring false)))

(defun cancel-action (action-id)
  "Cancel a scheduled action by its ID."
  (gen_server:call 'conductor `#(cancel ,action-id)))

(defun queue-event (event)
  "Queue an external event for processing on next tick."
  (gen_server:cast 'conductor `#(event ,event)))

(defun status ()
  "Get conductor status."
  (gen_server:call 'conductor 'status 5000))

;;; ============================================================
;;; gen_server callbacks
;;; ============================================================

(defun init (_args)
  ;; Schedule the first tick
  (erlang:send_after 100 (self) 'tick)
  `#(ok #M(timer-heap ,(gb_trees:empty)
           event-queue ()
           next-id 0
           metrics #M(ticks 0
                      events-processed 0
                      actions-fired 0
                      slow-path-count 0))))

(defun handle_call
  ;; Schedule an action
  ((`#(schedule ,action) _from state)
   (let* ((action-id (maps:get 'next-id state))
          (now-sec (erlang:system_time 'second))
          (interval (maps:get 'interval action 0))
          (run-at (+ now-sec (if (> interval 0) interval 0)))
          (key `#(,run-at ,action-id))
          (entry (maps:put 'id action-id action))
          (new-heap (gb_trees:insert key entry (maps:get 'timer-heap state)))
          (new-state (maps:merge state
                       #M(timer-heap ,new-heap
                          next-id ,(+ action-id 1)))))
     `#(reply #(ok ,action-id) ,new-state)))

  ;; Cancel an action — scan heap and remove matching ID
  ((`#(cancel ,action-id) _from state)
   (let ((new-heap (remove-action-by-id action-id (maps:get 'timer-heap state))))
     `#(reply ok ,(maps:put 'timer-heap new-heap state))))

  ;; Status
  (('status _from state)
   (let ((status #M(timer-count ,(gb_trees:size (maps:get 'timer-heap state))
                    event-queue-length ,(length (maps:get 'event-queue state))
                    metrics ,(maps:get 'metrics state))))
     `#(reply ,status ,state)))

  ;; Unknown
  ((msg _from state)
   `#(reply #(error #(unknown-call ,msg)) ,state)))

(defun handle_cast
  ;; Queue an external event
  ((`#(event ,event) state)
   (let* ((queue (maps:get 'event-queue state))
          (new-queue (++ queue (list event))))
     `#(noreply ,(maps:put 'event-queue new-queue state))))

  ((_msg state)
   `#(noreply ,state)))

(defun handle_info
  ;; Main tick — the heartbeat of the system
  (('tick state)
   (let* ((state2 (process-due-timers state))
          (state3 (process-events state2))
          (state4 (bump-metric 'ticks state3)))
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
  "Pop and execute all actions whose time has come."
  (let ((now (erlang:system_time 'second))
        (heap (maps:get 'timer-heap state)))
    (process-due-timers-loop now heap state)))

(defun process-due-timers-loop (now heap state)
  (case (gb_trees:is_empty heap)
    ('true (maps:put 'timer-heap heap state))
    ('false
     (let ((`#(#(,run-at ,_action-id) ,action) (gb_trees:smallest heap)))
       (if (=< run-at now)
         (let* ((`#(,_key ,_val ,heap2) (gb_trees:take_smallest heap))
                (state2 (execute-action action state))
                ;; Reschedule if recurring
                (heap3 (maybe-reschedule action now heap2)))
           (process-due-timers-loop now heap3 state2))
         ;; Not yet due — done
         (maps:put 'timer-heap heap state))))))

(defun execute-action (action state)
  "Execute a scheduled action. Fast-path runs directly, slow-path logs for now."
  (case (maps:get 'requires-llm action 'false)
    ('false
     ;; Fast path: execute the function directly
     (let ((action-fun (maps:get 'action action)))
       (catch (funcall action-fun))
       (bump-metric 'actions-fired state)))
    ('true
     ;; Slow path: would spawn agent — for now just log and count
     (logger:info "Conductor: slow-path action ~p needs LLM"
                  (list (maps:get 'name action 'unnamed)))
     (bump-metric 'slow-path-count (bump-metric 'actions-fired state)))))

(defun maybe-reschedule (action now heap)
  "If action is recurring, insert it again with next run time."
  (case (maps:get 'recurring action 'false)
    ('true
     (let* ((interval (maps:get 'interval action))
            (action-id (maps:get 'id action))
            (next-run (+ now interval))
            (key `#(,next-run ,action-id)))
       (gb_trees:insert key action heap)))
    ('false heap)))

(defun remove-action-by-id (target-id heap)
  "Remove an action by its ID. Rebuilds tree without matching entry."
  (let ((iter (gb_trees:iterator heap)))
    (remove-action-iter target-id iter (gb_trees:empty))))

(defun remove-action-iter (target-id iter acc)
  (case (gb_trees:next iter)
    ('none acc)
    (`#(,key ,value ,iter2)
     (let ((action-id (maps:get 'id value)))
       (if (== action-id target-id)
         ;; Skip this entry (remove it)
         (remove-action-iter target-id iter2 acc)
         ;; Keep this entry
         (remove-action-iter target-id iter2
           (gb_trees:insert key value acc)))))))

;;; ============================================================
;;; Event processing
;;; ============================================================

(defun process-events (state)
  "Process all queued events."
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
  "Process one event. Classify and handle."
  (let ((classified (classify-event event)))
    (case (maps:get 'requires-llm classified 'false)
      ('false
       ;; Fast path: log and count
       (logger:info "Conductor: fast-path event type=~p"
                    (list (maps:get 'type classified 'unknown)))
       (bump-metric 'events-processed state))
      ('true
       ;; Slow path: would spawn agent — log and count for now
       (logger:info "Conductor: slow-path event type=~p needs LLM"
                    (list (maps:get 'type classified 'unknown)))
       (bump-metric 'slow-path-count
         (bump-metric 'events-processed state))))))

(defun classify-event (event)
  "Classify an event as fast-path or slow-path."
  (let ((event-type (maps:get 'type event 'unknown)))
    (case event-type
      ('health-check  #M(type health-check requires-llm false payload ,event))
      ('metric-update #M(type metric-update requires-llm false payload ,event))
      ('heartbeat     #M(type heartbeat requires-llm false payload ,event))
      (_              #M(type ,event-type requires-llm true payload ,event)))))

;;; ============================================================
;;; Metrics helpers
;;; ============================================================

(defun bump-metric (key state)
  "Increment a counter in the metrics map."
  (let* ((metrics (maps:get 'metrics state))
         (current (maps:get key metrics 0))
         (new-metrics (maps:put key (+ current 1) metrics)))
    (maps:put 'metrics new-metrics state)))
```

#### 2. Register Conductor in Top-Level Supervisor

**File**: `lfe/apps/autopoiesis/src/autopoiesis-sup.lfe`
**Changes**: Add conductor as first child (before agent-sup and connector-sup)

The conductor should start before agents and connectors since they depend on it.

```lfe
(defmodule autopoiesis-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)))

(defun start_link ()
  (supervisor:start_link #(local autopoiesis-sup) 'autopoiesis-sup '()))

(defun init (_args)
  (let* ((sup-flags #M(strategy one_for_one
                       intensity 5
                       period 10))
         (children (list (conductor-spec)
                         (agent-sup-spec)
                         (connector-sup-spec))))
    `#(ok #(,sup-flags ,children))))

(defun conductor-spec ()
  #M(id conductor
     start #(conductor start_link ())
     restart permanent
     shutdown 5000
     type worker
     modules (conductor)))

(defun agent-sup-spec ()
  #M(id agent-sup
     start #(agent-sup start_link ())
     restart permanent
     shutdown infinity
     type supervisor
     modules (agent-sup)))

(defun connector-sup-spec ()
  #M(id connector-sup
     start #(connector-sup start_link ())
     restart permanent
     shutdown infinity
     type supervisor
     modules (connector-sup)))
```

#### 3. Update Application Descriptor

**File**: `lfe/apps/autopoiesis/src/autopoiesis.app.src`
**Changes**: Add `conductor` to registered list

```erlang
{application,autopoiesis,
             [{description,"Autopoiesis - Self-configuring agent platform"},
              {vsn,"0.1.0"},
              {registered,[conductor]},
              {applications,[kernel,stdlib,lfe]},
              {mod,{'autopoiesis-app',[]}},
              {env,[]}]}.
```

### Phase 3 Tests

#### Conductor Unit Tests

**File**: `lfe/apps/autopoiesis/test/conductor-tests.lfe` (new)

```lfe
(defmodule conductor-tests
  (export all))

;;; EUnit tests for conductor gen_server.
;;; Run with: rebar3 eunit --module=conductor-tests

;;; ============================================================
;;; classify-event tests
;;; ============================================================

(defun classify_event_health_check_test ()
  "Health check events are fast-path."
  (let ((result (conductor:classify-event #M(type health-check))))
    (assert-equal 'false (maps:get 'requires-llm result))
    (assert-equal 'health-check (maps:get 'type result))))

(defun classify_event_metric_update_test ()
  "Metric update events are fast-path."
  (let ((result (conductor:classify-event #M(type metric-update))))
    (assert-equal 'false (maps:get 'requires-llm result))))

(defun classify_event_heartbeat_test ()
  "Heartbeat events are fast-path."
  (let ((result (conductor:classify-event #M(type heartbeat))))
    (assert-equal 'false (maps:get 'requires-llm result))))

(defun classify_event_unknown_test ()
  "Unknown events go to slow-path."
  (let ((result (conductor:classify-event #M(type something-new))))
    (assert-equal 'true (maps:get 'requires-llm result))
    (assert-equal 'something-new (maps:get 'type result))))

(defun classify_event_no_type_test ()
  "Events without type key default to unknown slow-path."
  (let ((result (conductor:classify-event #M(data foo))))
    (assert-equal 'true (maps:get 'requires-llm result))
    (assert-equal 'unknown (maps:get 'type result))))

;;; ============================================================
;;; compute-next-run tests
;;; ============================================================

(defun compute_next_run_interval_test ()
  "Actions with interval get next run time = now + interval."
  (let ((result (conductor:compute-next-run #M(interval 30))))
    (assert-truthy (is_integer result))
    ;; Should be roughly now + 30 seconds
    (let ((now (erlang:system_time 'second)))
      (assert-truthy (=< (- result now) 31))
      (assert-truthy (>= (- result now) 29)))))

;;; ============================================================
;;; Conductor lifecycle tests (require running conductor)
;;; ============================================================

(defun conductor_starts_and_responds_test ()
  "Conductor can be started and returns status."
  ;; Clean state
  (application:stop 'autopoiesis)
  (catch (unregister 'conductor))

  (case (conductor:start_link)
    (`#(ok ,pid)
     (progn
       (assert-truthy (is_pid pid))
       (assert-truthy (is_process_alive pid))

       ;; Get status
       (let ((status (conductor:status)))
         (assert-equal 0 (maps:get 'timer-count status))
         (assert-equal 0 (maps:get 'event-queue-length status))
         ;; Metrics should exist
         (let ((metrics (maps:get 'metrics status)))
           (assert-truthy (is_map metrics))))

       ;; Clean up
       (unlink pid)
       (exit pid 'shutdown)
       'ok))
    (other (error `#(conductor-start-failed ,other)))))

(defun conductor_schedule_action_test ()
  "Scheduling an action increases timer count."
  (application:stop 'autopoiesis)
  (catch (unregister 'conductor))

  (case (conductor:start_link)
    (`#(ok ,pid)
     (progn
       ;; Schedule an action
       (let ((result (conductor:schedule
                       #M(name test-action
                          interval 60
                          action ,(lambda () 'ok)
                          requires-llm false
                          recurring false))))
         (case result
           (`#(ok ,action-id)
            (assert-truthy (is_integer action-id)))
           (other (error `#(schedule-failed ,other)))))

       ;; Verify timer count increased
       (let ((status (conductor:status)))
         (assert-equal 1 (maps:get 'timer-count status)))

       ;; Clean up
       (unlink pid)
       (exit pid 'shutdown)
       'ok))
    (other (error `#(conductor-start-failed ,other)))))

(defun conductor_queue_event_test ()
  "Queuing an event increases event queue length (if checked before tick)."
  (application:stop 'autopoiesis)
  (catch (unregister 'conductor))

  (case (conductor:start_link)
    (`#(ok ,pid)
     (progn
       ;; Queue an event
       (conductor:queue-event #M(type health-check source test))

       ;; Small sleep to let cast be processed (but less than tick interval)
       (timer:sleep 10)

       ;; Event should be queued
       (let ((status (conductor:status)))
         ;; May or may not have been processed by tick yet
         ;; Just verify we didn't crash
         (assert-truthy (is_map status)))

       ;; Clean up
       (unlink pid)
       (exit pid 'shutdown)
       'ok))
    (other (error `#(conductor-start-failed ,other)))))

(defun conductor_tick_fires_due_action_test ()
  "An action scheduled with interval 0 fires within one tick cycle."
  (application:stop 'autopoiesis)
  (catch (unregister 'conductor))

  (case (conductor:start_link)
    (`#(ok ,pid)
     (progn
       ;; Use a process dictionary flag to detect execution
       (let ((test-pid (self)))
         (conductor:schedule
           #M(name immediate-action
              interval 0
              action ,(lambda () (erlang:send test-pid 'action-fired))
              requires-llm false
              recurring false)))

       ;; Wait for tick to fire the action (tick is 100ms)
       (receive
         ('action-fired 'ok)
         (after 500 (error 'action-not-fired-within-500ms)))

       ;; Verify metrics show action was fired
       (let* ((status (conductor:status))
              (metrics (maps:get 'metrics status)))
         (assert-truthy (>= (maps:get 'actions-fired metrics 0) 1)))

       ;; Clean up
       (unlink pid)
       (exit pid 'shutdown)
       'ok))
    (other (error `#(conductor-start-failed ,other)))))

(defun conductor_recurring_action_test ()
  "A recurring action fires multiple times."
  (application:stop 'autopoiesis)
  (catch (unregister 'conductor))

  (case (conductor:start_link)
    (`#(ok ,pid)
     (progn
       ;; Schedule recurring action with 1-second interval
       ;; Since test needs to be fast, use interval=0 and check it fires twice
       (let ((test-pid (self)))
         (conductor:schedule
           #M(name recurring-action
              interval 1
              action ,(lambda () (erlang:send test-pid 'recurring-fired))
              requires-llm false
              recurring true)))

       ;; Wait for first fire
       (receive
         ('recurring-fired 'ok)
         (after 2000 (error 'first-fire-timeout)))

       ;; Wait for second fire
       (receive
         ('recurring-fired 'ok)
         (after 2000 (error 'second-fire-timeout)))

       ;; Clean up
       (unlink pid)
       (exit pid 'shutdown)
       'ok))
    (other (error `#(conductor-start-failed ,other)))))

(defun conductor_cancel_action_test ()
  "Cancelling an action removes it from the timer heap."
  (application:stop 'autopoiesis)
  (catch (unregister 'conductor))

  (case (conductor:start_link)
    (`#(ok ,pid)
     (progn
       ;; Schedule an action far in the future
       (let ((`#(ok ,action-id)
               (conductor:schedule
                 #M(name future-action
                    interval 9999
                    action ,(lambda () 'ok)
                    requires-llm false
                    recurring false))))

         ;; Verify it was scheduled
         (let ((status1 (conductor:status)))
           (assert-equal 1 (maps:get 'timer-count status1)))

         ;; Cancel it
         (conductor:cancel-action action-id)

         ;; Verify it was removed
         (let ((status2 (conductor:status)))
           (assert-equal 0 (maps:get 'timer-count status2))))

       ;; Clean up
       (unlink pid)
       (exit pid 'shutdown)
       'ok))
    (other (error `#(conductor-start-failed ,other)))))

;;; ============================================================
;;; Helpers
;;; ============================================================

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

### Phase 3 Success Criteria

#### Automated Verification
- [ ] `cd lfe && rebar3 lfe compile` succeeds with no errors
- [ ] `cd lfe && rebar3 eunit --module=conductor-tests` — all tests pass
- [ ] `cd lfe && rebar3 eunit` — all existing tests still pass (boot-tests, agent-worker-tests)
- [ ] All existing CL tests still pass: `./scripts/test.sh`

#### Manual Verification
- [ ] In REPL: `(application:ensure_all_started 'autopoiesis)` starts conductor
- [ ] `(conductor:status)` returns valid status map with metrics
- [ ] `(supervisor:which_children 'autopoiesis-sup)` shows 3 children (conductor, agent-sup, connector-sup)
- [ ] Killing conductor process: `(exit (whereis 'conductor) 'kill)` — supervisor restarts it within seconds
- [ ] After restart, `(conductor:status)` works again (fresh state, metrics reset)

**Implementation Note**: After completing Phase 3 and all automated verification passes, pause for manual confirmation before proceeding to Phase 4.

---

## Phase 4: HTTP Connectors (Webhook + Health)

### Overview

Add cowboy HTTP server under connector-sup. Two endpoints:
- `POST /webhook` — accepts JSON events, queues them to conductor
- `GET /health` — returns system health status

### Changes Required

#### 1. Add Dependencies

**File**: `lfe/rebar.config`

```erlang
{erl_opts, [debug_info]}.
{plugins, [{rebar3_lfe, "0.4.9"}]}.
{deps, [
    {lfe, "2.2.0"},
    {cowboy, "2.14.2"},
    {jsx, "3.1.0"}
]}.
{relx, [{release, {autopoiesis, "0.1.0"}, [autopoiesis]}]}.
{profiles, [{test, [{plugins, [rebar3_lfe]}]}]}.
```

#### 2. Update Application Descriptor

**File**: `lfe/apps/autopoiesis/src/autopoiesis.app.src`

```erlang
{application,autopoiesis,
             [{description,"Autopoiesis - Self-configuring agent platform"},
              {vsn,"0.1.0"},
              {registered,[conductor]},
              {applications,[kernel,stdlib,lfe,cowboy,jsx]},
              {mod,{'autopoiesis-app',[]}},
              {env,[
                {http_port, 4007}
              ]}]}.
```

#### 3. Add HTTP Port to System Config

**File**: `lfe/config/sys.config`

```erlang
[
  {autopoiesis, [
    {http_port, 4007}
  ]}
].
```

#### 4. Webhook Server (gen_server wrapping cowboy lifecycle)

**File**: `lfe/apps/autopoiesis/src/webhook-server.lfe` (new)

```lfe
(defmodule webhook-server
  (behaviour gen_server)
  (export
    ;; gen_server callbacks
    (start_link 0) (init 1)
    (handle_call 3) (handle_cast 2) (handle_info 2)
    (terminate 2) (code_change 3)))

;;; ============================================================
;;; gen_server callbacks
;;; ============================================================

(defun start_link ()
  (gen_server:start_link #(local webhook-server) 'webhook-server '() '()))

(defun init (_args)
  (let* ((port (get-http-port))
         (dispatch (cowboy_router:compile
                     `(#(_
                         (#("/webhook" webhook-handler ())
                          #("/health" health-handler ()))))))
         (result (cowboy:start_clear
                   'http_listener
                   `(#(port ,port))
                   #M(env #M(dispatch ,dispatch)))))
    (case result
      (`#(ok ,_listener-pid)
       (logger:info "Webhook server started on port ~p" (list port))
       `#(ok #M(port ,port)))
      (`#(error ,reason)
       (logger:error "Failed to start webhook server: ~p" (list reason))
       `#(stop #(cowboy-start-failed ,reason))))))

(defun handle_call (msg _from state)
  `#(reply #(error #(unknown-call ,msg)) ,state))

(defun handle_cast (_msg state)
  `#(noreply ,state))

(defun handle_info (_msg state)
  `#(noreply ,state))

(defun terminate (_reason _state)
  (catch (cowboy:stop_listener 'http_listener))
  'ok)

(defun code_change (_old-vsn state _extra)
  `#(ok ,state))

;;; ============================================================
;;; Internal
;;; ============================================================

(defun get-http-port ()
  "Get HTTP port from application env, default 4007."
  (case (application:get_env 'autopoiesis 'http_port)
    (`#(ok ,port) port)
    ('undefined 4007)))
```

#### 5. Webhook Handler

**File**: `lfe/apps/autopoiesis/src/webhook-handler.lfe` (new)

```lfe
(defmodule webhook-handler
  (export (init 2)))

;;; Cowboy 2.x plain handler.
;;; Accepts POST with JSON body, queues event to conductor.

(defun init (req state)
  (let ((method (cowboy_req:method req)))
    (case method
      (#"POST"
       (handle-post req state))
      (_
       (let ((req2 (cowboy_req:reply
                      405
                      #M(#"content-type" #"application/json")
                      (jsx:encode #M(#"error" #"method_not_allowed"))
                      req)))
         `#(ok ,req2 ,state))))))

(defun handle-post (req state)
  (case (cowboy_req:read_body req)
    (`#(ok ,body ,req2)
     (case (catch (jsx:decode body '(return_maps)))
       (`#(EXIT ,_reason)
        ;; Malformed JSON
        (let ((req3 (cowboy_req:reply
                       400
                       #M(#"content-type" #"application/json")
                       (jsx:encode #M(#"error" #"invalid_json"))
                       req2)))
          `#(ok ,req3 ,state)))
       (decoded
        ;; Valid JSON — queue to conductor
        (conductor:queue-event
          #M(type webhook
             source external
             payload ,decoded))
        (let ((req3 (cowboy_req:reply
                       200
                       #M(#"content-type" #"application/json")
                       (jsx:encode #M(#"status" #"accepted"))
                       req2)))
          `#(ok ,req3 ,state)))))
    (`#(more ,_body ,req2)
     ;; Body too large (streaming) — reject
     (let ((req3 (cowboy_req:reply
                    413
                    #M(#"content-type" #"application/json")
                    (jsx:encode #M(#"error" #"body_too_large"))
                    req2)))
       `#(ok ,req3 ,state)))))
```

#### 6. Health Handler

**File**: `lfe/apps/autopoiesis/src/health-handler.lfe` (new)

```lfe
(defmodule health-handler
  (export (init 2)))

;;; Cowboy 2.x plain handler.
;;; Returns system health status as JSON.

(defun init (req state)
  (let ((method (cowboy_req:method req)))
    (case method
      (#"GET"
       (handle-get req state))
      (_
       (let ((req2 (cowboy_req:reply
                      405
                      #M(#"content-type" #"application/json")
                      (jsx:encode #M(#"error" #"method_not_allowed"))
                      req)))
         `#(ok ,req2 ,state))))))

(defun handle-get (req state)
  (let* ((conductor-status (catch (conductor:status)))
         (health (build-health-response conductor-status))
         (status-code (case (maps:get #"status" health)
                        (#"ok" 200)
                        (_ 503)))
         (req2 (cowboy_req:reply
                  status-code
                  #M(#"content-type" #"application/json")
                  (jsx:encode health)
                  req)))
    `#(ok ,req2 ,state)))

(defun build-health-response (conductor-status)
  (case conductor-status
    (`#(EXIT ,_reason)
     ;; Conductor not responding
     #M(#"status" #"degraded"
        #"conductor" #"unavailable"))
    (status-map
     #M(#"status" #"ok"
        #"conductor" #M(#"timer_count" ,(maps:get 'timer-count status-map 0)
                        #"event_queue_length" ,(maps:get 'event-queue-length status-map 0))))))
```

#### 7. Update Connector Supervisor

**File**: `lfe/apps/autopoiesis/src/connector-sup.lfe`

```lfe
(defmodule connector-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)))

(defun start_link ()
  (supervisor:start_link #(local connector-sup) 'connector-sup '()))

(defun init (_args)
  (let* ((sup-flags #M(strategy one_for_one
                       intensity 5
                       period 10))
         (children (list (webhook-server-spec))))
    `#(ok #(,sup-flags ,children))))

(defun webhook-server-spec ()
  #M(id webhook-server
     start #(webhook-server start_link ())
     restart permanent
     shutdown 5000
     type worker
     modules (webhook-server)))
```

### Phase 4 Tests

#### Connector Tests

**File**: `lfe/apps/autopoiesis/test/connector-tests.lfe` (new)

```lfe
(defmodule connector-tests
  (export all))

;;; EUnit tests for HTTP connectors.
;;; Run with: rebar3 eunit --module=connector-tests
;;;
;;; These tests start the full application (which starts cowboy)
;;; and make HTTP requests to verify endpoints.

;;; ============================================================
;;; Health endpoint tests
;;; ============================================================

(defun health_endpoint_returns_200_test ()
  "GET /health returns 200 with status ok."
  (with-running-app
    (lambda ()
      ;; Need inets for httpc
      (inets:start)
      (let ((result (httpc:request
                      'get
                      `#("http://127.0.0.1:4007/health" ())
                      '()
                      '())))
        (case result
          (`#(ok #(#(,_http ,200 ,_reason) ,_headers ,body))
           (let ((decoded (jsx:decode (list_to_binary body) '(return_maps))))
             (assert-equal #"ok" (maps:get #"status" decoded))))
          (other (error `#(health-request-failed ,other))))))))

;;; ============================================================
;;; Webhook endpoint tests
;;; ============================================================

(defun webhook_post_returns_200_test ()
  "POST /webhook with valid JSON returns 200 accepted."
  (with-running-app
    (lambda ()
      (inets:start)
      (let* ((body (jsx:encode #M(#"type" #"test" #"data" #"hello")))
             (result (httpc:request
                       'post
                       `#("http://127.0.0.1:4007/webhook"
                          ()
                          "application/json"
                          ,body)
                       '()
                       '())))
        (case result
          (`#(ok #(#(,_http ,200 ,_reason) ,_headers ,resp-body))
           (let ((decoded (jsx:decode (list_to_binary resp-body) '(return_maps))))
             (assert-equal #"accepted" (maps:get #"status" decoded))))
          (other (error `#(webhook-request-failed ,other))))))))

(defun webhook_invalid_json_returns_400_test ()
  "POST /webhook with invalid JSON returns 400."
  (with-running-app
    (lambda ()
      (inets:start)
      (let ((result (httpc:request
                      'post
                      `#("http://127.0.0.1:4007/webhook"
                         ()
                         "application/json"
                         "not valid json{{{")
                      '()
                      '())))
        (case result
          (`#(ok #(#(,_http ,400 ,_reason) ,_headers ,_body)) 'ok)
          (other (error `#(expected-400 ,other))))))))

(defun webhook_get_returns_405_test ()
  "GET /webhook returns 405 method not allowed."
  (with-running-app
    (lambda ()
      (inets:start)
      (let ((result (httpc:request
                      'get
                      `#("http://127.0.0.1:4007/webhook" ())
                      '()
                      '())))
        (case result
          (`#(ok #(#(,_http ,405 ,_reason) ,_headers ,_body)) 'ok)
          (other (error `#(expected-405 ,other))))))))

(defun health_get_method_only_test ()
  "POST /health returns 405."
  (with-running-app
    (lambda ()
      (inets:start)
      (let ((result (httpc:request
                      'post
                      `#("http://127.0.0.1:4007/health"
                         ()
                         "application/json"
                         "{}")
                      '()
                      '())))
        (case result
          (`#(ok #(#(,_http ,405 ,_reason) ,_headers ,_body)) 'ok)
          (other (error `#(expected-405 ,other))))))))

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun with-running-app (test-fun)
  "Start the application, run the test, then clean up."
  (application:stop 'autopoiesis)
  ;; Small delay to ensure port is released
  (timer:sleep 100)
  (case (application:ensure_all_started 'autopoiesis)
    (`#(ok ,_apps)
     (progn
       ;; Give cowboy a moment to bind the port
       (timer:sleep 200)
       (let ((result (catch (funcall test-fun))))
         (application:stop 'autopoiesis)
         (timer:sleep 100)
         (case result
           (`#(EXIT ,reason) (error reason))
           (val val)))))
    (`#(error ,reason)
     (error `#(app-start-failed ,reason)))))

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

### Phase 4 Success Criteria

#### Automated Verification
- [ ] `cd lfe && rebar3 lfe compile` succeeds (fetches cowboy + jsx deps)
- [ ] `cd lfe && rebar3 eunit --module=connector-tests` — all tests pass
- [ ] `cd lfe && rebar3 eunit` — all tests pass (conductor-tests, boot-tests, agent-worker-tests, connector-tests)
- [ ] All existing CL tests still pass: `./scripts/test.sh`

#### Manual Verification
- [ ] `(application:ensure_all_started 'autopoiesis)` starts including cowboy
- [ ] `curl -s localhost:4007/health | jq .` returns `{"status":"ok","conductor":{...}}`
- [ ] `curl -s -X POST localhost:4007/webhook -H 'Content-Type: application/json' -d '{"type":"test"}'` returns `{"status":"accepted"}`
- [ ] `curl -s -X POST localhost:4007/webhook -d 'not json'` returns 400 with `{"error":"invalid_json"}`
- [ ] `curl -s localhost:4007/webhook` returns 405
- [ ] Killing webhook-server: `(exit (whereis 'webhook-server) 'kill)` — connector-sup restarts it
- [ ] After restart, health endpoint works again
- [ ] `(supervisor:which_children 'connector-sup)` shows webhook-server child

---

## Task Dependency Graph

```
Phase 3:
  Task 3.1: conductor.lfe ─────────────────────────┐
  Task 3.2: Update autopoiesis-sup.lfe ─────────────┤
  Task 3.3: Update autopoiesis.app.src ─────────────┤
                                                     ▼
                                              Task 3.4: conductor-tests.lfe
                                                     │
                                                     ▼
                                              Task 3.5: Compile + test
                                                     │
                                                     ▼
                                              [Manual verification]
                                                     │
Phase 4:                                             ▼
  Task 4.1: Update rebar.config (deps) ─────────────┐
  Task 4.2: Update autopoiesis.app.src ─────────────┤
  Task 4.3: Update sys.config ──────────────────────┤
  Task 4.4: webhook-server.lfe ─────────────────────┤
  Task 4.5: webhook-handler.lfe ────────────────────┤
  Task 4.6: health-handler.lfe ─────────────────────┤
  Task 4.7: Update connector-sup.lfe ──────────────┤
                                                     ▼
                                              Task 4.8: connector-tests.lfe
                                                     │
                                                     ▼
                                              Task 4.9: Compile + test
                                                     │
                                                     ▼
                                              [Manual verification]
```

## SCUD Waves

For parallel execution with SCUD:

- **Wave 1**: Tasks 3.1, 3.2, 3.3 (conductor source + supervisor update + app descriptor) — can be done in parallel
- **Wave 2**: Task 3.4 (conductor tests) — depends on 3.1
- **Wave 3**: Task 3.5 (compile + verify) — depends on all Phase 3 tasks
- **Wave 4**: Tasks 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7 (all Phase 4 source changes) — can be done in parallel after Phase 3 verified
- **Wave 5**: Task 4.8 (connector tests) — depends on 4.4-4.7
- **Wave 6**: Task 4.9 (compile + verify) — depends on all Phase 4 tasks

## Testing Strategy

### Unit Tests (Pure Functions)
- `classify-event` — all event types classified correctly
- `compute-next-run` — interval calculations correct

### Integration Tests (Running Processes)
- Conductor starts, responds to status, schedules actions, fires them
- Recurring actions fire multiple times
- Cancel removes actions from heap
- Webhook POST → conductor event queue
- Health endpoint reflects conductor status
- Malformed input handling (400, 405 responses)

### Manual Testing Steps

1. Start the release: `cd lfe && rebar3 lfe repl`
2. `(application:ensure_all_started 'autopoiesis)` — observe all components start
3. `(conductor:status)` — see empty state
4. `(conductor:schedule #M(name test interval 5 action (lambda () (logger:info "TICK!")) requires-llm false recurring true))` — schedule recurring action
5. Watch logs for "TICK!" every 5 seconds
6. `curl localhost:4007/health` — verify health response
7. `curl -X POST localhost:4007/webhook -H 'Content-Type: application/json' -d '{"type":"alert","severity":"warning"}'` — post webhook
8. `(conductor:status)` — observe events-processed metric increment
9. Kill conductor: `(exit (whereis 'conductor) 'kill)` — verify restart
10. Kill webhook-server: `(exit (whereis 'webhook-server) 'kill)` — verify restart

## Performance Considerations

- **Tick interval**: 100ms is a balance between responsiveness and CPU. At rest (no events, no due timers), each tick is just a gb_trees:is_empty check and a queue length check — sub-microsecond.
- **gb_trees**: O(log n) insert/delete/smallest. Fine for hundreds of scheduled actions.
- **Event queue**: Simple list append + drain. Fine for low-to-moderate event rates. If events arrive faster than ticks can process them, the queue will grow. For production, consider bounded queues.
- **Cowboy**: Handles HTTP efficiently with its own process pool. One webhook-server gen_server manages the lifecycle, not the request handling.

## What Comes After (Phase 5 Preview)

Phase 5 (Project Definition Format) would:
- Define project.sexpr config format
- Load triggers from config and register with conductor
- Auto-start agents on project load
- Connect conductor's slow-path to agent spawning via agent-sup

## References

- Master plan: `thoughts/shared/plans/2026-02-04-lfe-supervised-agent-platform.md`
- Phase 2 detailed plan: `thoughts/shared/plans/2026-02-05-phase2-lfe-project-skeleton.md`
- Status review: `thoughts/shared/research/2026-02-05-plans-status-review.md`
- Erlang gb_trees: https://www.erlang.org/doc/apps/stdlib/gb_trees.html
- Cowboy 2.x guide: https://ninenines.eu/docs/en/cowboy/2.12/guide/
- jsx on hex.pm: https://hex.pm/packages/jsx
