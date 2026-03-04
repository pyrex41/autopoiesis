;;;; context.lisp - Conversation context operations
;;;;
;;;; Contexts are mutable entity pointers to branch heads. Fork is O(1) --
;;;; creates a new context pointing at the same head turn.

(in-package #:autopoiesis.conversation)

(defun make-context (name &key agent-eid)
  "Create a new conversation context. Returns context entity ID."
  (let ((ctx-eid (intern-id (format nil "ctx-~A" (autopoiesis.core:make-uuid)))))
    (transact!
     (remove nil
      (list (make-datom ctx-eid :entity/type :context)
            (make-datom ctx-eid :context/name name)
            (make-datom ctx-eid :context/created-at (get-universal-time))
            (when agent-eid
              (make-datom ctx-eid :context/agent agent-eid)))))
    ctx-eid))

(defun fork-context (source-ctx-eid &key name)
  "Fork a conversation. O(1) -- creates new context pointing at same head turn."
  (let* ((ctx-attrs (pull source-ctx-eid '(:context/head :context/name)))
         (head (getf ctx-attrs :context/head))
         (source-name (getf ctx-attrs :context/name))
         (fork-name (or name (format nil "fork-~A" source-name)))
         (fork-eid (intern-id (format nil "ctx-~A" (autopoiesis.core:make-uuid)))))
    (transact!
     (remove nil
      (list (make-datom fork-eid :entity/type :context)
            (make-datom fork-eid :context/name fork-name)
            (when head
              (make-datom fork-eid :context/head head))
            (make-datom fork-eid :context/forked-from source-ctx-eid)
            (make-datom fork-eid :context/created-at (get-universal-time)))))
    fork-eid))

(defun context-head (ctx-eid)
  "Get the head turn entity ID for a context."
  (entity-attr ctx-eid :context/head))

(defun context-history (ctx-eid &key (limit 100))
  "Walk parent chain from context head, return turn eids in chronological order."
  (let ((turns nil)
        (current-eid (context-head ctx-eid)))
    (loop for i from 0 below limit
          while current-eid
          do (push current-eid turns)
             (setf current-eid (entity-attr current-eid :turn/parent)))
    turns))  ; Already chronological due to push + parent walk

;;; ===================================================================
;;; Query helpers (defined here because they depend on context-history)
;;; ===================================================================

(defun find-turns-by-role (ctx-eid role &key (limit 100))
  "Find turns in a context matching ROLE. Walks the parent chain from head."
  (let ((result nil))
    (dolist (turn-eid (context-history ctx-eid :limit limit))
      (when (eq role (entity-attr turn-eid :turn/role))
        (push turn-eid result)))
    (nreverse result)))

(defun find-turns-by-time-range (ctx-eid start-time end-time &key (limit 100))
  "Find turns in a context within a time range. Walks the parent chain from head."
  (let ((result nil))
    (dolist (turn-eid (context-history ctx-eid :limit limit))
      (let ((ts (entity-attr turn-eid :turn/timestamp)))
        (when (and ts (<= start-time ts) (<= ts end-time))
          (push turn-eid result))))
    (nreverse result)))
