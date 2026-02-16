(defmodule agent-worker-tests
  (export all))

;;; EUnit tests for agent-worker pure functions.
;;; Run with: rebar3 eunit --module=agent-worker-tests
;;;
;;; Note: EUnit discovers functions ending in _test (underscore),
;;; so we use underscored names here despite LFE convention.

;;; ============================================================
;;; build-cl-command tests
;;; ============================================================

(defun build_cl_command_defaults_test ()
  "Uses application env defaults when config has no overrides."
  (let ((cmd (agent-worker:build-cl-command
               #M(agent-id "test-1"))))
    (assert-truthy (is_list cmd))
    (assert-truthy (/= 'nomatch (string:find cmd "sbcl")))
    (assert-truthy (/= 'nomatch (string:find cmd "agent-worker.lisp")))))

(defun build_cl_command_custom_paths_test ()
  "Respects explicit sbcl-path and cl-worker-script in config."
  (let ((cmd (agent-worker:build-cl-command
               #M(agent-id "test-2"
                  sbcl-path "/usr/local/bin/sbcl"
                  cl-worker-script "/opt/worker.lisp"))))
    (assert-truthy (/= 'nomatch (string:find cmd "/usr/local/bin/sbcl")))
    (assert-truthy (/= 'nomatch (string:find cmd "/opt/worker.lisp")))))

(defun build_cl_command_minimal_config_test ()
  "Works with minimal config containing only agent-id."
  (let ((cmd (agent-worker:build-cl-command
               #M(agent-id "minimal"))))
    (assert-truthy (is_list cmd))
    (assert-truthy (>= (length cmd) 10))))

(defun build_cl_command_special_chars_test ()
  "Handles paths with special characters correctly."
  (let ((cmd (agent-worker:build-cl-command
               #M(agent-id "test-3"
                  sbcl-path "/usr/local/bin/sbcl"
                  cl-worker-script "/path with spaces/worker.lisp"))))
    (assert-truthy (is_list cmd))
    ;; Command should be properly formatted with quotes
    (assert-truthy (/= 'nomatch (string:find cmd "/path with spaces/worker.lisp")))))

(defun build_cl_command_format_test ()
  "Validates the command format follows 'sbcl --script <path>' pattern."
  (let ((cmd (agent-worker:build-cl-command
               #M(agent-id "test-4"
                  sbcl-path "sbcl"
                  cl-worker-script "worker.lisp"))))
    (assert-truthy (/= 'nomatch (string:find cmd " --script ")))
    ;; Ensure script flag is present
    (assert-truthy (/= 'nomatch (string:find cmd "--script")))))

;;; ============================================================
;;; parse-cl-response tests
;;; ============================================================

(defun parse_cl_response_ok_test ()
  "Parses :ok tagged response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary "(:ok :type :init)"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-ok-match ,other))))))

(defun parse_cl_response_error_test ()
  "Parses :error tagged response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary "(:error :type :init-failed)"))))
    (case result
      (`#(error ,_reason) 'ok)
      (other (error `#(expected-error-match ,other))))))

(defun parse_cl_response_heartbeat_test ()
  "Parses :heartbeat tagged response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:heartbeat :thoughts 5 :uptime-seconds 30)"))))
    (case result
      (`#(ok (:heartbeat . ,_rest)) 'ok)
      (other (error `#(expected-heartbeat-match ,other))))))

(defun parse_cl_response_blocking_request_test ()
  "Parses :blocking-request tagged response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:blocking-request :id req-1 :prompt choose :options (a b))"))))
    (case result
      (`#(ok (:blocking-request . ,_rest)) 'ok)
      (other (error `#(expected-blocking-request-match ,other))))))

(defun parse_cl_response_untagged_test ()
  "Parses unrecognized S-expression as ok."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary "(some random data)"))))
    (case result
      (`#(ok ,_) 'ok)
      (other (error `#(expected-ok-wrapper ,other))))))

(defun parse_cl_response_invalid_test ()
  "Returns error for unparseable input."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary ")))not valid((("))))
    (case result
      (`#(error #(parse-failed ,_)) 'ok)
      (other (error `#(expected-parse-error ,other))))))

(defun parse_cl_response_empty_test ()
  "Returns error for empty response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary ""))))
    (case result
      (`#(error #(empty-response ,_)) 'ok)
      (other (error `#(expected-empty-error ,other))))))

(defun parse_cl_response_whitespace_test ()
  "Returns error for whitespace-only response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary "   \n  \t  "))))
    (case result
      (`#(error #(empty-response ,_)) 'ok)
      (other (error `#(expected-empty-error ,other))))))

(defun parse_cl_response_nested_ok_test ()
  "Parses nested data structures in :ok response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :data #M(thoughts 5 state running))"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-nested-ok ,other))))))

(defun parse_cl_response_complex_error_test ()
  "Parses complex error structures."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:error :type :cognition-failed :reason timeout :retry true)"))))
    (case result
      (`#(error ,_reason) 'ok)
      (other (error `#(expected-complex-error ,other))))))

(defun parse_cl_response_list_data_test ()
  "Parses responses containing list data."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :thoughts (observation decision observation))"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-list-data ,other))))))

(defun parse_cl_response_symbols_test ()
  "Parses responses with various symbol types."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :status active :symbols (foo-bar baz_qux))"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-symbol-parsing ,other))))))

(defun parse_cl_response_numbers_test ()
  "Parses responses with numeric data."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :count 42 :pi 3.14159 :negative -10)"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-numeric-data ,other))))))

(defun parse_cl_response_strings_test ()
  "Parses responses with string data."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :message \"hello world\" :path \"/usr/local/bin\")"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-string-data ,other))))))

(defun parse_cl_response_mixed_types_test ()
  "Parses responses with mixed data types."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :data #M(name \"agent-1\" count 5 active true))"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-mixed-types ,other))))))

(defun parse_cl_response_boolean_test ()
  "Parses responses with boolean values."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :active true :initialized false)"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-boolean-data ,other))))))

;;; ============================================================
;;; Phase 4: parse-cl-response tests for new message types
;;; ============================================================

(defun parse_cl_response_thought_test ()
  "Parses :thought tagged response (streaming during agentic loop)."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:thought :type :llm-response :content \"hello\" :turn 1)"))))
    (case result
      (`#(ok (:thought . ,_rest)) 'ok)
      (other (error `#(expected-thought-match ,other))))))

(defun parse_cl_response_agentic_complete_test ()
  "Parses :ok :type :agentic-complete response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :type :agentic-complete :result \"done\" :turns 3 :snapshot-id \"abc\")"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-agentic-complete ,other))))))

(defun parse_cl_response_thoughts_query_test ()
  "Parses :ok :type :thoughts response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :type :thoughts :count 2 :thoughts ((:type :observation :content \"hi\")))"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-thoughts-query ,other))))))

(defun parse_cl_response_capabilities_test ()
  "Parses :ok :type :capabilities response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :type :capabilities :count 0 :capabilities ())"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-capabilities ,other))))))

(defun parse_cl_response_branches_test ()
  "Parses :ok :type :branches response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :type :branches :count 1 :branches ((:name main :head snap-1)))"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-branches ,other))))))

(defun parse_cl_response_checked_out_test ()
  "Parses :ok :type :checked-out response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :type :checked-out :snapshot-id \"abc123\")"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-checked-out ,other))))))

(defun parse_cl_response_diff_test ()
  "Parses :ok :type :diff response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :type :diff :from \"a\" :to \"b\" :edit-count 0 :edits ())"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-diff ,other))))))

(defun parse_cl_response_branch_created_test ()
  "Parses :ok :type :branch-created response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :type :branch-created :name experiment :from snap-1)"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-branch-created ,other))))))

(defun parse_cl_response_branch_switched_test ()
  "Parses :ok :type :branch-switched response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :type :branch-switched :name main :head snap-1)"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-branch-switched ,other))))))

(defun parse_cl_response_capability_result_test ()
  "Parses :ok :type :capability-result response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:ok :type :capability-result :name :test-cap :result \"42\")"))))
    (case result
      (`#(ok (:ok . ,_rest)) 'ok)
      (other (error `#(expected-capability-result ,other))))))

(defun parse_cl_response_snapshot_not_found_test ()
  "Parses :error :type :snapshot-not-found response."
  (let ((result (agent-worker:parse-cl-response
                  (unicode:characters_to_binary
                    "(:error :type :snapshot-not-found :snapshot-id \"bogus\")"))))
    (case result
      (`#(error ,_reason) 'ok)
      (other (error `#(expected-snapshot-not-found ,other))))))

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun assert-truthy (val)
  "Assert value is truthy (not false, not undefined)."
  (case val
    ('false (error 'assertion-failed))
    ('undefined (error 'assertion-failed))
    (_ 'ok)))
