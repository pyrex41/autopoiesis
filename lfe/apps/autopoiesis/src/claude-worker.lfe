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

;;; ============================================================
;;; Client API
;;; ============================================================

(defun start_link (task-config)
  (gen_server:start_link 'claude-worker (list task-config) '()))

(defun get-status (pid)
  "Get claude worker status."
  (gen_server:call pid 'status 5000))

;;; ============================================================
;;; gen_server callbacks
;;; ============================================================

(defun init
  (((list task-config))
   (let* ((task-id (maps:get 'task-id task-config
                     (make-task-id)))
          (shell-cmd (build-claude-command task-config))
          (timeout (maps:get 'timeout task-config 300000))
          ;; Use spawn (shell) with </dev/null to close stdin.
          ;; Claude CLI hangs when stdin is an Erlang port pipe.
          (port (erlang:open_port
                  `#(spawn ,shell-cmd)
                  '(#(line 65536)
                    binary
                    exit_status
                    use_stdio
                    stderr_to_stdout)))
          (timer-ref (erlang:send_after timeout (self) 'timeout))
          (started (erlang:system_time 'second)))
     `#(ok ,`#M(port ,port
                task-id ,task-id
                config ,task-config
                started ,started
                output-buffer ()
                status running
                timer-ref ,timer-ref
                timeout ,timeout)))))

(defun handle_call
  ;; Status
  (('status _from state)
   (let ((uptime (- (erlang:system_time 'second)
                    (maps:get 'started state))))
     `#(reply ,`#M(task-id ,(maps:get 'task-id state)
                   status ,(maps:get 'status state)
                   uptime ,uptime)
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
  ;; Streaming JSON line from Claude (complete line)
  ((`#(,_port #(data #(eol ,line))) state)
   (case (maps:get 'status state)
     ('running
      (let ((parsed (parse-json-line line)))
        (case parsed
          (`#(ok ,msg)
           `#(noreply ,(maps:update 'output-buffer
                         (++ (maps:get 'output-buffer state) (list msg))
                         state)))
          (`#(error ,_reason)
           `#(noreply ,state)))))
     (_
      `#(noreply ,state))))

  ;; Partial line (buffer overflow) — ignore
  ((`#(,_port #(data #(noeol ,_line))) state)
   `#(noreply ,state))

  ;; Claude process exited successfully
  ((`#(,_port #(exit_status 0)) state)
   (let ((result (parse-result (maps:get 'output-buffer state))))
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
   (case (maps:get 'status state)
     ('running
      (logger:warning "Claude worker ~s timed out after ~p ms"
                      (list (maps:get 'task-id state)
                            (maps:get 'timeout state)))
      (catch (erlang:port_close (maps:get 'port state)))
      (report-error (maps:get 'task-id state) 'timeout '())
      `#(stop timeout ,(maps:update 'status 'failed state)))
     (_
      `#(noreply ,state))))

  ((_msg state)
   `#(noreply ,state)))

(defun terminate (_reason state)
  (let ((port (maps:get 'port state 'undefined)))
    (if (is_port port)
      (catch (erlang:port_close port))))
  ;; Cancel timeout timer if active
  (let ((timer-ref (maps:get 'timer-ref state 'undefined)))
    (if (is_reference timer-ref)
      (erlang:cancel_timer timer-ref)))
  'ok)

(defun code_change (_old-vsn state _extra)
  `#(ok ,state))

;;; ============================================================
;;; Claude CLI command building
;;; ============================================================

(defun build-claude-command (config)
  "Build claude CLI shell command for non-interactive execution.
   Returns a shell command string with </dev/null to close stdin."
  (let* ((claude-path (ensure-string
                        (maps:get 'claude-path config
                          (find-claude-executable))))
         (prompt (ensure-string (maps:get 'prompt config "")))
         (mcp-config (maps:get 'mcp-config config 'undefined))
         (allowed-tools (ensure-string
                          (maps:get 'allowed-tools config "")))
         (max-turns (maps:get 'max-turns config 50))
         (args (list claude-path
                     "-p" (shell-quote prompt)
                     "--output-format" "stream-json"
                     "--verbose"
                     "--max-turns" (integer_to_list max-turns)
                     "--dangerously-skip-permissions"))
         ;; Add MCP config if specified
         (args2 (case mcp-config
                  ('undefined args)
                  (path (++ args (list "--mcp-config"
                                       (ensure-string path))))))
         ;; Add allowed tools if specified
         (args3 (case allowed-tools
                  ("" args2)
                  (tools (++ args2 (list "--allowedTools" tools))))))
    ;; Join args with spaces and redirect stdin from /dev/null
    (lists:flatten (++ (lists:join " " args3) " </dev/null"))))

(defun find-claude-executable ()
  "Find the claude executable path."
  (case (os:find_executable "claude")
    ('false "claude")
    (path path)))

(defun shell-quote (str)
  "Wrap a string in single quotes for shell, escaping internal single quotes."
  (let ((s (if (is_binary str) (binary_to_list str) str)))
    (lists:flatten
      (list "'" (shell-escape-single-quotes s) "'"))))

(defun shell-escape-single-quotes (str)
  "Replace ' with '\\'' in a string for safe shell quoting."
  (case str
    ('() '())
    ((cons 39 rest)  ;; 39 = single quote character
     (++ "'\\''" (shell-escape-single-quotes rest)))
    ((cons c rest)
     (cons c (shell-escape-single-quotes rest)))))

;;; ============================================================
;;; JSON parsing and result extraction
;;; ============================================================

(defun parse-json-line (binary)
  "Parse a JSON line from Claude's stream-json output."
  (try
    (let ((json (jsx:decode binary '(return_maps))))
      `#(ok ,json))
    (catch
      (`#(,_type ,_reason ,_stack)
       `#(error parse-failed)))))

(defun parse-result (messages)
  "Extract the final result from accumulated output-buffer messages.
   Messages is a list of already-parsed JSON maps.
   Returns the result map, or an error map if no result found."
  (case messages
    ('() #M(type error message "No output messages"))
    (_
     ;; Look for a 'result' type message
     (let ((result-msgs
             (lists:filter
               (lambda (msg)
                 (=:= (maps:get #"type" msg #"") #"result"))
               messages)))
       (case result-msgs
         ('()
          ;; No result message found — return the last message
          (lists:last messages))
         (_
          ;; Return the last result message
          (lists:last result-msgs)))))))

;;; ============================================================
;;; Result reporting
;;; ============================================================

(defun report-result (task-id result)
  "Report completed result to conductor."
  (catch (gen_server:cast 'conductor
           `#(task-result ,`#M(task-id ,task-id
                               status complete
                               result ,result)))))

(defun report-error (task-id reason output)
  "Report error to conductor."
  (catch (gen_server:cast 'conductor
           `#(task-result ,`#M(task-id ,task-id
                               status failed
                               error ,reason
                               output ,output)))))

;;; ============================================================
;;; Utilities
;;; ============================================================

(defun ensure-string (val)
  "Convert binary or atom to list string. Pass through lists."
  (cond ((is_binary val) (binary_to_list val))
        ((is_atom val) (atom_to_list val))
        ('true val)))

(defun make-task-id ()
  "Generate a unique task ID string."
  (let ((n (erlang:unique_integer '(positive))))
    (lists:flatten (io_lib:format "claude-task-~B" (list n)))))
