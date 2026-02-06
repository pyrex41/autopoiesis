(defmodule conductor-tests
  (export all))

;;; EUnit tests for conductor gen_server.
;;; Run with: rebar3 eunit --module=conductor-tests
;;;
;;; Structure:
;;; - Section 1: Pure function tests (no process needed)
;;; - Section 2: Standalone conductor tests (with-conductor helper)
;;; - Section 3: Integration tests (with-application, full app)
;;; - Section 4: Helpers

;;; ============================================================
;;; Section 1: Pure function tests (no process needed)
;;; ============================================================

(defun classify_event_health_check_test ()
  "Health check events should be fast-path."
  (let ((result (conductor:classify-event #M(type health-check))))
    (assert-equal 'false (maps:get 'requires-llm result))
    (assert-equal 'health-check (maps:get 'type result))))

(defun classify_event_metric_update_test ()
  "Metric update events should be fast-path."
  (let ((result (conductor:classify-event #M(type metric-update))))
    (assert-equal 'false (maps:get 'requires-llm result))
    (assert-equal 'metric-update (maps:get 'type result))))

(defun classify_event_ping_test ()
  "Ping events should be fast-path."
  (let ((result (conductor:classify-event #M(type ping))))
    (assert-equal 'false (maps:get 'requires-llm result))
    (assert-equal 'ping (maps:get 'type result))))

(defun classify_event_unknown_test ()
  "Unknown event types should be slow-path."
  (let ((result (conductor:classify-event #M(type something-complex))))
    (assert-equal 'true (maps:get 'requires-llm result))))

(defun classify_event_missing_type_test ()
  "Events without a type key should default to slow-path."
  (let ((result (conductor:classify-event #M(data some-payload))))
    (assert-equal 'true (maps:get 'requires-llm result))))

(defun classify_event_preserves_payload_test ()
  "Classified event should preserve original event as payload."
  (let* ((event #M(type health-check data important))
         (result (conductor:classify-event event)))
    (assert-equal event (maps:get 'payload result))))

(defun compute_next_run_interval_test ()
  "compute-next-run should add interval to current monotonic time."
  (let* ((now (erlang:monotonic_time 'second))
         (result (conductor:compute-next-run #M(interval 30))))
    ;; Result should be approximately now + 30 (allow 2s tolerance)
    (assert-truthy (>= result (+ now 29)))
    (assert-truthy (=< result (+ now 32)))))

(defun compute_next_run_default_test ()
  "compute-next-run should default to 60 seconds if no interval."
  (let* ((now (erlang:monotonic_time 'second))
         (result (conductor:compute-next-run #M(id no-interval))))
    (assert-truthy (>= result (+ now 59)))
    (assert-truthy (=< result (+ now 62)))))

(defun compute_next_run_zero_test ()
  "compute-next-run with interval 0 should return approximately now."
  (let* ((now (erlang:monotonic_time 'second))
         (result (conductor:compute-next-run #M(interval 0))))
    (assert-truthy (>= result now))
    (assert-truthy (=< result (+ now 2)))))

;;; ============================================================
;;; Claude dispatch tests
;;; ============================================================

(defun task_result_handling_test ()
  "Task result cast should be handled without crashing conductor."
  (with-conductor
    (lambda ()
      ;; Send a task-result cast to conductor
      (gen_server:cast 'conductor
        `#(task-result #M(task-id "test-task-1" status complete result #M())))
      (timer:sleep 50)
      ;; Conductor should still be alive
      (let ((status (conductor:status)))
        (assert-truthy (is_map status))
        (assert-truthy (>= (maps:get 'tasks-completed status) 1))))))

(defun task_result_failure_tracking_test ()
  "Failed task results should increment consecutive-failures."
  (with-conductor
    (lambda ()
      ;; Send a failed task-result
      (gen_server:cast 'conductor
        `#(task-result #M(task-id "fail-1" status failed error timeout)))
      (timer:sleep 50)
      (let ((status (conductor:status)))
        (assert-truthy (>= (maps:get 'consecutive-failures status) 1)))
      ;; Send a successful result — should reset failures
      (gen_server:cast 'conductor
        `#(task-result #M(task-id "ok-1" status complete result #M())))
      (timer:sleep 50)
      (let ((status2 (conductor:status)))
        (assert-equal 0 (maps:get 'consecutive-failures status2))))))

;;; ============================================================
;;; Section 2: Standalone conductor tests (with-conductor helper)
;;; ============================================================

(defun conductor_start_stop_test ()
  "Conductor start_link should return #(ok pid) and pid should be alive."
  (with-conductor
    (lambda ()
      (let ((pid (erlang:whereis 'conductor)))
        (assert-truthy (is_pid pid))
        (assert-truthy (is_process_alive pid))))))

(defun conductor_initial_status_test ()
  "Initial status should have 7 flat keys all at zero."
  (with-conductor
    (lambda ()
      (let ((status (conductor:status)))
        (assert-truthy (is_map status))
        (assert-equal 0 (maps:get 'timer-heap-size status))
        (assert-equal 0 (maps:get 'event-queue-length status))
        (assert-equal 0 (maps:get 'timers-fired status))
        (assert-equal 0 (maps:get 'timers-scheduled status))
        (assert-equal 0 (maps:get 'timers-cancelled status))
        (assert-equal 0 (maps:get 'events-processed status))))))

(defun schedule_convenience_api_test ()
  "schedule/2 and schedule/3 should increase timer-heap-size."
  (with-conductor
    (lambda ()
      (conductor:schedule 'test-timer (lambda () 'ok))
      (timer:sleep 50)
      (let ((status1 (conductor:status)))
        (assert-truthy (>= (maps:get 'timer-heap-size status1) 1)))
      (conductor:schedule 'test-timer-2 (lambda () 'ok) 30)
      (timer:sleep 50)
      (let ((status2 (conductor:status)))
        (assert-truthy (>= (maps:get 'timer-heap-size status2) 2))))))

(defun cancel_action_test ()
  "cancel/1 should remove a scheduled timer and increment timers-cancelled."
  (with-conductor
    (lambda ()
      ;; Schedule with long interval so it won't fire during the test
      (conductor:schedule 'cancel-me (lambda () 'ok) 10)
      (timer:sleep 50)
      (let ((status1 (conductor:status)))
        (assert-truthy (>= (maps:get 'timer-heap-size status1) 1)))
      ;; Cancel it
      (conductor:cancel 'cancel-me)
      (timer:sleep 50)
      (let ((status2 (conductor:status)))
        (assert-equal 0 (maps:get 'timer-heap-size status2))
        (assert-truthy (>= (maps:get 'timers-cancelled status2) 1))))))

(defun metrics_increment_test ()
  "Scheduling, cancelling, and queueing events should update metrics."
  (with-conductor
    (lambda ()
      ;; Schedule a timer
      (conductor:schedule 'metric-test (lambda () 'ok) 10)
      (timer:sleep 50)
      (let ((status1 (conductor:status)))
        (assert-truthy (>= (maps:get 'timers-scheduled status1) 1)))
      ;; Cancel it
      (conductor:cancel 'metric-test)
      (timer:sleep 50)
      (let ((status2 (conductor:status)))
        (assert-truthy (>= (maps:get 'timers-cancelled status2) 1)))
      ;; Queue a fast-path event and wait for tick to process
      (conductor:queue-event #M(type health-check))
      (timer:sleep 200)
      (let ((status3 (conductor:status)))
        (assert-truthy (>= (maps:get 'events-processed status3) 1))))))

(defun tick_processing_test ()
  "Tick counter should increment over time."
  (with-conductor
    (lambda ()
      ;; Wait 250ms (~2 ticks at 100ms interval)
      (timer:sleep 250)
      (let ((status (conductor:status)))
        (assert-truthy (> (maps:get 'tick-count status) 0))))))

;;; ============================================================
;;; Section 3: Integration tests (with-application, full app)
;;; ============================================================

(defun conductor_registered_test ()
  "Conductor should be registered after app boot."
  (with-application
    (lambda ()
      (let ((pid (erlang:whereis 'conductor)))
        (assert-truthy (is_pid pid))
        (assert-truthy (is_process_alive pid))))))

(defun schedule_and_fire_test ()
  "Action with interval=0 should fire within one tick cycle."
  (with-application
    (lambda ()
      (let ((test-pid (self)))
        (conductor:schedule
          `#M(id fire-now
              interval 0
              recurring false
              requires-llm false
              action ,(lambda () (erlang:send test-pid 'timer-fired))))
        ;; Wait for up to 500ms for the timer to fire
        (receive
          ('timer-fired (assert-truthy 'true))
          (after 500
            (error 'timer-did-not-fire)))))))

(defun recurring_action_test ()
  "Recurring action should fire multiple times."
  (with-application
    (lambda ()
      (let ((test-pid (self)))
        ;; Schedule recurring action every 0 seconds (fires each tick)
        (conductor:schedule
          `#M(id recurring-test
              interval 0
              recurring true
              requires-llm false
              action ,(lambda () (erlang:send test-pid 'recurring-tick))))
        ;; Collect at least 2 firings within 500ms
        (receive ('recurring-tick 'ok) (after 500 (error 'first-tick-timeout)))
        (receive ('recurring-tick 'ok) (after 500 (error 'second-tick-timeout)))
        (assert-truthy 'true)))))

(defun multiple_timers_ordering_test ()
  "Multiple timers should fire, proving no key collision."
  (with-application
    (lambda ()
      (let ((test-pid (self)))
        ;; Schedule two timers both at interval 0
        (conductor:schedule
          `#M(id timer-a interval 0 recurring false requires-llm false
              action ,(lambda () (erlang:send test-pid #(fired a)))))
        (conductor:schedule
          `#M(id timer-b interval 0 recurring false requires-llm false
              action ,(lambda () (erlang:send test-pid #(fired b)))))
        ;; Both should fire within 500ms
        (let ((results (collect-messages 500)))
          (assert-truthy (>= (length results) 2)))))))

(defun queue_event_test ()
  "Queuing a fast-path event should process it on next tick."
  (with-application
    (lambda ()
      (conductor:queue-event #M(type health-check))
      ;; Wait for tick to process
      (timer:sleep 200)
      (let ((status (conductor:status)))
        (assert-truthy (>= (maps:get 'events-processed status) 1))))))

(defun slow_path_graceful_failure_test ()
  "Slow-path spawn failure should not crash conductor."
  (catch (cowboy:stop_listener 'http_listener))
  (application:stop 'autopoiesis)
  (case (application:ensure_all_started 'autopoiesis)
    (`#(ok ,_apps)
     (let ((conductor-pid (erlang:whereis 'conductor)))
       ;; Queue an event that triggers slow-path (unknown type)
       (conductor:queue-event #M(type needs-llm-processing data test))
       ;; Wait for processing
       (timer:sleep 200)
       ;; Conductor should still be alive (spawn runs async now)
       (assert-truthy (is_process_alive conductor-pid))
       ;; And still responding to gen_server calls
       (let ((status (conductor:status)))
         (assert-truthy (is_map status)))
       ;; Force-kill entire supervision tree to avoid 10s agent-worker timeout
       (let ((sup-pid (erlang:whereis 'autopoiesis-sup)))
         (erlang:exit sup-pid 'kill))
       (timer:sleep 100)
       (catch (cowboy:stop_listener 'http_listener))
       (application:stop 'autopoiesis)))
    (`#(error ,reason)
     (error `#(setup-failed ,reason)))))

;;; ============================================================
;;; Section 4: Helpers
;;; ============================================================

(defun with-conductor (test-fn)
  "Start/stop conductor in isolation (no full app)."
  (case (conductor:start_link)
    (`#(ok ,pid)
     (try (funcall test-fn)
       (after (gen_server:stop pid)
              (timer:sleep 50))))
    (`#(error ,reason)
     (error `#(conductor-start-failed ,reason)))))

(defun with-application (test-fn)
  "Execute a test function with the application running, ensuring cleanup."
  (try
    (progn
      (application:stop 'autopoiesis)
      (catch (cowboy:stop_listener 'http_listener))
      (timer:sleep 300)
      (case (application:ensure_all_started 'autopoiesis)
        (`#(ok ,_apps)
         (funcall test-fn))
        (`#(error ,reason)
         (error `#(setup-failed ,reason))))
      (application:stop 'autopoiesis)
      (catch (cowboy:stop_listener 'http_listener))
      (timer:sleep 300))
    (catch
      (`#(,type ,reason ,_stack)
       (application:stop 'autopoiesis)
       (catch (cowboy:stop_listener 'http_listener))
       (timer:sleep 300)
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

(defun collect-messages (timeout)
  "Collect all messages received within timeout period."
  (collect-messages-loop '() timeout))

(defun collect-messages-loop (acc timeout)
  (receive
    (msg (collect-messages-loop (++ acc (list msg)) timeout))
    (after timeout
      acc)))
