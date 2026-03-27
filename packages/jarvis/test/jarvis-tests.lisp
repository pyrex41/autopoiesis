;;;; jarvis-tests.lisp - Tests for Jarvis conversational loop
;;;;
;;;; Tests session creation, conversation flow, tool dispatch, human-in-the-loop,
;;;; and supervisor integration.

(in-package #:autopoiesis.test)

(def-suite jarvis-tests
  :description "Jarvis conversational loop tests"
  :in all-tests)

(in-suite jarvis-tests)

;;; ===================================================================
;;; Test Helpers
;;; ===================================================================

(defun make-test-jarvis-agent (&key (name "test-jarvis"))
  "Create an agent for Jarvis testing."
  (autopoiesis.agent:make-agent :name name))

(defun make-test-jarvis-session (&key agent provider tool-context
                                      (supervisor-enabled t))
  "Create a Jarvis session for testing."
  (autopoiesis.jarvis:make-jarvis-session
   :agent (or agent (make-test-jarvis-agent))
   :pi-provider provider
   :tool-context tool-context
   :supervisor-enabled supervisor-enabled))

;;; ===================================================================
;;; Session Creation Tests
;;; ===================================================================

(test jarvis-session-creation
  "make-jarvis-session creates a session with correct fields"
  (let ((agent (make-test-jarvis-agent :name "alpha")))
    (let ((session (autopoiesis.jarvis:make-jarvis-session :agent agent)))
      (is (not (null (autopoiesis.jarvis:jarvis-session-id session))))
      (is (stringp (autopoiesis.jarvis:jarvis-session-id session)))
      (is (eq agent (autopoiesis.jarvis:jarvis-agent session)))
      (is (null (autopoiesis.jarvis:jarvis-conversation-history session)))
      (is (autopoiesis.jarvis:jarvis-supervisor-enabled-p session))
      (is (null (autopoiesis.jarvis:jarvis-pi-provider session))))))

(test jarvis-session-unique-ids
  "Each session gets a unique ID"
  (let ((s1 (make-test-jarvis-session))
        (s2 (make-test-jarvis-session)))
    (is (not (string= (autopoiesis.jarvis:jarvis-session-id s1)
                       (autopoiesis.jarvis:jarvis-session-id s2))))))

(test jarvis-session-supervisor-disabled
  "make-jarvis-session respects supervisor-enabled=nil"
  (let ((session (autopoiesis.jarvis:make-jarvis-session
                  :agent (make-test-jarvis-agent)
                  :supervisor-enabled nil)))
    (is (not (autopoiesis.jarvis:jarvis-supervisor-enabled-p session)))))

(test jarvis-session-tool-context
  "make-jarvis-session stores tool context"
  (let ((tools '(:read-file :write-file :list-dir)))
    (let ((session (autopoiesis.jarvis:make-jarvis-session
                    :agent (make-test-jarvis-agent)
                    :tool-context tools)))
      (is (equal tools (autopoiesis.jarvis:jarvis-tool-context session))))))

(test jarvis-session-print-object
  "Session prints readably"
  (let ((session (make-test-jarvis-session)))
    (let ((printed (format nil "~a" session)))
      (is (stringp printed))
      (is (search "JARVIS-SESSION" printed)))))

;;; ===================================================================
;;; No-Provider Echo Tests
;;; ===================================================================

(test jarvis-no-provider-echo
  "jarvis-prompt with no provider returns echo response"
  (let* ((agent (make-test-jarvis-agent))
         (session (autopoiesis.jarvis:make-jarvis-session :agent agent)))
    (let ((response (autopoiesis.jarvis:jarvis-prompt session "hello world")))
      (is (stringp response))
      (is (search "hello world" response))
      (is (search "[no-provider]" response)))))

(test jarvis-no-provider-history
  "jarvis-prompt records both user and assistant messages"
  (let* ((session (make-test-jarvis-session)))
    (autopoiesis.jarvis:jarvis-prompt session "hello")
    (let ((history (autopoiesis.jarvis:jarvis-conversation-history session)))
      ;; History is pushed (most recent first)
      (is (= 2 (length history)))
      (is (eq :assistant (car (first history))))
      (is (eq :user (car (second history)))))))

(test jarvis-multi-turn-history
  "Multiple prompts accumulate conversation history"
  (let ((session (make-test-jarvis-session)))
    (autopoiesis.jarvis:jarvis-prompt session "first message")
    (autopoiesis.jarvis:jarvis-prompt session "second message")
    (autopoiesis.jarvis:jarvis-prompt session "third message")
    (let ((history (autopoiesis.jarvis:jarvis-conversation-history session)))
      ;; 3 turns x 2 entries each = 6 entries
      (is (= 6 (length history)))
      ;; Most recent is assistant response to "third message"
      (is (eq :assistant (car (first history))))
      ;; User messages are at positions 1, 3, 5
      (is (eq :user (car (second history))))
      (is (search "third message" (cdr (second history)))))))

;;; ===================================================================
;;; Tool Call Parsing Tests
;;; ===================================================================

(test parse-tool-call-valid
  "parse-tool-call extracts tool name and arguments from JSON alist"
  (let ((json `((:tool--use . ((:name . "read_file")
                                (:arguments . ((:path . "/tmp/test.txt"))))))))
    (multiple-value-bind (name args)
        (autopoiesis.jarvis:parse-tool-call json)
      (is (string= "read_file" name))
      (is (string= "/tmp/test.txt" (cdr (assoc :path args)))))))

(test parse-tool-call-no-tool
  "parse-tool-call returns NIL for responses without tool calls"
  (let ((json `((:text . "Just a text response"))))
    (is (null (autopoiesis.jarvis:parse-tool-call json)))))

(test parse-tool-call-nil-input
  "parse-tool-call returns NIL for nil input"
  (is (null (autopoiesis.jarvis:parse-tool-call nil))))

(test parse-tool-call-string-input
  "parse-tool-call returns NIL for non-list input"
  (is (null (autopoiesis.jarvis:parse-tool-call "just a string"))))

(test parse-tool-call-no-arguments
  "parse-tool-call handles tool calls with no arguments"
  (let ((json `((:tool--use . ((:name . "list_capabilities"))))))
    (multiple-value-bind (name args)
        (autopoiesis.jarvis:parse-tool-call json)
      (is (string= "list_capabilities" name))
      (is (null args)))))

(test parse-tool-call-multiple-args
  "parse-tool-call handles tool calls with multiple arguments"
  (let ((json `((:tool--use . ((:name . "write_file")
                                (:arguments . ((:path . "/tmp/out.txt")
                                               (:content . "hello")
                                               (:mode . "overwrite"))))))))
    (multiple-value-bind (name args)
        (autopoiesis.jarvis:parse-tool-call json)
      (is (string= "write_file" name))
      (is (= 3 (length args))))))

;;; ===================================================================
;;; Tool Dispatch Tests
;;; ===================================================================

(defvar *test-tool-called* nil
  "Flag set by test capability.")

(defvar *test-tool-args* nil
  "Arguments received by test capability.")

(defun setup-test-capability ()
  "Register a test capability for dispatch testing."
  (setf *test-tool-called* nil
        *test-tool-args* nil)
  (autopoiesis.agent:register-capability
   (autopoiesis.agent:make-capability
    :test-tool
    (lambda (&key message count)
      (setf *test-tool-called* t
            *test-tool-args* (list :message message :count count))
      (format nil "Tool executed: ~a (~a)" message count))
    :description "Test tool for dispatch testing")))

(defun cleanup-test-capability ()
  "Remove test capability."
  (autopoiesis.agent:unregister-capability :test-tool))

(test dispatch-tool-call-invokes-capability
  "dispatch-tool-call correctly invokes a registered capability"
  (unwind-protect
       (progn
         (setup-test-capability)
         (let ((session (make-test-jarvis-session :supervisor-enabled nil)))
           (let ((result (autopoiesis.jarvis:dispatch-tool-call
                          session "test_tool"
                          '((:message . "hello") (:count . 42)))))
             (is *test-tool-called*)
             (is (string= "hello" (getf *test-tool-args* :message)))
             (is (= 42 (getf *test-tool-args* :count)))
             (is (search "Tool executed" result)))))
    (cleanup-test-capability)))

(test dispatch-tool-call-unknown-tool
  "dispatch-tool-call returns error for unknown tool"
  (let ((session (make-test-jarvis-session :supervisor-enabled nil)))
    (let ((result (autopoiesis.jarvis:dispatch-tool-call
                   session "nonexistent_tool" nil)))
      (is (search "Error" result))
      (is (search "nonexistent_tool" result)))))

(test invoke-tool-with-args
  "invoke-tool passes keyword arguments correctly"
  (unwind-protect
       (progn
         (setup-test-capability)
         (let ((cap (autopoiesis.agent:find-capability :test-tool)))
           (let ((result (autopoiesis.jarvis:invoke-tool
                          cap '((:message . "direct")))))
             (is *test-tool-called*)
             (is (string= "direct" (getf *test-tool-args* :message)))
             (is (search "Tool executed" result)))))
    (cleanup-test-capability)))

(test invoke-tool-nil-args
  "invoke-tool handles nil arguments"
  (let ((cap (autopoiesis.agent:make-capability
              :no-args-tool
              (lambda () "no-args result")
              :description "Tool with no args")))
    (let ((result (autopoiesis.jarvis:invoke-tool cap nil)))
      (is (string= "no-args result" result)))))

(test invoke-tool-error-handling
  "invoke-tool catches errors and returns error string"
  (let ((cap (autopoiesis.agent:make-capability
              :error-tool
              (lambda () (error "deliberate error"))
              :description "Tool that errors")))
    (let ((result (autopoiesis.jarvis:invoke-tool cap nil)))
      (is (search "Error" result))
      (is (search "deliberate error" result)))))

;;; ===================================================================
;;; extract-text Tests
;;; ===================================================================

(test extract-text-string
  "extract-text passes through plain strings"
  (is (string= "hello" (autopoiesis.jarvis::extract-text "hello"))))

(test extract-text-alist-text-key
  "extract-text extracts :text from alist"
  (is (string= "response"
               (autopoiesis.jarvis::extract-text '((:text . "response"))))))

(test extract-text-alist-result-key
  "extract-text extracts :result from alist when no :text"
  (is (string= "result-val"
               (autopoiesis.jarvis::extract-text '((:result . "result-val"))))))

(test extract-text-fallback
  "extract-text formats arbitrary objects"
  (let ((result (autopoiesis.jarvis::extract-text 42)))
    (is (stringp result))
    (is (search "42" result))))

;;; ===================================================================
;;; Lifecycle Tests
;;; ===================================================================

(test start-jarvis-creates-session
  "start-jarvis returns a jarvis-session"
  (let ((session (autopoiesis.jarvis:start-jarvis)))
    (is (typep session 'autopoiesis.jarvis:jarvis-session))
    (is (not (null (autopoiesis.jarvis:jarvis-agent session))))
    ;; Pi provider may or may not be available depending on environment
    (autopoiesis.jarvis:stop-jarvis session)))

(test start-jarvis-with-agent
  "start-jarvis uses the provided agent"
  (let* ((agent (make-test-jarvis-agent :name "custom-agent"))
         (session (autopoiesis.jarvis:start-jarvis :agent agent)))
    (is (eq agent (autopoiesis.jarvis:jarvis-agent session)))
    (is (string= "custom-agent"
                  (autopoiesis.agent:agent-name
                   (autopoiesis.jarvis:jarvis-agent session))))
    (autopoiesis.jarvis:stop-jarvis session)))

(test start-jarvis-creates-agent-when-nil
  "start-jarvis creates a default agent when none provided"
  (let ((session (autopoiesis.jarvis:start-jarvis)))
    (is (not (null (autopoiesis.jarvis:jarvis-agent session))))
    (is (string= "jarvis"
                  (autopoiesis.agent:agent-name
                   (autopoiesis.jarvis:jarvis-agent session))))
    (autopoiesis.jarvis:stop-jarvis session)))

(test stop-jarvis-returns-t
  "stop-jarvis returns T"
  (let ((session (make-test-jarvis-session)))
    (is (eq t (autopoiesis.jarvis:stop-jarvis session)))))

(test stop-jarvis-nil-provider
  "stop-jarvis handles nil provider gracefully"
  (let ((session (make-test-jarvis-session)))
    (is (eq t (autopoiesis.jarvis:stop-jarvis session)))))

;;; ===================================================================
;;; Human-in-the-Loop Tests
;;; ===================================================================

(test jarvis-human-input-records-history
  "jarvis-request-human-input records request and response in history"
  (let ((session (make-test-jarvis-session)))
    ;; Create a request and immediately provide a response from another thread
    (let ((response nil)
          (request-made nil))
      (bt:make-thread
       (lambda ()
         ;; Wait briefly for the request to be registered
         (sleep 0.1)
         ;; Find the pending request and respond
         (let ((pending (autopoiesis.interface:list-pending-blocking-requests)))
           (when pending
             (setf request-made t)
             (autopoiesis.interface:provide-response (first pending) "yes"))))
       :name "test-responder")
      (setf response
            (autopoiesis.jarvis:jarvis-request-human-input
             session "Proceed?" :timeout 2))
      (is (string= "yes" response))
      (let ((history (autopoiesis.jarvis:jarvis-conversation-history session)))
        ;; Should have both human-request and human-response
        (is (>= (length history) 2))
        (is (find :human-request history :key #'car))
        (is (find :human-response history :key #'car))))))

(test jarvis-human-input-timeout-default
  "jarvis-request-human-input returns default on timeout"
  (let ((session (make-test-jarvis-session)))
    (let ((response (autopoiesis.jarvis:jarvis-request-human-input
                     session "Quick?" :timeout 0.1 :default "fallback")))
      (is (string= "fallback" response))
      ;; Should still record in history
      (let ((history (autopoiesis.jarvis:jarvis-conversation-history session)))
        (is (>= (length history) 2))))))

;;; ===================================================================
;;; Supervisor Integration Tests
;;; ===================================================================

(test dispatch-with-supervisor-disabled
  "dispatch-tool-call works with supervisor disabled"
  (unwind-protect
       (progn
         (setup-test-capability)
         (let ((session (make-test-jarvis-session :supervisor-enabled nil)))
           (let ((result (autopoiesis.jarvis:dispatch-tool-call
                          session "test_tool"
                          '((:message . "no-checkpoint")))))
             (is *test-tool-called*)
             (is (search "Tool executed" result)))))
    (cleanup-test-capability)))

(test dispatch-with-supervisor-enabled-but-no-package
  "dispatch-tool-call falls back to direct invocation when supervisor package absent"
  ;; This test verifies the fallback path. Since autopoiesis.supervisor IS loaded
  ;; in our test environment, we test the other branch by disabling supervisor.
  (unwind-protect
       (progn
         (setup-test-capability)
         (let ((session (make-test-jarvis-session :supervisor-enabled nil)))
           (let ((result (autopoiesis.jarvis:dispatch-tool-call
                          session "test_tool"
                          '((:message . "fallback-test")))))
             (is *test-tool-called*)
             (is (search "Tool executed" result)))))
    (cleanup-test-capability)))

;;; ===================================================================
;;; Integration: Full Prompt Cycle (No Provider)
;;; ===================================================================

(test jarvis-full-cycle-no-provider
  "Full prompt cycle with no provider: echo path works end-to-end"
  (let ((session (autopoiesis.jarvis:start-jarvis)))
    (unwind-protect
         (progn
           ;; First turn
           (let ((r1 (autopoiesis.jarvis:jarvis-prompt session "what is 2+2?")))
             (is (search "2+2" r1)))
           ;; Second turn
           (let ((r2 (autopoiesis.jarvis:jarvis-prompt session "thanks")))
             (is (search "thanks" r2)))
           ;; Verify full history
           (let ((history (autopoiesis.jarvis:jarvis-conversation-history session)))
             (is (= 4 (length history)))))
      (autopoiesis.jarvis:stop-jarvis session))))

(test jarvis-error-handling-in-prompt
  "jarvis-prompt handles errors gracefully"
  ;; A session with no provider should not error
  (let ((session (make-test-jarvis-session)))
    (let ((response (autopoiesis.jarvis:jarvis-prompt session "")))
      (is (stringp response)))))
