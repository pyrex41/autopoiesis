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

;;; ============================================================
;;; Client API
;;; ============================================================

(defun start_link ()
  (gen_server:start_link #(local conductor) 'conductor '() '()))

(defun schedule (action)
  "Schedule a timer-based action.
   Action is a map with keys: id, interval, recurring, requires-llm, action."
  (gen_server:cast 'conductor `#(schedule ,action)))

(defun schedule (name action-fun)
  "Schedule a non-recurring fast-path action with default 60s interval."
  (schedule `#M(id ,name interval 60 recurring false requires-llm false action ,action-fun)))

(defun schedule (name action-fun interval)
  "Schedule a non-recurring fast-path action with custom interval."
  (schedule `#M(id ,name interval ,interval recurring false requires-llm false action ,action-fun)))

(defun cancel (name)
  "Cancel a scheduled action by its id/name."
  (gen_server:cast 'conductor `#(cancel ,name)))

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

(defun handle_call
  (('status _from state)
   `#(reply ,(build-status state) ,state))
  ((msg _from state)
   `#(reply #(error #(unknown-call ,msg)) ,state)))

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

(defun handle_info
  ;; Main tick — the heartbeat of the system
  (('tick state)
   (let* ((state2 (process-due-timers state))
          (state3 (process-events state2))
          (new-metrics (increment-metric 'tick-count (state-metrics state3))))
     (erlang:send_after 100 (self) 'tick)
     `#(noreply ,(set-state-metrics state3 new-metrics))))

  ((_msg state)
   `#(noreply ,state)))

(defun handle_continue (_continue state)
  `#(noreply ,state))

(defun format_status (_opt state)
  `#(data ((#(state ,state)))))

(defun terminate (reason _state)
  (logger:info "Conductor terminating: ~p" (list reason))
  'ok)

(defun code_change (_old-vsn state _extra)
  `#(ok ,state))

;;; ============================================================
;;; Timer heap processing
;;; ============================================================

(defun process-due-timers (state)
  "Pop and execute all timers whose time has come."
  (let ((now (erlang:monotonic_time 'second))
        (heap (state-timer-heap state)))
    (process-due-timers-loop now heap state)))

(defun process-due-timers-loop (now heap state)
  (case (gb_trees:is_empty heap)
    ('true
     (set-state-timer-heap state heap))
    ('false
     (let ((`#(#(,time ,_ref) ,action) (gb_trees:smallest heap)))
       (if (=< time now)
           (let* ((`#(,_key ,_val ,heap2) (gb_trees:take_smallest heap))
                  (state2 (execute-timer-action action state))
                  (heap3 (maybe-reschedule action heap2))
                  (new-metrics (increment-metric 'timers-fired (state-metrics state2))))
             (process-due-timers-loop now heap3 (set-state-metrics state2 new-metrics)))
           ;; Next timer is in the future — done for this tick
           (set-state-timer-heap state heap))))))

(defun execute-timer-action (action state)
  "Execute a scheduled action. Fast-path runs directly; slow-path spawns agent."
  (case (maps:get 'requires-llm action 'false)
    ('true
     (spawn-agent-for-work action)
     state)
    ('false
     (let ((func (maps:get 'action action 'undefined)))
       (case func
         ('undefined state)
         (_
          (try (funcall func)
            (catch
              (`#(,type ,reason ,_stack)
               (logger:warning "Timer action ~p failed: ~p:~p"
                               (list (maps:get 'id action 'unknown)
                                     type reason)))))
          state))))))

(defun compute-next-run (action)
  "Compute the next monotonic timestamp when this action should fire."
  (let ((now (erlang:monotonic_time 'second))
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
;;; Cancel support
;;; ============================================================

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

;;; ============================================================
;;; Event processing
;;; ============================================================

(defun process-events (state)
  "Drain the event queue, processing each event."
  (let ((events (state-event-queue state)))
    (process-events-loop events state)))

(defun process-events-loop (events state)
  (case events
    ('()
     (set-state-event-queue state '()))
    ((cons event rest)
     (let ((state2 (process-single-event event state)))
       (process-events-loop rest state2)))))

(defun process-single-event (event state)
  "Classify and process a single event."
  (let ((work-item (classify-event event)))
    (case (maps:get 'requires-llm work-item)
      ('true
       (spawn-agent-for-work work-item)
       (set-state-metrics state
         (increment-metric 'events-processed (state-metrics state))))
      ('false
       (execute-fast-path work-item)
       (set-state-metrics state
         (increment-metric 'events-processed (state-metrics state)))))))

(defun classify-event (event)
  "Classify an event as fast-path or slow-path based on its type."
  (let ((event-type (maps:get 'type event 'unknown)))
    (case event-type
      ('health-check
       `#M(type health-check requires-llm false payload ,event))
      ('metric-update
       `#M(type metric-update requires-llm false payload ,event))
      ('ping
       `#M(type ping requires-llm false payload ,event))
      ;; Unknown or complex events go to slow path
      (_
       `#M(type ,event-type requires-llm true payload ,event)))))

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
   Runs asynchronously to avoid blocking the conductor tick loop."
  (let ((agent-id (make-agent-id))
        (work-type (maps:get 'type work-item 'unknown)))
    (spawn
      (lambda ()
        (case (catch (agent-sup:spawn-agent
                       `#M(agent-id ,agent-id
                           name ,agent-id
                           task ,work-item)))
          (`#(ok ,pid)
           (logger:info "Spawned agent ~s (pid ~p) for ~p"
                        (list agent-id pid work-type)))
          (`#(EXIT ,reason)
           (logger:warning "Failed to spawn agent for ~p: ~p"
                           (list work-type reason)))
          (`#(error ,reason)
           (logger:warning "Failed to spawn agent for ~p: ~p"
                           (list work-type reason))))))))

(defun make-agent-id ()
  "Generate a unique agent ID string."
  (let ((n (erlang:unique_integer '(positive))))
    (lists:flatten (io_lib:format "agent-~B" (list n)))))

;;; ============================================================
;;; Metrics and status
;;; ============================================================

(defun increment-metric (name metrics)
  "Increment a named metric counter by 1."
  (let ((current (maps:get name metrics 0)))
    (maps:put name (+ current 1) metrics)))

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
