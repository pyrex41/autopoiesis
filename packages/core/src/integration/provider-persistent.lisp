;;;; provider-persistent.lisp - Persistent integration for provider-backed agents
;;;;
;;;; Bridges provider-backed-agent (CLI provider loop) with the persistent
;;;; agent layer, recording cognitive phases as persistent versions.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Provider Agent
;;; ═══════════════════════════════════════════════════════════════════

(defclass persistent-provider-agent (provider-backed-agent autopoiesis.agent:dual-agent)
  ()
  (:documentation "Provider-backed agent with persistent version tracking.
Each cognitive phase updates the persistent root, providing automatic
version history and O(1) forking of the agent's full state."))

(defun make-persistent-provider-agent (provider &key name system-prompt capabilities mode)
  "Create a provider-backed agent with persistent version tracking."
  (let ((agent (make-provider-backed-agent provider
                                           :name name
                                           :system-prompt system-prompt
                                           :capabilities capabilities
                                           :mode mode)))
    (change-class agent 'persistent-provider-agent)
    (setf (autopoiesis.agent:dual-agent-root agent)
          (autopoiesis.agent:agent-to-persistent agent))
    agent))

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Tracking After Cognitive Phases
;;; ═══════════════════════════════════════════════════════════════════

(defmethod autopoiesis.agent:perceive :after ((agent persistent-provider-agent) environment)
  "After perceive, update persistent root."
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

(defmethod autopoiesis.agent:act :after ((agent persistent-provider-agent) decision)
  "After act, update persistent root."
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
