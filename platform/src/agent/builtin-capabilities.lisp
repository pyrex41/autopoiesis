;;;; builtin-capabilities.lisp - Built-in agent capabilities
;;;;
;;;; Core capabilities that all agents have access to:
;;;; - introspect: Inspect own internal state
;;;; - spawn: Create new child agents
;;;; - communicate: Send messages to other agents

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Current Agent Context
;;; ═══════════════════════════════════════════════════════════════════

(defvar *current-agent* nil
  "The currently executing agent. Bound during capability invocation.")

(defmacro with-current-agent ((agent) &body body)
  "Execute BODY with *current-agent* bound to AGENT."
  `(let ((*current-agent* ,agent))
     ,@body))

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Queue for Agent Communication
;;; ═══════════════════════════════════════════════════════════════════

(defclass message ()
  ((id :initarg :id
       :accessor message-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique message identifier")
   (from :initarg :from
         :accessor message-from
         :documentation "Sender agent ID")
   (to :initarg :to
       :accessor message-to
       :documentation "Recipient agent ID")
   (content :initarg :content
            :accessor message-content
            :documentation "Message content (S-expression)")
   (timestamp :initarg :timestamp
              :accessor message-timestamp
              :initform (get-universal-time)
              :documentation "When the message was sent"))
  (:documentation "A message between agents"))

(defun make-message (from to content)
  "Create a new message."
  (make-instance 'message
                 :from from
                 :to to
                 :content content))

(defvar *agent-mailboxes* (make-hash-table :test 'equal)
  "Mailboxes for agent communication. Maps agent ID -> list of messages.")

(defun get-mailbox (agent-id)
  "Get or create mailbox for AGENT-ID."
  (or (gethash agent-id *agent-mailboxes*)
      (setf (gethash agent-id *agent-mailboxes*) nil)))

(defun deliver-message (message)
  "Deliver MESSAGE to recipient's mailbox."
  (let ((to-id (message-to message)))
    (push message (gethash to-id *agent-mailboxes*))
    message))

(defun receive-messages (agent-id &key clear)
  "Get all messages for AGENT-ID. If CLEAR is true, remove them from mailbox."
  (let ((messages (reverse (gethash agent-id *agent-mailboxes*))))
    (when clear
      (setf (gethash agent-id *agent-mailboxes*) nil))
    messages))

(defun send-message (from-agent to-agent-or-id content)
  "Send CONTENT from FROM-AGENT to TO-AGENT-OR-ID."
  (let* ((from-id (if (typep from-agent 'agent)
                      (agent-id from-agent)
                      from-agent))
         (to-id (if (typep to-agent-or-id 'agent)
                    (agent-id to-agent-or-id)
                    to-agent-or-id))
         (message (make-message from-id to-id content)))
    (deliver-message message)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Introspect Capability
;;; ═══════════════════════════════════════════════════════════════════

(defun introspect-capabilities (agent)
  "Return list of capability names available to AGENT."
  (agent-capabilities agent))

(defun introspect-thoughts (agent &key (limit 10))
  "Return recent thoughts from AGENT's thought stream."
  (let ((stream (agent-thought-stream agent)))
    (autopoiesis.core:stream-last stream limit)))

(defun introspect-state (agent)
  "Return AGENT's current execution state."
  (agent-state agent))

(defun introspect-children (agent)
  "Return list of child agent IDs."
  (agent-children agent))

(defun introspect-parent (agent)
  "Return parent agent ID or NIL."
  (agent-parent agent))

(defun introspect-identity (agent)
  "Return AGENT's identity information."
  `(:id ,(agent-id agent)
    :name ,(agent-name agent)
    :parent ,(agent-parent agent)
    :children ,(agent-children agent)))

(defun capability-introspect (what &key (limit 10))
  "Inspect own internal state.

   WHAT can be:
   - :capabilities - List available capability names
   - :thoughts - Recent thoughts (use :limit for count)
   - :state - Current execution state
   - :children - List of child agent IDs
   - :parent - Parent agent ID
   - :identity - Full identity information
   - :all - Everything"
  (unless *current-agent*
    (error 'autopoiesis.core:autopoiesis-error
           :message "introspect capability requires *current-agent* to be bound"))
  (ecase what
    (:capabilities (introspect-capabilities *current-agent*))
    (:thoughts (introspect-thoughts *current-agent* :limit limit))
    (:state (introspect-state *current-agent*))
    (:children (introspect-children *current-agent*))
    (:parent (introspect-parent *current-agent*))
    (:identity (introspect-identity *current-agent*))
    (:all `(:identity ,(introspect-identity *current-agent*)
            :state ,(introspect-state *current-agent*)
            :capabilities ,(introspect-capabilities *current-agent*)
            :thoughts ,(introspect-thoughts *current-agent* :limit limit)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Spawn Capability
;;; ═══════════════════════════════════════════════════════════════════

(defun capability-spawn (name &key capabilities)
  "Spawn a new child agent with NAME.

   If CAPABILITIES is not provided, the child inherits the parent's capabilities.
   Returns the newly created agent."
  (unless *current-agent*
    (error 'autopoiesis.core:autopoiesis-error
           :message "spawn capability requires *current-agent* to be bound"))
  (let ((child (spawn-agent *current-agent*
                            :name name
                            :capabilities capabilities)))
    ;; Register the child in the global registry
    (register-agent child)
    child))

;;; ═══════════════════════════════════════════════════════════════════
;;; Communicate Capability
;;; ═══════════════════════════════════════════════════════════════════

(defun capability-communicate (target content)
  "Send CONTENT to TARGET agent.

   TARGET can be an agent object, agent ID, or agent name.
   Returns the sent message."
  (unless *current-agent*
    (error 'autopoiesis.core:autopoiesis-error
           :message "communicate capability requires *current-agent* to be bound"))
  (let ((target-id (etypecase target
                     (agent (agent-id target))
                     (string target))))
    (send-message *current-agent* target-id content)))

(defun capability-receive (&key clear)
  "Receive messages sent to current agent.

   If CLEAR is true, removes messages from mailbox after reading.
   Returns list of messages."
  (unless *current-agent*
    (error 'autopoiesis.core:autopoiesis-error
           :message "receive capability requires *current-agent* to be bound"))
  (receive-messages (agent-id *current-agent*) :clear clear))

;;; ═══════════════════════════════════════════════════════════════════
;;; Register Built-in Capabilities
;;; ═══════════════════════════════════════════════════════════════════

(defun register-builtin-capabilities ()
  "Register all built-in capabilities in the global registry."
  ;; Introspect
  (register-capability
   (make-capability 'introspect
                    #'capability-introspect
                    :description "Inspect own internal state (capabilities, thoughts, state, identity)"))
  ;; Spawn
  (register-capability
   (make-capability 'spawn
                    #'capability-spawn
                    :description "Create a new child agent"))
  ;; Communicate
  (register-capability
   (make-capability 'communicate
                    #'capability-communicate
                    :description "Send a message to another agent"))
  ;; Receive (companion to communicate)
  (register-capability
   (make-capability 'receive
                    #'capability-receive
                    :description "Receive messages from other agents"))
  t)

;; Register on load
(register-builtin-capabilities)
