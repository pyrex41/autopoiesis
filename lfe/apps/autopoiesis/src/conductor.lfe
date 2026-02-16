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
  (export (classify-event 1) (compute-next-run 1)
          (schedule-infra-watcher 0)
          (find-pending-request 2) (remove-pending-request 2)
          (dispatch-sub-agent 2)))

;; State record — replaces plain maps
(defrecord state
  timer-heap        ; gb_trees with #(monotonic-time unique-ref) keys
  event-queue       ; list of event maps
  metrics           ; map of metric counters
  pending-requests) ; list of blocking-request maps (Phase 4.5)

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
                              timers-cancelled 0
                              tasks-completed 0
                              consecutive-failures 0
                              last-failure-time 0)
                   pending-requests '())))
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

  ;; Task result from claude worker
  ((`#(task-result ,result) state)
   (let* ((task-id (maps:get 'task-id result "unknown"))
          (task-status (maps:get 'status result 'unknown))
          (metrics (state-metrics state))
          (new-metrics (increment-metric 'tasks-completed metrics)))
     (case task-status
       ('complete
        (logger:info "Task ~s completed successfully" (list task-id))
        (process-task-result result)
        ;; Reset consecutive failures on success
        (let ((reset-metrics (maps:put 'consecutive-failures 0 new-metrics)))
          `#(noreply ,(set-state-metrics state reset-metrics))))
       ('failed
        (let* ((failures (+ 1 (maps:get 'consecutive-failures metrics 0)))
               (fail-metrics (maps:put 'consecutive-failures failures
                               (maps:put 'last-failure-time
                                 (erlang:system_time 'second) new-metrics))))
          (logger:warning "Task ~s failed: ~p (consecutive: ~p)"
                          (list task-id
                                (maps:get 'error result 'unknown)
                                failures))
          (if (> failures 3)
            (logger:error "~p consecutive task failures — backing off"
                          (list failures))
            'ok)
          `#(noreply ,(set-state-metrics state fail-metrics))))
       (_
        (logger:info "Task ~s status: ~p" (list task-id task-status))
        `#(noreply ,(set-state-metrics state new-metrics))))))

  ;; Phase 4.5: Store blocking request from agent worker
  ((`#(blocking-request ,request) state)
   (logger:notice "Agent blocking request: ~p" (list (maps:get 'request-id request 'unknown)))
   (let ((pending (state-pending-requests state)))
     `#(noreply ,(set-state-pending-requests state (cons request pending)))))

  ;; Phase 4.5: Resolve blocking request from external handler
  ((`#(resolve-request ,request-id ,response) state)
   (let ((pending (state-pending-requests state)))
     (case (find-pending-request request-id pending)
       ('false
        (logger:warning "No pending request ~p" (list request-id))
        `#(noreply ,state))
       (request
        (let ((worker-pid (maps:get 'worker-pid request)))
          ;; Send response back to CL via agent-worker
          (gen_server:cast worker-pid `#(resolve-blocking ,request-id ,response)))
        `#(noreply ,(set-state-pending-requests state
                      (remove-pending-request request-id pending)))))))

  ;; Phase 5: Spawn a sub-agent on behalf of a parent CL worker
  ((`#(spawn-sub-agent ,config) state)
   (let ((parent-pid (maps:get 'parent-pid config 'undefined))
         (sub-agent-id (maps:get 'agent-id config
                         (make-agent-id))))
     (logger:info "Conductor dispatching sub-agent ~p for parent ~p"
                   (list sub-agent-id parent-pid))
     (dispatch-sub-agent config parent-pid)
     `#(noreply ,state)))

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
  "Execute a scheduled action. Fast-path runs directly; slow-path spawns agent.
   Actions with action-type 'claude dispatch to Claude workers."
  (case (maps:get 'requires-llm action 'false)
    ('true
     (case (maps:get 'action-type action 'cl)
       ('claude
        ;; Check rate limiting — skip if same task type already running
        (let ((task-type (maps:get 'id action 'unknown)))
          (case (claude-task-running-p task-type)
            ('true
             (logger:info "Skipping ~p — already running" (list task-type)))
            ('false
             (spawn-claude-for-work action)))))
       ('agentic
        ;; Phase 4.4: Dispatch to CL agentic agent
        (dispatch-agentic-agent action))
       (_
        (spawn-agent-for-work action)))
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
;;; Claude agent spawning
;;; ============================================================

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
      (io_lib:format "Task type: ~p~nPayload: ~p~nAnalyze and report findings."
                     (list work-type payload)))))

;;; ============================================================
;;; Infrastructure watcher scheduling
;;; ============================================================

(defun schedule-infra-watcher ()
  "Schedule the infrastructure watcher to run periodically."
  (let* ((prompt (read-prompt-file "config/infra-watcher-prompt.md"))
         (mcp-config (mcp-config-path "config/cortex-mcp.json")))
    (schedule
      `#M(id infra-watcher
          interval 300
          recurring true
          requires-llm true
          action-type claude
          prompt ,prompt
          mcp-config ,mcp-config
          timeout 120000
          max-turns 20
          allowed-tools "mcp__cortex__cortex_status,mcp__cortex__cortex_schema,mcp__cortex__cortex_query,mcp__cortex__cortex_entity_detail"))))

(defun process-task-result (result)
  "Process a completed task result. Log findings, escalate if needed."
  (let ((data (maps:get 'result result #M())))
    (case (maps:get #"status" data 'undefined)
      (#"critical"
       (logger:error "CRITICAL: Infrastructure anomaly detected!")
       (logger:error "Details: ~p" (list data)))
      (#"warning"
       (logger:warning "Infrastructure warning: ~p"
                       (list (maps:get #"summary" data #"no summary"))))
      (_
       (logger:info "Infrastructure check: ~p"
                    (list (maps:get #"summary" data #"all clear")))))))

;;; ============================================================
;;; File reading utilities
;;; ============================================================

(defun read-prompt-file (relative-path)
  "Read a prompt file relative to the LFE config directory."
  (case (file:read_file relative-path)
    (`#(ok ,content) (binary_to_list content))
    (`#(error ,_reason)
     (logger:warning "Could not read prompt file ~s" (list relative-path))
     "Analyze infrastructure and report findings.")))

(defun mcp-config-path (relative-path)
  "Resolve MCP config path. Returns absolute path or undefined."
  (case (filelib:is_file relative-path)
    ('true (filename:absname relative-path))
    ('false 'undefined)))

;;; ============================================================
;;; Rate limiting
;;; ============================================================

(defun claude-task-running-p (task-type)
  "Check if a Claude task of this type is already running."
  (let ((agents (claude-sup:list-claude-agents)))
    (lists:any
      (lambda (child)
        (case child
          (`#(,_id ,pid ,_type ,_modules)
           (if (is_pid pid)
             (try
               (let ((status (claude-worker:get-status pid)))
                 (=:= (maps:get 'task-type status 'undefined) task-type))
               (catch (`#(,_ ,_ ,_) 'false)))
             'false))
          (_ 'false)))
      agents)))

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
        timers-cancelled ,(maps:get 'timers-cancelled metrics 0)
        tasks-completed ,(maps:get 'tasks-completed metrics 0)
        consecutive-failures ,(maps:get 'consecutive-failures metrics 0)
        pending-requests ,(length (state-pending-requests state)))))

;;; ============================================================
;;; Phase 4.4: Agentic agent dispatch
;;; ============================================================

(defun dispatch-agentic-agent (action)
  "Spawn a CL agent and run an agentic prompt on it.
   Runs asynchronously to avoid blocking the conductor tick loop."
  (let* ((agent-id (list_to_atom
                    (++ "agentic-" (integer_to_list (erlang:unique_integer '(positive))))))
         (prompt (maps:get 'prompt action ""))
         (capabilities (maps:get 'capabilities action '()))
         (max-turns (maps:get 'max-turns action 25))
         (config `#M(agent-id ,agent-id
                     name ,(maps:get 'name action "agentic-worker"))))
    (spawn
     (lambda ()
       (case (catch (agent-sup:spawn-agent config))
         (`#(ok ,pid)
          (logger:info "Agentic agent ~p spawned as ~p" (list agent-id pid))
          (case (catch (agent-worker:agentic-prompt pid prompt
                  `#M(capabilities ,capabilities max-turns ,max-turns)))
            (`#(ok ,result)
             (gen_server:cast 'conductor
               `#(task-result #M(task-id ,agent-id
                                 status complete
                                 result ,result))))
            (`#(error ,reason)
             (gen_server:cast 'conductor
               `#(task-result #M(task-id ,agent-id
                                 status failed
                                 error ,reason))))
            (`#(EXIT ,reason)
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
                              error ,reason))))
         (`#(EXIT ,reason)
          (logger:warning "Failed to spawn agentic agent ~p: ~p"
                          (list agent-id reason))
          (gen_server:cast 'conductor
            `#(task-result #M(task-id ,agent-id
                              status failed
                              error ,reason)))))))))

;;; ============================================================
;;; Phase 5: Sub-agent dispatch
;;; ============================================================

(defun dispatch-sub-agent (config parent-pid)
  "Spawn a CL agent worker as a sub-agent and run its task.
   When complete, sends #(sub-agent-complete result) to parent-pid.
   Modeled after dispatch-agentic-agent but with parent notification."
  (let* ((agent-id (maps:get 'agent-id config
                     (list_to_atom
                       (++ "sub-" (integer_to_list
                                    (erlang:unique_integer '(positive)))))))
         (prompt (maps:get 'task config ""))
         (system-prompt (maps:get 'system-prompt config ""))
         (capabilities (maps:get 'capabilities config '()))
         (max-turns (maps:get 'max-turns config 25))
         (worker-config `#M(agent-id ,agent-id
                            name ,(maps:get 'name config "sub-agent"))))
    (spawn
      (lambda ()
        (case (catch (agent-sup:spawn-agent worker-config))
          (`#(ok ,pid)
           (logger:info "Sub-agent ~p spawned as ~p for parent ~p"
                         (list agent-id pid parent-pid))
           (let ((result
                   (case (catch (agent-worker:agentic-prompt pid prompt
                           `#M(capabilities ,capabilities max-turns ,max-turns)))
                     (`#(ok ,r) `#M(status complete result ,r))
                     (`#(error ,reason) `#M(status failed error ,reason))
                     (`#(EXIT ,reason) `#M(status failed error ,reason)))))
             ;; Notify parent worker that sub-agent is done
             (if (is_pid parent-pid)
               (gen_server:cast parent-pid
                 `#(sub-agent-complete ,(maps:put 'agent-id agent-id result)))
               (logger:warning "Sub-agent ~p has no valid parent pid" (list agent-id)))
             ;; Also report to conductor metrics
             (gen_server:cast 'conductor
               `#(task-result #M(task-id ,agent-id
                                  status ,(maps:get 'status result 'unknown)
                                  result ,result)))))
          (`#(error ,reason)
           (logger:warning "Failed to spawn sub-agent ~p: ~p"
                           (list agent-id reason))
           (if (is_pid parent-pid)
             (gen_server:cast parent-pid
               `#(sub-agent-complete #M(agent-id ,agent-id
                                        status failed
                                        error ,reason)))
             'ok))
          (`#(EXIT ,reason)
           (logger:warning "Failed to spawn sub-agent ~p: ~p"
                           (list agent-id reason))
           (if (is_pid parent-pid)
             (gen_server:cast parent-pid
               `#(sub-agent-complete #M(agent-id ,agent-id
                                        status failed
                                        error ,reason)))
             'ok)))))))

;;; ============================================================
;;; Phase 4.5: Pending request helpers
;;; ============================================================

(defun find-pending-request (request-id pending)
  "Find a pending request by its ID. Returns the request map or false."
  (case pending
    ('() 'false)
    ((cons req rest)
     (if (=:= (maps:get 'request-id req 'undefined) request-id)
       req
       (find-pending-request request-id rest)))))

(defun remove-pending-request (request-id pending)
  "Remove a pending request by its ID."
  (lists:filter
    (lambda (req)
      (/= (maps:get 'request-id req 'undefined) request-id))
    pending))
