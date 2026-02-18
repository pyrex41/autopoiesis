# Consolidated CL Architecture: Substrate-First, Conductor, LFE Removal

## Overview

Consolidate autopoiesis into a single CL process built on a **substrate kernel** — a small datom store with `transact!`, hooks, and indexes. Build the conductor, orchestration, conversation branching, and blob storage as modules on top of the substrate. Remove the LFE/BEAM layer.

**Path C (substrate-first)**: Instead of building LMDB storage as standalone code and conversation turns as a separate module, build the substrate primitives (~500 LOC) first. Everything else — snapshots, conversations, conductor events, blob storage — becomes datoms in the same store, queryable through the same interface, reactive through the same hooks. Linda tuple-space coordination emerges for free.

This plan resolves tensions between three prior plans:
- **Jarvis plan** (Feb 14): Phases 1-4 complete, Phase 5 half-done with queue-drain-over-bridge pattern
- **Phase 4 bridge plan** (Feb 15): Fully implemented at commit 783cd02
- **Remove-LFE plan** (Feb 16): Proposes CL-only consolidation

Plus incorporates findings from:
- Thinking-repo evaluation (LMDB, conversation branching)
- Substrate decomposition (`~/projects/thinking/substrate-decomposition.md`)
- Substrate extension points (`~/projects/thinking/substrate-extension-points.md`)
- Linda tuple-space mapping (`thoughts/shared/research/2026-02-16-linda-tuple-spaces-substrate-evaluation.md`)
- HPC/Lisp optimization ideas (`~/projects/thinking/hpc-lisp-optimization-ideas.md`)

## Why Substrate-First (Path C)

The original plan had 7 phases across 3 tracks building standalone modules. Path C reorders to build the substrate kernel first, then everything else as modules on top. This is low-hanging fruit because:

1. **The substrate is ~500 LOC** (datom struct, intern, encode, transact!, basic query, hooks). It's smaller than the standalone LMDB storage module it replaces.

2. **Everything becomes uniform.** Snapshots, conversation turns, conductor events, blob metadata — all stored as datoms. One write path, one query interface, one hook surface. No separate `lmdb-store.lisp`, `blob-store.lisp`, `turn.lisp`, `context.lisp` with different storage patterns.

3. **Linda coordination is free.** With `transact!` + retraction semantics + EAV indexes, the conductor's event queue becomes a tuple space. Workers can self-select tasks via `take!`. No extra code needed — it's just the substrate used a certain way.

4. **Hooks unlock everything.** `register-hook` firing after `transact!` commits gives you: standing queries, materialized views, event bus, cache invalidation, audit logging — all as module-level code on top of one primitive.

5. **The extension points document is already the API spec.** `define-index`, `register-hook`, `define-tool`, `define-entity-type`, `define-condition` — these are designed and documented. The substrate is a small kernel with a rich hook surface.

6. **Conversation branching maps directly to datoms.** Turn entity with `:turn/parent`, `:turn/role`, `:turn/content-hash` attributes. Context entity with `:context/head` pointer. Fork = new context entity pointing to existing turn. O(1), no data copying. No separate "conversation module" — just datom patterns.

## Current State Analysis

### What's Done (Phases 1-4 of Jarvis Plan)

| Phase | Commit | Status | Key Files |
|-------|--------|--------|-----------|
| 1: Agentic loop | 5dfdf86 | Complete | `claude-bridge.lisp:174-226`, `agentic-agent.lisp:13-198` |
| 2: Self-extension | eac0b80, d0d5459 | Complete | `builtin-tools.lisp:283-437` (5 tools) |
| 3: Provider generalization | 3a8b5ca | Complete | `provider-inference.lisp`, `openai-bridge.lisp` |
| 4: Rich CL-LFE bridge | 783cd02 | Complete | `scripts/agent-worker.lisp` (16 msg types), `agent-worker.lfe`, `conductor.lfe` |

### What's Half-Done (Phase 5 Meta-Agent)

Orchestration tools exist in `builtin-tools.lisp:440-641` but use a **queue-drain-over-bridge** pattern:
- `spawn-agent` (line 459): Queues `:spawn-agent` request for LFE
- `save-session` (line 595): Queues `:save-session` request for LFE
- `resume-session` (line 607): Queues `:resume-session` request for LFE
- `query-agent` (line 488): Directly reads CL `*sub-agents*` registry
- `await-agent` (line 506): Polls CL `*sub-agents*` registry
- `fork-branch` (line 537): Directly calls CL snapshot functions
- `compare-branches` (line 551): Directly calls CL diff functions

The queue-drain pattern (lines 443-450) sends requests over the LFE bridge via `drain-orchestration-requests` called from `agent-worker.lisp:223-224`. **Removing LFE breaks the three queued tools.**

### What Exists in LFE (~1,605 LOC across 11 modules)

| Module | LOC | Disposition |
|--------|-----|------------|
| conductor.lfe | 564 | Port to CL |
| claude-worker.lfe | 257 | Port to CL |
| agent-worker.lfe | 484 | Drop (CL calls itself) |
| autopoiesis-sup.lfe | 49 | Drop |
| agent-sup.lfe | 42 | Drop |
| claude-sup.lfe | 37 | Drop |
| health-handler.lfe | 42 | Port to CL (add to Hunchentoot) |
| webhook-handler.lfe | 39 | Port to CL (add to Hunchentoot) |
| webhook-server.lfe | 60 | Drop (Hunchentoot running) |
| connector-sup.lfe | 21 | Drop |
| autopoiesis-app.lfe | 10 | Drop |

### Test Baseline

- **CL**: ~1,245 tests across 16 files (main system), 442 holodeck tests, 31 API tests
- **LFE**: 95 tests across 5 modules (will be deleted)
- **Bridge-specific**: `bridge-protocol-tests.lisp` (12 tests), `meta-agent-tests.lisp` (16 tests) — both need modification

## Desired End State

After this plan:

1. **Single CL process** runs everything — substrate, conductor, agents, tools, HTTP, REPL
2. **Substrate kernel** — datom store with LMDB, `transact!`, hooks, indexes, `take!`
3. **No LFE directory** — `lfe/` deleted, `scripts/agent-worker.lisp` deleted
4. **CL conductor** built on substrate — events as datoms, workers claim tasks via `take!`
5. **Orchestration tools work directly** — `spawn-agent` creates a thread, `save-session` writes datoms, no bridge IPC
6. **Content-addressed blob store** as substrate database — LLM responses, tool outputs stored as content-addressed blobs
7. **Conversation branching** — Turn/Context as datom entities on the substrate
8. **All existing CL tests pass** plus new substrate, orchestration, and conversation tests
9. **`(start-system)`** boots substrate + conductor + monitoring in one call

### Verification

```bash
# All CL tests
./scripts/test.sh

# Verify LFE removed
test ! -d lfe/ && echo "LFE removed"

# System startup
sbcl --eval '(ql:quickload :autopoiesis)' \
     --eval '(autopoiesis.orchestration:start-system)' \
     --eval '(autopoiesis.orchestration:conductor-status)'

# Substrate health
sbcl --eval '(ql:quickload :autopoiesis)' \
     --eval '(autopoiesis.substrate:open-store "/tmp/ap-test")' \
     --eval '(autopoiesis.substrate:transact! (list (autopoiesis.substrate:make-datom :test :attr/hello "world")))' \
     --eval '(autopoiesis.substrate:entity-attr :test :attr/hello)'
```

## What We're NOT Doing

- **OTP supervision trees in CL** — Simple thread + handler-case + retry. Not reimplementing Erlang.
- **Bitemporal valid-time** — Transaction time is sufficient. Valid-time can be added later via `define-index` with a `:scope`.
- **SoA columnar storage** — In-memory typed arrays for hot-path iteration. Module-level optimization via `register-hook` if needed. See `ecs-relevance.md` for design.
- **Full Rete incremental maintenance** — Start with declaration-filtered dispatch (defsystem). Full differential dataflow later.
- **Full Datalog query compiler** — Basic queries (point lookup, prefix scan, pattern match via `find-entities`). Datalog later.
- **Multi-user / multi-tenant** — Single-user system
- **SSE / web dashboard** — Cortex has this; AP uses SWANK
- **Streaming from Claude API (SSE)** — Separate concern

**Previously deferred, now IN the plan:**
- ~~MOP schema specialization~~ → Phase 1.5 `define-entity-type` with `slot-unbound`
- ~~Standing query / defsystem~~ → Phase 1.5 `defsystem` with declaration-filtered dispatch
- ~~define-entity-type~~ → Phase 1.5, pre-defines 7 entity types
- ~~Scoped indexes~~ → Phase 1, `:scope` parameter on `define-index`
- ~~Substrate conditions~~ → Phase 1, `substrate-validation-error` + `unknown-entity-type`

## Implementation Approach

**Substrate-first, bottom-up.** Build the substrate kernel, verify it works with tests, then build everything else as modules on top. Delete LFE last.

The plan has 9 phases across 3 tracks:

```
Track A: Substrate Foundation         Track B: Conductor + Removal      Track C: Conversations
──────────────────────────           ──────────────────────────        ────────────────────

Phase 1: Substrate Kernel             Phase 3: CL Conductor             Phase 6: Turn/Context DAG
    ↓                                     ↓                                ↓
Phase 1.5: Programming Model          Phase 4: Claude CLI Worker         Phase 7: Wire to Agentic Loop
    ↓                                     ↓
Phase 2: LMDB + Blob Store           Phase 5: Refactor Orchestration
                                          + Delete LFE
                                              ↓
                                          Phase 8: Linda Coordination
```

**Track A (Phases 1, 1.5, 2)** is the new foundation. Everything depends on Phase 1. Phase 1.5 (programming model) provides the typed entity access and reactive dispatch used by all later phases.

**Track B (Phases 3-5, 8)** is the critical path for LFE removal. Phase 3 can start after Phase 1.5 (uses `define-entity-type :event` and `:worker`). Phase 8 is optional polish.

**Track C (Phases 6-7)** can proceed in parallel with Track B after Phase 2. Phase 6 uses `define-entity-type :turn` and `:context` from Phase 1.5.

**Minimum viable product**: Phases 1-5 (substrate + programming model + conductor + LFE removed). The system is fully consolidated.

**Full product**: All 9 phases (substrate-backed everything with Linda coordination).

---

## Phase 1: Substrate Kernel — Datom + Transact + Hooks + Query + Conditions

### Overview

Build the core substrate: datom struct, monotonic-counter interning, key encoding, `transact!` (with hooks firing OUTSIDE lock), `define-index` (with `:scope` and `:strategy`), `find-entities` query, `take!` (with inverted value index), and substrate conditions. This is the foundation everything else builds on. ~610 LOC.

Design sources: `~/projects/thinking/substrate-decomposition.md` (Phase 1-2), `~/projects/thinking/substrate-extension-points.md`, `~/projects/thinking/performance-analysis.md` (scoped indexes, EA-CURRENT strategy).

### Changes Required

#### 1. New package definition
**File**: `src/substrate/packages.lisp` (new)

```lisp
(defpackage #:autopoiesis.substrate
  (:use #:cl #:alexandria)
  (:export
   ;; Store lifecycle
   #:*store*
   #:open-store
   #:close-store
   #:with-store
   ;; Datom
   #:datom
   #:make-datom
   #:d-entity
   #:d-attribute
   #:d-value
   #:d-tx
   #:d-added
   ;; Interning (monotonic counter)
   #:intern-id
   #:resolve-id
   ;; Transactions
   #:transact!
   #:next-tx-id
   ;; Query
   #:entity-attr
   #:entity-attrs
   #:entity-state
   #:find-entities
   #:find-entities-by-type
   #:scan-index
   #:query-first
   ;; Hooks
   #:register-hook
   #:unregister-hook
   ;; Indexes (with :scope and :strategy)
   #:define-index
   ;; Linda operations
   #:take!
   ;; Programming model (Phase 1.5)
   #:define-entity-type
   #:make-typed-entity
   #:*entity-type-registry*
   #:defsystem
   #:*system-registry*
   ;; Conditions
   #:substrate-condition
   #:substrate-error
   #:substrate-validation-error
   #:unknown-entity-type
   ;; Blob store (Phase 2)
   #:store-blob
   #:load-blob
   #:blob-exists-p))
```

#### 2. Datom struct
**File**: `src/substrate/datom.lisp` (new)

```lisp
(defstruct (datom (:conc-name d-)
                  (:constructor %make-datom))
  (entity   0   :type (unsigned-byte 64))
  (attribute 0  :type (unsigned-byte 32))
  (value    nil)
  (tx       0   :type (unsigned-byte 64))
  (added    t   :type boolean))

(defun make-datom (entity attribute value &key (added t))
  "Create a datom. ENTITY and ATTRIBUTE are auto-interned if not integers.
   Entity IDs use u64 counter, attribute IDs use u32 counter."
  (let ((eid (if (integerp entity) entity (intern-id entity :width :entity)))
        (aid (if (integerp attribute) attribute (intern-id attribute :width :attribute))))
    (%make-datom :entity eid :attribute aid :value value :added added)))
```

**Design decision**: Use u64 for entity IDs, u32 for attribute IDs (from `substrate-decomposition.md:400-402`). Attributes are a bounded vocabulary; entities grow indefinitely.

#### 3. Term interning (monotonic counter)
**File**: `src/substrate/intern.lisp` (new)

```lisp
;; Monotonic-counter interning from arbitrary objects to compact integers.
;; Pattern from Bubble CL's intern-term: SHA-256 is the LOOKUP KEY,
;; (incf *next-id*) produces the actual interned ID.
;; This avoids birthday-paradox collisions that SHA-256 truncation would cause
;; (~2^32 entities for u64, ~65K for u32 attributes).

(defvar *next-entity-id* 1
  "Monotonic counter for entity IDs (u64 space)")

(defvar *next-attribute-id* 1
  "Monotonic counter for attribute IDs (u32 space)")

(defvar *intern-table* (make-hash-table :test 'equal)
  "Forward map: object → interned integer ID")

(defvar *resolve-table* (make-hash-table :test 'eql)
  "Reverse map: integer ID → original object")

(defun intern-id (term &key (width :entity))
  "Intern TERM to a compact integer. Idempotent.
   WIDTH is :entity (u64, default) or :attribute (u32).
   Uses monotonic counter, NOT hash truncation."
  (or (gethash term *intern-table*)
      (let ((id (ecase width
                  (:entity (prog1 *next-entity-id*
                             (incf *next-entity-id*)))
                  (:attribute (prog1 *next-attribute-id*
                                (incf *next-attribute-id*))))))
        (setf (gethash term *intern-table*) id)
        (setf (gethash id *resolve-table*) term)
        id)))

(defun resolve-id (id)
  "Resolve interned ID back to original term."
  (gethash id *resolve-table*))
```

**Note**: Intern tables and counters are persisted to LMDB in Phase 2. Phase 1 uses in-memory tables. The monotonic counter approach is collision-free (unlike SHA-256 truncation) and produces dense, compact IDs that work well as LMDB keys.

#### 4. Key encoding
**File**: `src/substrate/encoding.lisp` (new)

```lisp
;; Big-endian key encoding for LMDB B+ tree ordering
;; Pattern from Bubble CL's encode-key

(defun encode-eavt-key (datom)
  "Encode datom as EAVT key for entity-centric lookups."
  (let ((buf (make-array 20 :element-type '(unsigned-byte 8))))
    (encode-u64-be buf 0 (d-entity datom))
    (encode-u32-be buf 8 (d-attribute datom))
    (encode-u64-be buf 12 (d-tx datom))
    buf))

(defun encode-aevt-key (datom)
  "Encode datom as AEVT key for attribute-centric lookups."
  (let ((buf (make-array 20 :element-type '(unsigned-byte 8))))
    (encode-u32-be buf 0 (d-attribute datom))
    (encode-u64-be buf 4 (d-entity datom))
    (encode-u64-be buf 12 (d-tx datom))
    buf))

(defun encode-u64-be (buf offset value)
  (loop for i from 7 downto 0
        do (setf (aref buf (+ offset (- 7 i)))
                 (ldb (byte 8 (* i 8)) value))))

(defun encode-u32-be (buf offset value)
  (loop for i from 3 downto 0
        do (setf (aref buf (+ offset (- 3 i)))
                 (ldb (byte 8 (* i 8)) value))))
```

#### 5. Store and transact!
**File**: `src/substrate/store.lisp` (new)

```lisp
(defclass substrate-store ()
  ((indexes :initform nil :accessor store-indexes
            :documentation "List of (name . index-spec) — each index has :key-fn and :db")
   (hooks :initform nil :accessor store-hooks
          :documentation "List of (name . hook-fn) called after each transaction")
   (tx-counter :initform 0 :accessor store-tx-counter)
   (lock :initform (bt:make-lock "substrate") :accessor store-lock)
   ;; LMDB fields (nil until Phase 2 wires them)
   (lmdb-env :initform nil :accessor store-lmdb-env)
   (data-db :initform nil :accessor store-data-db
            :documentation "Datom value storage: encoded-key → serialized value"))
  (:documentation "The substrate store — datoms, indexes, hooks."))

(defvar *store* nil "The active substrate store.")

;; --- Index registration ---

(defun define-index (store name key-fn &key description scope strategy)
  "Register a named index. TRANSACT! auto-writes to all registered indexes.
   SCOPE: optional predicate (lambda (datom) ...) — when non-nil, only datoms
   matching the scope are written to this index. Essential for cross-domain stores
   (e.g., Bubble triple indexes only fire for knowledge entities). A scope check
   is ~5-10ns vs ~1-5μs for a B+ tree insertion, so the savings are substantial.
   STRATEGY: :append (default, add new entry) or :replace (overwrite existing key).
   :replace is used for EA-CURRENT which maintains only the latest value."
  (push (cons name (list :key-fn key-fn
                         :description description
                         :scope scope
                         :strategy (or strategy :append)))
        (store-indexes store)))

;; --- Default indexes ---

(defun register-default-indexes (store)
  "Register EAVT and AEVT as the default indexes."
  (define-index store :eavt #'encode-eavt-key
    :description "Entity-Attribute-Tx"
    :strategy :append)
  (define-index store :aevt #'encode-aevt-key
    :description "Attribute-Entity-Tx"
    :strategy :append)
  ;; EA-CURRENT: latest value per (entity, attribute) — write-through cache
  ;; This is NOT a separate data structure — it's an index with :replace strategy
  ;; that the entity cache sits in front of as a write-through layer.
  (define-index store :ea-current
    (lambda (datom)
      (let ((buf (make-array 12 :element-type '(unsigned-byte 8))))
        (encode-u64-be buf 0 (d-entity datom))
        (encode-u32-be buf 8 (d-attribute datom))
        buf))
    :description "Entity-Attribute current value"
    :strategy :replace))

;; --- Hooks ---

(defun register-hook (store name hook-fn)
  "Register a hook that fires after every TRANSACT! with (datoms tx-id).
   Hooks fire AFTER the transaction commits."
  (push (cons name hook-fn) (store-hooks store))
  name)

(defun unregister-hook (store name)
  "Remove a named hook."
  (setf (store-hooks store) (remove name (store-hooks store) :key #'car))
  name)

;; --- The one function that matters ---

(defun transact! (datoms &key (store *store*))
  "Atomically write DATOMS to all registered indexes. Fire hooks after commit.
   This is the substrate's core contract:
   1. Assign tx-id (under lock)
   2. Write to ALL registered indexes (under lock, respecting :scope)
   3. Release lock
   4. Fire ALL registered hooks with (datoms tx-id) (OUTSIDE lock)
   Returns tx-id.

   CRITICAL: Hooks fire OUTSIDE the lock. This prevents deadlock when hooks
   call transact! (common for defsystem callbacks, materialized views, etc.).
   The trade-off: hooks see committed state but could interleave with the
   next transaction. This matches Bubble's design and the substrate extension
   points contract."
  (let ((tx-id nil)
        (committed-datoms nil))
    ;; Phase 1: Write under lock
    (bt:with-lock-held ((store-lock store))
      (setf tx-id (incf (store-tx-counter store)))
      ;; Stamp all datoms with tx-id
      (dolist (datom datoms)
        (setf (d-tx datom) tx-id))
      ;; Write to all indexes (respecting scope)
      (dolist (index-entry (store-indexes store))
        (let ((key-fn (getf (cdr index-entry) :key-fn))
              (scope (getf (cdr index-entry) :scope)))
          (dolist (datom datoms)
            (when (or (null scope) (funcall scope datom))
              (write-to-index store (car index-entry) key-fn datom)))))
      ;; Update entity cache (write-through over EA-CURRENT) + value index
      (dolist (datom datoms)
        (update-entity-cache store datom)
        (update-value-index datom))
      ;; Snapshot datoms for hooks (they're committed now)
      (setf committed-datoms (copy-list datoms)))
    ;; Phase 2: Fire hooks OUTSIDE the lock
    (dolist (hook-entry (store-hooks store))
      (handler-case
          (funcall (cdr hook-entry) committed-datoms tx-id)
        (error (e)
          (warn "Hook ~A error: ~A" (car hook-entry) e))))
    tx-id))
```

**Note on Phase 1 storage**: Phase 1 uses in-memory hash tables (like the current content-store). Phase 2 wires LMDB underneath. The API doesn't change.

#### 6. Entity state reconstruction
**File**: `src/substrate/entity.lisp` (new)

```lisp
;; Entity cache: (entity-id, attribute-id) → current-value
;; Updated on every transact!

(defvar *entity-cache* (make-hash-table :test 'equal)
  "In-memory cache of current entity state. Key: (entity-id . attribute-id) → value")

(defun update-entity-cache (store datom)
  "Update the entity cache with a datom."
  (let ((key (cons (d-entity datom) (d-attribute datom))))
    (if (d-added datom)
        (setf (gethash key *entity-cache*) (d-value datom))
        (remhash key *entity-cache*))))

(defun entity-attr (entity attribute &key (store *store*))
  "Get current value of ENTITY's ATTRIBUTE. O(1) from cache."
  (let ((eid (if (integerp entity) entity (intern-id entity)))
        (aid (if (integerp attribute) attribute (intern-id attribute))))
    (gethash (cons eid aid) *entity-cache*)))

(defun entity-state (entity &key (store *store*))
  "Reconstruct full current state of ENTITY as a plist."
  (let ((eid (if (integerp entity) entity (intern-id entity)))
        (attrs nil))
    (maphash (lambda (key value)
               (when (= (car key) eid)
                 (push (resolve-id (cdr key)) attrs)
                 (push value attrs)))
             *entity-cache*)
    (nreverse attrs)))

(defun entity-history (entity attribute &key (store *store*) (limit 100))
  "Get historical values of ENTITY's ATTRIBUTE, most recent first.
   Scans EAVT index. Returns list of (tx-id . value) pairs."
  ;; Phase 1: scan in-memory index
  ;; Phase 2: scan LMDB EAVT cursor
  ...)
```

#### 7. Linda take! primitive
**File**: `src/substrate/linda.lisp` (new)

```lisp
;; Inverted index for O(1) take! lookups instead of O(n) entity-cache scan.
;; Maps (attribute-id . value) → set of entity-ids.
;; Updated alongside entity-cache on every transact!.

(defvar *value-index* (make-hash-table :test 'equal)
  "Inverted index: (attribute-id . value) → hash-set of entity-ids")

(defun update-value-index (datom)
  "Update the inverted value index for take! lookups."
  (let ((key (cons (d-attribute datom) (d-value datom))))
    (if (d-added datom)
        ;; Assert: add entity to the value index
        (let ((set (or (gethash key *value-index*)
                       (setf (gethash key *value-index*)
                             (make-hash-table :test 'eql)))))
          (setf (gethash (d-entity datom) set) t))
        ;; Retract: remove entity from the value index
        (let ((set (gethash key *value-index*)))
          (when set
            (remhash (d-entity datom) set)
            (when (zerop (hash-table-count set))
              (remhash key *value-index*)))))))

(defun take! (attribute match-value &key (store *store*) (new-value nil new-value-p))
  "Linda in() — atomically find an entity where ATTRIBUTE equals MATCH-VALUE,
   and either retract it or update it to NEW-VALUE.
   Returns the entity ID, or nil if no match.

   Uses inverted value index for O(1) lookup instead of scanning
   the entire entity cache. This is the coordination primitive:
   - Workers call (take! :task/status :pending :new-value :in-progress)
   - Only one worker succeeds per entity (lock serializes)
   - Others see the updated value and move on."
  (bt:with-lock-held ((store-lock store))
    (let* ((aid (if (integerp attribute) attribute
                    (intern-id attribute :width :attribute)))
           (key (cons aid match-value))
           (set (gethash key *value-index*))
           (match-eid nil))
      ;; O(1) lookup via inverted index
      (when set
        (maphash (lambda (eid _)
                   (declare (ignore _))
                   (unless match-eid (setf match-eid eid)))
                 set))
      (when match-eid
        ;; Atomically update: retract old, assert new
        (let ((datoms (if new-value-p
                          (list (%make-datom :entity match-eid :attribute aid
                                            :value match-value :added nil)
                                (%make-datom :entity match-eid :attribute aid
                                            :value new-value :added t))
                          (list (%make-datom :entity match-eid :attribute aid
                                            :value match-value :added nil)))))
          ;; Internal transact (already holding lock)
          (let ((tx-id (incf (store-tx-counter store))))
            (dolist (datom datoms)
              (setf (d-tx datom) tx-id)
              (update-entity-cache store datom)
              (update-value-index datom)))
          match-eid)))))
```

#### 8. Query functions
**File**: `src/substrate/query.lisp` (new)

```lisp
(defun find-entities (attribute value &key (store *store*))
  "Find all entity IDs where ATTRIBUTE equals VALUE.
   Uses the inverted value index for O(1) lookup.
   Building block for defsystem dispatch and REPL exploration."
  (let* ((aid (if (integerp attribute) attribute
                  (intern-id attribute :width :attribute)))
         (key (cons aid value))
         (set (gethash key *value-index*))
         (results nil))
    (when set
      (maphash (lambda (eid _)
                 (declare (ignore _))
                 (push eid results))
               set))
    results))

(defun find-entities-by-type (type-keyword &key (store *store*))
  "Find all entity IDs of a given type.
   Sugar for (find-entities :entity/type type-keyword)."
  (find-entities :entity/type type-keyword :store store))
```

#### 9. Substrate conditions
**File**: `src/substrate/conditions.lisp` (new)

Extends AP's existing condition hierarchy at `src/core/conditions.lisp:12-62` with substrate-specific conditions and restarts. Pattern follows the three-level structure: base condition → error/warning branches → leaf conditions with domain slots.

```lisp
;; Base substrate condition (inherits AP's base)
(define-condition substrate-condition (autopoiesis-condition)
  ((entity-id :initarg :entity-id :reader condition-entity-id :initform nil)
   (attribute :initarg :attribute :reader condition-attribute :initform nil))
  (:documentation "Base condition for substrate operations"))

(define-condition substrate-error (substrate-condition autopoiesis-error)
  ()
  (:report (lambda (c s)
             (format s "Substrate error~@[ (entity: ~A)~]: ~A"
                     (condition-entity-id c) (condition-message c)))))

;; Validation error with restarts for schema mismatches
(define-condition substrate-validation-error (substrate-error)
  ((expected-type :initarg :expected-type :reader validation-expected-type)
   (actual-value :initarg :actual-value :reader validation-actual-value))
  (:report (lambda (c s)
             (format s "Validation error for ~A: expected ~A, got ~A"
                     (condition-attribute c)
                     (validation-expected-type c)
                     (type-of (validation-actual-value c))))))

;; Usage: (restart-case (signal 'substrate-validation-error ...)
;;          (coerce () ...) (store-raw () ...) (skip () ...))

;; Unknown entity type with classification restarts
(define-condition unknown-entity-type (substrate-condition)
  ((attributes :initarg :attributes :reader unknown-type-attributes))
  (:report (lambda (c s)
             (format s "Unknown entity type for entity ~A with attributes: ~A"
                     (condition-entity-id c)
                     (unknown-type-attributes c)))))

;; Usage: (restart-case (signal 'unknown-entity-type ...)
;;          (classify (type) ...) (store-generic () ...) (skip () ...))
```

**Design source**: Pattern from `src/core/conditions.lisp:12-62` (three-level hierarchy) and `src/core/recovery.lisp:159-199` (six standard restarts). The substrate conditions enable the self-adapting system workflow from `substrate-decomposition.md`: encounter unknown entity → signal condition → handler asks Claude → sandbox validates → resume with new adapter.

#### 10. Open/close store
**File**: `src/substrate/store.lisp` (addition)

```lisp
(defun open-store (&key path)
  "Open a substrate store. PATH is for LMDB (Phase 2). Without PATH, uses in-memory storage."
  (let ((store (make-instance 'substrate-store)))
    (register-default-indexes store)
    (setf *store* store)
    store))

(defun close-store (&key (store *store*))
  "Close the substrate store."
  (when (store-lmdb-env store)
    ;; Phase 2: close LMDB
    )
  (setf *store* nil))

(defmacro with-store ((&key path) &body body)
  `(let ((*store* (open-store :path ,path)))
     (unwind-protect (progn ,@body)
       (close-store :store *store*))))
```

#### 11. ASDF integration
**File**: `autopoiesis.asd`

Add substrate module as the first dependency (everything else depends on it):

```lisp
(:module "substrate"
 :serial t
 :components
 ((:file "packages")
  (:file "conditions")
  (:file "intern")
  (:file "encoding")
  (:file "datom")
  (:file "entity")
  (:file "query")
  (:file "store")
  (:file "linda")))
```

### Success Criteria

#### Automated Verification:
- [ ] `./scripts/test.sh` — all existing CL tests pass (no regressions)
- [ ] New test: open-store / close-store lifecycle
- [ ] New test: make-datom interns entity and attribute (monotonic IDs)
- [ ] New test: transact! assigns tx-id and updates entity cache
- [ ] New test: entity-attr returns current value after transact!
- [ ] New test: retraction (added=nil) removes value from cache
- [ ] New test: entity-state returns full plist for entity
- [ ] New test: register-hook fires after transact! with correct datoms and tx-id
- [ ] New test: hooks fire OUTSIDE lock (hook calling transact! does not deadlock)
- [ ] New test: define-index with :scope — scoped index only receives matching datoms
- [ ] New test: define-index with :strategy :replace — overwrites existing key
- [ ] New test: take! atomically claims and updates matching entity (O(1) via value index)
- [ ] New test: take! returns nil when no match
- [ ] New test: intern-id is idempotent (same input → same ID)
- [ ] New test: intern-id uses monotonic counter (sequential IDs, no collisions)
- [ ] New test: resolve-id returns original term
- [ ] New test: find-entities returns matching entity IDs
- [ ] New test: find-entities-by-type filters correctly
- [ ] New test: substrate-validation-error signals with expected slots
- [ ] New test: unknown-entity-type signals with attribute list

#### Manual Verification:
- [ ] `(open-store)` creates in-memory store
- [ ] `(transact! (list (make-datom :my-agent :agent/name "test")))` writes datom
- [ ] `(entity-attr :my-agent :agent/name)` → "test"
- [ ] `(entity-state :my-agent)` → `(:agent/name "test")`
- [ ] `(find-entities :agent/name "test")` → list with agent entity ID

**Implementation Note**: Phase 1 is entirely in-memory. No LMDB dependency yet. This lets us test the datom model without external dependencies.

---

## Phase 1.5: Programming Model — define-entity-type + defsystem

### Overview

Build the programming model that domain code uses to interact with the substrate. Without this, all code is raw `(entity-attr eid :turn/role)` calls. With it, you get CLOS slot access, schema validation, and declaration-filtered reactive dispatch. ~300 LOC.

This phase exists because the programming model is NOT an optimization for later — it's what you write domain code against. Phase 3's conductor, Phase 6's conversations, and Phase 7's agentic loop all benefit from typed entity access and reactive dispatch.

**Design sources**: `~/projects/thinking/ecs-relevance.md` (defsystem), `~/projects/thinking/substrate-extension-points.md` (define-entity-type, MOP slot-unbound), `src/agent/capability.lisp:138-171` (macro pattern), `src/holodeck/systems.lisp:47-88` (defsystem usage).

### Changes Required

#### 1. `define-entity-type` macro
**File**: `src/substrate/entity-type.lisp` (new)

Generates: schema metadata stored as datoms, validation function, CLOS class with MOP `slot-unbound` loading from entity cache.

```lisp
(defvar *entity-type-registry* (make-hash-table :test 'eq)
  "Registry of declared entity types: keyword → entity-type-descriptor")

(defclass entity-type-descriptor ()
  ((name :initarg :name :reader entity-type-name)
   (attributes :initarg :attributes :reader entity-type-attributes
               :documentation "List of (attr-keyword type &key indexed)")
   (validator :initarg :validator :reader entity-type-validator)
   (class-name :initarg :class-name :reader entity-type-class-name))
  (:documentation "Metadata about a declared entity type"))

(defmacro define-entity-type (name &body attribute-specs)
  "Define a substrate entity type. Generates:
   1. Schema metadata stored as datoms in the substrate
   2. A validation function that signals substrate-validation-error
   3. A CLOS class with MOP slot-unbound loading from entity cache

   Example:
     (define-entity-type :turn
       (:turn/role       :type keyword  :required t)
       (:turn/content-hash :type string :required t)
       (:turn/parent     :type (or null integer))
       (:turn/timestamp  :type integer  :required t)
       (:turn/model      :type (or null keyword))
       (:turn/tokens     :type (or null integer)))

   After this, you can:
     (let ((turn (make-typed-entity :turn eid)))
       (turn-role turn)        ; slot-unbound → loads from entity-attr
       (turn-content-hash turn))  ; cached after first access"
  (let* ((class-sym (intern (format nil "~A-ENTITY" (string-upcase name))))
         (slot-defs (loop for (attr . opts) in attribute-specs
                          for slot-name = (intern (string-upcase
                                                   (subseq (symbol-name attr)
                                                           (1+ (position #\/ (symbol-name attr))))))
                          collect `(,slot-name
                                   :initarg ,(intern (symbol-name slot-name) :keyword)
                                   :accessor ,(intern (format nil "~A-~A"
                                                              (string-upcase name)
                                                              slot-name))))))
    `(progn
       ;; Generate CLOS class
       (defclass ,class-sym ()
         ((entity-id :initarg :entity-id :reader entity-id)
          ,@slot-defs)
         (:documentation ,(format nil "Typed entity class for ~A" name)))

       ;; MOP slot-unbound: cache miss → load from substrate
       (defmethod slot-unbound (class (entity ,class-sym) slot-name)
         (let* ((attr-keyword (slot-name-to-attribute ',name slot-name))
                (value (entity-attr (entity-id entity) attr-keyword)))
           (when value
             (setf (slot-value entity slot-name) value))
           value))

       ;; Register in type registry
       (setf (gethash ,name *entity-type-registry*)
             (make-instance 'entity-type-descriptor
                            :name ,name
                            :attributes ',attribute-specs
                            :class-name ',class-sym))

       ;; Store schema as datoms (when store is open)
       (when *store*
         (let ((type-eid (intern-id ,name :width :entity)))
           (transact!
            (list (make-datom type-eid :entity/type :entity-type)
                  (make-datom type-eid :entity-type/name ,name)
                  (make-datom type-eid :entity-type/attributes
                              ',(mapcar #'car attribute-specs))))))

       ',name)))

(defun make-typed-entity (type-keyword entity-id)
  "Create a typed entity wrapper. Slot access lazily loads from substrate."
  (let ((descriptor (gethash type-keyword *entity-type-registry*)))
    (unless descriptor
      (error 'unknown-entity-type
             :entity-id entity-id
             :attributes (list type-keyword)
             :message (format nil "Unknown entity type: ~A" type-keyword)))
    (make-instance (entity-type-class-name descriptor)
                   :entity-id entity-id)))
```

**Pattern source**: `defcapability` at `src/agent/capability.lisp:138-171` — same parse-options-then-register structure. The MOP `slot-unbound` pattern is from `substrate-extension-points.md` lines 43-55.

#### 2. `defsystem` macro — declaration-filtered reactive dispatch
**File**: `src/substrate/system.lisp` (new)

```lisp
(defvar *system-registry* (make-hash-table :test 'eq)
  "Registry of substrate systems: name → system-descriptor")

(defvar *dispatch-table* (make-hash-table :test 'equal)
  "Dispatch index: (attribute-id) → list of system-descriptors.
   Built from system :watches declarations.")

(defclass system-descriptor ()
  ((name :initarg :name :reader system-name)
   (entity-type :initarg :entity-type :reader system-entity-type)
   (watches :initarg :watches :reader system-watches
            :documentation "List of attribute keywords this system cares about")
   (access :initarg :access :reader system-access
           :documentation ":read-only or :read-write")
   (handler :initarg :handler :reader system-handler
            :documentation "Function (entity datoms tx-id) → called on matching changes"))
  (:documentation "A reactive system that processes entity changes"))

(defmacro defsystem (name (&key entity-type watches (access :read-only)) &body body)
  "Define a declaration-filtered reactive system.
   Declares what entity type and attributes this system watches.
   The framework builds a dispatch table: attribute → list of systems.
   Only matching systems are invoked when datoms arrive.

   Example:
     (defsystem :restart-monitor
       (:entity-type :k8s/pod
        :watches (:k8s.pod/phase :k8s.pod/restarts)
        :access :read-only)
       (let ((phase (entity-attr (entity-id entity) :k8s.pod/phase))
             (restarts (entity-attr (entity-id entity) :k8s.pod/restarts)))
         (when (and (eq phase :running) (> restarts 5))
           (warn \"Pod ~A has high restarts: ~D\" (entity-id entity) restarts))))

   The system is automatically registered as a substrate hook with
   dispatch-table filtering. It only fires when watched attributes change."
  `(progn
     (let ((descriptor (make-instance 'system-descriptor
                                      :name ',name
                                      :entity-type ,entity-type
                                      :watches ',watches
                                      :access ,access
                                      :handler (lambda (entity datoms tx-id)
                                                 (declare (ignorable entity datoms tx-id))
                                                 ,@body))))
       ;; Register in system registry
       (setf (gethash ',name *system-registry*) descriptor)
       ;; Build dispatch table entries
       (dolist (attr ',watches)
         (let ((aid (intern-id attr :width :attribute)))
           (push descriptor (gethash aid *dispatch-table*))))
       ;; Register a hook that dispatches to this system
       ;; (Only done once — the hook checks the dispatch table)
       (ensure-system-dispatch-hook)
       ',name)))

(defvar *system-dispatch-hook-installed* nil)

(defun ensure-system-dispatch-hook ()
  "Install the system dispatch hook (once). Dispatches to systems
   via the dispatch table, not by scanning all systems."
  (unless *system-dispatch-hook-installed*
    (when *store*
      (register-hook *store* :system-dispatch
        (lambda (datoms tx-id)
          (let ((invoked (make-hash-table :test 'eq)))
            ;; Phase 1: narrow to affected systems via dispatch table
            (dolist (d datoms)
              (dolist (sys (gethash (d-attribute d) *dispatch-table*))
                (unless (gethash sys invoked)
                  ;; Check entity type matches
                  (let ((eid (d-entity d)))
                    (when (or (null (system-entity-type sys))
                              (eq (entity-attr eid :entity/type)
                                  (system-entity-type sys)))
                      (setf (gethash sys invoked) t))))))
            ;; Phase 2: invoke affected systems
            (maphash (lambda (sys _)
                       (declare (ignore _))
                       (handler-case
                           (dolist (d datoms)
                             (when (member (d-attribute d)
                                           (mapcar (lambda (w) (intern-id w :width :attribute))
                                                   (system-watches sys)))
                               (let ((entity (make-typed-entity
                                              (system-entity-type sys)
                                              (d-entity d))))
                                 (funcall (system-handler sys)
                                          entity datoms tx-id))))
                         (error (e)
                           (warn "System ~A error: ~A" (system-name sys) e))))
                     invoked)))))
    (setf *system-dispatch-hook-installed* t)))
```

**Design source**: `ecs-relevance.md` lines 77-92 for the declaration pattern. The dispatch table optimization (attribute → list of systems) comes from `ecs-relevance.md` lines 223-253: "The `:watches` declaration is equivalent to `defsystem`'s component list. It tells the hook dispatch exactly which (entity-type, attribute) combinations this query cares about."

#### 3. Pre-defined entity types
**File**: `src/substrate/builtin-types.lisp` (new)

```lisp
;; Pre-define the entity types used by later phases.
;; These are available as soon as the substrate loads.

(define-entity-type :event
  (:event/type       :type keyword  :required t)
  (:event/data       :type t)
  (:event/status     :type keyword  :required t)
  (:event/created-at :type integer  :required t)
  (:event/error      :type (or null string)))

(define-entity-type :worker
  (:worker/task-id    :type string  :required t)
  (:worker/status     :type keyword :required t)
  (:worker/thread     :type t)
  (:worker/started-at :type integer :required t))

(define-entity-type :agent
  (:agent/name       :type string   :required t)
  (:agent/task       :type string)
  (:agent/status     :type keyword  :required t)
  (:agent/started-at :type integer)
  (:agent/result     :type (or null string))
  (:agent/error      :type (or null string)))

(define-entity-type :session
  (:session/name       :type string  :required t)
  (:session/state-hash :type string)
  (:session/saved-at   :type integer))

(define-entity-type :snapshot
  (:snapshot/content-hash :type string  :required t)
  (:snapshot/timestamp    :type integer :required t)
  (:snapshot/agent-id     :type t)
  (:snapshot/parent       :type (or null integer)))

;; Turn and Context types are defined here but fully used in Phase 6
(define-entity-type :turn
  (:turn/role         :type keyword  :required t)
  (:turn/content-hash :type string   :required t)
  (:turn/parent       :type (or null integer))
  (:turn/context      :type integer)
  (:turn/timestamp    :type integer  :required t)
  (:turn/model        :type (or null keyword))
  (:turn/tokens       :type (or null integer))
  (:turn/tool-use     :type (or null string))
  (:turn/metadata     :type t))

(define-entity-type :context
  (:context/name       :type string   :required t)
  (:context/head       :type (or null integer))
  (:context/agent      :type (or null integer))
  (:context/forked-from :type (or null integer))
  (:context/created-at :type integer  :required t))
```

#### 4. ASDF integration for Phase 1.5
**File**: `autopoiesis.asd`

Add to substrate module after `linda`:

```lisp
  (:file "entity-type")
  (:file "system")
  (:file "builtin-types")
```

### Success Criteria

#### Automated Verification:
- [ ] `./scripts/test.sh` — all existing CL tests pass
- [ ] New test: define-entity-type creates CLOS class with correct slots
- [ ] New test: make-typed-entity creates wrapper, slot-unbound loads from substrate
- [ ] New test: slot access after transact! returns correct value (MOP cache)
- [ ] New test: slot-unbound returns nil for unset attributes
- [ ] New test: unknown-entity-type signaled for unregistered types
- [ ] New test: defsystem registers in dispatch table keyed by watched attributes
- [ ] New test: defsystem handler fires when watched attribute changes
- [ ] New test: defsystem handler does NOT fire for unwatched attributes
- [ ] New test: defsystem entity-type filter works (only matching entities)
- [ ] New test: multiple defsystems with different watches dispatch correctly
- [ ] New test: all 7 pre-defined entity types registered and accessible

#### Manual Verification:
- [ ] `(define-entity-type :test (:test/name :type string))` generates class
- [ ] `(make-typed-entity :test eid)` → CLOS object with lazy slot access
- [ ] `(defsystem :my-sys (:watches (:test/name)) (print entity))` registers hook

**Implementation Note**: This phase depends on Phase 1 (substrate kernel must be operational). The pre-defined entity types are declarations only — they don't create any entities. Actual entity creation happens in later phases when the conductor, conversations, etc. write datoms.

---

## Phase 2: LMDB Backend + Blob Store

### Overview

Wire LMDB underneath the substrate store. Add content-addressed blob storage as a substrate database. Replace filesystem snapshot persistence. This is the old plan's Phases 4+5 combined, but simpler because the substrate API already exists.

### Changes Required

#### 1. LMDB dependency
**File**: `autopoiesis.asd`

Add dependency: `:lmdb` (from Quicklisp — wraps liblmdb via CFFI).

#### 2. Wire LMDB into store
**File**: `src/substrate/lmdb-backend.lisp` (new)

```lisp
(defun open-lmdb-store (path &key (map-size (* 1024 1024 1024)))
  "Open substrate store backed by LMDB at PATH."
  (let ((store (make-instance 'substrate-store)))
    (ensure-directories-exist path)
    ;; Open LMDB environment with named databases
    (let ((env (lmdb:make-environment path :max-dbs 16 :map-size map-size)))
      (lmdb:open-environment env)
      (setf (store-lmdb-env store) env)
      ;; Open named databases for each index
      (register-default-indexes store)
      (dolist (index-entry (store-indexes store))
        (let* ((name (car index-entry))
               (db (lmdb:make-database env (string name))))
          (setf (getf (cdr index-entry) :db) db)))
      ;; Open special databases
      (setf (store-data-db store)
            (lmdb:make-database env "data"))  ; key → serialized value
      ;; Intern tables
      (let ((intern-db (lmdb:make-database env "intern"))
            (resolve-db (lmdb:make-database env "resolve")))
        ;; Load existing intern tables from LMDB
        (restore-intern-tables intern-db resolve-db))
      ;; Blob store
      (let ((blob-db (lmdb:make-database env "blobs")))
        (setf (store-blob-db store) blob-db)))
    (register-default-indexes store)
    (setf *store* store)
    store))
```

#### 3. Blob store as substrate database
**File**: `src/substrate/blob.lisp` (new)

Content-addressed blob storage within the substrate's LMDB environment:

```lisp
(defun store-blob (content &key (store *store*) (compress t))
  "Store content as a content-addressed blob. Returns hash string.
   CONTENT can be string or byte vector."
  (let* ((bytes (etypecase content
                  (string (babel:string-to-octets content :encoding :utf-8))
                  ((vector (unsigned-byte 8)) content)))
         (hash (ironclad:byte-array-to-hex-string
                (ironclad:digest-sequence :sha256 bytes)))
         (stored-bytes (if (and compress (> (length bytes) 256))
                           (maybe-compress bytes)
                           bytes)))
    ;; Write to blobs database
    (lmdb:put (store-blob-db store) hash stored-bytes)
    hash))

(defun load-blob (hash &key (store *store*) as-string)
  "Load blob by content hash."
  (let ((bytes (lmdb:get (store-blob-db store) hash)))
    (when bytes
      (let ((decompressed (maybe-decompress bytes)))
        (if as-string
            (babel:octets-to-string decompressed :encoding :utf-8)
            decompressed)))))

(defun blob-exists-p (hash &key (store *store*))
  "Check if blob exists without loading it."
  (not (null (lmdb:get (store-blob-db store) hash))))
```

#### 4. Override transact! for LMDB
**File**: `src/substrate/lmdb-backend.lisp` (addition)

```lisp
(defun write-to-index (store index-name key-fn datom)
  "Write a datom to a named index."
  (let* ((index-entry (assoc index-name (store-indexes store)))
         (db (getf (cdr index-entry) :db))
         (key (funcall key-fn datom))
         (value (serialize-datom-value datom)))
    (if db
        ;; LMDB path
        (if (eq index-name :ea-current)
            (lmdb:put db key value)  ; replace mode for EA-CURRENT
            (lmdb:put db key value))
        ;; In-memory fallback
        (setf (gethash key (store-memory-index store index-name)) value))))
```

#### 5. Migration from filesystem
**File**: `src/substrate/migration.lisp` (new)

```lisp
(defun migrate-filesystem-to-substrate (old-store-path &key (store *store*))
  "Migrate all snapshots from filesystem to substrate datoms + blobs.
   Each snapshot becomes:
   - A blob (the full S-expression content)
   - Datoms for metadata: :snapshot/hash, :snapshot/parent, :snapshot/agent-id, :snapshot/timestamp"
  ...)
```

#### 6. Wire snapshot layer
**File**: `src/snapshot/persistence.lisp` (modification)

Add `*storage-backend*` dispatch:

```lisp
(defvar *storage-backend* :filesystem
  "Storage backend: :filesystem (legacy) or :substrate")

(defun save-snapshot (store snapshot)
  (ecase *storage-backend*
    (:filesystem (save-snapshot-to-filesystem store snapshot))
    (:substrate
     (let* ((content (prin1-to-string (snapshot-to-sexpr snapshot)))
            (blob-hash (autopoiesis.substrate:store-blob content))
            (snap-id (snapshot-id snapshot)))
       (autopoiesis.substrate:transact!
        (list (autopoiesis.substrate:make-datom snap-id :snapshot/content-hash blob-hash)
              (autopoiesis.substrate:make-datom snap-id :snapshot/timestamp (get-universal-time))
              (autopoiesis.substrate:make-datom snap-id :snapshot/agent-id (snapshot-agent-id snapshot))
              (when (snapshot-parent-id snapshot)
                (autopoiesis.substrate:make-datom snap-id :snapshot/parent (snapshot-parent-id snapshot)))))))))
```

### Success Criteria

#### Automated Verification:
- [ ] `./scripts/test.sh` — all existing snapshot tests pass with filesystem backend
- [ ] New test: open-lmdb-store / close lifecycle
- [ ] New test: transact! persists to LMDB, survives close/reopen
- [ ] New test: store-blob / load-blob round-trip for string content
- [ ] New test: blob-exists-p returns t for stored, nil for missing
- [ ] New test: content-addressed deduplication (same content = same hash)
- [ ] New test: all existing snapshot-tests pass with `*storage-backend*` set to `:substrate`
- [ ] New test: migrate-filesystem-to-substrate transfers all snapshots
- [ ] New test: entity-attr works correctly after LMDB store reopen

#### Manual Verification:
- [ ] Start system with LMDB, create agents, verify datoms persist
- [ ] Restart system, verify state survives (crash-safe)
- [ ] `(autopoiesis.substrate:store-blob "hello world")` returns hash
- [ ] `(autopoiesis.substrate:load-blob hash :as-string t)` → "hello world"

---

## Phase 3: CL Conductor — Timer Heap + Tick Loop

### Overview

Port the conductor's core scheduling logic from LFE to CL. Background thread with 100ms tick, timer heap, event queue (as datoms in the substrate), metrics.

**Key difference from original plan**: The conductor's event queue IS the substrate. Events are datoms. Metrics are datoms. Worker status is datoms. Everything is queryable and hook-reactive.

**Uses Phase 1.5**: The conductor uses `define-entity-type :event` and `:worker` from Phase 1.5's pre-defined types. Worker and event operations use typed entity access via `make-typed-entity` instead of raw `entity-attr` calls.

### Changes Required

#### 1. Package definition
**File**: `src/orchestration/packages.lisp` (new)

```lisp
(defpackage #:autopoiesis.orchestration
  (:use #:cl #:alexandria #:autopoiesis.substrate)
  (:export
   #:*conductor*
   #:conductor
   #:start-conductor
   #:stop-conductor
   #:conductor-running-p
   #:conductor-status
   #:schedule-action
   #:cancel-action
   #:queue-event
   #:conductor-active-workers
   #:worker-running-p
   #:start-system
   #:stop-system
   #:run-claude-cli
   #:build-claude-command
   #:extract-result
   #:shell-quote
   #:register-conductor-endpoints))
```

#### 2. Conductor class
**File**: `src/orchestration/conductor.lisp` (new)

```lisp
(defclass conductor ()
  ((timer-heap :initform nil :accessor conductor-timer-heap
               :documentation "List of (fire-time . action-plist) sorted by time")
   (tick-thread :initform nil :accessor conductor-tick-thread)
   (running :initform nil :accessor conductor-running-p)
   (metrics :initform (make-hash-table :test 'eq) :accessor conductor-metrics)
   (failure-counts :initform (make-hash-table :test 'equal)
                   :accessor conductor-failure-counts))
  (:documentation "Central scheduler — tick loop with timer heap.
   Events and worker status are stored as datoms in the substrate."))
```

**Key difference**: No `event-queue` or `active-workers` slots. These are now datoms:

```lisp
;; Queue an event — write a datom
(defun queue-event (event-type data &key (store *store*))
  "Queue an event as a datom. Hooks fire, conductor processes on next tick."
  (let ((event-id (intern-id (format nil "event-~A-~A" event-type (make-uuid)))))
    (transact!
     (list (make-datom event-id :event/type event-type)
           (make-datom event-id :event/data data)
           (make-datom event-id :event/status :pending)
           (make-datom event-id :event/created-at (get-universal-time))))))

;; Process events — take! from the substrate
(defun process-events (conductor)
  "Process pending events by claiming them via take!."
  (loop for event-eid = (take! :event/status :pending :new-value :processing)
        while event-eid
        do (let ((event-type (entity-attr event-eid :event/type))
                 (event-data (entity-attr event-eid :event/data)))
             (handler-case
                 (progn
                   (dispatch-event conductor event-type event-data)
                   (transact! (list (make-datom event-eid :event/status :complete))))
               (error (e)
                 (transact! (list (make-datom event-eid :event/status :failed)
                                  (make-datom event-eid :event/error (format nil "~A" e)))))))))

;; Register a worker — write datoms
(defun register-worker (conductor task-id thread)
  "Register a running worker as datoms."
  (let ((worker-eid (intern-id task-id)))
    (transact!
     (list (make-datom worker-eid :worker/task-id task-id)
           (make-datom worker-eid :worker/status :running)
           (make-datom worker-eid :worker/thread thread)
           (make-datom worker-eid :worker/started-at (get-universal-time))))))

;; Check if worker is running — query the substrate
(defun worker-running-p (conductor task-id)
  (let ((worker-eid (intern-id task-id)))
    (eq (entity-attr worker-eid :worker/status) :running)))
```

#### 3. Tick loop
Same as original plan, but `process-events` uses `take!`:

```lisp
(defun conductor-tick-loop (conductor)
  (loop while (conductor-running-p conductor)
        do (handler-case
               (progn
                 (process-due-timers conductor)
                 (process-events conductor)
                 (increment-metric conductor :tick-count))
             (error (e)
               (format *error-output* "~&Conductor tick error: ~A~%" e)))
           (sleep 0.1)))
```

#### 4. Rest of conductor (same as original plan)
- `schedule-action` / `cancel-action` — timer heap management
- `execute-timer-action` — dispatch on `:action-type`
- `handle-task-result` — update worker datoms on completion
- `conductor-status` — query substrate for worker/event datoms
- Failure backoff from LFE `conductor.lfe:442-460`

### Success Criteria

Same as original Phase 1, plus:
- [ ] New test: queue-event creates datoms in substrate
- [ ] New test: process-events claims events via take!
- [ ] New test: register-worker creates worker datoms
- [ ] New test: worker-running-p queries substrate correctly
- [ ] New test: conductor-status returns correct metrics from datom queries

---

## Phase 4: CL Claude Worker — CLI Subprocess Driver

### Overview

Port Claude CLI subprocess management from `claude-worker.lfe` into CL using `sb-ext:run-program`. Same as original Phase 2 — no substrate changes needed.

### Changes Required

Same as original Phase 2 (`src/orchestration/claude-worker.lisp`):
- `build-claude-command` — construct CLI command string
- `run-claude-cli` — run subprocess in thread, parse stream-json output
- `extract-result` — find "result" type message
- `shell-quote` — escape for shell
- `find-claude-executable` — find claude binary
- Wire to conductor's `execute-timer-action` for `:claude` action type
- `schedule-infra-watcher` — periodic infrastructure check

### Success Criteria

Same as original Phase 2.

---

## Phase 5: Refactor Orchestration + Delete LFE

### Overview

Same three sub-steps as original Phase 3:
1. Refactor orchestration tools to use CL conductor directly (no bridge)
2. Wire endpoints and system startup
3. Delete LFE and bridge code

### 5.1: Refactor Orchestration Tools

**File**: `src/integration/builtin-tools.lisp`

#### `spawn-agent` — Refactor to use substrate

```lisp
;; Replace queue-orchestration-request with direct thread spawn + datom tracking
(let* ((agent-id (format nil "sub-~A-~A" name (autopoiesis.core:make-uuid)))
       (agent-eid (autopoiesis.substrate:intern-id agent-id))
       (agent (make-instance 'autopoiesis.integration:agentic-agent ...)))
  ;; Record agent as datoms
  (autopoiesis.substrate:transact!
   (list (autopoiesis.substrate:make-datom agent-eid :agent/name name)
         (autopoiesis.substrate:make-datom agent-eid :agent/task task)
         (autopoiesis.substrate:make-datom agent-eid :agent/status :running)
         (autopoiesis.substrate:make-datom agent-eid :agent/started-at (get-universal-time))))
  ;; Spawn thread
  (bt:make-thread
   (lambda ()
     (handler-case
         (let ((result (autopoiesis.integration:agentic-agent-prompt agent task)))
           (autopoiesis.substrate:transact!
            (list (autopoiesis.substrate:make-datom agent-eid :agent/status :complete)
                  (autopoiesis.substrate:make-datom agent-eid :agent/result (princ-to-string result))
                  (autopoiesis.substrate:make-datom agent-eid :agent/completed-at (get-universal-time)))))
       (error (e)
         (autopoiesis.substrate:transact!
          (list (autopoiesis.substrate:make-datom agent-eid :agent/status :failed)
                (autopoiesis.substrate:make-datom agent-eid :agent/error (format nil "~A" e)))))))
   :name (format nil "sub-agent-~A" name)))
```

#### `query-agent` — Query substrate
```lisp
;; Replace *sub-agents* hash table lookup with substrate query
(let* ((agent-eid (autopoiesis.substrate:intern-id agent-id))
       (status (autopoiesis.substrate:entity-attr agent-eid :agent/status))
       (task (autopoiesis.substrate:entity-attr agent-eid :agent/task)))
  ...)
```

#### `save-session` / `resume-session` — Direct substrate operations
```lisp
;; save: store session as datoms + blob
(let* ((session-id (or name (make-uuid)))
       (session-eid (autopoiesis.substrate:intern-id session-id))
       (state-blob (autopoiesis.substrate:store-blob (serialize-agent-state))))
  (autopoiesis.substrate:transact!
   (list (autopoiesis.substrate:make-datom session-eid :session/name session-id)
         (autopoiesis.substrate:make-datom session-eid :session/state-hash state-blob)
         (autopoiesis.substrate:make-datom session-eid :session/saved-at (get-universal-time)))))
```

#### Remove queue-drain infrastructure
Delete:
- `*orchestration-requests*` global
- `*sub-agents*` global (replaced by substrate)
- `queue-orchestration-request` function
- `drain-orchestration-requests` function

Keep:
- `update-sub-agent` → rewrite to use `transact!`
- `*session-directory*` → remove (substrate handles persistence)

### 5.2-5.6: Endpoints, ASDF, Delete LFE, Tests, CLAUDE.md

Same as original Phase 3 sections 3.2-3.6.

### Success Criteria

Same as original Phase 3, plus:
- [ ] New test: `spawn-agent` creates agent datoms in substrate
- [ ] New test: `query-agent` reads from substrate
- [ ] New test: `save-session` writes session datoms + blob
- [ ] New test: `resume-session` reads session from substrate

---

## Phase 6: Turn/Context DAG Model

### Overview

Implement conversation turns as datom entities stored in the substrate. Turns form a DAG via parent pointers. Contexts are mutable entity pointers to branch heads. This maps directly to the substrate — no separate "conversation module" needed.

### Changes Required

#### 1. Conversation package
**File**: `src/conversation/packages.lisp` (new)

```lisp
(defpackage #:autopoiesis.conversation
  (:use #:cl #:alexandria #:autopoiesis.substrate)
  (:export
   #:append-turn
   #:turn-content
   #:make-context
   #:fork-context
   #:context-head
   #:context-history
   #:find-turns-by-role
   #:find-turns-by-time-range))
```

#### 2. Turn operations — pure datom patterns
**File**: `src/conversation/turn.lisp` (new)

```lisp
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
    ;; Single transact! for atomicity — turn datoms + context head update
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
```

#### 3. Context operations — mutable pointers as datoms
**File**: `src/conversation/context.lisp` (new)

```lisp
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
  "Fork a conversation. O(1) — creates new context pointing at same head turn."
  (let* ((head (entity-attr source-ctx-eid :context/head))
         (source-name (entity-attr source-ctx-eid :context/name))
         (fork-name (or name (format nil "fork-~A" source-name)))
         (fork-eid (intern-id (format nil "ctx-~A" (autopoiesis.core:make-uuid)))))
    (transact!
     (list (make-datom fork-eid :context/name fork-name)
           (make-datom fork-eid :context/head head)
           (make-datom fork-eid :context/forked-from source-ctx-eid)
           (make-datom fork-eid :context/created-at (get-universal-time))))
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
```

### Success Criteria

- [ ] New test: append-turn stores turn datoms and updates context head
- [ ] New test: turn-content loads full text from blob store
- [ ] New test: context-history returns turns in chronological order
- [ ] New test: fork-context creates independent context pointing to same head
- [ ] New test: append to forked context doesn't affect original
- [ ] New test: find-turns-by-role filters correctly
- [ ] New test: conversation survives store close/reopen (LMDB persistence)

---

## Phase 7: Wire Conversations to Agentic Loop

### Overview

Connect the Turn/Context model to the agentic loop so every Claude interaction is automatically recorded as conversation turns in the substrate. Same as original Phase 7 but using substrate operations.

### Changes Required

Same as original Phase 7:
1. Add `conversation-context` slot to `agentic-agent`
2. Update `agentic-loop` to record each turn via `append-turn`
3. Update `fork-branch` tool to also fork conversation context
4. Build messages from `context-history` instead of in-memory list

The key difference: all operations go through `transact!`, so hooks fire on every conversation turn. This enables:

```lisp
;; Standing query: monitor for tool failures in conversations
(register-hook *store* :tool-failure-monitor
  (lambda (datoms tx-id)
    (dolist (d datoms)
      (when (and (eq (resolve-id (d-attribute d)) :turn/role)
                 (eq (d-value d) :tool))
        ;; Check if the tool result indicates failure
        (let ((content (turn-content (d-entity d))))
          (when (search "error" content :test #'char-equal)
            (warn "Tool failure in turn ~A" (d-entity d))))))))
```

### Success Criteria

Same as original Phase 7.

---

## Phase 8: Linda Coordination (Optional Polish)

### Overview

With the substrate in place, enhance the conductor to use Linda coordination patterns for work distribution. This is emergent — it's just using `take!` and `transact!` in the conductor's event processing.

### Changes Required

#### 1. Self-selecting workers

Instead of the conductor dispatching work to specific workers, workers self-select:

```lisp
(defun start-worker-pool (conductor n &key (types '(:claude :agentic)))
  "Start N workers that self-select tasks from the substrate."
  (dotimes (i n)
    (bt:make-thread
     (lambda ()
       (loop while (conductor-running-p conductor)
             do (let ((task-eid (take! :task/status :pending :new-value :in-progress)))
                  (if task-eid
                      (let ((task-type (entity-attr task-eid :task/type)))
                        (when (member task-type types)
                          (execute-task conductor task-eid)))
                      (sleep 0.5)))))
     :name (format nil "worker-~D" i))))
```

#### 2. Inter-agent coordination via datoms

Agents write findings to the substrate. Other agents or the conductor pick them up:

```lisp
;; Agent writes a finding
(transact!
 (list (make-datom finding-eid :finding/type :needs-review)
       (make-datom finding-eid :finding/agent agent-eid)
       (make-datom finding-eid :finding/content-hash (store-blob analysis))
       (make-datom finding-eid :finding/status :pending)))

;; Another agent claims it
(take! :finding/status :pending :new-value :reviewing)
```

### Success Criteria

- [ ] New test: worker-pool workers self-select tasks via take!
- [ ] New test: multiple workers don't claim the same task (atomicity)
- [ ] New test: inter-agent coordination via datom findings

---

## Testing Strategy

### Unit Tests (per phase)

- `test/substrate-tests.lisp` — Phase 1-1.5-2: datom, intern (monotonic), transact! (hooks outside lock), scoped indexes, entity-state, take! (value index), define-entity-type, defsystem dispatch, LMDB, blobs
- `test/orchestration-tests.lisp` — Phase 3-5: conductor, claude-worker, refactored tools
- `test/conversation-tests.lisp` — Phase 6-7: turns, contexts, forking, history
- `test/linda-tests.lisp` — Phase 8: take! coordination, worker pool

### Modified Tests

- `test/meta-agent-tests.lisp` — Update queue-drain tests to verify substrate datom operations
- `test/bridge-protocol-tests.lisp` — Rename suite, remove bridge-specific assertions

### Deleted Tests

- LFE tests (95 tests across 5 modules) — deleted with `lfe/` directory

### Test Counts (Expected)

| Suite | Before | After | Delta |
|-------|--------|-------|-------|
| Main CL tests | ~1,245 | ~1,240 | -5 (bridge/meta-agent changes) |
| New substrate tests (Phase 1) | 0 | ~25 | +25 (datom, intern, transact!, hooks, scoped indexes, take!, query, conditions) |
| New programming model tests (Phase 1.5) | 0 | ~15 | +15 (define-entity-type, defsystem, MOP, dispatch, builtin types) |
| New substrate LMDB tests (Phase 2) | 0 | ~10 | +10 |
| New orchestration tests | 0 | ~25 | +25 |
| New conversation tests | 0 | ~15 | +15 |
| New linda tests | 0 | ~5 | +5 |
| LFE tests | 95 | 0 | -95 |
| **Total** | ~1,340 | ~1,335 | ~-5 net |

---

## File Summary

### New Files

| File | Phase | Lines (est.) |
|------|-------|-------------|
| `src/substrate/packages.lisp` | 1 | ~50 |
| `src/substrate/conditions.lisp` | 1 | ~40 |
| `src/substrate/intern.lisp` | 1 | ~50 |
| `src/substrate/encoding.lisp` | 1 | ~60 |
| `src/substrate/datom.lisp` | 1 | ~30 |
| `src/substrate/entity.lisp` | 1 | ~80 |
| `src/substrate/query.lisp` | 1 | ~40 |
| `src/substrate/store.lisp` | 1 | ~180 |
| `src/substrate/linda.lisp` | 1 | ~80 |
| `src/substrate/entity-type.lisp` | 1.5 | ~120 |
| `src/substrate/system.lisp` | 1.5 | ~100 |
| `src/substrate/builtin-types.lisp` | 1.5 | ~80 |
| `src/substrate/lmdb-backend.lisp` | 2 | ~200 |
| `src/substrate/blob.lisp` | 2 | ~80 |
| `src/substrate/migration.lisp` | 2 | ~60 |
| `src/orchestration/packages.lisp` | 3 | ~30 |
| `src/orchestration/conductor.lisp` | 3-4 | ~300 |
| `src/orchestration/claude-worker.lisp` | 4 | ~120 |
| `src/orchestration/endpoints.lisp` | 5 | ~40 |
| `src/conversation/packages.lisp` | 6 | ~20 |
| `src/conversation/turn.lisp` | 6 | ~80 |
| `src/conversation/context.lisp` | 6 | ~80 |
| `config/cortex-mcp.json` | 5 | (moved) |
| `config/infra-watcher-prompt.md` | 5 | (moved) |
| `test/substrate-tests.lisp` | 1-1.5 | ~300 |
| `test/orchestration-tests.lisp` | 3-5 | ~200 |
| `test/conversation-tests.lisp` | 6-7 | ~120 |
| `test/linda-tests.lisp` | 8 | ~50 |
| **Total new** | | **~2,520** |

### Modified Files

| File | Phase | Change |
|------|-------|--------|
| `autopoiesis.asd` | 1,2,3,6 | Add substrate, orchestration, conversation modules |
| `src/integration/builtin-tools.lisp` | 5 | Refactor to use substrate (~100 lines changed) |
| `src/snapshot/persistence.lisp` | 2 | Add substrate backend dispatch (~30 lines) |
| `src/integration/agentic-agent.lisp` | 7 | Add conversation-context slot (~40 lines) |
| `src/integration/claude-bridge.lisp` | 7 | Add turn recording via append-turn (~20 lines) |
| `test/meta-agent-tests.lisp` | 5 | Update to verify substrate operations (~30 lines) |
| `test/bridge-protocol-tests.lisp` | 5 | Rename suite, clean up (~10 lines) |
| `test/run-tests.lisp` | 1 | Add new test suites (~5 lines) |
| `CLAUDE.md` | 5 | Update architecture, commands, test counts |

### Deleted Files

| File/Directory | Phase | Lines Removed |
|----------------|-------|--------------|
| `lfe/` (entire directory) | 5 | ~1,605 source + ~500 test |
| `scripts/agent-worker.lisp` | 5 | ~514 |
| **Total deleted** | | **~2,619** |

### Net Change

- **New code**: ~2,520 lines (~300 more than pre-revision plan, for programming model)
- **Modified**: ~235 lines changed
- **Deleted**: ~2,619 lines
- **Net**: ~-99 lines (slightly simpler overall, with dramatically more capability — typed entities, reactive systems, schema validation)

---

## Parallelization Plan for Agent Team

```
Agent A (Substrate):          Agent B (Conductor):       Agent C (Conversations):
  Phase 1: Substrate Kernel    (wait for Phase 1.5)       (wait for Phase 2)
  Phase 1.5: Programming Model Phase 3: CL Conductor      Phase 6: Turn/Context
  Phase 2: LMDB + Blobs        Phase 4: Claude Worker      Phase 7: Wire to Loop
                                Phase 5: Refactor + Delete
                                Phase 8: Linda (optional)
```

**Dependencies:**
- Phase 1 must complete first (everything needs the substrate)
- Phase 1.5 depends on Phase 1 (programming model wraps substrate primitives)
- Phase 2 depends on Phase 1.5 (wires LMDB underneath substrate, uses entity types)
- Phase 3 depends on Phase 1.5 (conductor uses `define-entity-type :event` and `:worker`)
- Phase 4 depends on Phase 3 (claude-worker wires to conductor)
- Phase 5 depends on Phases 3+4 (needs conductor + claude-worker)
- Phase 6 depends on Phase 2 (needs LMDB + blobs for conversation persistence; uses `:turn` and `:context` entity types from Phase 1.5)
- Phase 7 depends on Phase 6 (needs turn/context model)
- Phase 8 depends on Phase 5 (optional polish after LFE removal)

**Minimum viable product**: Phases 1-5 (substrate + programming model + conductor + LFE removed).

**Full product**: All 9 phases (substrate-backed everything with Linda coordination).

---

## Architecture: Before and After

### Before (Current)
```
LFE/BEAM Process
├── Conductor (timer heap, tick loop)
├── Supervisor Trees (agent-sup, claude-sup, connector-sup)
├── Agent Workers (spawn SBCL subprocesses)
│   └── S-expression bridge protocol (16 message types)
├── Claude Workers (spawn Claude CLI)
└── HTTP (Cowboy)

CL Autopoiesis (loaded into agent-worker subprocesses)
├── Cognitive Engine (dormant in main process)
├── Agentic Loop (active in subprocess)
├── Self-Extension Tools
├── Snapshot System (filesystem)
└── Monitoring (Hunchentoot)
```

### After (All 9 Phases)
```
CL Autopoiesis (single process)
├── Substrate (datom kernel + programming model)
│   ├── LMDB Environment (one store, named databases per index)
│   ├── transact! → EAVT, AEVT, EA-CURRENT indexes (scoped, with :append/:replace strategy)
│   ├── register-hook (on-transact callbacks, fire OUTSIDE lock)
│   ├── define-index (custom indexes with :scope predicate)
│   ├── define-entity-type (CLOS class + MOP slot-unbound + schema validation)
│   ├── defsystem (declaration-filtered reactive dispatch)
│   ├── Blob Store (content-addressed, SHA-256, optional Zstd)
│   ├── Entity Cache (write-through over EA-CURRENT)
│   ├── Value Index (inverted: (attr . value) → entity-ids, for take! and find-entities)
│   ├── Intern Tables (monotonic counter, string ↔ u64/u32 mapping)
│   ├── take! (Linda atomic claim, O(1) via value index)
│   └── Conditions (substrate-validation-error, unknown-entity-type + restarts)
├── Orchestration
│   ├── Conductor (bordeaux-threads timer heap + tick loop)
│   │   ├── Events as datoms (queue-event → take! processing)
│   │   └── Workers as datoms (status, metrics queryable)
│   ├── Claude CLI Worker (sb-ext:run-program)
│   └── Worker Pool (self-selecting via take!)
├── Cognitive Engine
│   ├── Agentic Agent (multi-turn tool loop)
│   ├── Self-Extension Compiler (sandboxed, ~170 symbols)
│   ├── Learning System (1,032 lines, ready for activation)
│   └── Orchestration Tools (spawn-agent, fork-branch, save-session)
│       └── All operations write datoms to substrate
├── Conversation (datom entities on substrate)
│   ├── Turn entities (:turn/parent, :turn/role, :turn/content-hash, ...)
│   ├── Context entities (:context/head, :context/name, :context/agent)
│   └── Forking = new context pointing to existing turn (O(1))
├── Snapshot (blob storage on substrate)
│   ├── Content as blobs (:snapshot/content-hash)
│   └── Metadata as datoms (:snapshot/parent, :snapshot/agent-id, :snapshot/timestamp)
├── Integration
│   ├── Claude API (direct dexador calls)
│   ├── OpenAI/Ollama bridges
│   ├── MCP client (Cortex infrastructure)
│   └── 22+ built-in tools
├── HTTP (Hunchentoot)
│   ├── /health, /healthz, /readyz, /metrics (existing)
│   └── /conductor/status, /conductor/webhook (new)
└── SWANK (live REPL)
```

---

## What We're NOT Doing (Revised)

Previous "NOT Doing" items, reconsidered:

| Item | Original | Revised |
|------|----------|---------|
| Datalog query language | Deferred | Still deferred. Basic queries (`find-entities`, `find-entities-by-type`) first. Datalog is the natural next step. |
| Full EAV decomposition of cognitive state | Deferred | **Partially doing.** Conversations and conductor events ARE datoms. Snapshots remain as blobs. |
| Standing query / defsystem reactive layer | Deferred | **NOW DOING.** Phase 1.5 `defsystem` with declaration-filtered dispatch. Full Rete is still deferred. |
| MOP schema specialization | Not doing | **NOW DOING.** Phase 1.5 `define-entity-type` with `slot-unbound` MOP cache. |
| Scoped indexes | Not considered | **NOW DOING.** Phase 1 `define-index` with `:scope` predicate. |
| Substrate conditions | Not considered | **NOW DOING.** Phase 1 `substrate-validation-error` + `unknown-entity-type`. |
| SoA columnar storage | Deferred | Still deferred. Module-level optimization via hooks when profiling shows need. |
| OTP supervision trees | Not doing | Not doing. Thread + handler-case + retry. |
| Multi-user / multi-tenant | Not doing | Not doing. |
| SSE / web dashboard | Not doing | Not doing. |

---

## Open Decisions (Resolved)

1. **Architecture path?** → Path C (substrate-first). Build the datom kernel, everything else as modules.
2. **LFE removal timing?** → Phase 5. Build substrate + conductor first, verify, then delete.
3. **OTP supervision in CL?** → No. Thread + handler-case + retry loops.
4. **EAV datoms vs blobs for snapshots?** → Blobs. Metadata as datoms, content as blobs.
5. **Conversation model?** → Datom entities. Turns and contexts as datoms on the substrate.
6. **Linda coordination?** → Built into the substrate via `take!`. Used by conductor in Phase 8.
7. **SHA-256 vs BLAKE3 for blob hashing?** → SHA-256. Already available via ironclad.
8. **Zstd compression?** → Include if available. Fallback to uncompressed.
9. **Entity ID width?** → u64 entities, u32 attributes. From substrate-decomposition.md.
10. **In-memory Phase 1?** → Yes. Phase 1 is in-memory only. LMDB wired in Phase 2.
11. **Interning strategy?** → Monotonic counter (not SHA-256 truncation). Collision-free. Counter + tables persisted to LMDB in Phase 2.
12. **Hook firing location?** → OUTSIDE the lock. Prevents deadlock when hooks call `transact!`.
13. **Programming model scope?** → Full. `define-entity-type` + `defsystem` + MOP `slot-unbound` in Phase 1.5. Not deferred.
14. **Scoped indexes?** → Yes. `:scope` predicate on `define-index`. Prevents cross-domain write amplification.
15. **Index strategy?** → `:append` (default) or `:replace` (for EA-CURRENT). Explicit in `define-index` API.
16. **take! implementation?** → Inverted value index `(attribute . value) → entity-ids` for O(1) lookup. Not O(n) cache scan.

## References

### Plans (synthesized)
- `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — Phases 1-5 (1-4 complete)
- `thoughts/shared/plans/2026-02-15-phase4-rich-cl-lfe-bridge.md` — Fully implemented, now being removed
- `thoughts/shared/plans/2026-02-16-remove-lfe-consolidate-cl.md` — CL consolidation design

### Substrate Design (from thinking repo)
- `~/projects/thinking/substrate-decomposition.md` — Datom model, store, transact!, three-project synthesis
- `~/projects/thinking/substrate-extension-points.md` — Extension points: define-index, register-hook, etc.
- `~/projects/thinking/hpc-lisp-optimization-ideas.md` — Linda tuple spaces (#7), arena allocation (#5), Bloom filters (#10)
- `~/projects/thinking/cxdb-comparison.md` — Turn/Context DAG design

### Research
- `thoughts/shared/research/2026-02-16-linda-tuple-spaces-substrate-evaluation.md` — Linda mapping to datom model
- `thoughts/shared/research/2026-02-16-hpc-lisp-optimization-evaluation.md` — HPC ideas evaluation
- `thoughts/shared/research/2026-02-16-thinking-repo-ideas-evaluation.md` — Full thinking-repo evaluation
- `thoughts/shared/research/2026-02-16-substrate-extension-points-gap-analysis.md` — Extension points gap analysis
- `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — Dormant CL engine finding
- `thoughts/shared/research/2026-02-16-lfe-control-plane-analysis.md` — LFE removal justification

### Key Source Files
- `src/integration/claude-bridge.lisp:174-226` — Agentic loop (foundation)
- `src/integration/builtin-tools.lisp:440-641` — Orchestration tools (refactor target)
- `src/integration/agentic-agent.lisp:13-198` — Agent class (conversation integration)
- `src/snapshot/persistence.lisp` — Filesystem persistence (substrate replacement target)
- `src/snapshot/content-store.lisp` — Content-addressable store (pattern for blob store)
- `src/core/recovery.lisp:159-199` — Restart system (conductor error handling)
- `src/monitoring/endpoints.lisp:405-456` — Hunchentoot server (add conductor endpoints)
- `scripts/agent-worker.lisp` — Bridge script (to be deleted)
