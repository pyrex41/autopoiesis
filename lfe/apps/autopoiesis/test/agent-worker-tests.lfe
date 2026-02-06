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
;;; Helpers
;;; ============================================================

(defun assert-truthy (val)
  "Assert value is truthy (not false, not undefined)."
  (case val
    ('false (error 'assertion-failed))
    ('undefined (error 'assertion-failed))
    (_ 'ok)))
