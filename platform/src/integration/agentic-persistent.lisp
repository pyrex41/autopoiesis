;;;; agentic-persistent.lisp - Persistent integration for agentic agents
;;;;
;;;; Bridges agentic-agent (direct LLM API loop) with the persistent
;;;; agent layer, recording each cognitive phase as a persistent version.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Agentic Agent
;;; ═══════════════════════════════════════════════════════════════════

(defclass persistent-agentic-agent (agentic-agent autopoiesis.agent:dual-agent)
  ()
  (:documentation "Agentic agent with persistent version tracking.
Each cognitive phase updates the persistent root, providing automatic
version history and O(1) forking of the agent's full state."))

(defun make-persistent-agentic-agent (&key api-key model name system-prompt
                                           capabilities max-turns provider)
  "Create an agentic agent with persistent version tracking."
  (let ((agent (make-agentic-agent :api-key api-key
                                   :model model
                                   :name name
                                   :system-prompt system-prompt
                                   :capabilities capabilities
                                   :max-turns max-turns
                                   :provider provider)))
    (change-class agent 'persistent-agentic-agent)
    (setf (autopoiesis.agent:dual-agent-root agent)
          (autopoiesis.agent:agent-to-persistent agent))
    agent))

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Tracking After Cognitive Phases
;;; ═══════════════════════════════════════════════════════════════════

(defmethod autopoiesis.agent:perceive :after ((agent persistent-agentic-agent) environment)
  "After perceive, update persistent root with new thoughts."
  (declare (ignore environment))
  (when (autopoiesis.agent:dual-agent-auto-snapshot-p agent)
    (let ((root (autopoiesis.agent:dual-agent-root agent)))
      (when root
        (setf (autopoiesis.agent:dual-agent-root agent)
              (autopoiesis.agent:copy-persistent-agent
               root
               :thoughts (autopoiesis.core:pvec-push
                          (autopoiesis.agent:persistent-agent-thoughts root)
                          (list :type :perceive
                                :timestamp (autopoiesis.core:get-precise-time)
                                :content "perceive-phase"))))))))

(defmethod autopoiesis.agent:act :after ((agent persistent-agentic-agent) decision)
  "After act, update persistent root with action record."
  (declare (ignore decision))
  (when (autopoiesis.agent:dual-agent-auto-snapshot-p agent)
    (let ((root (autopoiesis.agent:dual-agent-root agent)))
      (when root
        (setf (autopoiesis.agent:dual-agent-root agent)
              (autopoiesis.agent:copy-persistent-agent
               root
               :thoughts (autopoiesis.core:pvec-push
                          (autopoiesis.agent:persistent-agent-thoughts root)
                          (list :type :act
                                :timestamp (autopoiesis.core:get-precise-time)
                                :content "act-phase"))))))))
