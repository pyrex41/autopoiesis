;;;; interface-tests.lisp - Tests for human interface layer
;;;;
;;;; Tests the blocking input mechanism and session management.

(in-package #:autopoiesis.test)

(def-suite interface-tests
  :description "Human interface layer tests")

(in-suite interface-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Blocking Request Tests
;;; ═══════════════════════════════════════════════════════════════════

(test blocking-request-creation
  "Test creating a blocking request"
  (let ((request (autopoiesis.interface:make-blocking-request
                  "What is your name?"
                  :context '(:greeting t)
                  :options '("Alice" "Bob" "Charlie")
                  :default "Anonymous")))
    (is (stringp (autopoiesis.interface:blocking-request-id request)))
    (is (equal "What is your name?" (autopoiesis.interface:blocking-request-prompt request)))
    (is (equal '(:greeting t) (autopoiesis.interface:blocking-request-context request)))
    (is (equal '("Alice" "Bob" "Charlie") (autopoiesis.interface:blocking-request-options request)))
    (is (equal "Anonymous" (autopoiesis.interface:blocking-request-default request)))
    (is (eq :pending (autopoiesis.interface:blocking-request-status request)))))

(test blocking-request-registry
  "Test blocking request registration and lookup"
  (let ((request (autopoiesis.interface:make-blocking-request "Test prompt")))
    (is (not (null (autopoiesis.interface:find-blocking-request
                    (autopoiesis.interface:blocking-request-id request)))))
    ;; Clean up
    (autopoiesis.interface::unregister-blocking-request request)
    (is (null (autopoiesis.interface:find-blocking-request
               (autopoiesis.interface:blocking-request-id request))))))

(test provide-response-unblocks
  "Test that providing a response changes status"
  (let ((request (autopoiesis.interface:make-blocking-request "Enter value:")))
    (autopoiesis.interface:provide-response request "test-value")
    (is (eq :responded (autopoiesis.interface:blocking-request-status request)))
    (is (equal "test-value" (autopoiesis.interface:blocking-request-response request)))))

(test cancel-request
  "Test cancelling a blocking request"
  (let ((request (autopoiesis.interface:make-blocking-request "Enter value:")))
    (autopoiesis.interface:cancel-blocking-request request :reason "User cancelled")
    (is (eq :cancelled (autopoiesis.interface:blocking-request-status request)))
    (is (equal '(:cancelled :reason "User cancelled")
               (autopoiesis.interface:blocking-request-response request)))))

(test blocking-with-timeout
  "Test wait-for-response with timeout"
  (let ((request (autopoiesis.interface:make-blocking-request
                  "Prompt"
                  :default "default-value")))
    ;; Wait with very short timeout - should timeout since no one is responding
    (multiple-value-bind (response status)
        (autopoiesis.interface:wait-for-response request :timeout 0.1)
      (is (eq :timeout status))
      (is (equal "default-value" response)))))

(test blocking-with-immediate-response
  "Test wait-for-response when response is provided immediately"
  (let ((request (autopoiesis.interface:make-blocking-request "Prompt")))
    ;; Provide response before waiting
    (autopoiesis.interface:provide-response request "immediate-response")
    (multiple-value-bind (response status)
        (autopoiesis.interface:wait-for-response request :timeout 1.0)
      (is (eq :responded status))
      (is (equal "immediate-response" response)))))

(test threaded-blocking-response
  "Test that response from another thread unblocks waiter"
  (let ((request (autopoiesis.interface:make-blocking-request "Enter name:"))
        (result nil)
        (result-status nil))
    ;; Start waiter thread
    (let ((waiter (bordeaux-threads:make-thread
                   (lambda ()
                     (multiple-value-bind (r s)
                         (autopoiesis.interface:wait-for-response request :timeout 5.0)
                       (setf result r)
                       (setf result-status s)))
                   :name "test-waiter")))
      ;; Give waiter time to start
      (sleep 0.1)
      ;; Provide response from main thread
      (autopoiesis.interface:provide-response request "Alice")
      ;; Wait for waiter to complete
      (bordeaux-threads:join-thread waiter)
      (is (eq :responded result-status))
      (is (equal "Alice" result)))))

(test list-pending-requests
  "Test listing pending requests"
  ;; Clean up any existing requests first
  (bordeaux-threads:with-lock-held (autopoiesis.interface::*blocking-requests-lock*)
    (clrhash autopoiesis.interface::*blocking-requests*))

  (let ((req1 (autopoiesis.interface:make-blocking-request "Request 1"))
        (req2 (autopoiesis.interface:make-blocking-request "Request 2")))
    (let ((pending (autopoiesis.interface:list-pending-blocking-requests)))
      (is (= 2 (length pending)))
      (is (member req1 pending))
      (is (member req2 pending)))
    ;; Respond to one
    (autopoiesis.interface:provide-response req1 "done")
    (let ((pending (autopoiesis.interface:list-pending-blocking-requests)))
      (is (= 1 (length pending)))
      (is (member req2 pending)))
    ;; Clean up
    (autopoiesis.interface::unregister-blocking-request req2)))

;;; ═══════════════════════════════════════════════════════════════════
;;; CLI Command Tests
;;; ═══════════════════════════════════════════════════════════════════

(test cli-command-parsing
  "Test CLI command parsing"
  (let ((cmd (autopoiesis.interface:parse-cli-command "inject hello world")))
    (is (eq :inject (autopoiesis.interface:command-name cmd)))
    (is (equal '("hello" "world") (autopoiesis.interface:command-args cmd))))
  (let ((cmd (autopoiesis.interface:parse-cli-command "status")))
    (is (eq :status (autopoiesis.interface:command-name cmd)))
    (is (null (autopoiesis.interface:command-args cmd)))))

(test respond-to-request-command
  "Test the respond-to-request helper"
  ;; Clean up first
  (bordeaux-threads:with-lock-held (autopoiesis.interface::*blocking-requests-lock*)
    (clrhash autopoiesis.interface::*blocking-requests*))

  (let ((request (autopoiesis.interface:make-blocking-request "Enter value:")))
    (let ((id (autopoiesis.interface:blocking-request-id request)))
      (multiple-value-bind (did-succeed found-request)
          (autopoiesis.interface:respond-to-request id "my-response")
        (is (not (null did-succeed)))
        (is (eq request found-request))
        (is (equal "my-response" (autopoiesis.interface:blocking-request-response request)))
        (is (eq :responded (autopoiesis.interface:blocking-request-status request)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Session Tests
;;; ═══════════════════════════════════════════════════════════════════

(test session-creation
  "Test session creation and lifecycle"
  (let* ((agent (autopoiesis.agent:make-agent :name "test-agent"))
         (session (autopoiesis.interface:start-session "test-user" agent)))
    (is (not (null session)))
    (is (stringp (autopoiesis.interface:session-id session)))
    (is (equal "test-user" (autopoiesis.interface:session-user session)))
    (is (eq agent (autopoiesis.interface:session-agent session)))
    ;; Check it's registered
    (is (eq session (autopoiesis.interface:find-session (autopoiesis.interface:session-id session))))
    ;; End session
    (autopoiesis.interface:end-session session)
    (is (null (autopoiesis.interface:find-session (autopoiesis.interface:session-id session))))))

(test session-summary
  "Test session summary generation"
  (let* ((agent (autopoiesis.agent:make-agent :name "summary-test"))
         (session (autopoiesis.interface:start-session "user" agent)))
    (let ((summary (autopoiesis.interface:session-summary session)))
      (is (getf summary :id))
      (is (equal "user" (getf summary :user)))
      (is (equal "summary-test" (getf summary :agent))))
    (autopoiesis.interface:end-session session)))
