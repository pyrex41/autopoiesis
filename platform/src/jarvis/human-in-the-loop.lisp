;;;; human-in-the-loop.lisp - Jarvis human input integration
;;;;
;;;; Bridges the Jarvis conversation loop with the blocking input
;;;; mechanism from autopoiesis.interface.

(in-package #:autopoiesis.jarvis)

;;; ===================================================================
;;; Human Input Requests
;;; ===================================================================

(defun jarvis-request-human-input (session prompt &key timeout options default)
  "Request human input through the blocking request mechanism.

   Creates a blocking-input-request and waits for the response.
   Records the request and response in conversation history.

   PROMPT  - string describing what input is needed
   TIMEOUT - seconds to wait (nil = wait forever)
   OPTIONS - suggested response options
   DEFAULT - value to return on timeout

   Returns the human's response string, or DEFAULT on timeout."
  (let ((request (autopoiesis.interface:make-blocking-request
                  prompt
                  :options options
                  :default default)))
    ;; Record in conversation history
    (push (cons :human-request prompt)
          (jarvis-conversation-history session))
    ;; Wait for response
    (let ((response (autopoiesis.interface:wait-for-response
                     request :timeout timeout)))
      (push (cons :human-response (or response default))
            (jarvis-conversation-history session))
      (or response default))))
