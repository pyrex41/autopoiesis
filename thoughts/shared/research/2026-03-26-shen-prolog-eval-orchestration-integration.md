---
date: 2026-03-26T20:15:00+0000
researcher: Claude
git_commit: 73bb2de857fd23a3d3ea725e064dd025f97d17f5
branch: main
repository: pyrex41/autopoiesis
topic: "Shen Prolog for Eval Verification and Orchestration Control"
tags: [research, shen, prolog, eval, orchestration, type-system, verifier, datalog, conductor]
status: complete
last_updated: 2026-03-26
last_updated_by: Claude
---

# Research: Shen Prolog for Eval Verification and Orchestration Control

**Date**: 2026-03-26T20:15:00+0000
**Researcher**: Claude
**Git Commit**: 73bb2de
**Branch**: main
**Repository**: pyrex41/autopoiesis

## Research Question

How could Shen's Prolog capabilities be leveraged as part of the eval system and as a control interface for orchestration? What exists in the codebase today that these features would connect to?

## Summary

Shen provides three composable subsystems — functional programming with ML-style pattern matching, an embedded Prolog (`defprolog`), and a Turing-complete sequent calculus type system that is itself implemented in Shen Prolog. These run on Common Lisp via `shen-cl` (SBCL). The Autopoiesis codebase has three natural integration surfaces for Shen Prolog:

1. **Eval verifiers** — The eval system's `register-verifier` mechanism accepts arbitrary functions keyed by keyword. A `:prolog-query` verifier would let eval scenarios express success criteria as Prolog predicates rather than string matching or regex. The verifier receives the full harness result plist including sandbox metadata, giving Prolog predicates access to filesystem trees, diffs, and execution output.

2. **Orchestration control** — The conductor's `dispatch-event` is a `case` form with a silent `otherwise` no-op. The substrate already has a Datalog query engine with Prolog-style recursive rules (SLD resolution with cycle detection). Shen Prolog could serve as a more expressive rule engine for event routing, scheduling decisions, and agent coordination — either replacing or augmenting the existing Datalog.

3. **Cognitive reasoning** — The agent `reason` generic function is the natural injection point. An agent with a Shen knowledge base could query it during reasoning, using `prolog?` to derive conclusions from facts stored as substrate datoms.

## Detailed Findings

### 1. Shen's Prolog System

Shen embeds a full Prolog via `defprolog`. Clauses use `<--` (equivalent to `:-`) and `;` as terminators. Variables are capitalized symbols.

```shen
(defprolog mem
  X [X|_]   <--;
  X [_|Y]   <-- (mem X Y);)

(defprolog fac
  0 1 <--;
  N R <-- (when (> N 0))
          (is N1 (- N 1))
          (fac N1 R1)
          (is R (* N R1));)
```

Queries use `prolog?` with `return` to pass results back to functional Shen:

```shen
(prolog? (mem 1 [1 2 3]))                         \\ => true
(prolog? (app [1 2 3] [4 5 6] X) (return X))      \\ => [1 2 3 4 5 6]
(prolog? (fac 10 X) (return X))                    \\ => 3628800
```

`receive` binds Shen values into the Prolog context; `call` invokes Shen functions from within Prolog predicates. The two subsystems compose directly.

**Shen's type system is itself a Prolog program.** `datatype` rules compile to `defprolog` clauses. The type checker (`shen.t*`) backward-chains through them. This means the type system is user-extensible — you can add new typing rules at any time.

**CL interop**: `shen-cl` runs on SBCL. `shen-cl.eval-lisp` calls CL from Shen; `shen-utils:load-shen` loads Shen code from CL. Shen runs in the `:SHEN` package with case-sensitive mode.

Sources: [ShenDoc Prolog](https://shenlanguage.org/SD/Prolog.html) | [shen-cl](https://github.com/Shen-Language/shen-cl) | [INTEROP.md](https://github.com/Shen-Language/shen-cl/blob/master/INTEROP.md)

### 2. Eval System Integration Points

The eval verifier system at `packages/eval/src/verifiers.lisp` has a registry-based dispatch:

```lisp
(defvar *verifier-registry* (make-hash-table :test 'eq))

(defun register-verifier (name fn)
  (setf (gethash name *verifier-registry*) fn))

(defun run-verifier (verifier-designator output &key expected exit-code result)
  ;; etypecase dispatch on keyword, plist, function, or symbol
```

A Prolog-based verifier would register exactly like the existing filesystem verifiers:

```lisp
(register-verifier :prolog-query
  (lambda (output &key expected result &allow-other-keys)
    ;; expected = a Prolog query string or S-expression
    ;; result = full harness result plist (metadata, after-tree, etc.)
    ;; Call into Shen Prolog, return :pass or :fail
    ...))
```

Scenarios specify verifiers as data stored in substrate datoms. Any of these forms work:
- `:verifier :prolog-query` with `:expected "mem(X, [1,2,3])"` (keyword + expected)
- `:verifier (:type :prolog-query :value "(file-exists \"src/main.py\")")` (plist with value override)
- `:verifier #'my-prolog-verifier-fn` (direct function)

The **`:metadata` channel** in harness results enables rich context. The sandbox harness populates `:after-tree` (filesystem state), `:diff-summary` (human-readable changes), `:files-added`/`:files-removed`/`:files-modified` (counts). A Prolog verifier could reason over all of this:

```shen
(defprolog verify-project-structure
  Tree <-- (tree-has-file Tree "src/main.py")
           (tree-has-file Tree "tests/test_main.py")
           (tree-has-file Tree "README.md")
           (file-count-above Tree 3);)
```

The **LLM judge** (`packages/eval/src/judge.lisp`) constructs its prompt with optional sections. The `:diff-context` from sandbox metadata already flows into the judge prompt. Prolog reasoning results could similarly be injected — a Prolog pre-analysis of the output could produce structured facts that augment the judge's context.

### 3. Orchestration Integration Points

#### 3a. The Existing Datalog Engine

The substrate already has a Datalog query engine at `packages/substrate/src/datalog.lisp`:

```lisp
(q '(:find ?name
     :in ?status
     :where (?e :agent/status ?status)
            (?e :agent/name ?name))
   :running)
```

It supports **recursive rules** with SLD resolution and cycle detection:

```lisp
(q '(:find ?name
     :in % ?status
     :where (reachable ?e ?target)
            (?target :agent/name ?name))
   '(((reachable ?a ?b) (?a :agent/parent ?b))
     ((reachable ?a ?b) (?a :agent/parent ?mid) (reachable ?mid ?b)))
   :running)
```

Rules are passed as the first positional argument after `%` in `:in`. The engine unifies variables, handles multiple clauses per rule head (OR semantics), and uses a visited-set to prevent infinite recursion. Compiled queries use four strategies (value-index, direct-lookup, cache-scan, full-scan) but rule-containing queries fall back to interpretation.

**This is essentially a limited Prolog already embedded in the substrate.** Shen Prolog would be a more expressive, mature version of the same concept — with pattern matching, cut, negation-as-failure, and full bidirectional unification.

#### 3b. The Conductor's Event Dispatch

`dispatch-event` at `packages/core/src/orchestration/conductor.lisp:167` is a `case` form:

```lisp
(case event-type
  (:task-result ...)
  ((:team-created :team-started ...) ...)
  ((:swarm-evolution-started ...) ...)
  (otherwise nil))
```

The `otherwise` branch is a silent no-op. New event types are handled by adding `case` branches.

The **timer heap's `otherwise`** branch at line 127 is more interesting: unrecognized `:action-type` values automatically route to `queue-event`, feeding them back into the substrate event queue. This means any new timer action type naturally flows through the event system.

A Shen Prolog rule engine could sit at the `dispatch-event` level, replacing the static `case` with dynamic rule matching:

```shen
(defprolog handle-event
  :task-result Data <-- (task-completed Data);
  :agent-idle  Data <-- (when (idle-too-long Data))
                        (schedule-wakeup Data);
  EventType    Data <-- (log-unhandled EventType Data);)
```

#### 3c. The Cognitive `reason` Phase

The `reason` generic at `packages/core/src/agent/cognitive-loop.lisp:18` receives observations and returns understanding. Specializing it with Shen Prolog:

```lisp
(defmethod reason ((agent shen-agent) observations)
  ;; Convert observations to Prolog facts
  ;; Query agent's knowledge base
  ;; Return derived conclusions as understanding
  (shen-query agent observations))
```

#### 3d. The Heuristic Condition Matcher

`condition-matches-p` at `packages/core/src/agent/learning.lisp:324` is a recursive S-expression pattern matcher supporting `:any`, `(:type ...)`, `(:member ...)`, `(and ...)`, `(or ...)`, `(not ...)`. It's separate from Datalog and operates on arbitrary S-expressions. Shen Prolog could subsume this — heuristic conditions expressed as Prolog predicates would be strictly more powerful than the current combinators.

### 4. Existing Shen Research

The prior research document `thoughts/shared/research/2026-03-23-shen-ap-integration-surface-analysis.md` mapped 6 integration surfaces focused on Shen as a **type verification layer** for agent self-modification:

1. Extension compiler validation pipeline (between `validate-extension-source` and `compile`)
2. Persistent agent struct (new fields for invariants, capability types, knowledge base)
3. Agent self-modification flow (define→test→promote pipeline)
4. Snapshot metadata (storing proofs in the DAG)
5. ASDF system definition (new `autopoiesis/shen` module)
6. Jarvis dispatch (Shen REPL tool)

That research focused on verification. This research adds two new integration surfaces: **eval verifiers** and **orchestration control**.

## Code References

### Eval verifier registration
- `packages/eval/src/verifiers.lisp:12-18` — Registry and `register-verifier`
- `packages/eval/src/verifiers.lisp:24-73` — `run-verifier` dispatcher (4-branch etypecase)
- `packages/eval/src/verifiers.lisp:118-149` — Filesystem-aware verifiers (pattern for Prolog verifiers)
- `packages/eval/src/scenario.lisp:11-45` — `create-scenario` stores verifier designator as datom
- `packages/eval/src/run.lisp:119-195` — `execute-single-trial` wiring

### Orchestration extension points
- `packages/core/src/orchestration/conductor.lisp:167-191` — `dispatch-event` case form
- `packages/core/src/orchestration/conductor.lisp:85-128` — `execute-timer-action` dispatch
- `packages/core/src/orchestration/conductor.lisp:140-149` — `queue-event`
- `packages/substrate/src/datalog.lisp:784-844` — `q` function (Datomic-style queries)
- `packages/substrate/src/datalog.lisp:846-963` — Rule evaluation with SLD resolution
- `packages/substrate/src/linda.lisp:39-81` — `take!` atomic claim

### Cognitive reasoning injection
- `packages/core/src/agent/cognitive-loop.lisp:18` — `reason` generic
- `packages/core/src/agent/cognitive-loop.lisp:50-69` — `cognitive-cycle` orchestration
- `packages/core/src/agent/learning.lisp:324-374` — `condition-matches-p` S-expression matcher

### Prior Shen research
- `thoughts/shared/research/2026-03-23-shen-ap-integration-surface-analysis.md` — Type verification surface mapping

## Architecture Documentation

### Three Existing Logic Systems in the Codebase

The codebase already has three independent logic/pattern systems:

| System | Location | Capabilities | Scope |
|--------|----------|-------------|-------|
| **Datalog** | `packages/substrate/src/datalog.lisp` | Query substrate datoms with variables, recursive rules, negation, compiled queries | Substrate entities only |
| **Condition matcher** | `packages/core/src/agent/learning.lisp:324` | S-expression pattern matching: `:any`, `(:type)`, `(:member)`, `(and/or/not)` | Arbitrary S-expressions |
| **Eval verifiers** | `packages/eval/src/verifiers.lisp` | Keyword-dispatched output checking: string search, regex, file existence, tree matching | Harness output + metadata |

Shen Prolog would be a fourth system that subsumes aspects of all three: it can query facts (like Datalog), match patterns (like the condition matcher), and verify outputs (like eval verifiers), but with full bidirectional unification, backtracking, and user-defined rules.

### The `shen-cl` Integration Path

Shen runs on SBCL via `shen-cl`. The bootstrap produces KLambda (57 primitives) → CL `.lsp` files → SBCL binary. Integration in Autopoiesis would:

1. Load Shen into the running SBCL image (`:SHEN` package, case-sensitive)
2. Define AP-specific Prolog predicates via `defprolog` for eval verification
3. Bridge via `shen-cl.eval-lisp` (Shen→CL) and `shen-utils:load-shen` (CL→Shen)
4. Serialize Prolog knowledge bases as S-expressions in persistent agent metadata pmaps

Threading note: Shen uses global mutable state. All Shen calls must be serialized through a `*shen-lock*` or each thread needs its own environment.

## Historical Context (from thoughts/)

- `thoughts/shared/research/2026-03-23-shen-ap-integration-surface-analysis.md` — Comprehensive mapping of 6 integration surfaces for Shen as a verification layer. Covers extension compiler pipeline, persistent agent struct, self-modification flow, snapshot metadata, ASDF structure, and Jarvis dispatch. Notes that `shen-cl` is unmaintained and Shen bootstraps via `install.lsp` not ASDF.

## Related Research

- `thoughts/shared/research/2026-03-26-full-codebase-architecture.md` — Full architecture documentation (same session)
- `thoughts/shared/research/2026-03-23-agent-eval-platform-feasibility.md` — Eval platform design
- `thoughts/shared/research/2026-02-16-substrate-extension-points-gap-analysis.md` — Substrate extension analysis
- `thoughts/shared/research/2026-02-18-baml-integration-surface-analysis.md` — BAML typed LLM functions (type-checking adjacent)

## Open Questions

1. **Shen-cl maintenance**: The `shen-cl` repository is officially unmaintained. Active Shen development has moved to `shen-scheme`. Is there a maintained CL port, or would AP need to maintain a fork?

2. **Threading isolation**: A single `*shen-lock*` serializes all Shen calls. For concurrent eval trials (which use `lparallel:pmap`), this could be a bottleneck. Can Shen environments be isolated per-thread?

3. **Datalog subsumption**: The substrate's Datalog engine already provides recursive rule evaluation over datoms. Would Shen Prolog replace it, wrap it, or complement it? The Datalog engine has compiled query optimization that Shen Prolog would not.

4. **Knowledge base persistence**: Where do Prolog facts/rules live? Options: persistent agent metadata pmap (per-agent), substrate datoms (global, queryable), or Shen-native global state (in-memory only).

5. **ASDF bootstrapping**: Shen loads via `install.lsp`, not ASDF. The `autopoiesis/shen` system needs a strategy for ensuring Shen is available — feature conditional, custom `:perform` method, or a load-time side effect.
