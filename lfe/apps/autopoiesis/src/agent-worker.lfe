(defmodule agent-worker
  (behaviour gen_server)
  (export
    ;; gen_server callbacks
    (start_link 1) (init 1)
    (handle_call 3) (handle_cast 2) (handle_info 2)
    (terminate 2) (code_change 3)
    ;; Client API (Phase 1-3)
    (cognitive-cycle 2) (snapshot 1) (inject-observation 2)
    (get-status 1)
    ;; Client API (Phase 4)
    (agentic-prompt 2) (agentic-prompt 3)
    (query-thoughts 2) (list-capabilities 1)
    (invoke-capability 2) (invoke-capability 3)
    (checkout-snapshot 2) (diff-snapshots 3)
    (create-branch 2) (create-branch 3)
    (list-branches 1) (switch-branch 2)
    ;; Client API (Phase 5)
    (spawn-sub-agent 2) (query-sub-agent 2)
    (save-session 2) (resume-session 2)
    ;; Internal — exported for testing
    (build-cl-command 1) (parse-cl-response 1)))

;;; ============================================================
;;; Client API (Phase 1-3)
;;; ============================================================

(defun start_link (agent-config)
  (gen_server:start_link 'agent-worker (list agent-config) '()))

(defun cognitive-cycle (pid environment)
  "Run one cognitive cycle on the agent."
  (gen_server:call pid `#(cognitive-cycle ,environment) 30000))

(defun snapshot (pid)
  "Create a snapshot of the agent's state."
  (gen_server:call pid 'snapshot 10000))

(defun inject-observation (pid observation)
  "Inject an observation into the agent."
  (gen_server:call pid `#(inject-observation ,observation) 5000))

(defun get-status (pid)
  "Get agent worker status."
  (gen_server:call pid 'status 5000))

;;; ============================================================
;;; Client API (Phase 4)
;;; ============================================================

(defun agentic-prompt (pid prompt)
  "Run agentic loop on agent with default options."
  (gen_server:call pid `#(agentic-prompt ,prompt #M()) 600000))

(defun agentic-prompt (pid prompt opts)
  "Run agentic loop with options map (capabilities, max-turns)."
  (gen_server:call pid `#(agentic-prompt ,prompt ,opts) 600000))

(defun query-thoughts (pid last-n)
  "Query agent's recent thoughts."
  (gen_server:call pid `#(query-thoughts ,last-n) 5000))

(defun list-capabilities (pid)
  "List agent's available capabilities."
  (gen_server:call pid 'list-capabilities 5000))

(defun invoke-capability (pid cap-name)
  "Invoke a capability by name with no args."
  (gen_server:call pid `#(invoke-capability ,cap-name ()) 10000))

(defun invoke-capability (pid cap-name args)
  "Invoke a capability by name with args."
  (gen_server:call pid `#(invoke-capability ,cap-name ,args) 10000))

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
  (gen_server:call pid 'list-branches 5000))

(defun switch-branch (pid name)
  "Switch to a branch."
  (gen_server:call pid `#(switch-branch ,name) 10000))

;;; ============================================================
;;; Client API (Phase 5: Meta-Agent)
;;; ============================================================

(defun spawn-sub-agent (pid agent-config)
  "Request the worker to spawn a sub-agent via LFE supervision.
   Returns #(ok response) or #(error reason)."
  (gen_server:call pid `#(spawn-sub-agent ,agent-config) 30000))

(defun query-sub-agent (pid agent-id)
  "Query the status of a sub-agent spawned by this worker."
  (gen_server:call pid `#(query-sub-agent ,agent-id) 5000))

(defun save-session (pid name)
  "Save the current session state for later resumption."
  (gen_server:call pid `#(save-session ,name) 10000))

(defun resume-session (pid name)
  "Resume a previously saved session."
  (gen_server:call pid `#(resume-session ,name) 10000))

;;; ============================================================
;;; gen_server callbacks
;;; ============================================================

(defun init
  (((list agent-config))
   (let* ((agent-id (maps:get 'agent-id agent-config))
          (command (build-cl-command agent-config))
          (port (open-cl-port command)))
     ;; Send init command to CL worker
     (port-send port `(:init :agent-id ,agent-id
                             :name ,(maps:get 'name agent-config agent-id)))
     (case (port-receive port 10000)
       (`#(ok ,_response)
        (logger:info "Agent ~s initialized" (list agent-id))
        ;; Schedule heartbeat check timer (Phase 4.1)
        (erlang:send_after 30000 (self) 'check-heartbeat)
        `#(ok #M(port ,port
                 agent-id ,agent-id
                 config ,agent-config
                 started ,(erlang:system_time 'second)
                 last-heartbeat ,(erlang:system_time 'second))))
       (`#(error ,reason)
        (catch (erlang:port_close port))
        `#(stop #(init-failed ,reason)))
       ('timeout
        (catch (erlang:port_close port))
        `#(stop init-timeout))))))

(defun handle_call
  ;; Cognitive cycle
  ((`#(cognitive-cycle ,environment) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:cognitive-cycle :environment ,environment))
     (case (port-receive port 30000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Snapshot
  (('snapshot _from state)
   (let ((port (maps:get 'port state)))
     (port-send port '(:snapshot))
     (case (port-receive port 10000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Inject observation
  ((`#(inject-observation ,obs) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:inject-observation :content ,obs))
     (case (port-receive port 5000)
       (`#(ok ,_response)
        `#(reply ok ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Status (Phase 4.1: includes heartbeat info)
  (('status _from state)
   (let* ((uptime (- (erlang:system_time 'second)
                     (maps:get 'started state)))
          (last-hb (maps:get 'last-heartbeat state 0))
          (hb-age (- (erlang:system_time 'second) last-hb)))
     `#(reply #M(agent-id ,(maps:get 'agent-id state)
                 uptime ,uptime
                 port-alive ,(erlang:port_info (maps:get 'port state))
                 last-heartbeat ,last-hb
                 heartbeat-age-seconds ,hb-age
                 healthy ,(=< hb-age 30))
              ,state)))

  ;; Phase 4.3: Agentic prompt with streaming thought collection
  ((`#(agentic-prompt ,prompt ,opts) from state)
   (let* ((port (maps:get 'port state))
          (caps (maps:get 'capabilities opts '()))
          (max-turns (maps:get 'max-turns opts 25))
          (msg `(:agentic-prompt :prompt ,prompt
                                 :capabilities ,caps
                                 :max-turns ,max-turns)))
     (port-send port msg)
     ;; Collect streaming thoughts with 5 min total timeout
     (let ((result (collect-agentic-response port 300000 '())))
       (gen_server:reply from result)
       `#(noreply ,state))))

  ;; Phase 4.3: Query thoughts
  ((`#(query-thoughts ,n) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:query-thoughts :last-n ,n))
     (case (port-receive port 5000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Phase 4.3: List capabilities
  (('list-capabilities _from state)
   (let ((port (maps:get 'port state)))
     (port-send port '(:list-capabilities))
     (case (port-receive port 5000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Phase 4.3: Invoke capability
  ((`#(invoke-capability ,cap-name ,args) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:invoke-capability :name ,cap-name :args ,args))
     (case (port-receive port 10000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Phase 4.3: Checkout snapshot
  ((`#(checkout ,id) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:checkout :snapshot-id ,id))
     (case (port-receive port 10000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Phase 4.3: Diff snapshots
  ((`#(diff ,from-id ,to-id) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:diff :from ,from-id :to ,to-id))
     (case (port-receive port 10000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Phase 4.3: Create branch (without from-snapshot)
  ((`#(create-branch ,name) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:create-branch :name ,name))
     (case (port-receive port 5000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Phase 4.3: Create branch (with from-snapshot)
  ((`#(create-branch ,name ,from) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:create-branch :name ,name :from ,from))
     (case (port-receive port 5000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Phase 4.3: List branches
  (('list-branches _from state)
   (let ((port (maps:get 'port state)))
     (port-send port '(:list-branches))
     (case (port-receive port 5000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Phase 4.3: Switch branch
  ((`#(switch-branch ,name) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:switch-branch :name ,name))
     (case (port-receive port 10000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Phase 5: Spawn sub-agent
  ((`#(spawn-sub-agent ,config) _from state)
   (let* ((port (maps:get 'port state))
          (msg `(:spawn-sub-agent
                 :agent-id ,(maps:get 'agent-id config "")
                 :name ,(maps:get 'name config "sub-agent")
                 :task ,(maps:get 'task config "")
                 :capabilities ,(maps:get 'capabilities config '())
                 :max-turns ,(maps:get 'max-turns config 25))))
     (port-send port msg)
     (case (port-receive port 10000)
       (`#(ok ,response) `#(reply #(ok ,response) ,state))
       (`#(error ,reason) `#(reply #(error ,reason) ,state))
       ('timeout `#(reply #(error timeout) ,state)))))

  ;; Phase 5: Query sub-agent
  ((`#(query-sub-agent ,agent-id) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:query-sub-agent :agent-id ,agent-id))
     (case (port-receive port 5000)
       (`#(ok ,response) `#(reply #(ok ,response) ,state))
       (`#(error ,reason) `#(reply #(error ,reason) ,state))
       ('timeout `#(reply #(error timeout) ,state)))))

  ;; Phase 5: Save session
  ((`#(save-session ,name) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:save-session :name ,name))
     (case (port-receive port 10000)
       (`#(ok ,response) `#(reply #(ok ,response) ,state))
       (`#(error ,reason) `#(reply #(error ,reason) ,state))
       ('timeout `#(reply #(error timeout) ,state)))))

  ;; Phase 5: Resume session
  ((`#(resume-session ,name) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:resume-session :name ,name))
     (case (port-receive port 10000)
       (`#(ok ,response) `#(reply #(ok ,response) ,state))
       (`#(error ,reason) `#(reply #(error ,reason) ,state))
       ('timeout `#(reply #(error timeout) ,state)))))

  ;; Unknown
  ((msg _from state)
   `#(reply #(error #(unknown-call ,msg)) ,state)))

(defun handle_cast
  ;; Phase 4.5: Resolve a blocking request by sending response to CL
  ((`#(resolve-blocking ,request-id ,response) state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:blocking-response :id ,request-id :response ,response)))
   `#(noreply ,state))

  ;; Phase 5: Sub-agent completed — forward result to CL worker
  ((`#(sub-agent-complete ,result-map) state)
   (let* ((agent-id (maps:get 'agent-id result-map 'undefined))
          (status (maps:get 'status result-map 'unknown))
          (result (maps:get 'result result-map 'undefined))
          (error-val (maps:get 'error result-map 'undefined))
          (result-str (lists:flatten
                        (io_lib:format "~p" (list (if (=:= status 'complete)
                                                     result error-val))))))
     (logger:info "Sub-agent ~p completed with status ~p" (list agent-id status))
     (port-send (maps:get 'port state)
       `(:sub-agent-result :agent-id ,agent-id
                           :status ,status
                           :result ,result-str
                           :error ,(if (=:= status 'failed) result-str 'nil)))
     `#(noreply ,state)))

  (('stop state)
   `#(stop normal ,state))
  ((_msg state)
   `#(noreply ,state)))

(defun handle_info
  ;; Port closed — CL process exited
  ((`#(,_port #(exit_status ,code)) state)
   (logger:warning "CL worker exited with code ~p, agent ~s"
                   (list code (maps:get 'agent-id state)))
   `#(stop #(port-died ,code) ,state))

  ;; Complete line from port (unsolicited message from CL)
  ((`#(,_port #(data #(eol ,line))) state)
   (let ((new-state (handle-unsolicited-message line state)))
     `#(noreply ,new-state)))

  ;; Partial line from port (unsolicited, line exceeded buffer)
  ((`#(,_port #(data #(noeol ,_line))) state)
   (logger:warning "Partial unsolicited line from CL worker for ~s"
                   (list (maps:get 'agent-id state)))
   `#(noreply ,state))

  ;; Phase 4.1: Heartbeat check timer
  (('check-heartbeat state)
   (let* ((last-hb (maps:get 'last-heartbeat state 0))
          (age (- (erlang:system_time 'second) last-hb)))
     (if (> age 60)
       (progn
         (logger:error "Heartbeat timeout for agent ~s (last: ~ps ago)"
                       (list (maps:get 'agent-id state) age))
         `#(stop #(heartbeat-timeout ,age) ,state))
       (progn
         (if (> age 30)
           (logger:warning "Heartbeat stale for agent ~s (~ps)"
                           (list (maps:get 'agent-id state) age))
           'ok)
         ;; Reschedule check
         (erlang:send_after 30000 (self) 'check-heartbeat)
         `#(noreply ,state)))))

  ((_msg state)
   `#(noreply ,state)))

(defun terminate (_reason state)
  (let ((port (maps:get 'port state 'undefined)))
    (if (is_port port)
      (progn
        ;; Try graceful shutdown
        (catch (port-send port '(:shutdown)))
        (timer:sleep 1000)
        ;; Force close
        (catch (erlang:port_close port)))))
  'ok)

(defun code_change (_old-vsn state _extra)
  `#(ok ,state))

;;; ============================================================
;;; Port communication
;;; ============================================================

(defun build-cl-command (config)
  "Build the sbcl command to invoke the CL worker."
  (let* ((sbcl (maps:get 'sbcl-path config
                  (application:get_env 'autopoiesis 'sbcl_path "sbcl")))
         (script (maps:get 'cl-worker-script config
                   (application:get_env 'autopoiesis 'cl_worker_script
                     "../scripts/agent-worker.lisp"))))
    (lists:flatten (io_lib:format "~s --script ~s" (list sbcl script)))))

(defun open-cl-port (command)
  "Open a port to a CL worker process."
  (erlang:open_port `#(spawn ,command)
                    '(#(line 65536) binary exit_status use_stdio)))

(defun port-send (port msg)
  "Send an S-expression message to the CL worker via port."
  (let ((data (list (lfe_io:print1 msg) "\n")))
    (erlang:port_command port (unicode:characters_to_binary data))))

(defun port-receive (port timeout)
  "Receive and parse an S-expression response from the CL worker.
   Returns #(ok parsed-term) | #(error reason) | timeout"
  (receive
    ;; Complete line received
    (`#(,p #(data #(eol ,line))) (when (=:= p port))
     (parse-cl-response line))
    ;; Line exceeded buffer
    (`#(,p #(data #(noeol ,line))) (when (=:= p port))
     (logger:warning "Received partial line from CL worker: ~p" (list line))
     `#(error #(partial-line ,line)))
    (after timeout
      'timeout)))

(defun parse-cl-response (binary)
  "Parse an S-expression from binary port data.
   lfe_io:read_string returns #(ok (form ...)) — a list of all forms.
   We extract the first form and classify by its leading keyword."
  (let ((string (unicode:characters_to_list binary)))
    (case (lfe_io:read_string string)
      (`#(ok (,form . ,_rest-forms))
       (case form
         (`(:ok . ,_rest) `#(ok ,form))
         (`(:error . ,rest) `#(error ,rest))
         (`(:heartbeat . ,_rest) `#(ok ,form))
         (`(:thought . ,_rest) `#(ok ,form))
         (`(:blocking-request . ,_rest) `#(ok ,form))
         (other `#(ok ,other))))
      (`#(ok ())
       `#(error #(empty-response ,string)))
      (`#(error ,err)
       (logger:error "Failed to parse CL response: ~s (error: ~p)"
                     (list string err))
       `#(error #(parse-failed ,string))))))

;;; ============================================================
;;; Phase 4.3: Streaming response collection
;;; ============================================================

(defun collect-agentic-response (port timeout thoughts)
  "Collect streaming thoughts until final :ok or :error response.
   Thoughts arrive as (:thought ...) messages before the final response."
  (case (port-receive port timeout)
    (`#(ok (:thought . ,rest))
     ;; Accumulate thought, continue collecting
     (collect-agentic-response port timeout (cons rest thoughts)))
    (`#(ok (:ok . ,rest))
     ;; Final response — return result with collected thoughts
     `#(ok #M(result ,rest thoughts ,(lists:reverse thoughts))))
    (`#(ok (:error . ,rest))
     `#(error ,rest))
    (`#(error ,reason)
     `#(error ,reason))
    ('timeout
     `#(error #(timeout ,(length thoughts) thoughts-collected)))
    (_other
     ;; Unexpected message (e.g. heartbeat during agentic loop), skip it
     (collect-agentic-response port timeout thoughts))))

;;; ============================================================
;;; Unsolicited message handling (Phase 4.1 + 4.5)
;;; ============================================================

(defun handle-unsolicited-message (data state)
  "Handle messages initiated by CL worker (heartbeats, blocking requests).
   Returns updated state."
  (case (parse-cl-response data)
    ;; Phase 4.1: Update heartbeat timestamp
    (`#(ok (:heartbeat . ,_info))
     (maps:put 'last-heartbeat (erlang:system_time 'second) state))

    ;; Phase 4.5: Route blocking request to conductor
    (`#(ok (:blocking-request . ,details))
     (let* ((agent-id (maps:get 'agent-id state))
            (request-id (proplists:get_value ':id details))
            (prompt (proplists:get_value ':prompt details))
            (request-type (proplists:get_value ':type details 'input)))
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

    ;; Phase 5: Spawn request from CL tool during agentic loop
    (`#(ok (:spawn-request . ,details))
     (let* ((agent-id (proplists:get_value 'agent-id details))
            (name (proplists:get_value 'name details "sub-agent"))
            (task (proplists:get_value 'task details ""))
            (capabilities (proplists:get_value 'capabilities details '()))
            (max-turns (proplists:get_value 'max-turns details 25)))
       (logger:info "Spawn request from CL: ~p (~p)" (list name agent-id))
       (gen_server:cast 'conductor
         `#(spawn-sub-agent ,(maps:from_list
                               (list `#(agent-id ,agent-id)
                                     `#(name ,name)
                                     `#(task ,task)
                                     `#(capabilities ,capabilities)
                                     `#(max-turns ,max-turns)
                                     `#(parent-worker ,(self))))))
       state))

    ;; Phase 5: Sub-agent result notification (unsolicited)
    (`#(ok (:sub-agent-result . ,details))
     (let* ((agent-id (proplists:get_value 'agent-id details))
            (status (proplists:get_value 'status details)))
       (logger:info "Sub-agent ~p result: ~p" (list agent-id status))
       state))

    (`#(error ,reason)
     (logger:warning "Unparseable unsolicited message from ~s: ~p"
                     (list (maps:get 'agent-id state) reason))
     state)
    (_other
     state)))
