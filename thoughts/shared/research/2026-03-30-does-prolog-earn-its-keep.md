---
date: 2026-03-30T10:30:00Z
researcher: Claude
git_commit: 6b1d3d3
branch: main
repository: autopoiesis
topic: "Does Prolog actually earn its keep in this agent platform?"
tags: [research, architecture, prolog, shen, datalog, substrate, reasoning]
status: complete
last_updated: 2026-03-30
last_updated_by: Claude
---

# Research: Does Prolog Earn Its Keep?

**Git Commit**: 6b1d3d3
**Branch**: main

## Research Question

We built a Shen Prolog extension for Autopoiesis. But we're not actually using Prolog — the CL fallback handles everything the demos show. Is there a real use case for logic programming in this platform, or is rules-as-data the actual insight and Prolog is unnecessary overhead?

## Summary

**The honest answer: Prolog is the wrong tool. Datalog is the right one. And the substrate is already 80% of a Datalog engine.**

The substrate stores EAV triples (entity-attribute-value). That is literally the Datalog fact format. `(find-entities :entity/type :agent)` is a Datalog query. The missing 20% is recursive rules — the ability to say "X transitively depends on Y" and have the engine chase the chain. The codebase already does this imperatively in at least three places (snapshot ancestor walks, snapshot descendant collection, agent parent-child lineage). Each reimplements the same graph traversal by hand.

Full Prolog (unification, backtracking, depth-first search) is overkill. The codebase has zero use cases that require exploring multiple solution paths or building compound terms. But Datalog's subset — recursive rules over flat facts with guaranteed termination — would replace hand-written graph traversals with one-line declarations and open up cross-cutting queries the system currently can't express.

Shen's Prolog is not Datalog. It's full Prolog with all the footguns (non-termination, cuts, global state behind a lock). The value of the Shen extension is the rules-as-data architecture and the verification pipeline, not the Prolog engine.

## Detailed Findings

### Where the Codebase Does Relational Reasoning Today

#### 1. Snapshot DAG Traversal (hand-written graph walks)

Three separate functions implement the same pattern — chasing parent pointers:

**`snapshot-ancestors`** (`packages/core/src/snapshot/persistence.lisp`):
```lisp
(loop for id = (let ((snap (load-snapshot snapshot-id store)))
                 (when snap (snapshot-parent snap)))
      then (let ((snap (load-snapshot id store)))
             (when snap (snapshot-parent snap)))
      while id
      collect id)
```

**`walk-ancestors-paginated`** (`packages/core/src/snapshot/lazy-loading.lisp`):
Iterative ancestor walk with batching and depth limits via `make-lazy-dag-iterator`.

**`snapshot-descendants`** — same file, BFS/DFS collecting all children recursively.

As a Datalog rule, all three would be:
```
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).
```

One declaration replaces three hand-written traversal functions.

#### 2. Agent Parent-Child Lineage

`persistent-agent` struct has `children` (list) and `parent-root` fields. The `persistent-fork` function sets these. But there's no transitive lineage query — "give me all agents descended from agent X" requires writing another manual traversal.

#### 3. Capability Lookup (flat, no composition)

`find-agent-capability` (`packages/core/src/agent/agent-capability.lisp`):
```lisp
(find name (agent-capabilities agent) :key #'capability-name :test #'eq)
```

This is a flat list search. There's no capability inheritance ("agent A has all of team T's capabilities"), no capability composition ("if agent has :analyze and :report, it can :summarize"), no transitive capability delegation.

A Datalog model could express:
```
has-capability(Agent, Cap) :- direct-capability(Agent, Cap).
has-capability(Agent, Cap) :- member-of(Agent, Team), team-capability(Team, Cap).
has-capability(Agent, Cap) :- has-capability(Agent, C1), has-capability(Agent, C2), composes(C1, C2, Cap).
```

#### 4. Team Strategy (hardcoded dispatch, no constraint solving)

`make-strategy` is a flat `ecase` dispatch on a keyword → CLOS class. There's no constraint satisfaction, no matching of agent capabilities to task requirements, no backtracking over possible assignments. The human picks which strategy at team creation time.

#### 5. Conductor Event Dispatch (imperative, no dependency graph)

`process-events` in the conductor loop calls `dispatch-event` which is a `cond` chain on event type. No event dependencies, no ordering constraints, no "event X must complete before event Y" rules.

#### 6. Substrate Queries (EAV triples — almost Datalog)

The substrate stores datoms as `(entity attribute value)` triples. The query functions:

| Function | What it does | Datalog equivalent |
|----------|-------------|-------------------|
| `(entity-attr eid :name)` | Get one attribute | `?- name(eid, X).` |
| `(find-entities :entity/type :agent)` | Find by attribute=value | `?- entity_type(X, agent).` |
| `(find-entities-by-type :agent)` | Sugar for above | Same |
| `(take! :status :pending :new-value :running)` | Atomic claim (Linda) | No Datalog equivalent (mutation) |

What's missing: **joins** and **recursive rules**. "Find all agents of type :agent whose status is :running and who belong to a team with strategy :parallel" requires three separate `find-entities` calls and manual intersection in CL. In Datalog:
```
?- entity_type(A, agent), status(A, running), member_of(A, T), strategy(T, parallel).
```

### What Real Systems Use Logic Programming For

#### Datalog in production (thriving)

- **AWS (Soufflé)**: Verifying VPN connectivity across cloud infrastructure. Security policy reasoning over network topology.
- **Datomic/DataScript**: Datalog queries over immutable fact databases. Used in production for security scanning, taxonomy management.
- **CozoDB**: Embeddable database combining Datalog + vector search. Explicitly designed for AI agent memory.
- **RelationalAI**: Snowflake-native knowledge graph with Datalog reasoning. GA November 2024.

#### Full Prolog in production (thin)

- Configure-Price-Quote software (configuration spaces with millions of combinations)
- Medical/clinical reasoning protocols (auditable executable specifications)
- SWI-Prolog claims "24x7 mission critical commercial server processes"

#### Modern agent frameworks (none use logic programming)

CrewAI, AutoGen, LangGraph — all use LLMs as the reasoning engine. Task assignment is either hardcoded or LLM-decided. None have constraint satisfaction, unification, or backtracking.

#### Where Prolog was tried and abandoned

- Expert systems (knowledge base maintenance doesn't scale)
- The Fifth-Generation Computer Project (1982-1992, Japan — definitive failure)
- The cut operator (`!`) breaks declarative semantics; real Prolog programs use it constantly
- Debugging requires tracing execution paths through backtracking

### The Key Distinction: Datalog vs Full Prolog

| Feature | Datalog | Full Prolog | Does Autopoiesis need it? |
|---------|---------|-------------|--------------------------|
| Recursive rules | Yes | Yes | **Yes** — snapshot/agent lineage |
| Pattern matching on facts | Yes | Yes | **Yes** — substrate queries |
| Joins across entities | Yes | Yes | **Yes** — cross-entity queries |
| Guaranteed termination | **Yes** | No | Critical for a server process |
| Compound terms (nesting) | No | Yes | Not currently |
| Backtracking search | No (bottom-up) | Yes (top-down) | Not currently |
| Meta-programming | No | Yes | Not currently |
| Negation-as-failure | Stratified (safe) | Unrestricted (unsafe) | Safe version sufficient |

Datalog covers every current need. Full Prolog adds capabilities the codebase doesn't use.

### The Substrate Is Already 80% Datalog

The substrate's EAV triple store IS the Datalog fact base:
- `(transact! (list (make-datom eid :name "scout")))` = asserting `name(eid, "scout").`
- `(find-entities :entity/type :agent)` = querying `entity_type(X, agent).`
- `(entity-attr eid :status)` = querying `status(eid, X).`

The missing 20%:
1. **Recursive rules**: `ancestor(X, Y) :- parent(X, Z), ancestor(Z, Y).`
2. **Multi-attribute joins**: `?- type(A, agent), status(A, running), team(A, T).`
3. **Declarative rule registration**: a way to say "this rule exists" and have the substrate evaluate it

Adding these three things to the substrate would give the platform a Datalog engine over agent state with zero additional dependencies. No Shen. No external Prolog. Just recursive rule evaluation over the EAV triples that already exist.

## What the Shen Extension Actually Provides (vs. What It Claims)

| Claimed capability | Actual status | Could substrate Datalog replace it? |
|-------------------|---------------|-------------------------------------|
| Rules as S-expression data | **Works** | Yes — rules are already S-expressions |
| Serialization roundtrip | **Works** | Yes — same format |
| CL fallback verification | **Works** | Yes — this IS the working path |
| Prolog query execution | Partially works (simple facts only) | Datalog would handle all current uses |
| Recursive Prolog queries | **Broken** (list syntax mismatch) | Datalog handles recursion with termination guarantee |
| Agent reasoning mixin | Architecture exists, no real queries | Substrate Datalog queries would work here |

## The Three Real Options

### Option A: Keep Shen, fix recursive queries
Fix the `[X | Y]` vs `(cons X Y)` list syntax mismatch. Get real Prolog queries working. Accept the 43MB dependency, boot time cost, global lock, and unmaintained library.

### Option B: Replace Shen with substrate Datalog
Add recursive rule support to the existing substrate query layer. Zero new dependencies. Rules are still S-expression data. Queries run over the same EAV triples the system already stores. Termination is guaranteed.

### Option C: Keep rules-as-data, drop the Prolog engine entirely
The CL fallback verification and the rules-as-data architecture are the genuinely valuable parts. Keep those. Accept that "Prolog-powered reasoning" is aspirational marketing, not working infrastructure.

## Code References

- `packages/substrate/src/query.lisp:16` — `find-entities` (EAV query)
- `packages/substrate/src/entity.lisp:41` — `entity-attr` (single attribute lookup)
- `packages/substrate/src/linda.lisp:39` — `take!` (atomic claim)
- `packages/core/src/snapshot/persistence.lisp` — `snapshot-ancestors` (hand-written transitive closure)
- `packages/core/src/snapshot/lazy-loading.lisp` — `walk-ancestors-paginated`, `walk-descendants-paginated`
- `packages/core/src/agent/agent-capability.lisp` — `find-agent-capability` (flat list search)
- `packages/core/src/agent/persistent-agent.lisp` — `children`, `parent-root` fields
- `packages/team/src/strategy.lisp` — `make-strategy` (ecase dispatch)
- `packages/core/src/orchestration/conductor.lisp` — `dispatch-event` (cond chain)
- `packages/shen/src/rules.lisp` — rule storage, serialization
- `packages/shen/src/verifier.lisp:121-177` — `clauses-to-cl-check` (the actually useful part)

## Related Research

- `thoughts/shared/research/2026-03-29-self-compiling-specs-across-languages.md` — how the spec-to-code pattern works across paradigms
