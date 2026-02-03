;;;; entry-points.lisp - Human intervention points
;;;;
;;;; Where humans can intervene in agent execution.

(in-package #:autopoiesis.interface)

;;; ═══════════════════════════════════════════════════════════════════
;;; Human Input Request
;;; ═══════════════════════════════════════════════════════════════════

(defclass human-input-request ()
  ((id :initarg :id
       :accessor request-id
       :initform (autopoiesis.core:make-uuid))
   (prompt :initarg :prompt
           :accessor request-prompt
           :documentation "What to ask the human")
   (context :initarg :context
            :accessor request-context
            :initform nil
            :documentation "Context for the request")
   (options :initarg :options
            :accessor request-options
            :initform nil
            :documentation "Suggested options if any")
   (response :initarg :response
             :accessor request-response
             :initform nil
             :documentation "Human's response once provided")
   (status :initarg :status
           :accessor request-status
           :initform :pending
           :documentation ":pending :responded :cancelled"))
  (:documentation "A request for human input"))

(defvar *pending-requests* (make-hash-table :test 'equal)
  "Pending human input requests.")

(defun request-human-input (prompt &key context options)
  "Request input from a human. Returns a request object."
  (let ((request (make-instance 'human-input-request
                                :prompt prompt
                                :context context
                                :options options)))
    (setf (gethash (request-id request) *pending-requests*) request)
    request))

(defun await-human-response (request &key timeout)
  "Wait for human response to REQUEST.

   Uses the blocking input mechanism with proper synchronization.
   Returns two values: the response and the status."
  (let ((blocking-req (make-blocking-request
                       (request-prompt request)
                       :context (request-context request)
                       :options (request-options request))))
    ;; Link the requests
    (setf (gethash (request-id request) *pending-requests*)
          blocking-req)

    ;; Wait for response
    (multiple-value-bind (response status)
        (wait-for-response blocking-req :timeout timeout)
      ;; Update original request
      (setf (request-response request) response)
      (setf (request-status request) status)
      (values response status))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Human Override Actions
;;; ═══════════════════════════════════════════════════════════════════

(defun human-override (agent new-state)
  "Override agent state with human-provided state."
  ;; Record that this was a human override
  (autopoiesis.core:stream-append
   (autopoiesis.agent:agent-thought-stream agent)
   (autopoiesis.core:make-observation
    new-state
    :source :human-override
    :interpreted `(:human-override :new-state ,new-state)))
  new-state)

(defun human-approve (decision)
  "Mark a decision as human-approved."
  (setf (autopoiesis.core:thought-confidence decision) 1.0)
  decision)

(defun human-reject (decision &key reason)
  "Reject a decision with optional reason."
  (setf (autopoiesis.core:thought-confidence decision) 0.0)
  (when reason
    (setf (autopoiesis.core:decision-rationale decision)
          (format nil "REJECTED: ~a" reason)))
  decision)

(defun human-modify (thought modifications)
  "Apply human modifications to a thought."
  (declare (ignore thought modifications))
  ;; Placeholder - would apply modifications to thought content
  nil)
