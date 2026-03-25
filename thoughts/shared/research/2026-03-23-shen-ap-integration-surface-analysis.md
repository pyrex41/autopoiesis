---
date: 2026-03-23T19:29:57Z
researcher: Claude
git_commit: b6eac4193625e3581c1c73f1d7efb84b3b3933c0
branch: main
repository: autopoiesis
topic: "Shen-AP Integration Surface Analysis: Mapping all codebase integration points for Shen language verification layer"
tags: [research, codebase, shen, type-system, self-modification, extension-compiler, persistent-agent, snapshot, jarvis, threading]
status: complete
last_updated: 2026-03-23
last_updated_by: Claude
---

# Research: Shen-AP Integration Surface Analysis

**Date**: 2026-03-23T19:29:57Z
**Researcher**: Claude
**Git Commit**: b6eac4193625e3581c1c73f1d7efb84b3b3933c0
**Branch**: main
**Repository**: autopoiesis

## Research Question

Map all codebase integration points for adding a Shen programming language verification layer to the Autopoiesis platform. Identify the exact files, functions, data structures, and flows that the Shen integration (Phases 0-5) needs to connect to, without modifying AP's substrate, snapshot DAG core, conductor, or web console.

## Summary

The Shen integration has **six primary attachment surfaces** in the existing codebase:

1. **Extension compiler validation pipeline** — where Shen type checking inserts (between proposal and compilation)
2. **Persistent agent struct** — where new Shen fields (invariants, capability-types, knowledge-base) are added
3. **Agent self-modification flow** — the define→test→promote pipeline and persistent membrane that the verifier wraps
4. **Snapshot metadata** — where proofs are stored in the DAG
5. **ASDF system definition** — where the new `autopoiesis/shen` module is registered
6. **Jarvis dispatch** — where the Shen REPL tool is exposed

No prior research on Shen, sequent calculus, or formal verification exists in the thoughts/ directory — this is entirely new territory for the platform.

## Detailed Findings

### 1. Extension Compiler & Sandbox Validation Pipeline

**Files:**
- `platform/src/core/extension-compiler.lisp` — Core validation and compilation
- `platform/src/core/packages.lisp` — Exports (lines 192-223)

**Current validation flow** (the exact point where Shen verification inserts):

```
agent-define-capability (agent-capability.lisp:80)
  └─ validate-extension-code (extension-compiler.lisp:212)
       └─ validate-extension-source (extension-compiler.lisp:232)
            └─ recursive check-form walker:
                 - *sandbox-forbidden-patterns* scan
                 - check-forbidden-operator (*forbidden-symbols*)
                 - check-package (*allowed-packages*)
                 - check-operator (*sandbox-allowed-symbols* ∪ *allowed-special-forms*)
            returns: (values valid-p errors)
       └─ (compile nil full-code) → compiled function
```

**Key function signature:**
`validate-extension-source (source &key (sandbox-level :strict)) → (values valid-p errors)`

The sandbox validator is a recursive S-expression walker. It checks syntax and forbidden symbols but **does not check semantic correctness** — this is exactly the gap Shen fills. The Shen verification step should insert between `validate-extension-source` returning success and `(compile nil full-code)` being called.

**Sandbox configuration variables** (all exported from `autopoiesis.core`):
- `*allowed-packages*` — 6 package name strings (line 64)
- `*forbidden-symbols*` — ~30 symbols never allowed in operator position (line 69)
- `*allowed-special-forms*` — whitelist of safe control structures (line 94)
- `*sandbox-allowed-symbols*` — ~130 symbols for `:strict` mode (line 114)
- `*sandbox-forbidden-patterns*` — alist of `(symbol . reason)` pairs (line 178)

**`compile-extension` (line 389):** Takes `(name source &key author dependencies sandbox-level)`, validates, wraps in `(lambda () ,source)` thunk, compiles, returns `(values extension errors)`. The compiled thunk takes no arguments; `invoke-extension` uses `apply` for argument passing.

**`register-extension` (line 478):** Used by agent-level code. Wraps source in `(lambda () ,code)`, assigns UUID as ext-id, sets status to `:validated`.

**`invoke-extension` (line 521):** Requires status `:validated`. Auto-rejects after >3 errors. Supports `*checkpoint-on-invoke*` hook for supervisor wrapping.

### 2. Agent Self-Modification: The Define→Test→Promote Pipeline

**Files:**
- `platform/src/agent/agent-capability.lisp` — Three-step mutable agent flow
- `platform/src/integration/builtin-tools.lisp` — Tool interface for LLM agents

**The `agent-capability` class** (agent-capability.lisp:12-44) extends base `capability` with:
- `source-agent` — ID of authoring agent
- `source-code` — full `(lambda ...)` form as data
- `extension-id` — UUID (not same as extension registry key)
- `test-results` — plist results from testing
- `promotion-status` — `:draft` → `:testing` → `:promoted` or `:rejected`

**Step 1: `agent-define-capability`** (line 80)
Signature: `(agent name description params body) → (values agent-capability errors)`
- Constructs `full-code` as `(lambda ,lambda-list ,@body)`
- Calls `validate-extension-code full-code` ← **Shen verification inserts here**
- On validation success: `(compile nil full-code)` directly
- Creates `agent-capability` with status `:draft`
- Pushes onto `(agent-capabilities agent)`

**Step 2: `test-agent-capability`** (line 136)
Signature: `(capability test-cases) → (values passed-p results)`
- Sets status to `:testing`
- Each test case: `(apply cap-fn args)`, compare with `equal`
- Stores results in `cap-test-results`

**Step 3: `promote-capability`** (line 207)
Signature: `(capability) → T or NIL`
- Guards: status must be `:testing`, all test results `:pass`
- Optional human approval gate via `make-blocking-request` (dynamically resolved)
- On success: sets status to `:promoted`, calls `register-capability`

**Tool interface** (builtin-tools.lisp, starting line 357):
- `define-capability-tool` (line 361) — parses string inputs from LLM, creates temp agent, calls `agent-define-capability`, registers in global registry
- `test-capability-tool` (line 403) — looks up by name, calls `test-agent-capability`
- `promote-capability-tool` (line 440) — calls `promote-capability`

All three tools have `:permissions (:self-extend)` and are registered via `register-builtin-tools` (line 959).

### 3. Persistent Agent Struct & Membrane

**Files:**
- `platform/src/agent/persistent-agent.lisp` — Struct definition, copy, serialization
- `platform/src/agent/persistent-lineage.lisp` — Fork, diff, merge, ancestry
- `platform/src/agent/persistent-membrane.lisp` — Membrane gating
- `platform/src/agent/persistent-cognition.lisp` — Immutable cognitive cycle
- `platform/src/agent/packages.lisp` — All exports (lines 218-268 for persistent agent)

**The `persistent-agent` struct** (persistent-agent.lisp:13):

| Field | Type | Default | Notes |
|---|---|---|---|
| `id` | `string` | `(make-uuid)` | `:read-only t` |
| `name` | `string` | `"unnamed"` | |
| `version` | `integer` | `0` | Auto-incremented by `copy-persistent-agent` |
| `timestamp` | `number` | `(get-precise-time)` | Updated on every copy |
| `membrane` | pmap | `(pmap-empty)` | Perception/interface layer |
| `genome` | `list` | `nil` | Swarm evolution |
| `thoughts` | pvec | `(pvec-empty)` | Append-only thought log |
| `capabilities` | pset | `(pset-empty)` | Set of capability keywords |
| `heuristics` | `list` | `nil` | List of heuristic objects |
| `children` | `list` | `nil` | Child agent UUIDs |
| `parent-root` | any | `nil` | Parent agent UUID |
| `metadata` | pmap | `(pmap-empty)` | Arbitrary key-value |

**New Shen fields would be added here.** The spec calls for:
- `:shen-invariants` — list of Shen datatype s-expressions
- `:shen-capability-types` — list of Shen type signatures
- `:shen-knowledge-base` — list of defprolog s-expressions (Phase 3)

These can be stored in the `metadata` pmap (using `pmap-put`) without modifying the struct definition, OR added as new struct fields by editing the `defstruct` form. Using `metadata` avoids changing the struct but requires convention-based key lookups.

**`copy-persistent-agent`** (line 116): The sole update mechanism. Accepts keyword args for each mutable slot, auto-increments version, updates timestamp. Unchanged fields share structure (O(1) slot copy of same pmap/pvec/pset reference).

**`persistent-fork`** (persistent-lineage.lisp:12): Returns `(values child updated-parent)`. Child gets fresh UUID, version 0, all data fields shared by reference from parent. O(1) operation.

**Serialization:** `persistent-agent-to-sexpr` (line 63) converts pmaps→alists, pvecs→lists, psets→lists. `sexpr-to-persistent-agent` (line 80) reverses. Adding new fields requires updating both functions.

**Membrane gating** (persistent-membrane.lisp):

- `membrane-allows-p` (line 13): Checks `:allowed-actions` pset in membrane pmap, then optionally calls `validate-extension-source` if `:validate-source` is set. **This is the second insertion point for Shen verification** — the membrane could gate on type-checking in addition to sandbox validation.

- `propose-genome-modification` (line 47): Calls `membrane-allows-p` with `:genome-modification`, then prepends source-form to genome list.

- `promote-to-genome` (line 58): Direct `validate-extension-source` check, then `membrane-allows-p`, then prepends to genome and adds capability name to pset.

### 4. Cognitive Cycle (Mutable & Persistent)

**Files:**
- `platform/src/agent/cognitive-loop.lisp` — Mutable agent cycle
- `platform/src/agent/persistent-cognition.lisp` — Immutable agent cycle

**Mutable `cognitive-cycle`** (cognitive-loop.lisp:50):
```
perceive(agent, environment) → observations
reason(agent, observations) → understanding
decide(agent, understanding) → decision
act(agent, decision) → result  [handler-case wraps errors]
reflect(agent, result) → [always called, even on error]
```
The `reason` phase is where Shen Prolog queries (Phase 3) would integrate — agents can query their knowledge base during reasoning.

**Persistent `persistent-cognitive-cycle`** (persistent-cognition.lisp:146):
Runs perceive→reason→decide→act→reflect as a `let*` chain, each returning a new agent. Thoughts stored as plists in the `thoughts` pvec with `:type` of `:observation`, `:reasoning`, `:decision`, `:action`, `:reflection`.

**`persistent-act`** (line 81): The only phase with side effects — invokes capabilities via `invoke-capability` from the mutable registry if the capability name is in the agent's `capabilities` pset.

### 5. Learning System

**File:** `platform/src/agent/learning.lisp`

**Note:** There is no function named `record-experience` in the codebase. The storage entry point is `store-experience` (line 215), which does `(setf (gethash id store) experience)`.

The spec's `handle-rejected-modification` references `record-experience` — this should use `store-experience` instead, or a new wrapper function.

**Key types:**
- `experience` class (line 12): `task-type` (keyword), `context` (sexpr), `actions` (list), `outcome` (`:success`/`:failure`/`:partial`)
- `heuristic` class (line 104): `condition` (sexpr pattern), `recommendation` (sexpr), `confidence` (float 0.0-1.0)

**Heuristic matching:** `condition-matches-p` (line 324) — recursive pattern matcher supporting `:any`, `(:type ...)`, `(:member ...)`, `(and ...)`, `(or ...)`, `(not ...)`. Shen Prolog could subsume this pattern matching in Phase 3.

### 6. Snapshot System & Metadata

**Files:**
- `platform/src/snapshot/snapshot.lisp` — Snapshot class definition
- `platform/src/snapshot/persistence.lisp` — Serialization, storage, index

**The `snapshot` class** (snapshot.lisp:11-36):

| Slot | Accessor | Notes |
|---|---|---|
| `id` | `snapshot-id` | Auto-generated UUID |
| `timestamp` | `snapshot-timestamp` | `(get-precise-time)` |
| `parent` | `snapshot-parent` | String ID of parent (nil for root) |
| `agent-state` | `snapshot-agent-state` | S-expression of agent state |
| `metadata` | `snapshot-metadata` | **Free-form plist — no schema enforced** |
| `hash` | `snapshot-hash` | SHA256 of `agent-state` only |

**The metadata slot is the exact insertion point for Shen proofs (Phase 4).** It is a free-form plist that already accepts arbitrary key-value pairs. The crystallize layer already uses it for `:crystallized`, `:label`, and `:crystallized-at` keys. Shen proofs would add `:shen-proof`, `:invariants-verified`, and `:verified-at` keys.

**`make-snapshot`** (line 38): Takes `agent-state` required, `:parent` and `:metadata` optional. Hash is computed from `agent-state` only (not metadata).

**Serialization format** (persistence.lisp:69-92): `(snapshot :version 1 :id <id> :timestamp <ts> :parent <parent> :agent-state <state> :metadata <plist> :hash <hash>)`. Metadata survives round-trip serialization as-is.

**Crystallize integration** (`crystallize/snapshot-integration.lisp`):
- `store-crystallized-snapshot` (line 12): Calls `make-snapshot` with agent sexpr as body, metadata includes `:crystallized`, `:label`, `:crystallized-at`
- `crystallize-all` (line 25): Orchestrates capability + heuristic crystallization, calls `store-crystallized-snapshot`

### 7. ASDF System Structure

**File:** `platform/autopoiesis.asd`

The main system `#:autopoiesis` (line 6) uses `:serial t` with all modules under `(:module "src" ...)`. Optional extensions follow a uniform pattern:

```lisp
(asdf:defsystem #:autopoiesis/<name>
  :depends-on (#:autopoiesis [+ any additional libraries])
  :serial t
  :components
  ((:module "src/<name>"
    :serial t
    :components
    ((:file "packages")
     ... implementation files ...))))
```

**Existing optional systems** (for reference when adding `autopoiesis/shen`):

| System | Line | Extra deps | Source path |
|---|---|---|---|
| `autopoiesis/swarm` | 265 | `lparallel` | `src/swarm/` |
| `autopoiesis/supervisor` | 289 | none | `src/supervisor/` |
| `autopoiesis/crystallize` | 307 | none | `src/crystallize/` |
| `autopoiesis/team` | 329 | none | `src/team/` + `src/workspace/` |
| `autopoiesis/jarvis` | 362 | none | `src/jarvis/` |

Each paired with `#:autopoiesis/<name>-test` system that depends on the extension and `fiveam`.

**A new `#:autopoiesis/shen` system** would follow this exact pattern, depending on `#:autopoiesis` and any Shen bootstrap mechanism. Since Shen is not an ASDF system (it bootstraps via `install.lsp`), the ASDF system might need a custom `:perform` method or a pre-load step.

### 8. Jarvis NL Dispatch

**Files:**
- `platform/src/jarvis/dispatch.lisp` — Tool dispatch
- `platform/src/jarvis/loop.lisp` — Conversation loop
- `platform/src/jarvis/session.lisp` — Session state

**Tool registration:** Tools are not registered specifically to Jarvis. They come from the global capability registry (`autopoiesis.agent:list-capabilities`). Any capability in the registry is available to Jarvis sessions. To add a Shen REPL tool, register it as a capability in the global registry.

**Dispatch flow:**
1. `parse-tool-call` (dispatch.lisp:13) — checks for `:TOOL--USE` key in JSON response
2. `dispatch-tool-call` (dispatch.lisp:48) — converts tool name via `tool-name-to-lisp-name`, looks up via `find-capability`
3. `invoke-tool` (dispatch.lisp:28) — converts JSON args to keyword plist, `apply`s capability function

**Supervisor integration:** If supervisor is enabled and available, dispatch wraps tool invocation in checkpoint-and-revert (dispatch.lisp:63-88).

**Adding a Shen REPL tool:** Register a capability named `:shen-typecheck` (or similar) in the global registry. It will automatically be available in Jarvis sessions. The tool function would call `ap/shen:shen-typecheck` or `ap/shen:shen-eval` from the bridge.

### 9. Threading & Concurrency

**Pattern:** AP uses `bordeaux-threads` throughout with per-subsystem locks:
- Substrate: `(bt:make-lock "substrate")` on `store-lock` (substrate/store.lisp)
- Agent mailboxes: `bt:make-lock` + `bt:make-condition-variable` (agent/builtin-capabilities.lisp)
- Dual-agent: `bt:make-recursive-lock "dual-agent-root"` (agent/dual-agent.lisp) — recursive because `:after` methods re-enter
- Conductor: `bt:make-lock "conductor"` + `bt:make-thread` for tick loop (orchestration/conductor.lisp)
- API layer: per-subsystem locks (`*sse-clients-lock*`, `*api-keys-lock*`, `*chat-sessions-lock*`, etc.)

**Implication for Shen:** Shen uses global mutable state (`set`/`value` in the property vector). The spec correctly identifies this: Shen calls must be serialized through a single lock, or each thread needs its own Shen environment. Given AP's existing pattern of per-subsystem locks, a `*shen-lock*` with `bt:with-lock-held` wrapping all `ap/shen:*` calls is the most consistent approach.

## Code References

### Phase 0 (Bridge) touches:
- `platform/autopoiesis.asd` — add `autopoiesis/shen` system definition
- `platform/src/shen-bridge.lisp` (new) — CL-to-Shen interface

### Phase 1 (Invariants) touches:
- `platform/src/agent/persistent-agent.lisp:13` — add shen fields to defstruct (or use metadata pmap)
- `platform/src/agent/persistent-agent.lisp:63` — update `persistent-agent-to-sexpr` for new fields
- `platform/src/agent/persistent-agent.lisp:80` — update `sexpr-to-persistent-agent` for new fields
- `platform/src/agent/persistent-agent.lisp:34` — update `make-persistent-agent` for new keyword args
- `platform/src/agent/persistent-agent.lisp:116` — update `copy-persistent-agent` for new fields
- `platform/src/agent/packages.lisp:218` — export new accessors

### Phase 2 (Verified Self-Modification) touches:
- `platform/src/agent/agent-capability.lisp:80` — `agent-define-capability`: insert Shen verification between validate-extension-code and compile
- `platform/src/agent/persistent-membrane.lisp:13` — `membrane-allows-p`: optionally add Shen type checking
- `platform/src/agent/persistent-membrane.lisp:47` — `propose-genome-modification`: add Shen verification
- `platform/src/agent/persistent-membrane.lisp:58` — `promote-to-genome`: add Shen verification
- `platform/src/agent/learning.lisp:215` — `store-experience` (spec says `record-experience` but that function doesn't exist)

### Phase 3 (Prolog KB) touches:
- `platform/src/agent/persistent-cognition.lisp:39` — `persistent-reason`: add Prolog query integration
- `platform/src/agent/cognitive-loop.lisp:50` — `cognitive-cycle` reason phase

### Phase 4 (Proofs in DAG) touches:
- `platform/src/snapshot/snapshot.lisp:38` — `make-snapshot`: metadata plist already supports arbitrary keys
- `platform/src/crystallize/snapshot-integration.lisp:12` — `store-crystallized-snapshot`: pattern to follow for proof storage
- `platform/src/snapshot/persistence.lisp:69` — serialization already handles arbitrary metadata

### Phase 5 (Type Libraries) touches:
- `platform/src/shen-types/` (new directory) — .shen files

### Jarvis integration:
- `platform/src/jarvis/dispatch.lisp:48` — tool dispatch (no changes needed — just register capability)
- `platform/src/integration/builtin-tools.lisp:946` — add Shen tools to `builtin-tool-symbols` list

## Architecture Documentation

### Self-Modification Pipeline (Current)

Two parallel paths exist for self-modification:

**Mutable agent path** (tool-driven, LLM agentic loop):
```
LLM → define_capability_tool → agent-define-capability → validate-extension-code
    → (compile nil full-code) → agent-capability [status :draft]
LLM → test_capability_tool → test-agent-capability [status :testing]
LLM → promote_capability_tool → promote-capability → register-capability [status :promoted]
```

**Persistent agent path** (membrane-gated, structural):
```
propose-genome-modification → membrane-allows-p → validate-extension-source
    → copy-persistent-agent [genome prepended]
promote-to-genome → validate-extension-source → membrane-allows-p
    → copy-persistent-agent [genome + capabilities updated]
```

Both paths call `validate-extension-source` from the extension compiler. The Shen verifier inserts after this validation returns success.

### Persistent Data Structure Pattern

All persistent agent state uses fset wrappers (`pmap`, `pvec`, `pset`). Updates are non-destructive:
- `pmap-put` returns new pmap
- `pvec-push` returns new pvec
- `pset-add` returns new pset
- `copy-persistent-agent` returns new struct with selected fields replaced

Shen state (invariants, KB, capability types) stored as persistent data structures will automatically participate in O(1) forking and structural sharing.

### Snapshot Metadata Convention

The metadata slot on snapshots is a free-form plist. Current users:
- Crystallize layer: `:crystallized`, `:label`, `:crystallized-at`
- No schema enforcement — any keys are accepted

Shen would add: `:shen-proof`, `:invariants-verified`, `:verified-at`

## Historical Context (from thoughts/)

No prior research on Shen, sequent calculus, dependent types, or formal verification exists in the thoughts/ directory. The closest related documents are:

- `thoughts/shared/research/2026-02-16-substrate-extension-points-gap-analysis.md` — Gap analysis of substrate extension points; relevant to understanding where verification layers attach
- `thoughts/shared/research/2026-02-06-super-agent-synthesis.md` — Agent invariants, capability restrictions, membrane/guard concepts
- `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — Meta-agent feasibility with picoclaw/rho-calculus references
- `thoughts/shared/research/2026-03-02-platform-architecture-deep-dive.md` — Deep dive into current platform architecture
- `thoughts/shared/research/2026-02-18-baml-integration-surface-analysis.md` — BAML typed LLM function surface analysis (type-checking adjacent)
- `thoughts/shared/plans/2026-03-02-three-layer-autopoietic-agents.md` — Three-layer agent architecture plan
- `thoughts/shared/plans/ap-substrate-evolution.md` — Substrate evolution plan with extension/hook points

## Related Research

- `thoughts/shared/research/2026-03-02-platform-architecture-deep-dive.md` — comprehensive architecture reference
- `thoughts/shared/research/2026-02-16-substrate-extension-points-gap-analysis.md` — extension point analysis

## Open Questions

1. **Struct fields vs metadata pmap:** Should Shen state be added as new `defstruct` fields on `persistent-agent` (explicit, type-safe, requires serialization updates) or stored in the `metadata` pmap (zero struct changes, convention-based key lookups)? The spec assumes dedicated fields.

2. **`record-experience` doesn't exist:** The spec's `handle-rejected-modification` calls `record-experience` which is not in the codebase. The actual storage function is `store-experience`. Either the spec should be updated or a new `record-experience` wrapper should be created.

3. **Shen as ASDF dependency:** Shen bootstraps via `install.lsp`, not ASDF. The `autopoiesis/shen` system definition needs a strategy for ensuring Shen is loaded — possibly a custom `:perform` method, a feature check, or a load-time side effect in the packages file.

4. **Thread isolation strategy:** A single `*shen-lock*` serializing all Shen calls is simplest but could be a bottleneck. Per-agent Shen environments would require significant Shen internals knowledge. The lock approach matches AP's existing concurrency patterns.

5. **Mutable vs persistent path divergence:** The mutable agent path (define→test→promote via tools) and persistent agent path (membrane→genome) are separate code paths. Shen verification needs to be wired into both, or the paths need to be unified.

6. **Capability compilation timing:** In `agent-define-capability`, the code is compiled immediately after sandbox validation (line 108-112). Shen type checking should happen before compilation. But the Shen type checker needs Shen-format code, not CL lambdas — translation is required.
