(defmodule claude-worker-tests
  (export all))

;;; EUnit tests for claude-worker pure functions.
;;; Run with: rebar3 eunit --module=claude-worker-tests

;;; ============================================================
;;; build-claude-command tests
;;; ============================================================

(defun build_claude_command_basic_test ()
  "build-claude-command should construct claude CLI invocation."
  (let ((`#(,cmd ,args) (claude-worker:build-claude-command
                           #M(prompt "hello"))))
    (assert-truthy (is_list cmd))
    (assert-truthy (is_list args))
    ;; Should include -p flag
    (assert-truthy (lists:member "-p" args))
    ;; Should include prompt
    (assert-truthy (lists:member "hello" args))
    ;; Should include stream-json format
    (assert-truthy (lists:member "--output-format" args))
    (assert-truthy (lists:member "stream-json" args))
    ;; Should include dangerously-skip-permissions
    (assert-truthy (lists:member "--dangerously-skip-permissions" args))))

(defun build_claude_command_with_mcp_test ()
  "build-claude-command should include MCP config when specified."
  (let ((`#(,_cmd ,args) (claude-worker:build-claude-command
                            #M(prompt "test"
                               mcp-config "/tmp/mcp.json"))))
    (assert-truthy (lists:member "--mcp-config" args))
    (assert-truthy (lists:member "/tmp/mcp.json" args))))

(defun build_claude_command_without_mcp_test ()
  "build-claude-command should not include MCP config when not specified."
  (let ((`#(,_cmd ,args) (claude-worker:build-claude-command
                            #M(prompt "test"))))
    (assert-truthy (not (lists:member "--mcp-config" args)))))

(defun build_claude_command_with_max_turns_test ()
  "build-claude-command should include custom max-turns."
  (let ((`#(,_cmd ,args) (claude-worker:build-claude-command
                            #M(prompt "test" max-turns 10))))
    (assert-truthy (lists:member "--max-turns" args))
    (assert-truthy (lists:member "10" args))))

(defun build_claude_command_default_max_turns_test ()
  "build-claude-command should default to 50 max-turns."
  (let ((`#(,_cmd ,args) (claude-worker:build-claude-command
                            #M(prompt "test"))))
    (assert-truthy (lists:member "--max-turns" args))
    (assert-truthy (lists:member "50" args))))

(defun build_claude_command_with_allowed_tools_test ()
  "build-claude-command should include allowed tools when specified."
  (let ((`#(,_cmd ,args) (claude-worker:build-claude-command
                            #M(prompt "test"
                               allowed-tools "mcp__cortex__cortex_status"))))
    (assert-truthy (lists:member "--allowedTools" args))
    (assert-truthy (lists:member "mcp__cortex__cortex_status" args))))

(defun build_claude_command_without_allowed_tools_test ()
  "build-claude-command should not include --allowedTools when empty."
  (let ((`#(,_cmd ,args) (claude-worker:build-claude-command
                            #M(prompt "test"))))
    (assert-truthy (not (lists:member "--allowedTools" args)))))

(defun build_claude_command_custom_path_test ()
  "build-claude-command should use custom claude path."
  (let ((`#(,cmd ,_args) (claude-worker:build-claude-command
                            #M(prompt "test"
                               claude-path "/usr/local/bin/claude"))))
    (assert-equal "/usr/local/bin/claude" cmd)))

;;; ============================================================
;;; parse-result tests
;;; ============================================================

(defun parse_result_empty_test ()
  "parse-result should handle empty buffer."
  (let ((result (claude-worker:parse-result '())))
    (assert-truthy (is_map result))
    (assert-equal 'error (maps:get 'type result))))

(defun parse_result_with_result_msg_test ()
  "parse-result should extract result type message."
  (let ((msgs (list #M(#"type" #"assistant" #"content" #"thinking")
                    #M(#"type" #"result" #"content" #"final answer"))))
    (let ((result (claude-worker:parse-result msgs)))
      (assert-equal #"result" (maps:get #"type" result)))))

(defun parse_result_no_result_type_test ()
  "parse-result should return last message if no result type found."
  (let ((msgs (list #M(#"type" #"assistant" #"content" #"msg1")
                    #M(#"type" #"assistant" #"content" #"msg2"))))
    (let ((result (claude-worker:parse-result msgs)))
      (assert-equal #"msg2" (maps:get #"content" result)))))

(defun parse_result_multiple_results_test ()
  "parse-result should return the last result message."
  (let ((msgs (list #M(#"type" #"result" #"content" #"first")
                    #M(#"type" #"result" #"content" #"second"))))
    (let ((result (claude-worker:parse-result msgs)))
      (assert-equal #"second" (maps:get #"content" result)))))

(defun parse_result_single_message_test ()
  "parse-result should handle single message buffer."
  (let ((msgs (list #M(#"type" #"result" #"data" #"hello"))))
    (let ((result (claude-worker:parse-result msgs)))
      (assert-truthy (is_map result)))))

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun assert-truthy (val)
  "Assert value is truthy (not false, not undefined)."
  (case val
    ('false (error 'assertion-failed))
    ('undefined (error 'assertion-failed))
    (_ 'ok)))

(defun assert-equal (expected actual)
  "Assert expected equals actual."
  (case (== expected actual)
    ('true 'ok)
    ('false (error `#(assertion-failed expected ,expected actual ,actual)))))
