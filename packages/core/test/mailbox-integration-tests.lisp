;;;; mailbox-integration-tests.lisp - Mailbox to cognitive cycle integration tests
;;;;
;;;; Tests that cross the mailbox → agent boundary: send-message → deliver-message
;;;; → receive-messages works end-to-end in a threaded context.

(in-package #:autopoiesis.test)

;;; ===================================================================
;;; Test Suite
;;; ===================================================================

(def-suite mailbox-integration-tests
  :description "Integration tests for mailbox → cognitive cycle pipeline"
  :in integration-tests)

(in-suite mailbox-integration-tests)

;;; ===================================================================
;;; Test 1: deliver-message wakes blocking receive
;;; ===================================================================

(test deliver-message-wakes-blocking-receive
  "A message delivered to a mailbox wakes a thread blocked on receive-messages."
  (let* ((agent-id (format nil "mailbox-test-~a" (get-universal-time)))
         (received nil)
         (receiver-thread
           (bt:make-thread
            (lambda ()
              (setf received
                    (autopoiesis.agent:receive-messages
                     agent-id :clear t :block t :timeout 5)))
            :name "test-receiver")))
    ;; Give the receiver thread time to block
    (sleep 0.2)
    ;; Deliver a message
    (autopoiesis.agent:send-message "sender" agent-id "hello from test")
    ;; Wait for receiver to finish
    (bt:join-thread receiver-thread)
    ;; Verify
    (is (not (null received))
        "Receiver should have gotten the message")
    (is (= 1 (length received))
        "Exactly one message should be received")
    (when (> (length received) 0)
      (is (equal "hello from test"
                 (autopoiesis.agent:message-content (first received)))
          "Message content should match"))))

;;; ===================================================================
;;; Test 2: Cognitive cycle processes mailbox message
;;; ===================================================================

(test cognitive-cycle-processes-mailbox-message
  "An agentic-agent processes a message sent to its mailbox via cognitive cycle."
  (let ((autopoiesis.agent::*experience-store* (make-hash-table :test 'equal))
        (autopoiesis.agent::*heuristic-store* (make-hash-table :test 'equal)))
    (let* ((autopoiesis.integration:*claude-complete-function*
             (lambda (client messages &key system tools)
               (declare (ignore client system tools))
               ;; Echo back the last user message
               (let ((last-msg (first (last messages))))
                 (make-mock-text-response
                  (format nil "Processed: ~a"
                          (cdr (assoc "content" last-msg :test #'string=)))))))
           (agent (make-instance 'autopoiesis.integration::agentic-agent
                                 :name "mailbox-cycle-agent"
                                 :client (make-mock-client)
                                 :system-prompt "test"
                                 :capabilities nil
                                 :tool-capabilities nil
                                 :max-turns 1)))
      (autopoiesis.agent:start-agent agent)
      ;; Send message to mailbox
      (autopoiesis.agent:send-message "user" (autopoiesis.agent:agent-id agent) "hello")
      ;; Retrieve and process
      (let ((messages (autopoiesis.agent:receive-messages
                       (autopoiesis.agent:agent-id agent) :clear t :timeout 1)))
        (is (= 1 (length messages))
            "One message should be in the mailbox")
        ;; Process via cognitive cycle
        (let ((result (autopoiesis.agent:cognitive-cycle
                       agent (autopoiesis.agent:message-content (first messages)))))
          (is (not (null result))
              "Cognitive cycle should return a result")
          (when result
            (is (search "Processed:" result)
                "Result should contain processed message"))))
      ;; Verify thoughts were recorded
      (let* ((stream (autopoiesis.agent:agent-thought-stream agent))
             (len (autopoiesis.core:stream-length stream))
             (thoughts (autopoiesis.core:stream-last stream len))
             (types (mapcar #'autopoiesis.core:thought-type thoughts)))
        (is (member :observation types)
            "Thought stream should contain an observation")
        (is (member :decision types)
            "Thought stream should contain a decision")
        (is (member :reflection types)
            "Thought stream should contain a reflection")))))

;;; ===================================================================
;;; Test 3: Multiple messages processed sequentially
;;; ===================================================================

(test multiple-messages-processed-sequentially
  "Multiple messages sent to an agent's mailbox are all processed."
  (let ((autopoiesis.agent::*experience-store* (make-hash-table :test 'equal))
        (autopoiesis.agent::*heuristic-store* (make-hash-table :test 'equal)))
    (let* ((call-count 0)
           (autopoiesis.integration:*claude-complete-function*
             (lambda (client messages &key system tools)
               (declare (ignore client messages system tools))
               (incf call-count)
               (make-mock-text-response (format nil "Response ~a" call-count))))
           (agent (make-instance 'autopoiesis.integration::agentic-agent
                                 :name "multi-msg-agent"
                                 :client (make-mock-client)
                                 :system-prompt "test"
                                 :capabilities nil
                                 :tool-capabilities nil
                                 :max-turns 1))
           (agent-id (autopoiesis.agent:agent-id agent)))
      (autopoiesis.agent:start-agent agent)
      ;; Send 3 messages
      (dotimes (i 3)
        (autopoiesis.agent:send-message "user" agent-id (format nil "message ~a" i)))
      ;; Receive and process all
      (let ((messages (autopoiesis.agent:receive-messages agent-id :clear t :timeout 1)))
        (is (= 3 (length messages))
            "All 3 messages should be in the mailbox")
        ;; Process each message through a cognitive cycle
        (dolist (msg messages)
          (handler-case
              (autopoiesis.agent:cognitive-cycle
               agent (autopoiesis.agent:message-content msg))
            (error () nil))))
      ;; Verify all cycles ran
      (is (= 3 call-count)
          "LLM should have been called 3 times")
      ;; Verify reflections for each cycle
      (let* ((stream (autopoiesis.agent:agent-thought-stream agent))
             (len (autopoiesis.core:stream-length stream))
             (thoughts (autopoiesis.core:stream-last stream len))
             (reflections (remove-if-not
                           (lambda (t-) (eq (autopoiesis.core:thought-type t-) :reflection))
                           thoughts)))
        (is (= 3 (length reflections))
            "3 reflection thoughts should be present (one per cycle)")))))
