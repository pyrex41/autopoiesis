;;;; protocol.lisp - Human-in-the-loop protocol
;;;;
;;;; Defines the protocol for human-agent communication.

(in-package #:autopoiesis.interface)

;;; ═══════════════════════════════════════════════════════════════════
;;; Protocol Messages
;;; ═══════════════════════════════════════════════════════════════════

(defclass protocol-message ()
  ((id :initarg :id
       :accessor message-id
       :initform (autopoiesis.core:make-uuid))
   (type :initarg :type
         :accessor message-type
         :documentation "Message type keyword")
   (from :initarg :from
         :accessor message-from
         :documentation ":human or :agent")
   (to :initarg :to
       :accessor message-to
       :documentation ":human or :agent")
   (timestamp :initarg :timestamp
              :accessor message-timestamp
              :initform (autopoiesis.core:get-precise-time))
   (payload :initarg :payload
            :accessor message-payload
            :initform nil))
  (:documentation "A protocol message between human and agent"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Types
;;; ═══════════════════════════════════════════════════════════════════

(defun make-query-message (question &key context)
  "Create a query from agent to human."
  (make-instance 'protocol-message
                 :type :query
                 :from :agent
                 :to :human
                 :payload `(:question ,question :context ,context)))

(defun make-response-message (query-id response)
  "Create a response from human to agent."
  (make-instance 'protocol-message
                 :type :response
                 :from :human
                 :to :agent
                 :payload `(:query-id ,query-id :response ,response)))

(defun make-notification-message (content &key priority)
  "Create a notification from agent to human."
  (make-instance 'protocol-message
                 :type :notification
                 :from :agent
                 :to :human
                 :payload `(:content ,content :priority ,(or priority :normal))))

(defun make-command-message (command &rest args)
  "Create a command from human to agent."
  (make-instance 'protocol-message
                 :type :command
                 :from :human
                 :to :agent
                 :payload `(:command ,command :args ,args)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Handling
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric handle-message (agent message)
  (:documentation "Handle an incoming protocol message.")
  (:method ((agent t) (message protocol-message))
    ;; Default: log and ignore
    (declare (ignore agent message))
    nil))
