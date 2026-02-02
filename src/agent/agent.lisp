;;;; agent.lisp - Agent class and core operations
;;;;
;;;; Defines the agent class and basic lifecycle operations.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass agent ()
  ((id :initarg :id
       :accessor agent-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique identifier for this agent")
   (name :initarg :name
         :accessor agent-name
         :initform "unnamed"
         :documentation "Human-readable name")
   (state :initarg :state
          :accessor agent-state
          :initform :initialized
          :documentation "Current state: :initialized :running :paused :stopped")
   (capabilities :initarg :capabilities
                 :accessor agent-capabilities
                 :initform nil
                 :documentation "List of capability names this agent can use")
   (thought-stream :initarg :thought-stream
                   :accessor agent-thought-stream
                   :initform (autopoiesis.core:make-thought-stream)
                   :documentation "Stream of agent's thoughts")
   (parent :initarg :parent
           :accessor agent-parent
           :initform nil
           :documentation "Parent agent ID if spawned")
   (children :initarg :children
             :accessor agent-children
             :initform nil
             :documentation "List of spawned child agent IDs"))
  (:documentation "An autonomous agent with cognitive capabilities"))

(defun make-agent (&key name capabilities parent)
  "Create a new agent."
  (make-instance 'agent
                 :name (or name "unnamed")
                 :capabilities capabilities
                 :parent parent))

;;; ═══════════════════════════════════════════════════════════════════
;;; Lifecycle Operations
;;; ═══════════════════════════════════════════════════════════════════

(defun start-agent (agent)
  "Start the agent's cognitive loop."
  (setf (agent-state agent) :running)
  agent)

(defun stop-agent (agent)
  "Stop the agent."
  (setf (agent-state agent) :stopped)
  agent)

(defun pause-agent (agent)
  "Pause the agent."
  (when (eq (agent-state agent) :running)
    (setf (agent-state agent) :paused))
  agent)

(defun resume-agent (agent)
  "Resume a paused agent."
  (when (eq (agent-state agent) :paused)
    (setf (agent-state agent) :running))
  agent)

(defun agent-running-p (agent)
  "Return T if agent is running."
  (eq (agent-state agent) :running))
