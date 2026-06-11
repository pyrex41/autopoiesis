;;;; room-mcp.lisp - "Shared room" MCP tools backed by the substrate branch API
;;;;
;;;; The keystone for the multi-agent "shared room": multiple independent MCP
;;;; clients connect to ONE substrate-backed room. Each agent stages its work
;;;; onto its OWN speculative branch (via MCP tool calls), and the room folds
;;;; the branches back into the shared base with a cardinality-aware FACT-merge:
;;;;   - independent facts union cleanly
;;;;   - a genuine same-(entity,attribute) divergence on a :one attr is FLAGGED
;;;;     (a merge-conflict), never silently lost.
;;;;
;;;; This reuses, verbatim, the proven substrate primitives in
;;;; packages/substrate/src/speculative.lisp (branch-fork / branch-stage /
;;;; branch-read / branch-merge / declare-cardinality). The only new thing here
;;;; is the *room layer*: an agent->branch registry and the MCP tool surface
;;;; that lets two people's agents reach the same room over the wire.
;;;;
;;;; Tools (registered into mcp-tool-definitions, dispatched in
;;;; mcp-execute-tool):
;;;;   room_join  (agent)                       -> fork a branch for that agent
;;;;   room_post  (agent,entity,attribute,value) -> branch-stage onto its branch
;;;;   room_read  (entity,attribute)             -> read the shared base
;;;;   room_merge (agent)                        -> branch-merge into base
;;;;   room_state ()                             -> agents + staged writes (obs.)
;;;;
;;;; Reads/writes go through the REAL substrate; this is exercised against the
;;;; GLOBAL *store* (set by open-store), which is what Hunchentoot handler
;;;; threads see.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Room state: agent-name -> speculative branch
;;; ===================================================================

(defvar *room-branches* (make-hash-table :test 'equal)
  "Maps agent-name (string) -> the agent's speculative datom-branch.")

(defvar *room-lock* (bordeaux-threads:make-lock "room-branches-lock")
  "Guards *room-branches* so concurrent MCP clients can join/post/merge safely.")

(defvar *room-schema-declared* nil
  "Whether the demo room attribute cardinalities have been declared.")

(defun room-ensure-schema ()
  "Declare cardinalities for the demo room attributes (idempotent).
   Real builds would declare these on define-entity-type; the room layer just
   needs every staged attribute to have a decidable cardinality before merge.
   We register a couple of conventional attrs plus accept any caller attr,
   defaulting unknown attrs to :one unless the name ends in a plural-ish marker."
  (unless *room-schema-declared*
    ;; A canonical :one attribute (single-valued, can diverge) and a :many
    ;; attribute (accumulates, unions cleanly).
    (autopoiesis.substrate:declare-cardinality "room/decision" :one)
    (autopoiesis.substrate:declare-cardinality "room/owner"    :one)
    (autopoiesis.substrate:declare-cardinality "room/status"   :one)
    (autopoiesis.substrate:declare-cardinality "room/note"     :many)
    (autopoiesis.substrate:declare-cardinality "room/file"     :many)
    (setf *room-schema-declared* t)))

(defun room-declare-attr (attribute cardinality)
  "Allow a caller to declare an attribute's cardinality through the room layer
   (so a client can introduce its own :one/:many attrs)."
  (autopoiesis.substrate:declare-cardinality attribute cardinality))

;;; ===================================================================
;;; Room operations (the thin layer the MCP tools call)
;;; ===================================================================

(defun room-join (agent-name)
  "Fork a fresh speculative branch for AGENT-NAME off the shared base.
   Returns a result alist with the branch handle."
  (room-ensure-schema)
  (bordeaux-threads:with-lock-held (*room-lock*)
    (let ((branch (autopoiesis.substrate:branch-fork :name agent-name)))
      (setf (gethash agent-name *room-branches*) branch)
      `((:agent . ,agent-name)
        (:branch . ,agent-name)
        (:fork--tx . ,(autopoiesis.substrate:datom-branch-fork-tx branch))
        (:joined . t)))))

(defun room-find-branch (agent-name)
  (or (gethash agent-name *room-branches*)
      (error "Agent ~a has not joined the room (call room_join first)" agent-name)))

(defun room-post (agent-name entity attribute value)
  "Stage ENTITY ATTRIBUTE = VALUE onto AGENT-NAME's branch (intern-free;
   reads base only, does not touch shared state until merge)."
  (room-ensure-schema)
  (bordeaux-threads:with-lock-held (*room-lock*)
    (let ((branch (room-find-branch agent-name)))
      (autopoiesis.substrate:branch-stage branch entity attribute value)
      `((:agent . ,agent-name)
        (:entity . ,entity)
        (:attribute . ,attribute)
        (:value . ,value)
        (:staged . t)))))

(defun room-read (entity attribute)
  "Read the SHARED BASE value for (ENTITY,ATTRIBUTE) -- what every agent sees
   after merges. (Branch-private staged writes are not visible here.)"
  `((:entity . ,entity)
    (:attribute . ,attribute)
    (:value . ,(autopoiesis.substrate:entity-attr entity attribute))))

(defun room-conflict-alist (c)
  "Serialize a merge-conflict struct to a JSON-ready alist."
  `((:entity . ,(autopoiesis.substrate:merge-conflict-entity c))
    (:attribute . ,(autopoiesis.substrate:merge-conflict-attribute c))
    (:forked . ,(autopoiesis.substrate:merge-conflict-forked c))
    (:base--now . ,(autopoiesis.substrate:merge-conflict-base-now c))
    (:wanted . ,(autopoiesis.substrate:merge-conflict-wanted c))))

(defun room-merge (agent-name)
  "Fold AGENT-NAME's branch into the shared base. Returns applied count plus
   any flagged conflicts (same-(E,A) :one divergences -- never silently lost)."
  (bordeaux-threads:with-lock-held (*room-lock*)
    (let ((branch (room-find-branch agent-name)))
      (multiple-value-bind (applied conflicts)
          (autopoiesis.substrate:branch-merge branch)
        ;; Branch is consumed by the merge; drop it so a stale re-merge can't
        ;; double-apply. Agent must room_join again to stage more work.
        (remhash agent-name *room-branches*)
        `((:agent . ,agent-name)
          (:applied . ,applied)
          (:conflict--count . ,(length conflicts))
          (:conflicts . ,(mapcar #'room-conflict-alist conflicts)))))))

(defun room-state ()
  "Observability: list joined agents and their staged (entity,attribute,value)."
  (bordeaux-threads:with-lock-held (*room-lock*)
    (let ((agents nil)
          (names nil))
      (maphash
       (lambda (name branch)
         (push name names)
         (push `((:agent . ,name)
                 (:fork--tx . ,(autopoiesis.substrate:datom-branch-fork-tx branch))
                 (:staged .
                  ,(mapcar
                    (lambda (w)
                      `((:entity . ,(autopoiesis.substrate:branch-write-entity w))
                        (:attribute . ,(autopoiesis.substrate:branch-write-attribute w))
                        (:value . ,(autopoiesis.substrate:branch-write-value w))))
                    ;; oldest-first for readability
                    (reverse (autopoiesis.substrate:datom-branch-writes branch)))))
               agents))
       *room-branches*)
      ;; :agent--count is a scalar (unambiguous over the JSON encoder);
      ;; :agent--names is a flat list of strings (encodes as a clean array).
      `((:agent--count . ,(length names))
        (:agent--names . ,names)
        (:agents . ,agents)))))

;;; ===================================================================
;;; MCP tool definitions for the room
;;; ===================================================================

(defun room-mcp-tool-definitions ()
  "Tool definitions (same alist shape as mcp-tool-definitions) for the room."
  (list
   `((:name . "room_join")
     (:description . "Join the shared room: fork a private speculative branch for this agent. Returns a branch handle. Call before room_post.")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent . ((:type . "string")
                                    (:description . "Agent name (the branch owner)")))))
                       (:required . ("agent")))))

   `((:name . "room_post")
     (:description . "Stage a fact (entity, attribute, value) onto this agent's branch. Does NOT touch shared state until room_merge. attribute 'room/decision'|'room/owner'|'room/status' are single-valued (:one, can diverge); 'room/note'|'room/file' accumulate (:many, union cleanly).")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent . ((:type . "string") (:description . "Agent name (must have joined)")))
                         (:entity . ((:type . "string") (:description . "Entity name, e.g. 'task-42'")))
                         (:attribute . ((:type . "string") (:description . "Attribute, e.g. 'room/decision'")))
                         (:value . ((:type . "string") (:description . "Value to stage")))))
                       (:required . ("agent" "entity" "attribute" "value")))))

   `((:name . "room_read")
     (:description . "Read the SHARED BASE value for an (entity, attribute) -- what everyone sees after merges.")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:entity . ((:type . "string") (:description . "Entity name")))
                         (:attribute . ((:type . "string") (:description . "Attribute name")))))
                       (:required . ("entity" "attribute")))))

   `((:name . "room_merge")
     (:description . "Fold this agent's branch into the shared base. Returns applied count and any flagged conflicts (same-(entity,attribute) :one divergences are reported, never silently lost).")
     (:input-schema . ((:type . "object")
                       (:properties .
                        ((:agent . ((:type . "string") (:description . "Agent name whose branch to merge")))))
                       (:required . ("agent")))))

   `((:name . "room_state")
     (:description . "List joined agents and their staged (entity, attribute, value) writes (observability).")
     (:input-schema . ((:type . "object")
                       (:properties)
                       (:additional-properties . nil))))))

;;; ===================================================================
;;; MCP dispatch for the room tools
;;; ===================================================================

(defun room-mcp-tool-p (tool-name)
  "True if TOOL-NAME is a room tool handled by room-mcp-execute-tool."
  (member tool-name '("room_join" "room_post" "room_read" "room_merge" "room_state")
          :test #'string=))

(defun room-mcp-execute-tool (tool-name arguments)
  "Execute a room MCP tool. ARGUMENTS is the cl-json-decoded alist."
  (cond
    ((string= tool-name "room_join")
     (room-join (cdr (assoc :agent arguments))))

    ((string= tool-name "room_post")
     (room-post (cdr (assoc :agent arguments))
                (cdr (assoc :entity arguments))
                (cdr (assoc :attribute arguments))
                (cdr (assoc :value arguments))))

    ((string= tool-name "room_read")
     (room-read (cdr (assoc :entity arguments))
                (cdr (assoc :attribute arguments))))

    ((string= tool-name "room_merge")
     (room-merge (cdr (assoc :agent arguments))))

    ((string= tool-name "room_state")
     (room-state))

    (t (error "Unknown room tool: ~a" tool-name))))
