;;;; turn.lisp - Conversation turn operations
;;;;
;;;; Turns are datom entities stored in the substrate. Content is stored as
;;;; content-addressed blobs. All datoms for a turn (including context head
;;;; update) are written in a single transact! call for atomicity.

(in-package #:autopoiesis.conversation)

(defun append-turn (context-eid role content &key model tokens tool-use metadata)
  "Append a new turn to a conversation context.
   Stores content as blob, creates turn datoms, updates context head.
   Returns the new turn entity ID.

   IMPORTANT: All datoms (turn + context head update) are written in a
   SINGLE transact! call to prevent orphaned turns on crash."
  (let* ((turn-eid (intern-id (format nil "turn-~A" (autopoiesis.core:make-uuid))))
         (content-hash (store-blob content))
         (tool-hash (when tool-use (store-blob (prin1-to-string tool-use))))
         (parent-eid (entity-attr context-eid :context/head)))
    ;; Single transact! for atomicity -- turn datoms + context head update
    (transact!
     (remove nil
      (list (make-datom turn-eid :turn/role role)
            (make-datom turn-eid :turn/content-hash content-hash)
            (make-datom turn-eid :turn/context context-eid)
            (make-datom turn-eid :turn/timestamp (get-universal-time))
            (make-datom turn-eid :entity/type :turn)
            (when parent-eid
              (make-datom turn-eid :turn/parent parent-eid))
            (when model
              (make-datom turn-eid :turn/model model))
            (when tokens
              (make-datom turn-eid :turn/tokens tokens))
            (when tool-hash
              (make-datom turn-eid :turn/tool-use tool-hash))
            (when metadata
              (make-datom turn-eid :turn/metadata metadata))
            ;; Context head update in the SAME transaction
            (make-datom context-eid :context/head turn-eid))))
    turn-eid))

(defun turn-content (turn-eid)
  "Load the full content of a turn from blob store."
  (load-blob (entity-attr turn-eid :turn/content-hash) :as-string t))

