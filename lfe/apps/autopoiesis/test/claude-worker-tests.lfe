(defmodule claude-worker-tests
  (export all))

;;; EUnit tests for claude-worker pure functions.
;;; Run with: rebar3 eunit --module=claude-worker-tests

;;; ============================================================
;;; build-claude-command tests
;;; ============================================================

(defun build_claude_command_basic_test ()
  "build-claude-command should construct a shell command string."
  (let ((cmd (claude-worker:build-claude-command #M(prompt "hello"))))
    (assert-truthy (is_list cmd))
    ;; Should include -p flag with quoted prompt
    (assert-contains "-p 'hello'" cmd)
    ;; Should include stream-json format
    (assert-contains "--output-format stream-json" cmd)
    ;; Should include dangerously-skip-permissions
    (assert-contains "--dangerously-skip-permissions" cmd)
    ;; Should include --verbose (required for stream-json with -p)
    (assert-contains "--verbose" cmd)
    ;; Should redirect stdin from /dev/null
    (assert-contains "</dev/null" cmd)))

(defun build_claude_command_with_mcp_test ()
  "build-claude-command should include MCP config when specified."
  (let ((cmd (claude-worker:build-claude-command
               #M(prompt "test" mcp-config "/tmp/mcp.json"))))
    (assert-contains "--mcp-config /tmp/mcp.json" cmd)))

(defun build_claude_command_without_mcp_test ()
  "build-claude-command should not include MCP config when not specified."
  (let ((cmd (claude-worker:build-claude-command #M(prompt "test"))))
    (assert-not-contains "--mcp-config" cmd)))

(defun build_claude_command_with_max_turns_test ()
  "build-claude-command should include custom max-turns."
  (let ((cmd (claude-worker:build-claude-command
               #M(prompt "test" max-turns 10))))
    (assert-contains "--max-turns 10" cmd)))

(defun build_claude_command_default_max_turns_test ()
  "build-claude-command should default to 50 max-turns."
  (let ((cmd (claude-worker:build-claude-command #M(prompt "test"))))
    (assert-contains "--max-turns 50" cmd)))

(defun build_claude_command_with_allowed_tools_test ()
  "build-claude-command should include allowed tools when specified."
  (let ((cmd (claude-worker:build-claude-command
               #M(prompt "test"
                  allowed-tools "mcp__cortex__cortex_status"))))
    (assert-contains "--allowedTools mcp__cortex__cortex_status" cmd)))

(defun build_claude_command_without_allowed_tools_test ()
  "build-claude-command should not include --allowedTools when empty."
  (let ((cmd (claude-worker:build-claude-command #M(prompt "test"))))
    (assert-not-contains "--allowedTools" cmd)))

(defun build_claude_command_custom_path_test ()
  "build-claude-command should use custom claude path."
  (let ((cmd (claude-worker:build-claude-command
               #M(prompt "test" claude-path "/usr/local/bin/claude"))))
    (assert-contains "/usr/local/bin/claude" cmd)))

(defun build_claude_command_quotes_prompt_test ()
  "build-claude-command should single-quote the prompt for shell safety."
  (let ((cmd (claude-worker:build-claude-command #M(prompt "hello world"))))
    (assert-contains "-p 'hello world'" cmd)))

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

(defun assert-contains (substring str)
  "Assert that str contains substring."
  (case (string:find str substring)
    ('nomatch (error `#(assertion-failed substring-not-found ,substring)))
    (_ 'ok)))

(defun assert-not-contains (substring str)
  "Assert that str does NOT contain substring."
  (case (string:find str substring)
    ('nomatch 'ok)
    (_ (error `#(assertion-failed substring-found ,substring)))))
