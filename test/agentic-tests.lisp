;;;; agentic-tests.lisp - Tests for agentic loop and agentic agent
;;;;
;;;; Tests the multi-turn agentic loop (claude-bridge.lisp) and the
;;;; agentic-agent class that wraps it with the cognitive loop protocol.

(in-package #:autopoiesis.test)

;;; ===================================================================
;;; Test Suites
;;; ===================================================================

(def-suite agentic-loop-tests
  :description "Tests for the multi-turn agentic loop"
  :in integration-tests)

(def-suite agentic-agent-tests
  :description "Tests for the agentic-agent class"
  :in integration-tests)

;;; ===================================================================
;;; Mock Infrastructure
;;; ===================================================================

(defun make-mock-text-response (text)
  "Create a mock Claude API response with just text content."
  `((:id . "msg_mock")
    (:type . "message")
    (:role . "assistant")
    (:content . (((:type . "text") (:text . ,text))))
    (:model . "claude-sonnet-4-20250514")
    (:stop--reason . "end_turn")))

(defun make-mock-tool-response (tool-name tool-id input)
  "Create a mock Claude API response requesting tool use."
  `((:id . "msg_mock")
    (:type . "message")
    (:role . "assistant")
    (:content . (((:type . "tool_use")
                  (:id . ,tool-id)
                  (:name . ,tool-name)
                  (:input . ,input))))
    (:model . "claude-sonnet-4-20250514")
    (:stop--reason . "tool_use")))

(defun make-mock-mixed-response (text tool-name tool-id input)
  "Create a mock Claude API response with both text and tool use."
  `((:id . "msg_mock")
    (:type . "message")
    (:role . "assistant")
    (:content . (((:type . "text") (:text . ,text))
                 ((:type . "tool_use")
                  (:id . ,tool-id)
                  (:name . ,tool-name)
                  (:input . ,input))))
    (:model . "claude-sonnet-4-20250514")
    (:stop--reason . "tool_use")))

(defun make-test-echo-capability ()
  "Create a simple capability that echoes its input for testing."
  (autopoiesis.agent:make-capability
   :echo-input
   (lambda (&key message)
     (format nil "Echo: ~a" message))
   :description "Echoes the input message back"
   :parameters '((message string :required t :doc "Message to echo"))))

(defun make-test-error-capability ()
  "Create a capability that always signals an error."
  (autopoiesis.agent:make-capability
   :error-tool
   (lambda (&key)
     (error "Intentional test error"))
   :description "Always errors"))

(defun make-mock-client ()
  "Create a mock client (just needs to exist, not call API)."
  (autopoiesis.integration:make-claude-client :api-key "test-key"))

(defun make-user-message (text)
  "Create a user message alist for the API."
  `(("role" . "user") ("content" . ,text)))

(defmacro with-mock-claude (responses &body body)
  "Execute BODY with claude-complete mocked to return RESPONSES in order.
   RESPONSES is evaluated and should produce a list of response alists."
  (let ((count (gensym "COUNT"))
        (resps (gensym "RESPS")))
    `(let ((,count 0)
           (,resps ,responses))
       (let ((autopoiesis.integration:*claude-complete-function*
               (lambda (client messages &key system tools)
                 (declare (ignore client messages system tools))
                 (prog1 (nth ,count ,resps)
                   (incf ,count)))))
         ,@body))))

;;; ===================================================================
;;; Agentic Loop Tests
;;; ===================================================================

(in-suite agentic-loop-tests)

(test test-single-turn-text-response
  "Agentic loop returns immediately when Claude responds with text (no tool use)."
  (with-mock-claude (list (make-mock-text-response "Hello, world!"))
    (multiple-value-bind (final-response all-messages turn-count)
        (autopoiesis.integration:agentic-loop
         (make-mock-client)
         (list (make-user-message "Hi"))
         nil)
      (is (not (null final-response)))
      (is (equal "end_turn" (autopoiesis.integration:response-stop-reason final-response)))
      (is (= 1 turn-count))
      ;; Messages: original user + assistant response
      (is (= 2 (length all-messages))))))

(test test-multi-turn-tool-use
  "Agentic loop executes tools and continues until end_turn."
  (with-mock-claude (list (make-mock-tool-response
                           "echo_input" "toolu_001"
                           '(("message" . "test")))
                          (make-mock-text-response "Done echoing."))
    (multiple-value-bind (final-resp all-messages turn-count)
        (autopoiesis.integration:agentic-loop
         (make-mock-client)
         (list (make-user-message "Echo something"))
         (list (make-test-echo-capability)))
      (is (= 2 turn-count))
      (is (equal "end_turn" (autopoiesis.integration:response-stop-reason final-resp)))
      ;; Messages: user + assistant-tool-use + tool-result + assistant-final
      (is (= 4 (length all-messages))))))

(test test-max-turns-limit
  "Agentic loop stops at max-turns even if Claude keeps requesting tools."
  (let ((tool-response (make-mock-tool-response
                        "echo_input" "toolu_loop"
                        '(("message" . "again")))))
    (let ((autopoiesis.integration:*claude-complete-function*
            (lambda (client messages &key system tools)
              (declare (ignore client messages system tools))
              tool-response)))
      (multiple-value-bind (final-resp all-messages turn-count)
          (autopoiesis.integration:agentic-loop
           (make-mock-client)
           (list (make-user-message "Loop"))
           (list (make-test-echo-capability))
           :max-turns 3)
        (declare (ignore all-messages))
        (is (= 3 turn-count))
        (is (not (null final-resp)))))))

(test test-on-thought-callback
  "The on-thought callback is called at each step with correct event types."
  (let ((thought-log nil))
    (with-mock-claude (list (make-mock-tool-response
                             "echo_input" "toolu_cb"
                             '(("message" . "callback test")))
                            (make-mock-text-response "Callback done."))
      (autopoiesis.integration:agentic-loop
       (make-mock-client)
       (list (make-user-message "Test callbacks"))
       (list (make-test-echo-capability))
       :on-thought (lambda (type data)
                     (declare (ignore data))
                     (push type thought-log))))
    ;; Check that we got expected callback types
    (let ((types (reverse thought-log)))
      (is (member :llm-response types))
      (is (member :tool-execution types))
      (is (member :tool-result types))
      (is (member :complete types)))))

(test test-empty-capabilities
  "Agentic loop works with no tools for simple text exchange."
  (let ((received-tools :unset))
    (let ((autopoiesis.integration:*claude-complete-function*
            (lambda (client messages &key system tools)
              (declare (ignore client messages system))
              (setf received-tools tools)
              (make-mock-text-response "Just text, no tools."))))
      (multiple-value-bind (final-resp all-messages turn-count)
          (autopoiesis.integration:agentic-loop
           (make-mock-client)
           (list (make-user-message "Hello"))
           nil)
        (is (null received-tools))
        (is (= 1 turn-count))
        (is (equal "Just text, no tools."
                   (autopoiesis.integration:response-text final-resp)))
        (is (= 2 (length all-messages)))))))

(test test-tool-execution-error
  "Tool errors are caught and reported as results without crashing the loop."
  (with-mock-claude (list (make-mock-tool-response
                           "error_tool" "toolu_err" nil)
                          (make-mock-text-response "Error handled."))
    (multiple-value-bind (final-resp all-messages turn-count)
        (autopoiesis.integration:agentic-loop
         (make-mock-client)
         (list (make-user-message "Trigger error"))
         (list (make-test-error-capability)))
      (is (= 2 turn-count))
      (is (equal "end_turn" (autopoiesis.integration:response-stop-reason final-resp)))
      ;; The tool result message should contain the error
      (let* ((tool-result-msg (third all-messages))
             (content (cdr (assoc "content" tool-result-msg :test #'string=)))
             (result-block (first content)))
        (is (cdr (assoc "is_error" result-block :test #'string=)))))))

(test test-agentic-complete-convenience
  "agentic-complete returns text, response, messages, and turn count."
  (with-mock-claude (list (make-mock-text-response "Convenience works."))
    (multiple-value-bind (text final-resp all-messages turn-count)
        (autopoiesis.integration:agentic-complete
         (make-mock-client)
         "Simple prompt"
         nil)
      (is (equal "Convenience works." text))
      (is (not (null final-resp)))
      (is (= 2 (length all-messages)))
      (is (= 1 turn-count)))))

(test test-mixed-text-and-tool-response
  "Agentic loop handles responses containing both text and tool use."
  (with-mock-claude (list (make-mock-mixed-response
                           "Let me echo that."
                           "echo_input" "toolu_mix"
                           '(("message" . "mixed")))
                          (make-mock-text-response "All done."))
    (multiple-value-bind (final-resp all-messages turn-count)
        (autopoiesis.integration:agentic-loop
         (make-mock-client)
         (list (make-user-message "Mixed test"))
         (list (make-test-echo-capability)))
      (is (= 2 turn-count))
      (is (equal "All done." (autopoiesis.integration:response-text final-resp)))
      (is (= 4 (length all-messages))))))

(test test-system-prompt-passed-through
  "System prompt is forwarded to claude-complete."
  (let ((received-system nil))
    (let ((autopoiesis.integration:*claude-complete-function*
            (lambda (client messages &key system tools)
              (declare (ignore client messages tools))
              (setf received-system system)
              (make-mock-text-response "Got system prompt."))))
      (autopoiesis.integration:agentic-loop
       (make-mock-client)
       (list (make-user-message "Test"))
       nil
       :system "You are a test agent.")
      (is (equal "You are a test agent." received-system)))))

;;; ===================================================================
;;; Agentic Agent Tests
;;; ===================================================================

(in-suite agentic-agent-tests)

(test test-make-agentic-agent
  "Create an agentic agent and verify all slots are set."
  (let ((agent (autopoiesis.integration:make-agentic-agent
                :api-key "test-key"
                :model "claude-sonnet-4-20250514"
                :name "test-agent"
                :system-prompt "You are helpful."
                :max-turns 10)))
    (is (equal "test-agent" (autopoiesis.agent:agent-name agent)))
    (is (equal "You are helpful." (autopoiesis.integration:agent-system-prompt agent)))
    (is (= 10 (autopoiesis.integration:agent-max-turns agent)))
    (is (not (null (autopoiesis.integration:agent-client agent))))))

(test test-agentic-agent-perceive
  "Perceive coerces various input types to message lists."
  (let ((agent (autopoiesis.integration:make-agentic-agent
                :api-key "test-key"
                :name "perceive-test")))
    (autopoiesis.agent:start-agent agent)
    ;; String input
    (let ((result (autopoiesis.agent:perceive agent "Hello")))
      (is (listp result))
      (is (= 1 (length result)))
      (is (equal "user" (cdr (assoc "role" (first result) :test #'string=)))))
    ;; Plist input with :prompt
    (let ((result (autopoiesis.agent:perceive agent '(:prompt "From plist"))))
      (is (listp result))
      (is (= 1 (length result))))
    ;; Pre-formed message list
    (let* ((msgs (list (make-user-message "Pre-formed")))
           (result (autopoiesis.agent:perceive agent msgs)))
      (is (listp result))
      (is (>= (length result) 1)))))

(test test-agentic-agent-cognitive-cycle
  "Run a full cognitive cycle with mocked Claude API."
  (let ((agent (autopoiesis.integration:make-agentic-agent
                :api-key "test-key"
                :name "cycle-test")))
    (autopoiesis.agent:start-agent agent)
    (with-mock-claude (list (make-mock-text-response "Cycle complete."))
      (let ((result (autopoiesis.agent:cognitive-cycle agent "Test prompt")))
        ;; Should return a meaningful result
        (is (not (null result)))
        ;; Thought stream should have entries
        (is (> (autopoiesis.core:stream-length
                (autopoiesis.agent:agent-thought-stream agent))
               0))
        ;; Conversation history should be populated
        (is (> (length (autopoiesis.integration:agent-conversation-history agent)) 0))))))

(test test-agentic-agent-thought-recording
  "Multi-turn cycle records proper thoughts in the stream."
  (let* ((echo-cap (make-test-echo-capability))
         (agent (autopoiesis.integration:make-agentic-agent
                 :api-key "test-key"
                 :name "thought-test")))
    ;; Register the capability so the agent can find it
    (autopoiesis.agent:register-capability echo-cap)
    (setf (autopoiesis.integration:agent-tool-capabilities agent) (list echo-cap))
    (autopoiesis.agent:start-agent agent)
    (with-mock-claude (list (make-mock-tool-response
                             "echo_input" "toolu_thoughts"
                             '(("message" . "thought test")))
                            (make-mock-text-response "Thoughts recorded."))
      (autopoiesis.agent:cognitive-cycle agent "Record thoughts")
      (let* ((stream (autopoiesis.agent:agent-thought-stream agent))
             (count (autopoiesis.core:stream-length stream)))
        ;; Should have recorded multiple thoughts
        (is (>= count 2))))))

(test test-agentic-agent-serialization
  "Serialize agentic agent to sexpr and verify structure."
  (let ((agent (autopoiesis.integration:make-agentic-agent
                :api-key "test-key"
                :model "claude-sonnet-4-20250514"
                :name "serialize-test"
                :system-prompt "Serialization test."
                :max-turns 15)))
    (let ((sexpr (autopoiesis.integration:agentic-agent-to-sexpr agent)))
      (is (listp sexpr))
      (is (eq :agentic-agent (first sexpr)))
      (let ((plist (rest sexpr)))
        (is (equal "serialize-test" (getf plist :name)))
        (is (equal "Serialization test." (getf plist :system-prompt)))
        (is (equal "claude-sonnet-4-20250514" (getf plist :model)))
        (is (= 15 (getf plist :max-turns)))))))

(test test-agentic-agent-conversation-persistence
  "Conversation history accumulates across multiple cognitive cycles."
  (let* ((call-count 0)
         (agent (autopoiesis.integration:make-agentic-agent
                 :api-key "test-key"
                 :name "persist-test")))
    (autopoiesis.agent:start-agent agent)
    (let ((autopoiesis.integration:*claude-complete-function*
            (lambda (client messages &key system tools)
              (declare (ignore client messages system tools))
              (prog1 (make-mock-text-response
                      (format nil "Response ~a." (1+ call-count)))
                (incf call-count)))))
      ;; First cycle
      (autopoiesis.agent:cognitive-cycle agent "First prompt")
      (let ((history-after-first
              (length (autopoiesis.integration:agent-conversation-history agent))))
        (is (> history-after-first 0))
        ;; Second cycle
        (autopoiesis.agent:cognitive-cycle agent "Second prompt")
        (let ((history-after-second
                (length (autopoiesis.integration:agent-conversation-history agent))))
          ;; History should have grown
          (is (> history-after-second history-after-first)))))))

(test test-agentic-agent-default-name
  "Agent gets a reasonable default name when none is provided."
  (let ((agent (autopoiesis.integration:make-agentic-agent
                :api-key "test-key")))
    (is (stringp (autopoiesis.agent:agent-name agent)))
    (is (> (length (autopoiesis.agent:agent-name agent)) 0))))

(test test-agentic-agent-prompt-convenience
  "agentic-agent-prompt starts the agent and runs a cycle."
  (let ((agent (autopoiesis.integration:make-agentic-agent
                :api-key "test-key"
                :name "prompt-test")))
    (with-mock-claude (list (make-mock-text-response "Convenient!"))
      (let ((result (autopoiesis.integration:agentic-agent-prompt agent "Quick test")))
        (is (not (null result)))
        ;; Agent should be running after prompt
        (is (autopoiesis.agent:agent-running-p agent))))))

;;; ===================================================================
;;; Self-Extension Tool Tests
;;; ===================================================================

(def-suite self-extension-tests
  :description "Tests for self-extension tools (define, test, promote capabilities)"
  :in integration-tests)

(in-suite self-extension-tests)

;; Helper to get tool function by its defcapability symbol
(defun get-tool-fn (tool-symbol)
  "Get the function for a tool defined via defcapability."
  (autopoiesis.agent:capability-function
   (autopoiesis.agent:find-capability tool-symbol)))

;; Helper to clean up a capability from the global registry after test
(defmacro with-temp-capability (cap-name-string &body body)
  "Execute BODY, then remove the capability named CAP-NAME-STRING from the registry."
  (let ((name-sym (gensym "NAME")))
    `(let ((,name-sym (intern (string-upcase ,cap-name-string) :keyword)))
       (unwind-protect (progn ,@body)
         (autopoiesis.agent:unregister-capability ,name-sym)))))

(test test-define-capability-success
  "define-capability-tool creates a new capability from code string."
  (with-temp-capability "test-adder"
    (let ((result (funcall (get-tool-fn 'autopoiesis.integration::define-capability-tool)
                           :name "test-adder"
                           :description "Add two numbers"
                           :parameters "((x integer) (y integer))"
                           :code "(+ x y)")))
      ;; Should succeed
      (is (search "defined successfully" result))
      ;; Should be findable in the global registry
      (let ((cap (autopoiesis.agent:find-capability :test-adder)))
        (is (not (null cap)))
        (is (typep cap 'autopoiesis.agent:agent-capability))
        (is (eq :draft (autopoiesis.agent:cap-promotion-status cap)))))))

(test test-define-capability-rejects-unsafe-code
  "define-capability-tool rejects code with forbidden operations."
  (with-temp-capability "evil-tool"
    (let ((result (funcall (get-tool-fn 'autopoiesis.integration::define-capability-tool)
                           :name "evil-tool"
                           :description "Tries to eval"
                           :parameters "((code string))"
                           :code "(eval code)")))
      ;; Should fail with validation error
      (is (search "Error" result))
      ;; Should NOT be in the registry
      (is (null (autopoiesis.agent:find-capability :evil-tool))))))

(test test-define-capability-rejects-file-ops
  "define-capability-tool rejects code that opens files."
  (with-temp-capability "file-stealer"
    (let ((result (funcall (get-tool-fn 'autopoiesis.integration::define-capability-tool)
                           :name "file-stealer"
                           :description "Tries to read files"
                           :parameters "((path string))"
                           :code "(open path)")))
      (is (search "Error" result))
      (is (null (autopoiesis.agent:find-capability :file-stealer))))))

(test test-test-capability-pass
  "test-capability-tool runs tests and reports pass."
  (with-temp-capability "test-multiply"
    ;; First define the capability
    (funcall (get-tool-fn 'autopoiesis.integration::define-capability-tool)
             :name "test-multiply"
             :description "Multiply two numbers"
             :parameters "((x integer) (y integer))"
             :code "(* x y)")
    ;; Now test it
    (let ((result (funcall (get-tool-fn 'autopoiesis.integration::test-capability-tool)
                           :name "test-multiply"
                           :test-cases "(((2 3) 6) ((4 5) 20) ((0 100) 0))")))
      (is (search "ALL TESTS PASSED" result))
      (is (search "PASS" result))
      ;; Status should now be :testing
      (let ((cap (autopoiesis.agent:find-capability :test-multiply)))
        (is (eq :testing (autopoiesis.agent:cap-promotion-status cap)))))))

(test test-test-capability-fail
  "test-capability-tool reports failures when tests don't match."
  (with-temp-capability "test-bad-math"
    ;; Define a capability that adds instead of multiplies
    (funcall (get-tool-fn 'autopoiesis.integration::define-capability-tool)
             :name "test-bad-math"
             :description "Should multiply but adds"
             :parameters "((x integer) (y integer))"
             :code "(+ x y)")
    ;; Test with multiplication expectations
    (let ((result (funcall (get-tool-fn 'autopoiesis.integration::test-capability-tool)
                           :name "test-bad-math"
                           :test-cases "(((2 3) 6) ((4 5) 20))")))
      (is (search "SOME TESTS FAILED" result))
      (is (search "FAIL" result)))))

(test test-test-capability-not-found
  "test-capability-tool returns error for nonexistent capability."
  (let ((result (funcall (get-tool-fn 'autopoiesis.integration::test-capability-tool)
                         :name "nonexistent-cap"
                         :test-cases "(((1) 1))")))
    (is (search "not found" result))))

(test test-test-capability-rejects-builtin
  "test-capability-tool rejects testing built-in capabilities."
  (let ((result (funcall (get-tool-fn 'autopoiesis.integration::test-capability-tool)
                         :name "read-file"
                         :test-cases "(((1) 1))")))
    ;; read-file is a builtin, registered under symbol, not keyword
    ;; This should fail because :READ-FILE won't find the builtin
    ;; (builtins are registered under their package symbol, not keyword)
    (is (search "not found" result))))

(test test-promote-capability-success
  "promote-capability-tool promotes a tested capability to global registry."
  (with-temp-capability "test-promotable"
    ;; Define
    (funcall (get-tool-fn 'autopoiesis.integration::define-capability-tool)
             :name "test-promotable"
             :description "A promotable capability"
             :parameters "((x integer))"
             :code "(1+ x)")
    ;; Test
    (funcall (get-tool-fn 'autopoiesis.integration::test-capability-tool)
             :name "test-promotable"
             :test-cases "(((5) 6) ((0) 1) ((-1) 0))")
    ;; Promote
    (let ((result (funcall (get-tool-fn 'autopoiesis.integration::promote-capability-tool)
                           :name "test-promotable")))
      (is (search "promoted" result))
      ;; Status should be :promoted
      (let ((cap (autopoiesis.agent:find-capability :test-promotable)))
        (is (eq :promoted (autopoiesis.agent:cap-promotion-status cap)))))))

(test test-promote-capability-without-testing
  "promote-capability-tool rejects promoting untested capabilities."
  (with-temp-capability "test-untested"
    ;; Define but don't test
    (funcall (get-tool-fn 'autopoiesis.integration::define-capability-tool)
             :name "test-untested"
             :description "Never tested"
             :parameters "((x integer))"
             :code "(1+ x)")
    ;; Try to promote
    (let ((result (funcall (get-tool-fn 'autopoiesis.integration::promote-capability-tool)
                           :name "test-untested")))
      (is (search "Cannot promote" result)))))

(test test-promote-capability-with-failing-tests
  "promote-capability-tool rejects promoting capabilities with failed tests."
  (with-temp-capability "test-failing"
    ;; Define
    (funcall (get-tool-fn 'autopoiesis.integration::define-capability-tool)
             :name "test-failing"
             :description "Will fail tests"
             :parameters "((x integer))"
             :code "(1+ x)")
    ;; Test with wrong expectations
    (funcall (get-tool-fn 'autopoiesis.integration::test-capability-tool)
             :name "test-failing"
             :test-cases "(((5) 100))")
    ;; Try to promote - should be rejected
    (let ((result (funcall (get-tool-fn 'autopoiesis.integration::promote-capability-tool)
                           :name "test-failing")))
      (is (search "Cannot promote" result)))))

(test test-list-capabilities-tool
  "list-capabilities-tool lists registered capabilities."
  ;; There should be builtin tools registered at load time
  (let ((result (funcall (get-tool-fn 'autopoiesis.integration::list-capabilities-tool))))
    (is (stringp result))
    ;; Should list at least some capabilities (the defcapability ones)
    (is (> (length result) 0))))

(test test-list-capabilities-tool-with-filter
  "list-capabilities-tool filters by name."
  (let ((result (funcall (get-tool-fn 'autopoiesis.integration::list-capabilities-tool)
                         :filter "read")))
    (is (stringp result))
    ;; Should find read-file at minimum
    (is (search "READ" (string-upcase result)))))

(test test-inspect-thoughts-tool
  "inspect-thoughts returns a response."
  (let ((result (funcall (get-tool-fn 'autopoiesis.integration::inspect-thoughts)
                         :count 5)))
    (is (stringp result))
    (is (> (length result) 0))))

;;; ===================================================================
;;; End-to-End Self-Extension Workflow
;;; ===================================================================

(test test-self-extension-e2e-workflow
  "Full end-to-end: define → test → promote → use as tool."
  (with-temp-capability "test-e2e-double"
    ;; Step 1: Define a capability
    (let ((def-result (funcall (get-tool-fn 'autopoiesis.integration::define-capability-tool)
                               :name "test-e2e-double"
                               :description "Double a number"
                               :parameters "((n integer))"
                               :code "(* n 2)")))
      (is (search "defined successfully" def-result)))

    ;; Step 2: Test it
    (let ((test-result (funcall (get-tool-fn 'autopoiesis.integration::test-capability-tool)
                                :name "test-e2e-double"
                                :test-cases "(((5) 10) ((0) 0) ((-3) -6))")))
      (is (search "ALL TESTS PASSED" test-result)))

    ;; Step 3: Promote it
    (let ((promote-result (funcall (get-tool-fn 'autopoiesis.integration::promote-capability-tool)
                                   :name "test-e2e-double")))
      (is (search "promoted" promote-result)))

    ;; Step 4: Verify it's usable as a tool
    (let ((cap (autopoiesis.agent:find-capability :test-e2e-double)))
      (is (not (null cap)))
      (is (eq :promoted (autopoiesis.agent:cap-promotion-status cap)))
      ;; Actually invoke it
      (let ((result (funcall (autopoiesis.agent:capability-function cap) 7)))
        (is (= 14 result))))))

(defun wrap-as-keyword-capability (cap)
  "Create a keyword-named wrapper capability for use in agentic loop.
   The agentic loop's execute-tool-call converts tool names to keywords,
   so capabilities must have keyword names for dispatch to work."
  (autopoiesis.agent:make-capability
   (intern (string (autopoiesis.agent:capability-name cap)) :keyword)
   (autopoiesis.agent:capability-function cap)
   :description (autopoiesis.agent:capability-description cap)
   :parameters (autopoiesis.agent:capability-parameters cap)))

(test test-self-extension-e2e-in-agentic-loop
  "Agent uses self-extension tools in a mocked agentic loop."
  (with-temp-capability "test-loop-triple"
    (let* ((capabilities (mapcar #'wrap-as-keyword-capability
                                 (list (autopoiesis.agent:find-capability
                                        'autopoiesis.integration::define-capability-tool)
                                       (autopoiesis.agent:find-capability
                                        'autopoiesis.integration::test-capability-tool)
                                       (autopoiesis.agent:find-capability
                                        'autopoiesis.integration::promote-capability-tool))))
           ;; Mock responses: Claude calls define → test → promote → final text
           (responses (list
                       ;; Turn 1: Claude calls define_capability_tool
                       (make-mock-tool-response
                        "define_capability_tool" "toolu_def"
                        '(("name" . "test-loop-triple")
                          ("description" . "Triple a number")
                          ("parameters" . "((n integer))")
                          ("code" . "(* n 3)")))
                       ;; Turn 2: Claude calls test_capability_tool
                       (make-mock-tool-response
                        "test_capability_tool" "toolu_test"
                        '(("name" . "test-loop-triple")
                          ("test-cases" . "(((3) 9) ((0) 0))")))
                       ;; Turn 3: Claude calls promote_capability_tool
                       (make-mock-tool-response
                        "promote_capability_tool" "toolu_promote"
                        '(("name" . "test-loop-triple")))
                       ;; Turn 4: Claude says done
                       (make-mock-text-response "I've created and promoted the triple capability."))))

      (with-mock-claude responses
        (multiple-value-bind (final-resp all-messages turn-count)
            (autopoiesis.integration:agentic-loop
             (make-mock-client)
             (list (make-user-message "Create a capability that triples a number"))
             capabilities
             :max-turns 10)
          (declare (ignore all-messages))
          (is (= 4 turn-count))
          (is (equal "end_turn" (autopoiesis.integration:response-stop-reason final-resp)))

          ;; Verify the capability was actually created and promoted
          (let ((cap (autopoiesis.agent:find-capability :test-loop-triple)))
            (is (not (null cap)))
            (is (eq :promoted (autopoiesis.agent:cap-promotion-status cap)))
            ;; Actually invoke it
            (is (= 9 (funcall (autopoiesis.agent:capability-function cap) 3)))))))))

