;;;; session.lisp - Jarvis session state
;;;;
;;;; A Jarvis session wraps a provider, an agent, and conversation
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
   (provider             :initarg :provider
                         :initarg :pi-provider
                         :accessor jarvis-provider
                         :initform nil
                         :documentation "Active provider for the session")
   (agent                :initarg :agent
                         :accessor jarvis-agent
                         :documentation "The backing agent")
   (tool-context         :initarg :tool-context
                         :accessor jarvis-tool-context
                         :initform nil
                         :documentation "Available capability names for the provider")
   (conversation-history :initarg :conversation-history
                         :accessor jarvis-conversation-history
                         :initform nil
                         :documentation "List of (role . content) pairs")
   (supervisor-enabled   :initarg :supervisor-enabled
                         :accessor jarvis-supervisor-enabled-p
                         :initform t
                         :documentation "Whether to wrap tool calls in checkpoints"))
  (:documentation "A Jarvis conversational session backed by an LLM provider."))

;; Backward compatibility alias
(defmethod jarvis-pi-provider ((session jarvis-session))
  (jarvis-provider session))

(defmethod (setf jarvis-pi-provider) (value (session jarvis-session))
  (setf (jarvis-provider session) value))

(defun make-jarvis-session (&key agent provider pi-provider tool-context
                                 (supervisor-enabled t))
  "Create a new Jarvis session.

   AGENT - the backing agent instance
   PROVIDER - a started provider for communication (preferred)
   PI-PROVIDER - alias for PROVIDER (backward compat)
   TOOL-CONTEXT - list of capability names available to the provider
   SUPERVISOR-ENABLED - whether to wrap tool calls in checkpoints (default T)"
  (make-instance 'jarvis-session
                 :agent agent
                 :provider (or provider pi-provider)
                 :tool-context tool-context
                 :supervisor-enabled supervisor-enabled))

(defmethod print-object ((session jarvis-session) stream)
  (print-unreadable-object (session stream :type t)
    (format stream "~a turns:~d"
            (jarvis-session-id session)
            (length (jarvis-conversation-history session)))))
