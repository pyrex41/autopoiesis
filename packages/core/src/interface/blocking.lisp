;;;; blocking.lisp - Human input blocking mechanism
;;;;
;;;; Provides thread-safe blocking primitives for agent code that
;;;; needs to wait for human input.

(in-package #:autopoiesis.interface)

;;; ═══════════════════════════════════════════════════════════════════
;;; Blocking Input Request
;;; ═══════════════════════════════════════════════════════════════════

(defclass blocking-input-request ()
  ((id :initarg :id
       :accessor blocking-request-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique request ID")
   (prompt :initarg :prompt
           :accessor blocking-request-prompt
           :documentation "What to ask the human")
   (context :initarg :context
            :accessor blocking-request-context
            :initform nil
            :documentation "Context for the request")
   (options :initarg :options
            :accessor blocking-request-options
            :initform nil
            :documentation "Suggested options if any")
   (default :initarg :default
            :accessor blocking-request-default
            :initform nil
            :documentation "Default value if timeout occurs")
   (response :initarg :response
             :accessor blocking-request-response
             :initform nil
             :documentation "Human's response once provided")
   (status :initarg :status
           :accessor blocking-request-status
           :initform :pending
           :documentation ":pending :responded :cancelled :timeout")
   (lock :initarg :lock
         :accessor blocking-request-lock
         :documentation "Lock for synchronization")
   (condition-variable :initarg :condition-variable
                       :accessor blocking-request-cv
                       :documentation "Condition variable for blocking")
   (created-at :initarg :created-at
               :accessor blocking-request-created
               :initform (autopoiesis.core:get-precise-time)
               :documentation "When request was created"))
  (:documentation "A blocking request for human input with synchronization primitives"))

(defmethod initialize-instance :after ((request blocking-input-request) &key)
  "Initialize synchronization primitives."
  (unless (slot-boundp request 'lock)
    (setf (blocking-request-lock request)
          (bordeaux-threads:make-lock "blocking-input-lock")))
  (unless (slot-boundp request 'condition-variable)
    (setf (blocking-request-cv request)
          (bordeaux-threads:make-condition-variable
           :name "blocking-input-cv"))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Request Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *blocking-requests* (make-hash-table :test 'equal)
  "Registry of pending blocking requests.")

(defvar *blocking-requests-lock* (bordeaux-threads:make-lock "blocking-requests-lock")
  "Lock for the blocking requests registry.")

(defun register-blocking-request (request)
  "Register a blocking request in the global registry."
  (bordeaux-threads:with-lock-held (*blocking-requests-lock*)
    (setf (gethash (blocking-request-id request) *blocking-requests*) request))
  request)

(defun unregister-blocking-request (request)
  "Remove a blocking request from the registry."
  (bordeaux-threads:with-lock-held (*blocking-requests-lock*)
    (remhash (blocking-request-id request) *blocking-requests*))
  request)

(defun find-blocking-request (id)
  "Find a blocking request by ID."
  (bordeaux-threads:with-lock-held (*blocking-requests-lock*)
    (gethash id *blocking-requests*)))

(defun list-pending-blocking-requests ()
  "List all pending blocking requests."
  (bordeaux-threads:with-lock-held (*blocking-requests-lock*)
    (loop for request being the hash-values of *blocking-requests*
          when (eq (blocking-request-status request) :pending)
            collect request)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Blocking Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun make-blocking-request (prompt &key context options default)
  "Create and register a new blocking input request."
  (let ((request (make-instance 'blocking-input-request
                                :prompt prompt
                                :context context
                                :options options
                                :default default)))
    (register-blocking-request request)
    request))

(defun wait-for-response (request &key (timeout nil))
  "Wait for a response to a blocking request.

   Returns two values:
   - The response (or default on timeout)
   - The final status (:responded, :timeout, or :cancelled)"
  (let ((lock (blocking-request-lock request))
        (cv (blocking-request-cv request)))
    (bordeaux-threads:with-lock-held (lock)
      ;; Wait loop - handles spurious wakeups
      (loop
        ;; Check if already responded
        (when (not (eq (blocking-request-status request) :pending))
          (unregister-blocking-request request)
          (return-from wait-for-response
            (values (or (blocking-request-response request)
                        (blocking-request-default request))
                    (blocking-request-status request))))

        ;; Wait for signal
        (if timeout
            ;; Timed wait
            (let ((signaled (bordeaux-threads:condition-wait
                             cv lock :timeout timeout)))
              (unless signaled
                ;; Timeout occurred
                (setf (blocking-request-status request) :timeout)
                (unregister-blocking-request request)
                (return-from wait-for-response
                  (values (blocking-request-default request) :timeout))))
            ;; Indefinite wait
            (bordeaux-threads:condition-wait cv lock))))))

(defun provide-response (request-or-id response)
  "Provide a response to a blocking request, unblocking the waiter."
  (let ((request (if (stringp request-or-id)
                     (find-blocking-request request-or-id)
                     request-or-id)))
    (when request
      (let ((lock (blocking-request-lock request))
            (cv (blocking-request-cv request)))
        (bordeaux-threads:with-lock-held (lock)
          (setf (blocking-request-response request) response)
          (setf (blocking-request-status request) :responded)
          (bordeaux-threads:condition-notify cv))
        request))))

(defun cancel-blocking-request (request-or-id &key (reason nil))
  "Cancel a blocking request, unblocking the waiter."
  (let ((request (if (stringp request-or-id)
                     (find-blocking-request request-or-id)
                     request-or-id)))
    (when request
      (let ((lock (blocking-request-lock request))
            (cv (blocking-request-cv request)))
        (bordeaux-threads:with-lock-held (lock)
          (setf (blocking-request-response request)
                (if reason `(:cancelled :reason ,reason) :cancelled))
          (setf (blocking-request-status request) :cancelled)
          (bordeaux-threads:condition-notify cv))
        request))))

;;; ═══════════════════════════════════════════════════════════════════
;;; High-Level API
;;; ═══════════════════════════════════════════════════════════════════

(defun blocking-human-input (prompt &key context options default (timeout nil))
  "Request human input and block until received or timeout.

   This is the primary API for agent code that needs human input.

   Arguments:
     prompt   - String describing what input is needed
     context  - Optional context to display to human
     options  - Optional list of suggested options
     default  - Value to return on timeout (nil if not specified)
     timeout  - Seconds to wait (nil = wait forever)

   Returns two values:
     response - The human's response, or default on timeout/cancel
     status   - :responded, :timeout, or :cancelled"
  (let ((request (make-blocking-request prompt
                                        :context context
                                        :options options
                                        :default default)))
    ;; Notify any listeners that we're waiting for input
    (when *current-session*
      (let ((out (session-output-stream *current-session*)))
        (format out "~&~%[AWAITING INPUT] ~a~%" prompt)
        (when options
          (format out "Options: ~{~a~^, ~}~%" options))
        (format out "Request ID: ~a~%" (blocking-request-id request))
        (force-output out)))

    (wait-for-response request :timeout timeout)))

;;; ═══════════════════════════════════════════════════════════════════
;;; CLI Integration
;;; ═══════════════════════════════════════════════════════════════════

(defun respond-to-request (request-id response)
  "CLI command handler: respond to a pending request by ID.

   For use in the CLI session when a human wants to respond
   to a pending blocking request."
  (let ((request (find-blocking-request request-id)))
    (if request
        (progn
          (provide-response request response)
          (values t request))
        (values nil nil))))

(defun show-pending-requests (&optional (stream *standard-output*))
  "Display all pending blocking requests."
  (let ((requests (list-pending-blocking-requests)))
    (if requests
        (progn
          (format stream "~&Pending human input requests:~%")
          (dolist (req requests)
            (format stream "  [~a] ~a~%"
                    (subseq (blocking-request-id req) 0 8)
                    (blocking-request-prompt req))
            (when (blocking-request-options req)
              (format stream "       Options: ~{~a~^, ~}~%"
                      (blocking-request-options req)))))
        (format stream "~&No pending requests.~%"))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Timed Read Line
;;; ═══════════════════════════════════════════════════════════════════

(defun read-line-with-timeout (stream timeout)
  "Read a line from STREAM with TIMEOUT seconds.

   Returns two values:
     line    - The line read, or nil on timeout/EOF
     status  - :ok, :timeout, or :eof"
  (let ((result-lock (bordeaux-threads:make-lock "read-result-lock"))
        (result-cv (bordeaux-threads:make-condition-variable :name "read-result-cv"))
        (line nil)
        (status :pending))

    ;; Spawn a reader thread
    (bordeaux-threads:make-thread
     (lambda ()
       (handler-case
           (let ((read-line (read-line stream nil :eof)))
             (bordeaux-threads:with-lock-held (result-lock)
               (if (eq read-line :eof)
                   (setf status :eof)
                   (progn
                     (setf line read-line)
                     (setf status :ok)))
               (bordeaux-threads:condition-notify result-cv)))
         (error ()
           (bordeaux-threads:with-lock-held (result-lock)
             (setf status :error)
             (bordeaux-threads:condition-notify result-cv)))))
     :name "read-line-with-timeout")

    ;; Wait for result with timeout
    (bordeaux-threads:with-lock-held (result-lock)
      (loop while (eq status :pending)
            do (let ((signaled (bordeaux-threads:condition-wait
                                result-cv result-lock :timeout timeout)))
                 (unless signaled
                   ;; Timeout - we can't easily interrupt the read thread
                   ;; so just return timeout status
                   (setf status :timeout)
                   (return)))))

    (values line status)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Request Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun blocking-request-to-sexpr (request)
  "Serialize a blocking request to an S-expression."
  `(:blocking-request
    :id ,(blocking-request-id request)
    :prompt ,(blocking-request-prompt request)
    :context ,(blocking-request-context request)
    :options ,(blocking-request-options request)
    :default ,(blocking-request-default request)
    :status ,(blocking-request-status request)
    :response ,(blocking-request-response request)
    :created-at ,(blocking-request-created request)))
