# Three-Layer Autopoietic Agent Evolution Plan

**Date:** 2026-03-02
**Status:** PROPOSED
**Reviewed:** 2026-03-03
**Scope:** Major feature evolution — persistent functional core, ECS embodiment, parallel metabolism
**Estimated Effort:** ~40 SCUD tasks across 8 waves

---

> **Review Notes (2026-03-03)**
>
> The core insight — agents *are* persistent trees, not objects that *produce* snapshots —
> is architecturally correct. The three-layer decomposition and bridge compatibility
> (`dual-agent`) are well-designed. However, the plan was written before `swarm/`,
> `supervisor/`, `crystallize/` modules were added, creating major redundancy in later waves.
> The Bend/HVM GPU layer is not implementable as specified.
>
> **Critical issues:**
>
> 1. **Wave 0: Don't reinvent persistent data structures.** Implementing a HAMT, 32-way trie
>    vector, and persistent set from scratch is a multi-month correctness minefield (Clojure's
>    PersistentVector took months of iteration). Use the `fset` library instead — it provides
>    mature, tested persistent maps/sequences/sets. Wrap with `pmap-*`, `pvec-*`, `pset-*` API
>    names. This reduces Wave 0 from ~6 weeks to ~1 week.
>
> 2. **Wave 4: Duplicates `autopoiesis.swarm`.** The existing swarm module already implements:
>    `genome` class, `population` class, `evolve-generation`, `run-evolution`, `production-rule`
>    class, `apply-production-rules`, fitness evaluation, tournament/roulette/elitism selection,
>    crossover, mutation. Wave 4 should *integrate* persistent agents with the existing swarm
>    module, not recreate it in `autopoiesis.agent`. Replace with:
>    - Task 4.1: Bridge `persistent-agent` to `autopoiesis.swarm.genome`
>    - Task 4.2: Extend `evolve-generation` to operate on persistent agents
>    - Task 4.3: Expose swarm population to Holodeck
>
> 3. **Wave 5: Bend/HVM is not implementable as specified.** Three problems:
>    - Production rules in Bend only get content *hashes* (u64), not evaluable S-expressions.
>      Bend cannot apply CL lambdas — it can only operate on Bend ADTs. `apply_transform` in
>      `metabolism.bend` would be operating on hash integers, not actual code.
>    - HVM shared memory with external runtimes has no stable API. The "Apple M unified memory
>      mmap" option has no implementation basis in current HVM tooling.
>    - Subprocess serialization latency negates GPU benefits for populations < 10,000 agents.
>    **Recommendation:** Demote to a single research spike task. Gate remaining tasks on the
>    prototype demonstrating measurable speedup over `lparallel`.
>
> **Moderate issues:**
>
> 4. **`persistent-cognitive-cycle` purity claim is contradicted by design.** The `persistent-act`
>    function invokes capabilities from the global mutable `*capability-registry*` — capabilities
>    call into substrate, spawn threads, make HTTP requests. Rename success criterion from "Purity"
>    to "Immutability" (old root unchanged after step). The *state transitions* are pure; the act
>    phase is effectful.
>
> 5. **`agent-merge` is underspecified.** Merging divergent agent trees requires semantic understanding
>    of what genome modifications *mean*, not just structural S-expression diffing. Two agents with
>    conflicting capability additions or incompatible heuristic weights cannot be merged structurally.
>    The existing `merge-branches` in snapshot is also unimplemented. Scope to "append-only merge"
>    (union of thoughts, latest-wins for genome) or defer entirely.
>
> 6. **`dual-agent` threading hazard.** The persistent root *pointer* on `dual-agent` is a mutable
>    CLOS slot. Multiple threads (conductor tick loop, Claude workers) calling `(setf agent-state)`
>    will race on this slot. Needs per-agent lock or `sb-ext:cas`.
>
> 7. **Gap analysis is outdated.** The "What's Missing" section should acknowledge:
>    - `autopoiesis.swarm` already provides population-level operations
>    - `autopoiesis.supervisor` already provides checkpoint-and-revert via `with-checkpoint`
>    - `autopoiesis.crystallize` already extracts capabilities/genomes/heuristics to files
>    - Task 1.5 `persistent-snapshot-bridge` should build on existing `with-checkpoint`
>
> **What's valuable and should be kept:**
>
> - Layer 1 persistent functional core design (after using `fset` for data structures)
> - `dual-agent` bridge strategy for backward compatibility
> - Wave dependency DAG ordering
> - ECS embodiment components (Wave 2) — no overlap with existing code
> - Concrete test assertion targets per task
> - LOC estimates are realistic (~6,000 LOC across 33 files)
> - Fallback-first risk management approach

---

## Executive Summary

This plan evolves the Autopoiesis agent platform from mutable in-memory agents to a three-layer architecture where:

1. **Persistent Functional Core** — Every agent is an immutable S-expression tree with structural sharing. `agent-step` is a pure function returning a new root. The existing snapshot DAG becomes the agent's native representation.
2. **ECS Embodiment Layer** — Holodeck's cl-fast-ecs gains components that bind to persistent agent roots, enabling real-time 3D visualization of agent cognition, lineage, and evolution.
3. **Parallel Metabolism Layer** — A Bend/HVM-backed engine applies production rules across populations of agents on GPU, enabling massively parallel self-reproduction and evolution.

The key insight: agents don't *produce* snapshots — agents *are* persistent trees, and snapshots are just pointers into the shared structure. This eliminates serialization overhead, makes branching O(1), and gives every cognitive step automatic version history.

---

## Current State Analysis

### What Exists (strengths to build on)

| Component | Location | Status | Integration Point |
|-----------|----------|--------|-------------------|
| Agent class (CLOS) | `agent/agent.lisp` | Mutable, 7 slots | Will become a view over persistent tree |
| Cognitive loop (PRDAR) | `agent/cognitive-loop.lisp` | 5 generic functions | Each phase becomes a pure tree transform |
| Capability registry | `agent/capability.lisp` | Hash-table global | Persistent set per agent |
| Extension compiler | `core/extension-compiler.lisp` | Sandboxed eval | Genome modification engine |
| Learning system | `agent/learning.lisp` | Experience/heuristic | Pattern→heuristic as tree operations |
| Agent spawner | `agent/spawner.lisp` | Parent/child refs | Fork = share tree + cons new root |
| Snapshot DAG | `snapshot/` | Content-addressed SHA256 | Becomes the persistent tree backend |
| Content store | `snapshot/content-store.lisp` | Hash→content + refcount | Backing for structural sharing |
| Diff engine | `core/s-expr.lisp` | `sexpr-diff`/`sexpr-patch` | Minimal edit computation |
| Holodeck ECS | `holodeck/` | 11 components, 3 systems | Gains persistent-root binding |
| Substrate datoms | `substrate/` | EAV + Linda + LMDB | Mutable coordination layer |
| Agentic loop | `integration/agentic-agent.lisp` | Multi-turn LLM tool use | Records turns as persistent thoughts |
| Agent serialization | `agent/agent.lisp` | `agent-to-sexpr`/`sexpr-to-agent` | Becomes the persistent tree format |

### What's Missing (gaps this plan fills)

1. **No persistent data structures** — Agent state is mutable CLOS objects; snapshotting requires explicit serialization
2. **No immutable agent representation** — Agents can't cheaply fork, branch, or time-travel without full copy
3. **Holodeck doesn't bind to agent internals** — Visualization shows snapshots but not live cognitive state
4. **No population-level operations** — Can't evolve 1000 agents simultaneously
5. **Spawner is shallow** — `spawn-with-snapshot` is a placeholder; lineage traversal is incomplete
6. **Learning is disconnected** — Experiences/heuristics stored separately, not as part of agent tree

---

## Architecture Design

### Layer 1: Persistent Functional Core

**Principle:** Every agent is a single pointer to an immutable tree. All cognitive operations return new roots. Old versions persist via structural sharing.

```
persistent-agent-root
├── :id          → UUID
├── :version     → SHA256 of entire tree
├── :timestamp   → creation time
├── :membrane    → persistent-map of boundary rules
│   ├── :allowed-packages → (:cl :autopoiesis.core ...)
│   ├── :max-depth        → 10
│   └── :sandbox-level    → :strict
├── :genome      → persistent-list of S-expressions (code-as-data)
│   ├── (lambda (x) (+ x 1))    ; capability source 1
│   ├── (lambda (obs) ...)       ; perceive override
│   └── ...
├── :thoughts    → persistent-vector of (:phase :content :timestamp) triples
│   ├── (:observe "user said hello" 1709337600)
│   ├── (:reason  "greeting detected" 1709337601)
│   └── ...
├── :capabilities → persistent-set of capability keywords
│   ├── :introspect
│   ├── :spawn
│   └── :communicate
├── :heuristics  → persistent-list of heuristic S-expressions
├── :children    → persistent-list of child root pointers
├── :parent-root → pointer to parent's root (or nil)
└── :metadata    → persistent-map of additional properties
```

**Key operations (all pure functions):**

```lisp
;; Core step — returns new root, old root unchanged
(agent-step root observation) → new-root

;; Fork — O(1), shares entire tree
(agent-fork root &key mutation) → new-root

;; Diff — structural comparison
(agent-diff root-a root-b) → edit-list

;; Merge — apply edits from one lineage to another
(agent-merge base-root branch-root) → merged-root

;; Time-travel — just follow parent-root pointers
(agent-ancestor root n) → nth-ancestor-root
```

### Layer 2: ECS Embodiment

**Principle:** The Holodeck's cl-fast-ecs provides the "body" — a cache-friendly, real-time view of the persistent agent tree. Components are derived from the tree; systems animate them.

**New ECS components:**

```lisp
(defcomponent persistent-root ()
  (root-pointer nil))    ; Pointer to persistent agent tree

(defcomponent cognitive-state ()
  (phase :idle)          ; Current cognitive phase
  (thought-count 0)      ; Number of thoughts
  (last-thought-hash 0)) ; For change detection

(defcomponent genome-state ()
  (capability-count 0)   ; Number of capabilities
  (genome-hash 0)        ; For change detection
  (mutation-count 0))    ; Total self-modifications

(defcomponent lineage ()
  (parent-entity 0)      ; ECS entity of parent agent
  (child-count 0)        ; Number of children
  (generation 0)         ; Depth from root agent
  (fork-type :spawn))    ; :spawn, :fork, :branch

(defcomponent metabolic-state ()
  (energy 1.0)           ; Current metabolic energy
  (production-rate 0.0)  ; Self-production rate
  (fitness 0.0))         ; Evaluated fitness score
```

**New ECS systems:**

```lisp
;; Sync persistent tree → ECS components (runs each frame)
(defsystem persistent-sync-system ...)

;; Animate based on cognitive phase
(defsystem cognitive-animation-system ...)

;; Draw lineage connections between agents
(defsystem lineage-rendering-system ...)

;; Highlight metabolically active agents
(defsystem metabolic-glow-system ...)
```

### Layer 3: Parallel Metabolism (Bend/HVM)

**Principle:** When population-level operations are needed (evolve N agents, apply production rules across a swarm), hand the array of root pointers to Bend, which exploits GPU parallelism via HVM's interaction net reduction.

**Operations:**

```
apply-production-rules(roots, rules) → new-roots
evaluate-fitness(roots, environment) → scored-roots
select-and-reproduce(scored-roots, params) → next-generation
```

**Integration:** SBCL ↔ Bend via shared memory (Apple M unified memory) or serialized root exchange.

---

## Implementation Plan

### Wave 0: Foundation — Persistent Data Structures (4 tasks)

These provide the building blocks for the persistent agent tree.

#### Task 0.1: Persistent Map (persistent-map.lisp)
**File:** `platform/src/core/persistent-map.lisp`
**Package:** `autopoiesis.core`

Implement a persistent (immutable) association map using a hash-array-mapped trie (HAMT) or red-black tree.

**API:**
```lisp
(pmap-empty)                          ; → empty persistent map
(pmap-get map key &optional default)  ; → value (O(log n))
(pmap-put map key value)              ; → new-map (O(log n), shares structure)
(pmap-remove map key)                 ; → new-map
(pmap-contains-p map key)             ; → boolean
(pmap-keys map)                       ; → list of keys
(pmap-values map)                     ; → list of values
(pmap-count map)                      ; → integer
(pmap-merge map1 map2 &key resolver) ; → new-map (union, resolver for conflicts)
(pmap-to-alist map)                   ; → association list
(alist-to-pmap alist)                 ; → persistent map
(pmap-equal map1 map2)               ; → boolean
(pmap-hash map)                       ; → SHA256 structural hash
```

**Implementation:** Red-black tree (simpler than HAMT, sufficient for agent-sized maps of ~20-100 keys). Structural sharing via shared subtrees.

**Tests:** 40+ assertions covering creation, insert, delete, merge, structural sharing verification (eq on shared subtrees), hash consistency.

**Depends on:** Nothing (pure data structure)

#### Task 0.2: Persistent Vector (persistent-vector.lisp)
**File:** `platform/src/core/persistent-vector.lisp`
**Package:** `autopoiesis.core`

Implement a persistent (immutable) indexed vector using a bit-partitioned trie (Bagwell-style, like Clojure's PersistentVector).

**API:**
```lisp
(pvec-empty)                          ; → empty persistent vector
(pvec-push vec element)               ; → new-vec with element appended (O(log32 n) ≈ O(1))
(pvec-ref vec index)                  ; → element at index (O(log32 n))
(pvec-set vec index value)            ; → new-vec with updated element
(pvec-pop vec)                        ; → (values new-vec popped-element)
(pvec-length vec)                     ; → integer
(pvec-last vec &optional n)           ; → last n elements as list
(pvec-slice vec start &optional end)  ; → list of elements
(pvec-to-list vec)                    ; → list
(list-to-pvec list)                   ; → persistent vector
(pvec-map fn vec)                     ; → new-vec with fn applied
(pvec-reduce fn vec initial)          ; → accumulated result
(pvec-equal vec1 vec2)               ; → boolean
(pvec-hash vec)                       ; → SHA256 structural hash
```

**Implementation:** 32-way branching trie. Each node is a 32-element array. Tail optimization for fast appends. Structural sharing on all non-modified paths.

**Tests:** 50+ assertions covering push, pop, random access, structural sharing, large vectors (10K+), hash consistency.

**Depends on:** Nothing (pure data structure)

#### Task 0.3: Persistent Set (persistent-set.lisp)
**File:** `platform/src/core/persistent-set.lisp`
**Package:** `autopoiesis.core`

Implement a persistent (immutable) set backed by the persistent map (keys only).

**API:**
```lisp
(pset-empty)                          ; → empty persistent set
(pset-add set element)                ; → new-set
(pset-remove set element)             ; → new-set
(pset-contains-p set element)         ; → boolean
(pset-count set)                      ; → integer
(pset-union set1 set2)               ; → new-set
(pset-intersection set1 set2)        ; → new-set
(pset-difference set1 set2)          ; → new-set
(pset-to-list set)                   ; → list
(list-to-pset list)                  ; → persistent set
(pset-equal set1 set2)              ; → boolean
(pset-hash set)                      ; → SHA256 structural hash
```

**Tests:** 30+ assertions covering set operations, structural sharing, hash consistency.

**Depends on:** Task 0.1 (persistent-map)

#### Task 0.4: Core Package Exports & ASDF Registration
**File:** `platform/src/core/packages.lisp`, `platform/autopoiesis.asd`

Add all persistent data structure exports to `autopoiesis.core` package. Register new files in ASDF system (after `s-expr.lisp`, before `cognitive-primitives.lisp`).

**Tests:** Compilation and symbol accessibility tests.

**Depends on:** Tasks 0.1, 0.2, 0.3

---

### Wave 1: Persistent Agent Core (5 tasks)

Build the immutable agent representation on top of the persistent data structures.

#### Task 1.1: Persistent Agent Structure (persistent-agent.lisp)
**File:** `platform/src/agent/persistent-agent.lisp`
**Package:** `autopoiesis.agent`

Define the persistent agent tree as a nested persistent data structure.

```lisp
(defstruct persistent-agent
  (id nil)                 ; UUID string
  (version nil)            ; SHA256 of tree
  (timestamp 0)            ; Creation time
  (membrane (pmap-empty))  ; Boundary rules
  (genome nil)             ; List of S-expression source forms
  (thoughts (pvec-empty))  ; Persistent vector of thought plists
  (capabilities (pset-empty)) ; Persistent set of capability keywords
  (heuristics nil)         ; List of heuristic S-expressions
  (children nil)           ; List of child root pointers
  (parent-root nil)        ; Previous version's root
  (metadata (pmap-empty))) ; Additional properties
```

**Core operations:**
```lisp
(make-persistent-agent &key name capabilities membrane)
(persistent-agent-hash agent)  ; Compute SHA256 of entire tree
(persistent-agent-to-sexpr agent) ; Serialize to S-expression
(sexpr-to-persistent-agent sexpr) ; Deserialize
```

**Tests:** 30+ assertions for creation, serialization round-trip, hash consistency, structural equality.

**Depends on:** Wave 0 (all persistent data structures)

#### Task 1.2: Pure Cognitive Operations (persistent-cognition.lisp)
**File:** `platform/src/agent/persistent-cognition.lisp`
**Package:** `autopoiesis.agent`

Implement each cognitive phase as a pure function that takes a persistent-agent and returns a new one.

```lisp
;; Append observation to thoughts vector
(persistent-perceive agent observation)
  → new-agent with observation appended to thoughts

;; Analyze recent thoughts, produce reasoning
(persistent-reason agent)
  → new-agent with reasoning thought appended

;; Choose action based on understanding + heuristics
(persistent-decide agent alternatives)
  → new-agent with decision thought appended

;; Execute action (may modify genome via extension compiler)
(persistent-act agent decision capabilities-registry)
  → new-agent with action result appended

;; Reflect on outcome, potentially generate heuristic
(persistent-reflect agent action-result)
  → new-agent with reflection thought appended

;; Full cycle — compose all five phases
(persistent-cognitive-cycle agent observation environment)
  → new-agent (all phases applied, new version hash computed)
```

Each function returns a brand-new `persistent-agent` struct sharing 99%+ of the tree with the old version.

**Tests:** 50+ assertions covering each phase independently, full cycle, structural sharing (old agent unchanged), thought accumulation.

**Depends on:** Task 1.1

#### Task 1.3: Agent Forking and Lineage (persistent-lineage.lisp)
**File:** `platform/src/agent/persistent-lineage.lisp`
**Package:** `autopoiesis.agent`

Implement branching, forking, and lineage as operations on persistent trees.

```lisp
;; Fork — create child sharing parent's tree
(persistent-fork agent &key name mutation)
  → child-agent (shares parent's thoughts/genome, has own id)

;; Diff two agents
(persistent-agent-diff agent-a agent-b)
  → edit-list (structural diff of their trees)

;; Merge — apply branch's changes to base
(persistent-agent-merge base branch &key conflict-resolver)
  → merged-agent

;; Walk ancestors (follow parent-root chain)
(persistent-ancestors agent &optional max-depth)
  → list of ancestor agents

;; Find common ancestor
(persistent-common-ancestor agent-a agent-b)
  → common-ancestor-agent (or nil)

;; Lineage depth
(persistent-generation agent)
  → integer (distance from root ancestor)
```

**Tests:** 40+ assertions covering fork-share, diff symmetry, merge correctness, ancestor traversal, common ancestor finding.

**Depends on:** Task 1.1

#### Task 1.4: Membrane and Self-Modification (persistent-membrane.lisp)
**File:** `platform/src/agent/persistent-membrane.lisp`
**Package:** `autopoiesis.agent`

Implement the autopoietic membrane — boundary rules that govern what can cross into/out of the agent.

```lisp
;; Check if a capability can cross the membrane
(membrane-allows-p membrane capability-source)
  → boolean

;; Update membrane rules (returns new membrane)
(membrane-update membrane key value)
  → new-membrane

;; Self-modification: agent proposes genome change
(propose-genome-modification agent new-code)
  → (values modified-agent validation-errors)
  ;; Uses extension-compiler validation
  ;; Membrane enforces sandbox-level
  ;; Returns new agent with modified genome if valid

;; Promote tested capability into genome
(promote-to-genome agent capability-name test-results)
  → new-agent with capability added to genome and capabilities set
```

The membrane integrates with `autopoiesis.core:validate-extension-source` for sandboxing.

**Tests:** 40+ assertions covering membrane rules, validation, rejection of unsafe code, promotion workflow.

**Depends on:** Task 1.1, core extension-compiler

#### Task 1.5: Snapshot DAG Integration (persistent-snapshot-bridge.lisp)
**File:** `platform/src/agent/persistent-snapshot-bridge.lisp`
**Package:** `autopoiesis.agent`

Bridge persistent agents to the existing snapshot system. Each persistent-agent version becomes a snapshot node in the DAG.

```lisp
;; Store a persistent agent version as a snapshot
(persist-agent-version agent &key store)
  → snapshot-id (SHA256 hash)

;; Retrieve a persistent agent from snapshot store
(restore-persistent-agent snapshot-id &key store)
  → persistent-agent

;; Create snapshot from agent step (automatic)
(with-persistent-tracking (agent &key store)
  body...)
  ;; Every agent-step inside body auto-snapshots

;; Bridge: convert mutable agent ↔ persistent agent
(agent-to-persistent agent)
  → persistent-agent (from current mutable agent)

(persistent-to-agent persistent-agent)
  → agent (mutable CLOS agent from persistent tree)
```

**Tests:** 40+ assertions covering round-trip persistence, snapshot DAG structure, content-addressing, bridge conversions.

**Depends on:** Tasks 1.1-1.4, snapshot layer

---

### Wave 2: ECS Embodiment Components (4 tasks)

Extend the Holodeck to visualize persistent agents.

#### Task 2.1: Persistent Agent ECS Components (holodeck-agent-components.lisp)
**File:** `platform/src/holodeck/agent-components.lisp`
**Package:** `autopoiesis.holodeck`

Define new cl-fast-ecs components for persistent agent visualization.

```lisp
(defcomponent persistent-root ()
  (root-pointer nil)       ; Pointer to persistent-agent struct
  (version-hash 0)         ; For change detection
  (dirty-p 0))             ; 1 if needs resync

(defcomponent cognitive-state ()
  (phase 0)                ; Encoded phase: 0=idle 1=perceive 2=reason 3=decide 4=act 5=reflect
  (thought-count 0)        ; Number of thoughts in vector
  (last-thought-hash 0))   ; Hash of last thought for change detection

(defcomponent genome-state ()
  (capability-count 0)     ; Size of capabilities set
  (genome-size 0)          ; Number of genome entries
  (mutation-count 0)       ; Total self-modifications
  (genome-hash 0))         ; Hash of genome for change detection

(defcomponent lineage-binding ()
  (parent-entity 0)        ; ECS entity ID of parent agent
  (child-count 0)          ; Number of children
  (generation 0)           ; Depth from root ancestor
  (fork-type 0))           ; 0=spawn, 1=fork, 2=branch, 3=merge

(defcomponent metabolic-state ()
  (energy 1.0)             ; Current energy level (0.0-1.0)
  (production-rate 0.0)    ; Self-production events per second
  (fitness 0.0)            ; Evaluated fitness (0.0-1.0)
  (last-step-time 0.0))    ; When last cognitive step occurred
```

**Tests:** 20+ assertions covering component creation, field access, type safety.

**Depends on:** Wave 0 complete, Holodeck ECS infrastructure

#### Task 2.2: Agent Materialization System (holodeck-agent-systems.lisp)
**File:** `platform/src/holodeck/agent-systems.lisp`
**Package:** `autopoiesis.holodeck`

ECS systems that derive visual state from persistent agent trees.

```lisp
;; Sync persistent tree → ECS components
(defsystem persistent-sync-system
  (:components-rw (persistent-root cognitive-state genome-state)
   :before (movement-system))
  ;; If version-hash changed, update cognitive-state and genome-state
  ;; from the persistent tree
  ...)

;; Animate visual properties based on cognitive phase
(defsystem cognitive-animation-system
  (:components-rw (cognitive-state visual-style scale3d)
   :after (persistent-sync-system))
  ;; Phase → color transition, glow intensity, pulse rate
  ;; perceive=blue, reason=gold, decide=orange, act=green, reflect=purple
  ...)

;; Update lineage connections
(defsystem lineage-system
  (:components-rw (lineage-binding position3d)
   :after (persistent-sync-system))
  ;; Position children relative to parent
  ;; Draw connection entities for parent-child relationships
  ...)

;; Metabolic glow based on energy/fitness
(defsystem metabolic-glow-system
  (:components-rw (metabolic-state visual-style)
   :after (persistent-sync-system))
  ;; High energy = bright glow, low = dim
  ;; High fitness = green tint, low = red tint
  ...)
```

**Tests:** 30+ assertions covering sync correctness, animation state transitions, lineage layout.

**Depends on:** Task 2.1

#### Task 2.3: Agent Entity Factory (holodeck-agent-entities.lisp)
**File:** `platform/src/holodeck/agent-entities.lisp`
**Package:** `autopoiesis.holodeck`

Factory functions to materialize persistent agents as ECS entities.

```lisp
;; Create ECS entity from persistent agent
(make-persistent-agent-entity agent &key x y z)
  → entity-id

;; Create full agent tree in ECS (agent + all children recursively)
(materialize-agent-tree root-agent &key layout-fn)
  → list of entity-ids

;; Remove agent entity and its connections
(remove-agent-entity entity-id)

;; Update entity from new persistent agent version
(update-agent-entity entity-id new-agent)

;; Layout function: position agents in 3D space based on lineage
(default-agent-layout agent generation sibling-index)
  → (values x y z)
```

**Tests:** 30+ assertions covering entity creation, tree materialization, update, removal.

**Depends on:** Tasks 2.1, 2.2

#### Task 2.4: Holodeck Integration & HUD Updates
**File:** `platform/src/holodeck/window.lisp` (modifications), `platform/src/holodeck/hud.lisp` (modifications)
**Package:** `autopoiesis.holodeck`

Wire persistent agent entities into the main Holodeck frame loop and update HUD panels.

**Changes to window.lisp:**
- `setup-scene` initializes agent-related systems
- `holodeck-frame` runs new systems (persistent-sync, cognitive-animation, lineage, metabolic-glow)
- `collect-agent-render-descriptions` added alongside snapshot descriptions
- Agent sync uses persistent roots instead of mutable agent pointers

**Changes to hud.lisp:**
- New "Agent Detail" panel showing: phase, thought count, genome size, capabilities, generation, energy
- Updated "Timeline" panel to show agent version history
- New "Lineage" panel showing parent/child tree

**Tests:** 20+ assertions for integration, HUD content, frame loop stability.

**Depends on:** Tasks 2.1-2.3

---

### Wave 3: Bridge Layer — Mutable ↔ Persistent (4 tasks)

Make existing mutable agents work seamlessly with persistent agents.

#### Task 3.1: Dual-Mode Agent Wrapper (dual-agent.lisp)
**File:** `platform/src/agent/dual-agent.lisp`
**Package:** `autopoiesis.agent`

A wrapper that presents a mutable CLOS interface while backed by a persistent tree internally. This allows existing code (agentic-agent, provider-backed-agent) to work unchanged.

```lisp
(defclass dual-agent (agent)
  ((persistent-root :accessor dual-agent-root
                    :initform nil
                    :documentation "Current persistent agent root")
   (version-history :accessor dual-agent-history
                    :initform nil
                    :documentation "Stack of previous roots for undo")
   (auto-snapshot-p :accessor dual-agent-auto-snapshot-p
                    :initform t
                    :documentation "Auto-snapshot on state changes"))
  (:documentation "Agent that maintains both mutable and persistent representations"))

;; Override CLOS accessors to update persistent tree
(defmethod (setf agent-state) :after (new-state (agent dual-agent))
  ;; Update persistent root with new state
  ...)

;; Convert existing agents to dual-mode
(defun upgrade-to-dual (agent)
  → dual-agent with persistent root initialized from current state)

;; Undo last N state changes
(defun dual-agent-undo (agent &optional (n 1))
  → agent with root rolled back n versions)
```

**Tests:** 40+ assertions covering CLOS interface compatibility, auto-snapshotting, undo, upgrade path.

**Depends on:** Wave 1 (persistent agent core)

#### Task 3.2: Agentic Agent Integration (agentic-persistent.lisp)
**File:** `platform/src/integration/agentic-persistent.lisp`
**Package:** `autopoiesis.integration`

Extend `agentic-agent` to optionally operate in persistent mode.

```lisp
(defclass persistent-agentic-agent (agentic-agent dual-agent)
  ()
  (:documentation "Agentic agent with persistent state tracking"))

;; Specialized perceive: records observation to persistent tree
(defmethod perceive ((agent persistent-agentic-agent) environment)
  ;; Call parent method, then update persistent root
  ...)

;; Each agentic-loop turn creates a new persistent version
;; on-thought callback updates the persistent root
```

**Tests:** 30+ assertions covering LLM interaction with persistent state, thought recording, version accumulation.

**Depends on:** Task 3.1, integration layer

#### Task 3.3: Provider-Backed Agent Integration
**File:** `platform/src/integration/provider-persistent.lisp`
**Package:** `autopoiesis.integration`

Same treatment for provider-backed agents.

```lisp
(defclass persistent-provider-agent (provider-backed-agent dual-agent)
  ()
  (:documentation "Provider-backed agent with persistent state tracking"))
```

**Tests:** 20+ assertions covering provider invocation with persistent state.

**Depends on:** Task 3.1, integration layer

#### Task 3.4: Substrate Event Integration
**File:** `platform/src/agent/persistent-substrate.lisp`
**Package:** `autopoiesis.agent`

Connect persistent agent operations to the substrate event system.

```lisp
;; Record agent version transitions as substrate datoms
(defun record-agent-transition (agent old-root new-root &key store)
  (transact!
   (list (make-datom agent-eid :agent/version (persistent-agent-version new-root))
         (make-datom agent-eid :agent/root-hash (persistent-agent-hash new-root))
         (make-datom agent-eid :agent/thought-count
                     (pvec-length (persistent-agent-thoughts new-root)))
         ...)))

;; Reactive system: trigger on agent state changes
(defsystem :agent-version-tracker
  (:entity-type :agent
   :watches (:agent/version))
  ;; Emit integration event on version change
  (emit-integration-event :agent-evolved ...))
```

**Tests:** 30+ assertions covering datom creation, event emission, reactive system dispatch.

**Depends on:** Task 3.1, substrate layer

---

### Wave 4: Population Management (4 tasks)

Enable managing groups of persistent agents as a population.

#### Task 4.1: Agent Population (population.lisp)
**File:** `platform/src/agent/population.lisp`
**Package:** `autopoiesis.agent`

A population is an immutable collection of persistent agent roots with metadata.

```lisp
(defstruct agent-population
  (id nil)                    ; UUID
  (generation 0)              ; Generation counter
  (agents (pvec-empty))       ; Persistent vector of agent roots
  (fitness-scores nil)        ; Alist of (agent-id . score)
  (metadata (pmap-empty))     ; Population-level metadata
  (parent-population nil)     ; Previous generation
  (timestamp 0))

;; Population operations (all pure, return new populations)
(population-add population agent)
(population-remove population agent-id)
(population-size population)
(population-agents population) ; → list of persistent-agents
(population-best population n) ; → top n by fitness
(population-worst population n)
(population-mean-fitness population)
```

**Tests:** 30+ assertions covering population CRUD, fitness ranking, structural sharing between generations.

**Depends on:** Wave 1

#### Task 4.2: Production Rules Engine (production-rules.lisp)
**File:** `platform/src/agent/production-rules.lisp`
**Package:** `autopoiesis.agent`

Define production rules that transform agents based on pattern matching.

```lisp
(defstruct production-rule
  (name nil)
  (pattern nil)          ; S-expression pattern to match against agent genome
  (transform nil)        ; Function: agent → agent
  (priority 0)           ; Higher = applied first
  (probability 1.0))     ; Stochastic application rate

;; Apply one rule to one agent
(apply-rule rule agent)
  → (values new-agent applied-p)

;; Apply all matching rules to an agent
(apply-rules rules agent &key max-applications)
  → new-agent

;; Apply rules across a population (sequential baseline)
(evolve-population population rules &key selection-fn)
  → new-population
```

**Selection functions:**
```lisp
(tournament-select population k)     ; k-tournament selection
(roulette-select population)         ; Fitness-proportional
(elitist-select population n)        ; Keep top n unchanged
```

**Tests:** 40+ assertions covering rule matching, single/multi application, population evolution, selection strategies.

**Depends on:** Task 4.1

#### Task 4.3: Fitness Evaluation Framework (fitness.lisp)
**File:** `platform/src/agent/fitness.lisp`
**Package:** `autopoiesis.agent`

Evaluate agent fitness based on configurable criteria.

```lisp
(defstruct fitness-function
  (name nil)
  (evaluator nil)        ; Function: agent → score (0.0-1.0)
  (weight 1.0))          ; Relative importance

;; Built-in fitness evaluators
(thought-diversity-fitness agent)     ; Variety of thought types
(capability-breadth-fitness agent)    ; Number of capabilities
(genome-efficiency-fitness agent)     ; Genome size vs capability count
(heuristic-quality-fitness agent)     ; Average heuristic confidence
(error-rate-fitness agent)            ; Low error rate = high fitness

;; Composite fitness
(evaluate-fitness agent fitness-functions)
  → weighted-average-score

;; Population-level evaluation
(evaluate-population population fitness-functions)
  → population with updated fitness-scores
```

**Tests:** 30+ assertions covering individual evaluators, composite scoring, population evaluation.

**Depends on:** Task 4.1

#### Task 4.4: Population Visualization
**File:** `platform/src/holodeck/population-viz.lisp`
**Package:** `autopoiesis.holodeck`

Visualize agent populations in the Holodeck.

```lisp
;; Materialize a population as a cluster of agent entities
(materialize-population population &key layout)
  → list of entity-ids

;; Layout strategies
(grid-layout population rows cols spacing)
(radial-layout population radius)
(fitness-landscape-layout population) ; X=generation, Y=fitness, Z=diversity

;; Update population visualization after evolution step
(update-population-viz old-entities new-population)
```

**Tests:** 20+ assertions covering materialization, layouts, update.

**Depends on:** Wave 2, Task 4.1

---

### Wave 5: Bend/HVM Integration (5 tasks)

Connect to Bend for GPU-parallel metabolism.

#### Task 5.1: Agent Serialization for Bend (bend-serialization.lisp)
**File:** `platform/src/integration/bend-serialization.lisp`
**Package:** `autopoiesis.integration`

Serialize persistent agent trees to a format Bend can consume and produce.

```lisp
;; Serialize agent to Bend-compatible representation
(agent-to-bend-repr agent)
  → string (Bend algebraic data type encoding)

;; Deserialize Bend output back to persistent agent
(bend-repr-to-agent repr)
  → persistent-agent

;; Batch serialize a population
(population-to-bend-repr population)
  → string

;; Batch deserialize
(bend-repr-to-population repr)
  → agent-population
```

**Format:** Agents encoded as Bend algebraic data types:
```
Agent { id: u64, genome: (List Gene), thoughts: (List Thought), caps: (List u32) }
Gene { code_hash: u64, validated: u8 }
Thought { phase: u8, content_hash: u64, timestamp: u64 }
```

**Tests:** 30+ assertions covering round-trip serialization, batch operations, edge cases.

**Depends on:** Wave 1, Bend installed

#### Task 5.2: Bend Production Rules (metabolism.bend)
**File:** `platform/bend/metabolism.bend`

Implement core production rules in Bend for GPU execution.

```python
# Apply production rules in parallel across all agents
def apply_production_rules(agents: List[Agent], rules: List[Rule]) -> List[Agent]:
  match agents:
    case []: return []
    case [head | tail]:
      new_head = reduce_one(head, rules)
      new_tail = apply_production_rules(tail, rules)
      return [new_head | new_tail]

def reduce_one(agent: Agent, rules: List[Rule]) -> Agent:
  match rules:
    case []: return agent
    case [r | rs]:
      if matches_pattern(agent.genome, r.pattern):
        return apply_transform(agent, r.transform)
      else:
        return reduce_one(agent, rs)

# Fitness evaluation in parallel
def evaluate_all(agents: List[Agent], env: Environment) -> List[(Agent, f32)]:
  match agents:
    case []: return []
    case [head | tail]:
      score = evaluate_one(head, env)
      rest = evaluate_all(tail, env)
      return [(head, score) | rest]
```

**Tests:** Bend-side tests using HVM's test infrastructure.

**Depends on:** Task 5.1, Bend/HVM installed

#### Task 5.3: SBCL ↔ Bend Bridge (bend-bridge.lisp)
**File:** `platform/src/integration/bend-bridge.lisp`
**Package:** `autopoiesis.integration`

FFI bridge between SBCL and Bend/HVM runtime.

```lisp
;; Check if Bend is available
(bend-available-p) → boolean

;; Run a Bend program with input data
(bend-run program-path input &key timeout)
  → output-string

;; High-level: evolve population via Bend
(bend-evolve-population population rules &key timeout)
  → new-population

;; Fallback: if Bend unavailable, use sequential CL implementation
(evolve-population-auto population rules)
  → new-population (uses Bend if available, else CL sequential)
```

**Implementation options (in priority order):**
1. **Subprocess:** `bend run metabolism.bend` with stdin/stdout serialization
2. **Shared memory:** For Apple M unified memory, mmap a shared buffer
3. **C FFI:** When HVM4 C backend is stable, direct function calls

Start with option 1 (subprocess) — simplest, works everywhere, sufficient for initial integration.

**Tests:** 30+ assertions covering availability check, subprocess execution, fallback behavior, round-trip data integrity.

**Depends on:** Tasks 5.1, 5.2

#### Task 5.4: Metabolic Cycle Orchestration (metabolic-cycle.lisp)
**File:** `platform/src/orchestration/metabolic-cycle.lisp`
**Package:** `autopoiesis.orchestration`

Integrate metabolism into the conductor's tick loop.

```lisp
;; Schedule a metabolic burst
(schedule-metabolism conductor population rules &key delay)

;; Conductor dispatches to Bend (or CL fallback)
;; Records results as substrate events
;; Updates Holodeck visualization

;; Configuration
(defparameter *metabolic-tick-interval* 10)  ; seconds between bursts
(defparameter *metabolic-batch-size* 100)    ; agents per burst
(defparameter *metabolic-timeout* 30)        ; seconds max per burst
```

**Tests:** 30+ assertions covering scheduling, dispatch, result recording, timeout handling.

**Depends on:** Task 5.3, orchestration layer

#### Task 5.5: GPU Memory Management (bend-memory.lisp)
**File:** `platform/src/integration/bend-memory.lisp`
**Package:** `autopoiesis.integration`

Manage data transfer between SBCL heap and GPU/HVM memory.

```lisp
;; Estimate memory needed for population
(estimate-bend-memory population)
  → bytes

;; Pinned buffer for zero-copy on unified memory
(with-pinned-buffer (buf size)
  body...)

;; Batch transfer with chunking
(transfer-population-chunked population chunk-size)
  → list of chunk results
```

**Tests:** 20+ assertions covering memory estimation, chunking, cleanup.

**Depends on:** Task 5.3

---

### Wave 6: Specialized Agent Types (4 tasks)

Build concrete agent specializations that demonstrate the three-layer architecture.

#### Task 6.1: Root Agent — Self-Producing Foundation
**File:** `platform/src/agent/root-agent.lisp`
**Package:** `autopoiesis.agent`

The root agent is the autopoietic foundation — it literally produces its own next version.

```lisp
(defclass root-agent (dual-agent)
  ((production-rules :accessor root-agent-rules
                     :initform nil
                     :documentation "Rules for self-production")
   (metabolic-energy :accessor root-agent-energy
                     :initform 1.0
                     :documentation "Current energy (depleted by actions, replenished by success)"))
  (:documentation "Self-producing agent — the autopoietic foundation"))

;; Specialized cognitive loop:
;; perceive: gather observations + energy check
;; reason: apply heuristics + check production rules
;; decide: choose action or self-modification
;; act: execute, potentially modifying own genome
;; reflect: update heuristics, adjust energy, maybe spawn child
```

**Autopoietic property:** Every cognitive cycle, the root agent can modify its own genome (via the membrane-gated extension compiler), producing a new version of itself. If energy is sufficient, it can fork children with variations.

**Tests:** 40+ assertions covering self-production cycle, energy dynamics, genome modification, child spawning.

**Depends on:** Waves 1-3

#### Task 6.2: Self-Extender Agent — Code Evolution
**File:** `platform/src/agent/self-extender-agent.lisp`
**Package:** `autopoiesis.agent`

An agent specialized in extending its own capabilities through code generation.

```lisp
(defclass self-extender-agent (persistent-agentic-agent)
  ((extension-history :accessor extender-history
                      :initform nil
                      :documentation "History of self-modifications")
   (test-harness :accessor extender-test-harness
                 :initform nil
                 :documentation "Test cases for validation"))
  (:documentation "Agent that evolves its own capabilities"))

;; Cognitive specialization:
;; reason: analyze capability gaps
;; decide: propose new S-expression capability
;; act: validate via extension compiler, test, promote if passing
;; reflect: record success/failure, adjust heuristics
```

**Tests:** 30+ assertions covering capability proposal, validation, testing, promotion cycle.

**Depends on:** Tasks 3.2, 6.1

#### Task 6.3: Holodeck Visualizer Agent — Observer
**File:** `platform/src/agent/visualizer-agent.lisp`
**Package:** `autopoiesis.agent`

An agent that observes other agents and controls Holodeck visualization.

```lisp
(defclass visualizer-agent (dual-agent)
  ((observed-agents :accessor visualizer-observed
                    :initform nil
                    :documentation "Agent IDs being observed")
   (visualization-mode :accessor visualizer-mode
                       :initform :cognitive
                       :documentation ":cognitive :lineage :population :metabolic"))
  (:documentation "Agent that observes and visualizes other agents"))

;; Cognitive specialization:
;; perceive: read observed agents' persistent roots
;; reason: detect interesting changes (forks, mutations, energy shifts)
;; decide: choose visualization emphasis
;; act: update Holodeck entities, camera position, HUD
;; reflect: learn what visualizations are most informative
```

**Tests:** 20+ assertions covering observation, mode switching, Holodeck entity management.

**Depends on:** Wave 2, Task 6.1

#### Task 6.4: Metabolic Swarm Agent — Population Manager
**File:** `platform/src/agent/swarm-agent.lisp`
**Package:** `autopoiesis.agent`

An agent that manages a population and drives evolution.

```lisp
(defclass swarm-agent (dual-agent)
  ((population :accessor swarm-population
               :initform nil
               :documentation "Managed agent population")
   (production-rules :accessor swarm-rules
                     :initform nil
                     :documentation "Rules for population evolution")
   (fitness-functions :accessor swarm-fitness
                      :initform nil
                      :documentation "Fitness evaluation criteria")
   (generation-count :accessor swarm-generation
                     :initform 0))
  (:documentation "Agent that manages and evolves a population of agents"))

;; Cognitive specialization:
;; perceive: evaluate current population fitness
;; reason: identify underperforming agents, promising variations
;; decide: choose evolution strategy (mutation rate, selection pressure)
;; act: trigger metabolic burst (Bend if available, else sequential)
;; reflect: compare generation fitness, adjust strategy
```

**Tests:** 30+ assertions covering population management, evolution triggering, strategy adjustment.

**Depends on:** Waves 4-5, Task 6.1

---

### Wave 7: Test Infrastructure & Integration Tests (3 tasks)

#### Task 7.1: Persistent Agent Test Suite (persistent-agent-tests.lisp)
**File:** `platform/test/persistent-agent-tests.lisp`
**Package:** `autopoiesis.test`

Comprehensive tests for the persistent agent core.

```lisp
(def-suite persistent-agent-tests
  :description "Persistent agent core tests")

;; Structural sharing tests
;; Round-trip serialization tests
;; Cognitive cycle purity tests
;; Forking and lineage tests
;; Membrane and self-modification tests
;; Snapshot bridge tests
;; Performance benchmarks (O(log n) verification)
```

**Target:** 150+ assertions

**Depends on:** Waves 0-1

#### Task 7.2: Population & Evolution Test Suite (population-tests.lisp)
**File:** `platform/test/population-tests.lisp`
**Package:** `autopoiesis.test`

Tests for population management and evolution.

```lisp
(def-suite population-tests
  :description "Population management and evolution tests")

;; Population CRUD
;; Production rule matching and application
;; Fitness evaluation
;; Selection strategies
;; Multi-generation evolution
;; Bend integration (if available, else skip)
```

**Target:** 100+ assertions

**Depends on:** Waves 4-5

#### Task 7.3: End-to-End Agent Evolution Tests (evolution-e2e-tests.lisp)
**File:** `platform/test/evolution-e2e-tests.lisp`
**Package:** `autopoiesis.test`

Full lifecycle tests demonstrating autopoiesis.

```lisp
(def-suite evolution-e2e-tests
  :description "End-to-end agent evolution tests")

;; Scenario 1: Agent self-modifies genome, fork, both versions persist
;; Scenario 2: Population evolves over 10 generations, fitness improves
;; Scenario 3: Agent writes new capability, tests pass, gets promoted
;; Scenario 4: Two agents merge, combined capabilities > either alone
;; Scenario 5: Time-travel to previous agent version, branch from there
;; Scenario 6: Holodeck visualizes agent evolution in real-time
```

**Target:** 80+ assertions

**Depends on:** All previous waves

---

### Wave 8: Package Registration & Documentation (2 tasks)

#### Task 8.1: Package Exports and ASDF Finalization

Update all package definitions and ASDF system definition to include all new files.

**Files modified:**
- `platform/src/core/packages.lisp` — persistent data structure exports
- `platform/src/agent/packages.lisp` — persistent agent exports
- `platform/src/holodeck/packages.lisp` — new component/system exports
- `platform/src/integration/packages.lisp` — Bend bridge exports
- `platform/src/orchestration/packages.lisp` — metabolic cycle exports
- `platform/autopoiesis.asd` — all new file registrations
- `platform/test/packages.lisp` — new test suite exports
- `platform/test/run-tests.lisp` — new test runners

**Depends on:** All previous waves

#### Task 8.2: Spec Document Update
**File:** `platform/docs/specs/09-autopoietic-agents.md`

New specification document covering:
- Three-layer architecture rationale
- Persistent data structure design decisions
- ECS embodiment mapping
- Bend integration protocol
- Agent type taxonomy
- Migration guide from mutable to persistent agents

**Depends on:** All previous waves

---

## Dependency DAG Summary

```
Wave 0: [0.1] [0.2] [0.3] → [0.4]
           \     |     /
Wave 1:     [1.1] → [1.2] [1.3] [1.4] → [1.5]
              |       |       |      |        |
Wave 2:   [2.1] → [2.2] → [2.3] → [2.4]    |
              |                               |
Wave 3:   [3.1] → [3.2] [3.3] [3.4]         |
              |       |     |                 |
Wave 4:   [4.1] → [4.2] [4.3] → [4.4]       |
              |       |                       |
Wave 5:   [5.1] → [5.2] → [5.3] → [5.4] [5.5]
              |               |
Wave 6:   [6.1] → [6.2] [6.3] [6.4]
              |       |     |     |
Wave 7:   [7.1]    [7.2]      [7.3]
              |       |          |
Wave 8:   [8.1] ← ← ← ← ← [8.2]
```

**Parallelism opportunities within waves:**
- Wave 0: Tasks 0.1 and 0.2 are independent (parallel)
- Wave 1: Tasks 1.2, 1.3, 1.4 are independent after 1.1 (parallel)
- Wave 2: Tasks 2.1 is independent of Wave 1 completion (can start early)
- Wave 3: Tasks 3.2 and 3.3 are independent (parallel)
- Wave 4: Tasks 4.2 and 4.3 are independent after 4.1 (parallel)
- Wave 5: Tasks 5.1 and 5.2 are independent (parallel)
- Wave 6: All four tasks are independent (parallel)
- Wave 7: Tasks 7.1 and 7.2 are independent (parallel)

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Persistent data structures too slow | High | Low | Benchmark in Wave 0; fallback to fset library |
| Bend/HVM not stable enough | Medium | Medium | Sequential CL fallback in Task 5.3 (always works) |
| Structural sharing memory overhead | Medium | Low | 32-way trie minimizes node count; measure in tests |
| Existing tests break with dual-agent | High | Low | dual-agent is opt-in, existing agent class unchanged |
| Thread safety with persistent roots | Medium | Medium | Persistent structures are immutable = thread-safe by construction |
| ASDF dependency cycles | Medium | Low | Strict layering; bridge files in integration module |

---

## Success Criteria

1. **Purity:** `persistent-cognitive-cycle` is a pure function — same input always produces same output, no side effects
2. **Sharing:** After 1000 agent steps, memory usage < 2x a single agent (structural sharing working)
3. **Branching:** `persistent-fork` is O(1) — verified by benchmark
4. **Visualization:** Holodeck shows live agent cognition, lineage, and population evolution
5. **Evolution:** Population fitness measurably improves over 10+ generations
6. **Compatibility:** All existing 2,775+ test assertions still pass
7. **Fallback:** System works fully without Bend installed (sequential CL metabolism)

---

## File Summary (new files)

| File | Module | LOC Est. |
|------|--------|----------|
| `core/persistent-map.lisp` | core | ~300 |
| `core/persistent-vector.lisp` | core | ~350 |
| `core/persistent-set.lisp` | core | ~150 |
| `agent/persistent-agent.lisp` | agent | ~200 |
| `agent/persistent-cognition.lisp` | agent | ~250 |
| `agent/persistent-lineage.lisp` | agent | ~200 |
| `agent/persistent-membrane.lisp` | agent | ~200 |
| `agent/persistent-snapshot-bridge.lisp` | agent | ~150 |
| `agent/dual-agent.lisp` | agent | ~200 |
| `agent/population.lisp` | agent | ~200 |
| `agent/production-rules.lisp` | agent | ~250 |
| `agent/fitness.lisp` | agent | ~200 |
| `agent/root-agent.lisp` | agent | ~200 |
| `agent/self-extender-agent.lisp` | agent | ~150 |
| `agent/visualizer-agent.lisp` | agent | ~150 |
| `agent/swarm-agent.lisp` | agent | ~200 |
| `agent/persistent-substrate.lisp` | agent | ~150 |
| `holodeck/agent-components.lisp` | holodeck | ~100 |
| `holodeck/agent-systems.lisp` | holodeck | ~200 |
| `holodeck/agent-entities.lisp` | holodeck | ~150 |
| `holodeck/population-viz.lisp` | holodeck | ~150 |
| `integration/agentic-persistent.lisp` | integration | ~150 |
| `integration/provider-persistent.lisp` | integration | ~100 |
| `integration/bend-serialization.lisp` | integration | ~200 |
| `integration/bend-bridge.lisp` | integration | ~200 |
| `integration/bend-memory.lisp` | integration | ~150 |
| `orchestration/metabolic-cycle.lisp` | orchestration | ~150 |
| `bend/metabolism.bend` | bend (new dir) | ~100 |
| `test/persistent-agent-tests.lisp` | test | ~400 |
| `test/population-tests.lisp` | test | ~300 |
| `test/evolution-e2e-tests.lisp` | test | ~250 |
| `docs/specs/09-autopoietic-agents.md` | docs | ~500 |
| **Total** | | **~6,000** |

---

## Agent Team Assignment (recommended)

For a team of agents working in parallel:

| Agent | Role | Waves | Skills Needed |
|-------|------|-------|---------------|
| **Alpha** | Persistent Data Structures | 0, 1.1, 1.2 | Pure functional programming, tree algorithms |
| **Beta** | Agent Architecture | 1.3, 1.4, 1.5, 3.1 | CLOS, snapshot system, agent domain |
| **Gamma** | ECS/Holodeck | 2.1-2.4, 4.4, 6.3 | cl-fast-ecs, 3D visualization |
| **Delta** | Population/Evolution | 4.1-4.3, 6.4 | Evolutionary algorithms, fitness functions |
| **Epsilon** | Bend Integration | 5.1-5.5 | Bend/HVM, FFI, GPU programming |
| **Zeta** | Integration Bridge | 3.2-3.4, 6.1, 6.2 | Agentic loops, provider system |
| **Eta** | Testing | 7.1-7.3, 8.1-8.2 | FiveAM, ASDF, documentation |

Agents Alpha and Gamma can start simultaneously (Wave 0 and Wave 2.1 are independent).
Agent Epsilon can begin Wave 5.1-5.2 as soon as Wave 1 completes.
All Wave 6 agents can work in parallel once their dependencies are met.
