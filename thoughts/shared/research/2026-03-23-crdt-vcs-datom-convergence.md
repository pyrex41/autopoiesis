# CRDT-Based Version Control and Autopoiesis: Convergent Design Patterns

## Context

Bram Cohen (creator of BitTorrent) released **Manyana** (March 2026), a proof-of-concept demonstrating CRDT-based version control. The core thesis: using CRDTs (Conflict-Free Replicated Data Types) for VCS gives you merges that never fail, informative conflict presentation, order-independent merge results, and rebase without history destruction — because "history lives in the structure" (the weave), not in the DAG.

This document analyzes how Manyana's concepts relate to Autopoiesis's datom store, snapshot DAG, persistent agent architecture, and swarm evolution — and identifies opportunities where we're already doing related things or could pioneer novel approaches.

---

## 1. The Weave vs. The Datom Store

### Manyana's Weave
A weave is a single structure containing every line that has ever existed in a file, with metadata about when each line was added and removed. Merges don't need to find a common ancestor — two states go in, one comes out.

### Our Datom Store
The Autopoiesis substrate is strikingly similar in spirit:

- **Append-only history** (`EAVT` index with `:append` strategy): Every datom ever written is preserved with its transaction ID. The full history of every entity-attribute pair lives in the structure.
- **Materialized current state** (`EA-CURRENT` index with `:replace` strategy): A snapshot of "what's true now" — analogous to the weave's "visible lines" view.
- **Retraction as tombstoning**: When a value is superseded, the datom `(added = nil)` marks it as removed but doesn't delete it from `EAVT`. This parallels how weaves mark deleted lines.
- **Transaction ordering**: Each write gets a monotonic `tx-id`, giving a total order — similar to how weave entries carry insertion timestamps.

**Key difference**: Our store is single-process, single-lock, last-write-wins. There's no merge function because there's only one writer. But the *data model* — append-only history with materialized current views — is already weave-shaped.

**Opportunity**: If the datom store were extended to support multiple independent writers (e.g., multiple agents transacting concurrently on different substrates, then merging), the EAV structure with transaction metadata would support CRDT merge semantics naturally. Each datom already carries `(entity, attribute, value, tx, added)` — adding a `writer-id` would give us a multi-writer weave over structured data rather than text lines.

---

## 2. The Snapshot DAG: Where CRDT Merge Would Slot In

### Current State
Our snapshot system forms a Git-like DAG:
- Content-addressable storage via `sexpr-hash` (SHA-256 over S-expression trees)
- Single-parent pointers forming the DAG
- `find-common-ancestor` for three-way merge setup
- `sexpr-diff` / `sexpr-patch` for structural tree diffing
- `branch` objects as named head pointers
- **`merge-branches` raises "not yet implemented"**

This is exactly the gap Manyana addresses. We have all the supporting infrastructure for merge — ancestry traversal, structural diffing, content addressing — but no merge algorithm.

### What CRDT Merge Would Give Us
For agent state (which is an S-expression tree, not a text file), CRDT merge would mean:
- Two agents fork from a common ancestor, evolve independently, then merge without conflicts blocking the operation
- The merge result is deterministic regardless of merge order (critical for multi-agent swarms)
- Structural conflicts (two agents modified the same cognitive element) are flagged for review but don't prevent the merge

### Our Diff Is Already Tree-Structural
Unlike Git's line-based diff, our `sexpr-diff` operates on the cons-cell tree using `:car`/`:cdr` path navigation. This is closer to a tree CRDT (like Kleppmann's Automerge) than a sequence CRDT (like Manyana's line weave). We're diffing structured cognition, not flat text — which is both harder and more powerful.

**Opportunity**: Implement `merge-branches` using CRDT semantics on S-expression trees. The merge function would:
1. Diff both branches from the common ancestor
2. Apply both edit lists to the base
3. Where edits touch the same path, use type-appropriate merge (see Section 3)
4. Flag structural conflicts (same path, incompatible changes) without blocking

---

## 3. Persistent Agent Merge: We Already Have Proto-CRDTs

The most direct connection is in `persistent-agent-merge` (persistent-lineage.lisp:51-86), which already implements field-specific merge strategies that map to well-known CRDT types:

| Agent Field | Our Strategy | CRDT Equivalent |
|---|---|---|
| `capabilities` | `pset-union` — capabilities only grow | **G-Set** (Grow-Only Set) |
| `thoughts` | `pvec-concat` — append-only | **G-Counter** variant / append-only log |
| `heuristics` | `append + remove-duplicates` | **OR-Set** (Observed-Remove Set) without removes |
| `genome` | Latest timestamp wins | **LWW-Register** (Last-Write-Wins) |
| `membrane` | Earlier as base, later overwrites | **LWW-Register** per key |
| `metadata` | Same as membrane | **LWW-Register** per key |
| `children` | `cl:union` | **G-Set** |
| `version` | `1+ (max v1 v2)` | **G-Counter** (max merge) |

### What's Missing for True CRDT Semantics

1. **Commutativity**: `(merge A B)` ≠ `(merge B A)` for thoughts (concat order depends on argument order) and for LWW fields when timestamps are equal. A true CRDT would need canonical ordering (e.g., by agent UUID as tiebreaker).

2. **Associativity**: `(merge (merge A B) C)` should equal `(merge A (merge B C))`. The thoughts concat is associative, but the LWW fields may not be if all three have identical timestamps.

3. **Logical clocks**: We use wall-clock `get-precise-time` for LWW ordering. In a distributed setting, this is unreliable. A vector clock or Lamport timestamp per agent would make the ordering causal rather than physical.

4. **Tombstones for capabilities**: Capabilities can only grow via `pset-union`. If an agent deliberately removes a dangerous capability, merge with an older version re-adds it. A proper OR-Set CRDT with add/remove semantics would fix this.

**Opportunity**: Upgrade `persistent-agent-merge` to use proper CRDT semantics:
- Add vector clocks to persistent agents (one counter per agent lineage)
- Use OR-Set for capabilities (track add and remove operations, not just current set)
- Use RGA (Replicated Growable Array) for thoughts to get commutative append
- The merge becomes truly order-independent — critical for swarm evolution where N agents merge

---

## 4. Swarm Crossover as Branch Merging

This is perhaps the most novel connection. Manyana frames merge as a VCS operation. We frame crossover as an evolutionary operation. But structurally, they solve the same problem: combining two divergent histories of the same entity.

### Crossover ≈ CRDT Merge of Genomes
Our `crossover-genomes` (operators.lisp:12-38):
- **Capabilities**: Random subset of union (stochastic G-Set merge)
- **Heuristic weights**: Average shared keys, union unique keys (numeric CRDT with interpolation)
- **Parameters**: Same averaging/union strategy

This is a **probabilistic CRDT merge** — instead of deterministic conflict resolution, it uses randomness to explore the merge space. This is actually more general than what Manyana proposes.

### Evolution as Multi-Way Merge
A swarm generation is effectively an N-way merge with selection pressure:
1. N agents (branches) exist in parallel
2. Pairs are merged (crossover) with stochastic conflict resolution
3. The merged results are mutated (analogous to new commits on the merged branch)
4. Selection pressure (fitness) determines which merges survive

**Insight**: We could reframe swarm evolution as CRDT-based version control where:
- Each agent is a branch
- Crossover is a CRDT merge with type-specific resolution
- Mutation is a commit on the merged branch
- Fitness-based selection is analogous to code review / CI gating

---

## 5. Homoiconicity: Our Unique Advantage

Manyana operates on text files (sequences of lines). Our system operates on S-expressions (trees that are simultaneously code and data). This gives us capabilities that a traditional VCS cannot have:

### Self-Describing Merges
Because agent state is an S-expression, the merge function can inspect the *semantics* of what it's merging, not just the structure. A VCS merging Python code sees text lines. We merge cognitive primitives — observations, decisions, capabilities — and can apply domain-appropriate merge strategies per type.

### Executable Diffs
An `sexpr-edit` is itself an S-expression. A diff between two agent states is a data structure that can be:
- Stored as a first-class entity in the datom store
- Applied by agents to transform their own state
- Evolved through the swarm (diffs as genomes)
- Composed, inverted, and reasoned about programmatically

### Code-as-Data Merge Conflicts
When two agents independently extend their capabilities (via `crystallize` / genome modification), a merge conflict is literally a conflict between two pieces of code. The system could, in principle, *evaluate* both code paths and merge based on behavioral equivalence rather than structural similarity.

---

## 6. What Manyana Gets Right That We Should Adopt

### 6a. Informative Conflict Presentation
Manyana's key UX insight: show *what each side did*, not just the two results. Our `sexpr-diff` already produces edit operations with `:type` (replace/insert/delete) and `:path`. We should surface these in conflict presentation rather than showing two opaque S-expression blobs.

### 6b. Conflicts as Annotations, Not Blockers
Merge always succeeds. Conflicts are flagged for human review. In our agent system, this means:
- Two agents fork and diverge
- Merge always produces a valid agent
- Conflicting cognitive elements are tagged with `:conflict` metadata
- The agent (or human supervisor) resolves conflicts as a subsequent cognitive operation

### 6c. Rebase Without History Destruction
Our `dual-agent-undo` is a limited form of history manipulation. A CRDT-based rebase would let us replay an agent's cognitive history onto a different base state without losing the original timeline — valuable for "what if" scenarios in agent evolution.

---

## 7. What We Pioneer That Goes Beyond Manyana

| Innovation | Description |
|---|---|
| **Structured CRDT merge** | Merging trees (S-expressions), not sequences (text lines) |
| **Semantic merge strategies** | Per-field CRDT selection based on cognitive semantics |
| **Probabilistic merge (crossover)** | Stochastic conflict resolution exploring the merge space |
| **Evolutionary merge selection** | Fitness functions evaluating merge quality post-hoc |
| **Self-modifying merge subjects** | Agents can modify their own merge behavior through genome/membrane |
| **Append-only cognition** | Agent thoughts as a natural grow-only CRDT |
| **Multi-layer mergeability** | Substrate (EAV), snapshot (S-expr tree), agent (struct), genome (evolved) — merge at every level |

---

## 8. Concrete Next Steps (If Pursued)

### Phase 1: Complete the CRDT Foundation
- Add vector clocks to persistent agents (Lamport timestamps, one per fork lineage)
- Implement `merge-branches` in the snapshot layer using three-way S-expression merge
- Upgrade `persistent-agent-merge` for commutativity and associativity
- Add OR-Set semantics to capabilities (track add/remove, not just current set)

### Phase 2: Informative Conflict Presentation
- Extend `sexpr-diff` to produce annotated conflict markers (like Manyana's `begin deleted left` / `begin added right`)
- Surface conflicts as substrate entities (`:conflict` entity type) that agents can reason about
- Add conflict resolution as a cognitive operation in the agent loop

### Phase 3: CRDT-Native Agent Evolution
- Reframe swarm crossover as a CRDT merge with stochastic tiebreaking
- Implement multi-way merge (not just pairwise) for swarm generations
- Use merge commutativity to parallelize evolution across machines
- Explore rebase-as-replay for cognitive time-travel ("replay this agent's learning on a different base knowledge")

### Phase 4: Distributed Agent Substrate
- Extend the datom store with writer-ID per transaction
- Implement datom-level CRDT merge for multi-writer substrates
- Enable agents on different machines to transact independently and merge substrates
- The weave becomes a distributed agent memory

---

## 9. Related Work

- **Automerge** (Martin Kleppmann): JSON CRDT — closest to what we'd need for S-expression merge
- **Yjs**: Sequence CRDT used in collaborative editing — relevant for text-based agent outputs
- **Datomic** (Rich Hickey): Immutable database with EAV triples and time-travel — our substrate is already heavily inspired by this model
- **Pijul** (Pierre-Étienne Meunier): Patch-based VCS using category theory — merges are commutative by construction
- **Benzen** (hyoo-ru): Referenced in Manyana comments — claims to implement CRDT VCS already
- **Operational Transformation**: Predecessor to CRDTs for collaborative editing — less relevant given CRDT superiority for our use case

---

## Summary

Autopoiesis and Manyana are converging on the same insight from different directions:

- **Manyana**: "Version control should use CRDTs so merges never fail and history lives in the structure"
- **Autopoiesis**: "Agent cognition should use persistent functional data structures so forks are free and state is never destroyed"

Both systems want: append-only history, structural sharing, deterministic merge, conflict-as-annotation. The difference is Manyana applies this to text files in a VCS, while we apply it to agent cognitive state in a self-modifying system.

The most exciting synthesis: **treat agent evolution as distributed version control**, where each agent is a branch, crossover is CRDT merge, mutation is a commit, and fitness selection replaces code review. We're already 60% of the way there with `persistent-agent-merge` and the swarm system. The remaining 40% is making the merge truly order-independent (vector clocks, proper CRDTs) and connecting the snapshot DAG to the agent merge pipeline.
