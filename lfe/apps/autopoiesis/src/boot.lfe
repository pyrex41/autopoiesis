(defmodule boot
  (export (main 1) (start 0)
          ;; Exported for testing
          (parse-args 1)))

;;; ============================================================
;;; CLI entry point
;;; ============================================================

(defun main (args)
  "Escript / CLI entry point for Jarvis.
   Usage:
     jarvis \"deploy the new feature to staging\"
     jarvis --resume
     jarvis --branch experiment \"try a different approach\"
     jarvis --status"
  (case (parse-args args)
    (`#(prompt ,prompt)
     (start)
     (run-prompt prompt))
    (`#(resume ,session-name)
     (start)
     (resume-session session-name))
    (`#(branch ,branch-name ,prompt)
     (start)
     (run-branched branch-name prompt))
    ('status
     (start)
     (show-status))
    ('help
     (print-usage))
    (`#(error ,msg)
     (io:format "Error: ~s~n" (list msg))
     (print-usage))))

;;; ============================================================
;;; Application bootstrap
;;; ============================================================

(defun start ()
  "Boot the OTP application (supervisor tree, conductor, etc.)."
  (application:ensure_all_started 'autopoiesis))

;;; ============================================================
;;; CLI actions
;;; ============================================================

(defun run-prompt (prompt)
  "Run a prompt through the agentic pipeline."
  (io:format "Jarvis: Processing...~n")
  ;; Schedule an agentic action via conductor
  (conductor:schedule
    `#M(id jarvis-cli
        interval 0
        recurring false
        requires-llm true
        action-type agentic
        prompt ,prompt
        max-turns 25))
  ;; Wait for result
  (receive
    (`#(jarvis-result ,result)
     (io:format "~nResult: ~p~n" (list result)))
    (after 300000
      (io:format "~nTimeout waiting for result.~n"))))

(defun resume-session (session-name)
  "Resume a previously saved session."
  (io:format "Jarvis: Resuming session '~s'...~n" (list session-name))
  ;; Find an available agent worker and resume
  (case (agent-sup:spawn-agent
          `#M(agent-id ,(list_to_atom (++ "resume-" session-name))
              name ,(++ "resume-" session-name)))
    (`#(ok ,pid)
     (case (agent-worker:resume-session pid session-name)
       (`#(ok ,state)
        (io:format "Session '~s' restored. Agent ready.~n" (list session-name))
        (io:format "State: ~p~n" (list state)))
       (`#(error ,reason)
        (io:format "Failed to resume: ~p~n" (list reason)))))
    (`#(error ,reason)
     (io:format "Failed to spawn agent: ~p~n" (list reason)))))

(defun run-branched (branch-name prompt)
  "Create a cognitive branch and run a prompt on it."
  (io:format "Jarvis: Branching '~s' and processing...~n" (list branch-name))
  (case (agent-sup:spawn-agent
          `#M(agent-id ,(list_to_atom (++ "branch-" branch-name))
              name ,(++ "branch-" branch-name)))
    (`#(ok ,pid)
     (case (agent-worker:create-branch pid branch-name)
       (`#(ok ,_)
        (case (agent-worker:agentic-prompt pid prompt)
          (`#(ok ,result)
           (io:format "~nBranch '~s' result: ~p~n" (list branch-name result)))
          (`#(error ,reason)
           (io:format "Failed: ~p~n" (list reason)))))
       (`#(error ,reason)
        (io:format "Failed to create branch: ~p~n" (list reason)))))
    (`#(error ,reason)
     (io:format "Failed to spawn agent: ~p~n" (list reason)))))

(defun show-status ()
  "Display current system status."
  (let ((status (conductor:status)))
    (io:format "~n=== Jarvis Status ===~n")
    (io:format "Timers:      ~p scheduled~n"
               (list (maps:get 'timer-heap-size status 0)))
    (io:format "Events:      ~p queued~n"
               (list (maps:get 'event-queue-length status 0)))
    (io:format "Tasks done:  ~p~n"
               (list (maps:get 'tasks-completed status 0)))
    (io:format "Ticks:       ~p~n"
               (list (maps:get 'tick-count status 0)))
    (io:format "Failures:    ~p consecutive~n"
               (list (maps:get 'consecutive-failures status 0)))
    (io:format "Pending:     ~p blocking requests~n"
               (list (maps:get 'pending-requests status 0)))
    (io:format "=====================~n")))

;;; ============================================================
;;; Argument parsing
;;; ============================================================

(defun parse-args (args)
  "Parse CLI arguments into action tuples."
  (case args
    ('() 'help)
    ((list "--help") 'help)
    ((list "-h") 'help)
    ((list "--status") 'status)
    ((list "--resume") `#(resume "default"))
    ((list "--resume" name) `#(resume ,name))
    ((cons "--branch" (cons name rest))
     (case rest
       ('() `#(error "Branch requires a prompt"))
       (_ `#(branch ,name ,(string:join rest " ")))))
    (_
     ;; Everything else is a prompt
     `#(prompt ,(string:join args " ")))))

(defun print-usage ()
  (io:format "~nUsage: jarvis [OPTIONS] [PROMPT]~n~n")
  (io:format "Options:~n")
  (io:format "  --status              Show system status~n")
  (io:format "  --resume [NAME]       Resume a saved session~n")
  (io:format "  --branch NAME PROMPT  Create branch and run prompt~n")
  (io:format "  --help, -h            Show this help~n~n")
  (io:format "Examples:~n")
  (io:format "  jarvis \"deploy the new feature to staging\"~n")
  (io:format "  jarvis --resume~n")
  (io:format "  jarvis --branch experiment \"try a different approach\"~n"))
