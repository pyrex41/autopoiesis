# Plan: AP Substrate Evolution

## Overview

Transform ap/'s substrate into the core foundation for a family of applications (bubble, cortex, etc.) by: simplifying the integration/API layers, strengthening the substrate with Datalog queries and batched writes, unifying the HTTP client protocol, and extracting the substrate as a standalone ASDF system within the ap/ repo. Bubble integration deferred; focus is on making ap's substrate worthy of being *the* substrate.

## Current State Analysis

### Substrate (~1,078 lines, 15 files)
The substrate is solid but has threading fragility and missing capabilities:
- `src/substrate/store.lisp:204-217` — `with-store` binds 7 special variables
- `src/substrate/store.lisp:115-173` — `transact!` with two-phase commit (write under lock, hooks outside)
- `src/substrate/entity.lisp:23-31` — `entity-attr` O(1) via entity-cache
- `src/substrate/linda.lisp:32-72` — `take!` with inverted value index
- `src/substrate/system.lisp:74-102` — `defsystem` with dispatch table
- `src/substrate/entity-type.lisp:36-90` — `define-entity-type` with MOP slot-unbound
- `src/substrate/lmdb-backend.lisp:13-71` — LMDB store opening, intern restoration

**Key issues:**
1. 7+ special variables must be captured for threads (`conductor.lisp:262-268` uses `autopoiesis.substrate::` for 4 unexported symbols)
2. No temporal queries (entity-history returns only current value, `entity.lisp:63-71`)
3. No batched writes (transact! is per-call)
4. No declarative query language
5. `scan-index` returns nil in Phase 1 (`query.lisp:34-38`)

### Integration Layer (~4,233 lines, 20 files)
- 5 CLI providers share ~80% structure (529 lines total)
- 2 bridges (Claude 237 lines, OpenAI 247 lines) use identical HTTP patterns with different auth/format
- Both use Dexador `dex:post`, differ on headers (`x-api-key` vs `Bearer`) and message format

### API Layer (~2,860 lines, 13 files)
- 20 operations have exact 1:1 mapping between REST (`routes.lisp`) and MCP (`mcp-server.lisp`)
- Both call identical backend functions — duplication is in routing/serialization only

### Orchestration
- `conductor.lisp:251-283` — `start-conductor` captures 7 substrate specials with fully-qualified names for 4 unexported symbols

## Desired End State

1. **Substrate context object** — One special variable `*substrate*` replaces 7+, thread capture is `(let ((*substrate* ctx)) ...)`
2. **`define-cli-provider` macro** — 5 provider files collapse to data-driven definitions
3. **Unified operation layer** — Operations defined once, REST and MCP generated from metadata
4. **Unified HTTP client** — One `http-llm-client` protocol, Claude/OpenAI are format adapters
5. **Datalog queries** — `(query '((?e :agent/status :running) (?e :agent/name ?name)))` works
6. **Batched writes** — `(with-batch-transaction () ...)` accumulates, flushes atomically
7. **Temporal queries** — `(entity-history entity :attribute :last-n 10)` scans EAVT/LMDB
8. **Standalone `:substrate` ASDF system** — Other systems depend on it, not on `:autopoiesis`

## Implementation Approach

Bottom-up: fix the substrate first (it's the foundation everything else depends on), then simplify the layers above, then add new capabilities. Each phase is independently shippable and testable.

---

## Phases

### Phase 1: Substrate Context Object
**Goal**: Replace 7+ special variables with a single `substrate-context` struct. Eliminate the thread-capture fragility.

**Changes**:
- [ ] Create `substrate-context` struct in new file `src/substrate/context.lisp`
  ```lisp
  (defstruct substrate-context
    (store nil)
    (entity-cache (make-hash-table :test 'equal))
    (value-index (make-hash-table :test 'equal))
    (intern-table (make-hash-table :test 'equal))
    (resolve-table (make-hash-table :test 'eql))
    (next-entity-id 1 :type (unsigned-byte 64))
    (next-attribute-id 1 :type (unsigned-byte 32)))
  ```
- [ ] Add single special variable `*substrate*` of type `substrate-context`
- [ ] Update `with-store` (`store.lisp:204-217`) to bind `*substrate*` instead of 7 variables
- [ ] Update `transact!` (`store.lisp:115-173`) to access context slots
- [ ] Update `entity-attr` (`entity.lisp:23-31`) to use `(substrate-context-entity-cache *substrate*)`
- [ ] Update `take!` (`linda.lisp:32-72`) to use context's value-index
- [ ] Update `intern-id` (`intern.lisp:22-34`) to use context's intern-table
- [ ] Update `open-store` (`store.lisp:183-194`) to initialize context
- [ ] Update `lmdb-backend.lisp:13-71` — restore interns into context
- [ ] Export `*substrate*` and `substrate-context` from `packages.lisp`
- [ ] Keep old special variables as deprecated accessors: `(defun *entity-cache* () (substrate-context-entity-cache *substrate*))` — only if needed for backward compat during transition
- [ ] Update `start-conductor` (`conductor.lisp:251-283`) to capture single `*substrate*` instead of 7 vars
- [ ] Update `conductor.lisp:270-281` tick thread to rebind single `*substrate*`
- [ ] Update `packages.lisp:12-68` — remove individual exports of `*entity-cache*`, `*value-index*`; add `*substrate*`, `substrate-context`, accessors

**Success Criteria — Automated**:
- [ ] `./scripts/test.sh` passes (all 2,775+ assertions)
- [ ] `(5am:run! 'autopoiesis.test::substrate-tests)` passes (112 checks)
- [ ] `(5am:run! 'autopoiesis.test::orchestration-tests)` passes (91 checks) — validates conductor thread capture
- [ ] `(5am:run! 'autopoiesis.test::conversation-tests)` passes (45 checks)

**Success Criteria — Manual**:
- [ ] REPL: `(with-store (:path "/tmp/test-ctx") (transact! (list (make-datom :entity :e1 :attribute :name :value "test"))) (entity-attr :e1 :name))` returns `"test"`
- [ ] Conductor starts and ticks without errors after context change

---

### Phase 2: Consolidate CLI Providers
**Goal**: Replace 5 provider files with a data-driven `define-cli-provider` macro.

**Changes**:
- [ ] Create `src/integration/provider-macro.lisp` with `define-cli-provider` macro
  ```lisp
  (define-cli-provider :claude-code
    (:command "claude")
    (:modes (:one-shot :streaming))
    (:flags
      (:prompt      "-p" :required t)
      (:output-format "--output-format" :default "json")
      (:max-turns   "--max-turns")
      (:model       "--model")
      (:skip-permissions "--dangerously-skip-permissions" :flag t)
      (:max-budget  "--max-budget-total-usd")
      (:allowed-tools "--allowedTools" :list t))
    (:parser :json-object
      (:result "result")
      (:cost "cost_usd")
      (:turns "num_turns")
      (:session-id "session_id"))
    (:extra-slots
      (skip-permissions :initarg :skip-permissions :initform nil)
      (max-budget-usd :initarg :max-budget-usd :initform nil)))
  ```
- [ ] Macro generates: `defclass`, `make-*-provider`, `provider-supported-modes`, `provider-build-command`, `provider-parse-output`, `provider-to-sexpr`
- [ ] Port each provider to macro form:
  - [ ] `provider-claude-code.lisp` (98 lines) → ~15 lines of macro call
  - [ ] `provider-cursor.lisp` (71 lines) → ~12 lines
  - [ ] `provider-opencode.lisp` (105 lines) → ~15 lines (JSONL parser needs custom `:parser` spec)
  - [ ] `provider-codex.lisp` (123 lines) → ~15 lines (JSONL with multiple event types)
  - [ ] `provider-agent.lisp` (132 lines) → evaluate if this fits macro pattern (may keep separate)
- [ ] Update `autopoiesis.asd` to load `provider-macro.lisp` before individual providers
- [ ] Delete original provider files after verification
- [ ] Update `integration/packages.lisp` — exports remain identical (macro generates same symbols)

**Design Decision — Parser Specification**:
The 5 providers have 3 parsing patterns:
1. **JSON object** (Claude Code, Cursor) — parse single JSON, extract named fields
2. **JSONL stream** (OpenCode) — parse line-by-line, dispatch on `type` field
3. **JSONL with event dispatch** (Codex) — parse line-by-line, dispatch on `type` with nested field extraction

The macro should support all three via `:parser` keyword:
- `:json-object` — field name mapping
- `:jsonl-events` — event type → field extraction mapping
- Custom function — for provider-agent.lisp which wraps another provider

**Success Criteria — Automated**:
- [ ] `(5am:run! 'autopoiesis.test::provider-tests)` passes (70 checks)
- [ ] `(5am:run! 'autopoiesis.test::integration-tests)` passes (649 checks)
- [ ] `./scripts/test.sh` passes

**Success Criteria — Manual**:
- [ ] `(make-claude-code-provider :model "claude-sonnet-4-5-20250929")` creates valid provider
- [ ] `(provider-build-command provider "test prompt")` returns correct command + args
- [ ] Each provider's `provider-parse-output` handles sample output correctly

---

### Phase 3: Unify REST/MCP into Operation Layer
**Goal**: Define operations once with metadata; generate both REST routes and MCP tools from the same source.

**Changes**:
- [ ] Create `src/api/operations.lisp` with `defoperation` macro
  ```lisp
  (defoperation list-agents
    (:description "List all agents with optional status filter")
    (:parameters
      (status :type (or null keyword) :optional t :description "Filter by status"))
    (:permission :agent/read)
    (:handler (lambda (&key status)
                (let ((agents (autopoiesis.agent:list-agents)))
                  (if status
                      (remove-if-not (lambda (a) (eq (agent-state a) status)) agents)
                      agents))))
    (:serializer #'agent-to-json-alist)
    (:rest :get "/api/agents")
    (:mcp "list_agents"))
  ```
- [ ] Macro generates:
  - REST route handler (extracts params from URL/query/body, checks permission, calls handler, serializes)
  - MCP tool definition (schema from `:parameters`, handler calls same function)
  - Operation metadata for introspection
- [ ] Port the 20 overlapping operations from `routes.lisp` and `mcp-server.lisp`:
  - [ ] Agent lifecycle (8 operations)
  - [ ] Cognitive operations (4 operations)
  - [ ] Snapshot operations (4 operations)
  - [ ] Branch operations (3 operations)
  - [ ] HITL operations (2 operations)
  - [ ] System info (1 operation, different structure — handle as special case or separate ops)
- [ ] Keep REST-only operations (6) in `routes.lisp` as explicit handlers
- [ ] Keep MCP session/lifecycle management in `mcp-server.lisp`
- [ ] Update `api/packages.lisp` — add `defoperation`, operation registry

**Success Criteria — Automated**:
- [ ] `(5am:run! 'autopoiesis.test::rest-api-tests)` passes (73 checks)
- [ ] `./scripts/test.sh` passes
- [ ] New test: verify each defoperation generates both REST and MCP handlers

**Success Criteria — Manual**:
- [ ] REST `GET /api/agents` returns same response as before
- [ ] MCP `list_agents` tool returns same response as before
- [ ] Adding a new operation requires only one `defoperation` form

---

### Phase 4: Batched Writes
**Goal**: Add `with-batch-transaction` for atomic multi-datom writes with single lock acquisition.

**Changes**:
- [ ] Add thread-local batch accumulator to `substrate-context` (`context.lisp`)
  ```lisp
  ;; Add to substrate-context struct:
  (batch-queue nil :type list)  ; accumulated datoms during batch
  (batch-depth 0 :type fixnum) ; nesting counter for nested with-batch-transaction
  ```
- [ ] Create `with-batch-transaction` macro in `store.lisp`
  ```lisp
  (defmacro with-batch-transaction ((&key (store '*substrate*)) &body body)
    `(let ((ctx ,store))
       (incf (substrate-context-batch-depth ctx))
       (unwind-protect (progn ,@body)
         (when (zerop (decf (substrate-context-batch-depth ctx)))
           (let ((datoms (substrate-context-batch-queue ctx)))
             (setf (substrate-context-batch-queue ctx) nil)
             (when datoms
               (transact! (nreverse datoms))))))))
  ```
- [ ] Modify `transact!` (`store.lisp:115-173`) to check batch mode:
  - If `(substrate-context-batch-depth *substrate*) > 0`, push datoms to queue instead of writing
  - If depth = 0 (normal mode), write immediately as before
- [ ] Export `with-batch-transaction` from `packages.lisp`
- [ ] Add tests for:
  - [ ] Basic batching: multiple transact! calls flush as one
  - [ ] Nested batching: inner batch doesn't flush, outer does
  - [ ] Error rollback: unwind-protect clears queue on error
  - [ ] Hook firing: hooks fire once after batch, not per-datom

**Success Criteria — Automated**:
- [ ] `(5am:run! 'autopoiesis.test::substrate-tests)` passes (existing + new batch tests)
- [ ] New test: `(with-batch-transaction () (transact! d1) (transact! d2))` writes both atomically
- [ ] New test: hooks called once with combined datom list
- [ ] `./scripts/test.sh` passes

**Success Criteria — Manual**:
- [ ] REPL: batch of 100 datoms writes in single LMDB transaction (verify with timing comparison)

---

### Phase 5: Temporal Queries
**Goal**: Implement entity-history by scanning LMDB EAVT index. Enable "what did this entity look like at time T?"

**Changes**:
- [ ] Implement `entity-history` in `entity.lisp:63-71` (currently stub)
  ```lisp
  (defun entity-history (entity-id &key attribute (last-n 10))
    "Return historical values from EAVT index.
     If ATTRIBUTE given, returns values for that attribute over time.
     Otherwise returns full entity snapshots at each tx."
    ;; Scan EAVT with entity prefix, decode tx timestamps, collect
    ...)
  ```
- [ ] Implement `entity-as-of` — reconstruct entity state at a given tx-id
  ```lisp
  (defun entity-as-of (entity-id tx-id)
    "Reconstruct entity state as of TX-ID by scanning EAVT up to that tx."
    ...)
  ```
- [ ] Implement `scan-index` (`query.lisp:34-38`) — currently returns nil
  - Use LMDB cursor with prefix matching (same pattern as bubble's `scan-index`)
  - Support both EAVT and AEVT scans
- [ ] Add `entity-changes` — diff between two tx-ids for an entity
- [ ] Export new functions from `packages.lisp`

**Success Criteria — Automated**:
- [ ] New test: write 3 values for same (entity, attribute), verify entity-history returns all 3 with tx-ids
- [ ] New test: entity-as-of returns correct state at historical tx-id
- [ ] New test: entity-changes between two tx-ids shows correct diff
- [ ] `./scripts/test.sh` passes

**Success Criteria — Manual**:
- [ ] REPL: `(entity-history :agent-1 :attribute :agent/status :last-n 5)` shows status changes over time

---

### Phase 6: Datalog Query Language
**Goal**: Add a query compiler that translates Datalog patterns into index walks. Interpreted by default, with `compile-query` macro for hot paths.

**Changes**:
- [ ] Create `src/substrate/datalog.lisp` (~200 lines estimated)
- [ ] Implement pattern compiler:
  ```lisp
  ;; Interpreted (runtime)
  (query '((?e :agent/status :running)
           (?e :agent/name ?name)))
  ;; => Returns list of binding maps: ((:?e 42 :?name "researcher") ...)

  ;; Compiled (macro-time)
  (compile-query running-agents
    ((?e :agent/status :running)
     (?e :agent/name ?name)))
  ;; => Defines function RUNNING-AGENTS that returns same bindings
  ```
- [ ] Query execution strategy:
  1. For each pattern clause, determine best index (AEVT for `(?e :attr value)`, EAVT for `(entity :attr ?v)`)
  2. Execute first clause to get initial bindings
  3. For each subsequent clause, join with existing bindings
  4. Return final binding set
- [ ] Support basic operations:
  - [ ] Variable binding: `?e`, `?name` etc.
  - [ ] Constant matching: `:running`, `42`, `"string"`
  - [ ] Multi-clause joins (shared variables across clauses)
  - [ ] Negation: `(not (?e :agent/status :stopped))`
- [ ] `compile-query` macro compiles pattern to closures at macro-expansion time
  - Interns attribute keywords at compile time
  - Generates index-specific scan code
  - Returns a named function
- [ ] Add to `autopoiesis.asd` substrate module file list
- [ ] Export `query`, `compile-query` from `packages.lisp`

**Success Criteria — Automated**:
- [ ] New test: single-clause query `(query '((?e :agent/status :running)))` returns correct entities
- [ ] New test: two-clause join `(query '((?e :agent/status :running) (?e :agent/name ?name)))` returns bindings
- [ ] New test: negation clause excludes matching entities
- [ ] New test: compiled query produces same results as interpreted
- [ ] `./scripts/test.sh` passes

**Success Criteria — Manual**:
- [ ] REPL: `(query '((?e :entity/type :turn) (?e :turn/role :assistant)))` finds all assistant turns
- [ ] Performance: compiled query is measurably faster than interpreted for repeated execution

---

### Phase 7: Unified HTTP Client Protocol
**Goal**: One HTTP LLM client protocol with Claude and OpenAI as format adapters.

**Changes**:
- [ ] Create `src/integration/llm-client.lisp` with protocol definition
  ```lisp
  (defgeneric llm-complete (client messages &key tools system max-tokens)
    (:documentation "Send completion request. Returns normalized response."))

  (defgeneric llm-format-messages (client messages)
    (:documentation "Format messages for this provider's API."))

  (defgeneric llm-parse-response (client raw-response)
    (:documentation "Parse raw HTTP response into normalized format."))

  (defgeneric llm-auth-headers (client)
    (:documentation "Return authentication headers for this provider."))
  ```
- [ ] Create normalized response struct:
  ```lisp
  (defstruct llm-response
    (content nil :type (or null string))
    (tool-calls nil :type list)
    (stop-reason nil :type keyword)
    (usage nil :type list)
    (raw nil))
  ```
- [ ] Refactor `claude-bridge.lisp` to implement protocol:
  - `llm-auth-headers` returns `(("x-api-key" . key) ("anthropic-version" . "2023-06-01"))`
  - `llm-format-messages` passes through (native format)
  - `llm-parse-response` wraps existing parsing into `llm-response`
- [ ] Refactor `openai-bridge.lisp` to implement protocol:
  - `llm-auth-headers` returns `(("Authorization" . "Bearer key"))`
  - `llm-format-messages` calls existing `claude-messages-to-openai`
  - `llm-parse-response` calls existing `openai-response-to-claude-format` then wraps
- [ ] Shared HTTP transport in `llm-client.lisp`:
  ```lisp
  (defun llm-http-post (client url body)
    "Common HTTP POST with provider-specific auth headers."
    (let ((headers (append (llm-auth-headers client)
                          '(("content-type" . "application/json")))))
      (dex:post url :headers headers :content (jonathan:to-json body) ...)))
  ```
- [ ] Update `agentic-loop` (`claude-bridge.lisp:174-236`) to use protocol generics
- [ ] Update `*claude-complete-function*` usage to dispatch through protocol
- [ ] Update `integration/packages.lisp` — add protocol exports

**Success Criteria — Automated**:
- [ ] `(5am:run! 'autopoiesis.test::bridge-protocol-tests)` passes
- [ ] `(5am:run! 'autopoiesis.test::integration-tests)` passes (649 checks)
- [ ] `./scripts/test.sh` passes

**Success Criteria — Manual**:
- [ ] REPL: `(llm-complete (make-claude-client :api-key key) messages)` returns `llm-response`
- [ ] REPL: `(llm-complete (make-openai-client :api-key key) messages)` returns same struct shape
- [ ] Agentic loop works with both clients without code changes

---

### Phase 8: Extract Substrate as Standalone ASDF System
**Goal**: The substrate becomes `:substrate` — a separate ASDF system within ap/ that other projects can depend on.

**Changes**:
- [ ] Create `substrate.asd` at project root (alongside `autopoiesis.asd`)
  ```lisp
  (defsystem #:substrate
    :description "EAV datom store with LMDB, Datalog queries, reactive systems"
    :version "0.1.0"
    :depends-on (#:alexandria #:bordeaux-threads #:ironclad #:babel #:lmdb)
    :serial t
    :components
    ((:module "src/substrate"
      :components
      ((:file "packages")
       (:file "conditions")
       (:file "context")
       (:file "intern")
       (:file "encoding")
       (:file "datom")
       (:file "entity")
       (:file "query")
       (:file "store")
       (:file "linda")
       (:file "entity-type")
       (:file "system")
       (:file "lmdb-backend")
       (:file "blob")
       (:file "datalog")
       (:file "migration")))))
  ```
- [ ] Update `autopoiesis.asd` to depend on `:substrate` instead of including substrate module
- [ ] Rename package from `autopoiesis.substrate` to `substrate` (or keep as alias)
  - [ ] If renaming: add package nickname `autopoiesis.substrate` for backward compat
- [ ] Verify all 11 modules that use substrate still resolve correctly
- [ ] Update conductor.lisp — should no longer need `autopoiesis.substrate::` since context is exported
- [ ] Remove `builtin-types.lisp` from substrate (it defines ap-specific types like `:agent`, `:turn`) — move to ap's agent/conversation modules

**Success Criteria — Automated**:
- [ ] `(ql:quickload :substrate)` loads successfully without loading `:autopoiesis`
- [ ] `(ql:quickload :autopoiesis)` still works (depends on `:substrate`)
- [ ] `./scripts/test.sh` passes
- [ ] New standalone test: load `:substrate`, create store, transact, query — all works without ap

**Success Criteria — Manual**:
- [ ] A fresh SBCL image can `(ql:quickload :substrate)` and use the full datom store
- [ ] The substrate has zero references to `autopoiesis.*` packages

---

### Phase 9: Hook Ordering
**Goal**: Make hook firing deterministic by adding priority to hooks and dependency ordering to systems.

**Changes**:
- [ ] Add `:priority` parameter to `register-hook` (`store.lisp:75-82`)
  - Default priority: 0
  - Lower number = fires first
  - Hooks with same priority fire in registration order
- [ ] Add `:after` and `:before` declarations to `defsystem` (`system.lisp:74-102`)
  ```lisp
  (defsystem :derived-status
    (:entity-type :agent
     :watches (:agent/error-count :agent/uptime)
     :after (:cache-invalidation)  ; fires after cache is updated
     :access :read-only)
    ...)
  ```
- [ ] Implement topological sort for system dispatch order
- [ ] Update hook snapshot in `transact!` (`store.lisp:165-166`) to sort by priority
- [ ] Export `:priority` keyword from `packages.lisp`

**Success Criteria — Automated**:
- [ ] New test: hooks with priority 0, 1, 2 fire in correct order
- [ ] New test: system with `:after` fires after its dependency
- [ ] New test: circular dependency detected and signaled as condition
- [ ] `./scripts/test.sh` passes

**Success Criteria — Manual**:
- [ ] REPL: register hooks with different priorities, verify ordering via logging

---

## Phase Dependency Graph

```
Phase 1 (Context Object)
    |
    +---> Phase 4 (Batched Writes) ---> Phase 5 (Temporal Queries)
    |                                        |
    +---> Phase 8 (Extract Substrate) <------+---> Phase 6 (Datalog)
    |
    +---> Phase 9 (Hook Ordering)

Phase 2 (CLI Providers)  [independent]

Phase 3 (Operation Layer) [independent]

Phase 7 (HTTP Client)    [independent]
```

**Phase 1 is the prerequisite** for phases 4, 5, 6, 8, 9 (all substrate changes).
**Phases 2, 3, 7 are independent** — can be done in any order, in parallel with substrate work.
**Phase 8 should come after** 4, 5, 6 are done (extract a complete substrate, not a partial one).

## Recommended Execution Order

1. **Phase 1** — Context object (unblocks everything else)
2. **Phase 2** — CLI providers (quick win, independent)
3. **Phase 4** — Batched writes (small, high-value)
4. **Phase 5** — Temporal queries (completes the substrate's read path)
5. **Phase 6** — Datalog (the big new capability)
6. **Phase 3** — Operation layer (bigger refactor, defer a bit)
7. **Phase 7** — HTTP client (can happen anytime)
8. **Phase 9** — Hook ordering (nice-to-have, low urgency)
9. **Phase 8** — Extract substrate (capstone, do last when substrate is complete)

## Open Questions

None. All decisions resolved:
- Substrate stays in ap/ as separate ASDF system (user decision)
- Datalog: interpreted + compiled (user decision)
- Bubble integration: deferred (user decision)
- Entity identity: keep ap's monotonic counters (u64 entity, u32 attribute) — proven, simpler than SHA-256 interning for this use case
- Hook ordering via priority + topological sort (standard approach)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Context object breaks thread isolation | High — silent data corruption | Run full test suite after Phase 1; add thread-safety specific tests |
| `define-cli-provider` macro can't handle all 5 parsers | Medium — some providers stay manual | Allow `:parser` to be a custom function as escape hatch |
| Operation layer macro too rigid | Medium — some operations need custom handling | Keep explicit handler as fallback; only macro-ify the 20 that overlap |
| Datalog join performance on large stores | Low — only matters at scale | Start interpreted, profile, optimize hot paths with compile-query |
| Package rename during extraction (Phase 8) | Medium — breaks downstream code | Use package nicknames for backward compat |
| LMDB cursor lifetime management in temporal queries | Medium — cursor leaks | Follow bubble's pattern: cursor within read-txn in unwind-protect |
