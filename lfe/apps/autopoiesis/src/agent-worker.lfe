(defmodule agent-worker
  (behaviour gen_server)
  (export
    ;; gen_server callbacks
    (start_link 1) (init 1)
    (handle_call 3) (handle_cast 2) (handle_info 2)
    (terminate 2) (code_change 3)
    ;; Client API
    (cognitive-cycle 2) (snapshot 1) (inject-observation 2)
    (get-status 1)
    ;; Internal — exported for testing
    (build-cl-command 1) (parse-cl-response 1)))

;;; ============================================================
;;; Client API
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
        `#(ok #M(port ,port
                 agent-id ,agent-id
                 config ,agent-config
                 started ,(erlang:system_time 'second))))
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

  ;; Status
  (('status _from state)
   (let ((uptime (- (erlang:system_time 'second)
                    (maps:get 'started state))))
     `#(reply #M(agent-id ,(maps:get 'agent-id state)
                 uptime ,uptime
                 port-alive ,(erlang:port_info (maps:get 'port state)))
              ,state)))

  ;; Unknown
  ((msg _from state)
   `#(reply #(error #(unknown-call ,msg)) ,state)))

(defun handle_cast
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
   (handle-unsolicited-message line state)
   `#(noreply ,state))

  ;; Partial line from port (unsolicited, line exceeded buffer)
  ((`#(,_port #(data #(noeol ,_line))) state)
   (logger:warning "Partial unsolicited line from CL worker for ~s"
                   (list (maps:get 'agent-id state)))
   `#(noreply ,state))

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
         (`(:blocking-request . ,_rest) `#(ok ,form))
         (other `#(ok ,other))))
      (`#(ok ())
       `#(error #(empty-response ,string)))
      (`#(error ,err)
       (logger:error "Failed to parse CL response: ~s (error: ~p)"
                     (list string err))
       `#(error #(parse-failed ,string))))))

(defun handle-unsolicited-message (data state)
  "Handle messages initiated by CL worker (heartbeats, blocking requests)."
  (case (parse-cl-response data)
    (`#(ok (:heartbeat . ,_info))
     ;; Just log for now — conductor will use these in Phase 3
     'ok)
    (`#(ok (:blocking-request :id ,id :prompt ,prompt :options ,opts))
     ;; TODO: Route to human interface in Phase 4
     (logger:info "Blocking request from ~s: ~s"
                  (list (maps:get 'agent-id state) prompt))
     'ok)
    (`#(error ,reason)
     (logger:warning "Unparseable unsolicited message from ~s: ~p"
                     (list (maps:get 'agent-id state) reason))
     'ok)
    (_other
     'ok)))
