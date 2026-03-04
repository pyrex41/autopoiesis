;;;; dual-agent.lisp - Bridge between mutable agents and persistent agents
;;;;
;;;; Wraps a mutable CLOS agent with a persistent-agent root, providing
;;;; thread-safe version tracking, undo, and automatic sync.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Dual-Mode Agent
;;; ═══════════════════════════════════════════════════════════════════

(defclass dual-agent (agent)
  ((persistent-root :accessor %dual-agent-root
                    :initform nil
                    :documentation "Current persistent-agent root struct")
   (root-lock :initform (bt:make-recursive-lock "dual-agent-root")
              :documentation "Lock guarding persistent-root access")
   (version-history :accessor dual-agent-history
                    :initform nil
                    :documentation "List of previous persistent-agent roots")
   (auto-snapshot-p :accessor dual-agent-auto-snapshot-p
                    :initform t
                    :documentation "When T, automatically update persistent root on state changes"))
  (:documentation "Agent that maintains both a mutable CLOS object and an immutable
persistent-agent root. The persistent root provides O(1) forking, automatic
version history, and structural sharing."))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thread-Safe Root Access
;;; ═══════════════════════════════════════════════════════════════════

(defun dual-agent-root (agent)
  "Thread-safe reader for the persistent root of AGENT."
  (bt:with-recursive-lock-held ((slot-value agent 'root-lock))
    (%dual-agent-root agent)))

(defun (setf dual-agent-root) (new-root agent)
  "Thread-safe writer for the persistent root of AGENT.
   Pushes old root onto version history before replacing."
  (bt:with-recursive-lock-held ((slot-value agent 'root-lock))
    (let ((old (%dual-agent-root agent)))
      (when old
        (push old (dual-agent-history agent))))
    (setf (%dual-agent-root agent) new-root)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Conversion and Upgrade
;;; ═══════════════════════════════════════════════════════════════════

(defun agent-to-persistent (agent)
  "Convert a mutable agent's current state to a persistent-agent struct."
  (make-persistent-agent
   :name (agent-name agent)
   :capabilities (agent-capabilities agent)
   :metadata (alist-to-pmap
              (list (cons :state (agent-state agent))
                    (cons :parent (agent-parent agent))))))

(defun sync-persistent-to-agent (dual)
  "Sync the persistent root's state back to the mutable agent slots."
  (let ((root (dual-agent-root dual)))
    (when root
      (setf (agent-name dual) (persistent-agent-name root))
      (setf (agent-capabilities dual)
            (pset-to-list (persistent-agent-capabilities root))))))

(defun sync-agent-to-persistent (dual)
  "Create a new persistent root reflecting the mutable agent's current state.
   Does not push to history (caller is responsible for setf)."
  (let ((root (dual-agent-root dual)))
    (if root
        (copy-persistent-agent root
                               :name (agent-name dual)
                               :capabilities (list-to-pset (agent-capabilities dual)))
        (agent-to-persistent dual))))

(defun upgrade-to-dual (agent)
  "Upgrade a plain agent to a dual-agent, initializing persistent root.
   Returns a new dual-agent instance."
  (let ((dual (change-class agent 'dual-agent)))
    (setf (dual-agent-root dual) (agent-to-persistent agent))
    dual))

;;; ═══════════════════════════════════════════════════════════════════
;;; Undo
;;; ═══════════════════════════════════════════════════════════════════

(defun dual-agent-undo (agent)
  "Revert the persistent root to the previous version.
   Returns the reverted root, or NIL if no history."
  (bt:with-recursive-lock-held ((slot-value agent 'root-lock))
    (let ((prev (pop (dual-agent-history agent))))
      (when prev
        (setf (%dual-agent-root agent) prev)
        (sync-persistent-to-agent agent)
        prev))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Automatic Sync
;;; ═══════════════════════════════════════════════════════════════════

(defmethod (setf agent-state) :after (new-state (agent dual-agent))
  "After setting state on a dual-agent, sync to persistent root if auto-snapshot."
  (declare (ignore new-state))
  (when (and (dual-agent-auto-snapshot-p agent)
             (%dual-agent-root agent))
    (setf (dual-agent-root agent) (sync-agent-to-persistent agent))))

(defmethod (setf agent-name) :after (new-name (agent dual-agent))
  "After setting name on a dual-agent, sync to persistent root."
  (declare (ignore new-name))
  (when (and (dual-agent-auto-snapshot-p agent)
             (%dual-agent-root agent))
    (setf (dual-agent-root agent) (sync-agent-to-persistent agent))))

(defmethod (setf agent-capabilities) :after (new-caps (agent dual-agent))
  "After setting capabilities on a dual-agent, sync to persistent root."
  (declare (ignore new-caps))
  (when (and (dual-agent-auto-snapshot-p agent)
             (%dual-agent-root agent))
    (setf (dual-agent-root agent) (sync-agent-to-persistent agent))))
