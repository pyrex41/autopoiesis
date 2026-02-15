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
