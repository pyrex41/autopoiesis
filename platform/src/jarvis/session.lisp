;;;; session.lisp - Jarvis session state
;;;;
;;;; A Jarvis session wraps a Pi RPC provider, an agent, and conversation
;;;; history into a single conversational unit.

(in-package #:autopoiesis.jarvis)

;;; ===================================================================
;;; Session Class
;;; ===================================================================

(defclass jarvis-session ()
  ((id                   :initarg :id
                         :accessor jarvis-session-id
                         :initform (autopoiesis.core:make-uuid)
                         :documentation "Unique session identifier")
   (pi-provider          :initarg :pi-provider
                         :accessor jarvis-pi-provider
                         :initform nil
                         :documentation "Active Pi provider with RPC session")
   (agent                :initarg :agent
                         :accessor jarvis-agent
                         :documentation "The backing agent")
   (tool-context         :initarg :tool-context
                         :accessor jarvis-tool-context
                         :initform nil
                         :documentation "Available capability names for Pi")
   (conversation-history :initarg :conversation-history
                         :accessor jarvis-conversation-history
                         :initform nil
                         :documentation "List of (role . content) pairs")
   (supervisor-enabled   :initarg :supervisor-enabled
                         :accessor jarvis-supervisor-enabled-p
                         :initform t
                         :documentation "Whether to wrap tool calls in checkpoints"))
  (:documentation "A Jarvis conversational session backed by Pi RPC."))

(defun make-jarvis-session (&key agent pi-provider tool-context
                                 (supervisor-enabled t))
  "Create a new Jarvis session.

   AGENT - the backing agent instance
   PI-PROVIDER - a started Pi provider for RPC communication
   TOOL-CONTEXT - list of capability names available to Pi
   SUPERVISOR-ENABLED - whether to wrap tool calls in checkpoints (default T)"
  (make-instance 'jarvis-session
                 :agent agent
                 :pi-provider pi-provider
                 :tool-context tool-context
                 :supervisor-enabled supervisor-enabled))

(defmethod print-object ((session jarvis-session) stream)
  (print-unreadable-object (session stream :type t)
    (format stream "~a turns:~d"
            (jarvis-session-id session)
            (length (jarvis-conversation-history session)))))
