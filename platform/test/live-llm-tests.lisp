;;;; live-llm-tests.lisp - Real LLM integration tests
;;;;
;;;; These tests make actual calls to rho-cli and verify the full
;;;; cognitive-cycle pipeline works end-to-end with a real LLM.
;;;;
;;;; NOT included in run-all-tests — run manually:
;;;;   (run! 'autopoiesis.test::live-llm-tests)
;;;;   or: (autopoiesis.test::test-live-llm)
;;;;
;;;; Prerequisites:
;;;;   - rho-cli on PATH
;;;;   - Valid API credentials configured in rho

(in-package #:autopoiesis.test)

(def-suite live-llm-tests
  :description "Live LLM integration tests (requires rho-cli + API credentials)")

(in-suite live-llm-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun rho-cli-available-p ()
  "Check if rho-cli is on PATH."
  (ignore-errors
    (multiple-value-bind (out err code)
        (uiop:run-program (list "which" "rho-cli")
                          :output :string :error-output :string
                          :ignore-error-status t)
      (declare (ignore out err))
      (eql code 0))))

(defun make-live-rho-provider (&key (name "live-test") (model "claude-sonnet"))
  "Create a real rho-cli provider for testing."
  (let ((p (make-instance 'autopoiesis.integration::rho-provider
                          :name name
                          :command "rho-cli")))
    (setf (autopoiesis.integration:provider-default-model p) model)
    (setf (autopoiesis.integration:provider-timeout p) 120)
    ;; Don't let it use tools — we want fast, pure text responses
    (setf (autopoiesis.integration::rho-skip-tools p) nil)
    (autopoiesis.integration:provider-start-session p)
    p))

(defmacro with-live-skip (&body body)
  "Skip test body if rho-cli is not available."
  `(if (rho-cli-available-p)
       (progn ,@body)
       (skip "rho-cli not available — skipping live test")))

;;; ═══════════════════════════════════════════════════════════════════
;;; Test 1: Raw provider-send-streaming works
;;; ═══════════════════════════════════════════════════════════════════

(test live-rho-streaming-basic
  "Verify rho-cli streaming produces text deltas and a result."
  (with-live-skip
    (let* ((provider (make-live-rho-provider))
           (deltas nil)
           (result (autopoiesis.integration:provider-send-streaming
                    provider
                    "Reply with exactly one word: PONG"
                    (lambda (delta)
                      (push delta deltas)))))
      ;; Got a provider-result
      (is (typep result 'autopoiesis.integration:provider-result))
      ;; Result has text
      (is (not (null (autopoiesis.integration:provider-result-text result))))
      (is (> (length (autopoiesis.integration:provider-result-text result)) 0))
      ;; Got streaming deltas
      (is (> (length deltas) 0))
      ;; The accumulated deltas should contain PONG
      (let ((full (format nil "~{~a~}" (nreverse deltas))))
        (is (search "PONG" (string-upcase full))
            "Expected streaming output to contain PONG, got: ~a" full))
      ;; Clean up
      (autopoiesis.integration:provider-stop-session provider))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Test 2: cognitive-cycle with real provider-backed-agent
;;; ═══════════════════════════════════════════════════════════════════

(test live-cognitive-cycle-streaming
  "Full cognitive-cycle through provider-backed-agent with real rho-cli.
   Verifies: result returned, all thought phases recorded, callbacks fired."
  (with-live-skip
    (let ((autopoiesis.integration:*events-enabled* nil))
      (let* ((provider (make-live-rho-provider :name "cognitive-test"))
             (agent (autopoiesis.integration:make-provider-backed-agent
                     provider
                     :name "live-cycle-agent"
                     :system-prompt "You are a test agent. Always respond concisely."
                     :mode :streaming))
             (events nil))
        (autopoiesis.agent:start-agent agent)
        ;; Wire callbacks
        (setf (autopoiesis.integration:agent-streaming-callbacks agent)
              (list :on-start (lambda () (push :start events))
                    :on-delta (lambda (d) (push (cons :delta d) events))
                    :on-end   (lambda () (push :end events))
                    :on-complete (lambda (text)
                                   (push (cons :complete text) events))))
        ;; Run cognitive cycle
        (let ((result (autopoiesis.agent:cognitive-cycle
                       agent "Reply with exactly: HELLO WORLD")))
          ;; Result is a provider-result
          (is (typep result 'autopoiesis.integration:provider-result))
          ;; Has response text
          (let ((text (autopoiesis.integration:provider-result-text result)))
            (is (not (null text)))
            (is (> (length text) 0))
            (is (search "HELLO" (string-upcase text))
                "Expected response to contain HELLO, got: ~a" text))
          ;; Thought stream has all phase types
          (let* ((stream (autopoiesis.agent:agent-thought-stream agent))
                 (len (autopoiesis.core:stream-length stream))
                 (thoughts (autopoiesis.core:stream-last stream len))
                 (types (mapcar #'autopoiesis.core:thought-type thoughts)))
            ;; perceive -> observation, decide -> decision, act -> observations+actions,
            ;; reflect -> reflection
            (is (member :observation types)
                "Missing :observation in thought types: ~a" types)
            (is (member :decision types)
                "Missing :decision in thought types: ~a" types)
            (is (member :reflection types)
                "Missing :reflection in thought types: ~a" types)
            ;; At least 4 thoughts (observation + decision + exchange recording + reflection)
            (is (>= len 4)
                "Expected >=4 thoughts, got ~d" len))
          ;; Callbacks fired in correct order
          (setf events (nreverse events))
          (is (> (length events) 0) "No callback events recorded")
          (is (eq :start (first events))
              "First event should be :start, got: ~a" (first events))
          ;; Should have at least one delta
          (is (some (lambda (e) (and (consp e) (eq :delta (car e)))) events)
              "Expected at least one :delta event")
          ;; End and complete should be present
          (is (member :end events)
              "Missing :end event")
          (is (some (lambda (e) (and (consp e) (eq :complete (car e)))) events)
              "Missing :complete event")
          ;; :end should come before :complete
          (let ((end-pos (position :end events))
                (complete-pos (position-if (lambda (e) (and (consp e) (eq :complete (car e))))
                                           events)))
            (when (and end-pos complete-pos)
              (is (< end-pos complete-pos)
                  ":end (~d) should come before :complete (~d)" end-pos complete-pos))))
        ;; Clean up
        (autopoiesis.integration:provider-stop-session provider)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Test 3: change-class upgrade path (simulates runtime-start-agent)
;;; ═══════════════════════════════════════════════════════════════════

(test live-change-class-upgrade
  "Verify that a plain agent upgraded via change-class works with real LLM."
  (with-live-skip
    (let ((autopoiesis.integration:*events-enabled* nil))
      (let* ((provider (make-live-rho-provider :name "upgrade-test"))
             ;; Start as a plain agent (like the dashboard creates)
             (agent (autopoiesis.agent:make-agent :name "upgrade-target")))
        ;; Upgrade via change-class (what runtime-start-agent does)
        (change-class agent 'autopoiesis.integration:provider-backed-agent
                      :provider provider
                      :invocation-mode :streaming
                      :system-prompt "You are a test agent. Respond concisely.")
        (autopoiesis.agent:start-agent agent)
        ;; Should be a provider-backed-agent now
        (is (typep agent 'autopoiesis.integration:provider-backed-agent))
        ;; Original identity preserved
        (is (string= "upgrade-target" (autopoiesis.agent:agent-name agent)))
        ;; Run a real cognitive cycle
        (let* ((deltas nil)
               (_ (setf (autopoiesis.integration:agent-streaming-callbacks agent)
                        (list :on-start (lambda ())
                              :on-delta (lambda (d) (push d deltas))
                              :on-end   (lambda ())
                              :on-complete (lambda (text) (declare (ignore text))))))
               (result (autopoiesis.agent:cognitive-cycle
                        agent "What is 2+2? Reply with just the number.")))
          (declare (ignore _))
          ;; Got a real result
          (is (typep result 'autopoiesis.integration:provider-result))
          (let ((text (autopoiesis.integration:provider-result-text result)))
            (is (not (null text)))
            (is (search "4" text)
                "Expected response to contain '4', got: ~a" text))
          ;; Streaming deltas arrived
          (is (> (length deltas) 0)
              "Expected streaming deltas, got none"))
        ;; Clean up
        (autopoiesis.integration:provider-stop-session provider)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Test 4: Multi-turn session continuity via --resume
;;; ═══════════════════════════════════════════════════════════════════

(test live-session-continuity
  "Verify rho-cli session continuity across multiple cognitive cycles."
  (with-live-skip
    (let ((autopoiesis.integration:*events-enabled* nil))
      (let* ((provider (make-live-rho-provider :name "session-test"))
             (agent (autopoiesis.integration:make-provider-backed-agent
                     provider
                     :name "session-agent"
                     :system-prompt "You are a test agent. Remember what the user tells you."
                     :mode :streaming)))
        (autopoiesis.agent:start-agent agent)
        ;; Turn 1: Tell it a secret
        (setf (autopoiesis.integration:agent-streaming-callbacks agent) nil)
        (let ((r1 (autopoiesis.agent:cognitive-cycle
                   agent "Remember this code word: BANANA7. Just acknowledge.")))
          (is (typep r1 'autopoiesis.integration:provider-result))
          (is (not (null (autopoiesis.integration:provider-result-text r1)))))
        ;; Provider should now have a real session ID (not our placeholder)
        (let ((sid (autopoiesis.integration:provider-session-id provider)))
          (is (not (null sid)) "Expected session ID after first turn")
          ;; Turn 2: Ask it to recall
          (let ((r2 (autopoiesis.agent:cognitive-cycle
                     agent "What was the code word I told you? Reply with just the word.")))
            (is (typep r2 'autopoiesis.integration:provider-result))
            (let ((text (autopoiesis.integration:provider-result-text r2)))
              (is (not (null text)))
              (is (search "BANANA" (string-upcase text))
                  "Expected session to remember BANANA7, got: ~a" text))))
        ;; Clean up
        (autopoiesis.integration:provider-stop-session provider)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Runner
;;; ═══════════════════════════════════════════════════════════════════

(defun test-live-llm ()
  "Run live LLM integration tests. Requires rho-cli and API credentials."
  (format t "~%=== Live LLM Integration Tests ===~%")
  (format t "These tests make real API calls. They cost money and take time.~%~%")
  (run! 'live-llm-tests))
