---
date: 2026-03-23T12:00:00-07:00
researcher: claude
git_commit: b6eac4193625e3581c1c73f1d7efb84b3b3933c0
branch: main
repository: autopoiesis
topic: "Agent Evaluation Platform: Using Autopoiesis Infrastructure for Multi-Harness Evals"
tags: [research, evaluation, evals, metrics, agent-comparison, ralph-loop, multi-provider, fitness, llm-judge]
status: complete
last_updated: 2026-03-23
last_updated_by: claude
---

# Research: Agent Evaluation Platform — Using Autopoiesis for Multi-Harness Evals

**Date**: 2026-03-23
**Researcher**: claude
**Git Commit**: b6eac4193625e3581c1c73f1d7efb84b3b3933c0
**Branch**: main
**Repository**: autopoiesis

## Research Question

Can Autopoiesis serve as a platform for evaluating different agent systems (ralph loop, Claude team of agents, various harnesses)? The challenge is threefold: (1) flexibility to support wildly different harnesses and systems, (2) tracking both "squishy" metrics (LLM-as-judge quality assessment) and hard data (time, cost, pass/fail), and (3) crystallizing reusable test scenarios that work across implementations with different nuances but equivalent outcomes. There's also the question of what abstraction level evals should operate at.

## Summary

Autopoiesis has an unusually strong foundation for this. Six existing infrastructure pieces map directly to eval platform requirements: multi-provider harness abstraction (6+ providers already wrapped), the substrate datom store (schema-free EAV that can model eval entities without migration), thought-stream trajectory capture (every cognitive phase recorded as S-expressions), the conductor's concurrent worker management, the swarm fitness evaluation system (the only existing automated agent scoring code), and the monitoring/profiling/audit infrastructure (defined but largely unwired — available to be repurposed).

The tricky problems the user identifies are real and worth examining in detail: harness heterogeneity, metric duality (hard vs. squishy), scenario portability across implementations, and abstraction levels. This document maps each challenge against what exists in the codebase today.

## Detailed Findings

### 1. The Harness Flexibility Problem

The core challenge: different agent systems have fundamentally different interfaces, execution models, and observability surfaces.

#### What Exists: Provider Abstraction Layer

The multi-provider architecture in `platform/src/integration/` already solves the "wrapping different CLIs" problem:

**`provider` base class** (`provider.lisp:13`): generic protocol with `provider-invoke`, `provider-build-command`, `provider-parse-output`, `provider-start-session`, `provider-send`, `provider-send-streaming`.

**`define-cli-provider` macro** (`provider-macro.lisp:103`): generates a complete provider class from a declarative spec — command name, output format, session style.

**Six concrete providers already exist:**

| Provider | Wraps | Output Format | Session Model |
|---|---|---|---|
| `claude-code-provider` | `claude` CLI | stream-json | Per-invocation |
| `codex-provider` | `codex` CLI | parsed | Per-invocation |
| `opencode-provider` | `opencode` CLI | parsed | Per-invocation |
| `cursor-provider` | `cursor-agent` CLI | parsed | Per-invocation |
| `rho-provider` | `rho-cli` | JSONL stream | `--resume` continuation |
| `pi-provider` | `pi` RPC | JSON line-delimited | Long-lived subprocess |

**`inference-provider`** (`provider-inference.lisp:19`): for direct API calls (Anthropic, OpenAI, Ollama) — runs `agentic-loop` in-process.

**`provider-result`** (`provider-result.lisp`): captures `text`, `tool-calls`, `turns`, `cost` (USD), `duration` (seconds), `exit-code`, `raw-output`, `error-output`, `session-id`, `metadata`. This is the uniform output contract.

#### Where It Gets Tricky

The provider abstraction works well for systems that look like "send prompt, get response." But the user's list includes fundamentally different execution models:

- **Ralph loop** (`platform/ralph/loop.sh`): A bash script that iterates a CLI tool in a `while true` loop, reading `PROMPT_build.md` or `PROMPT_plan.md` each iteration, with persistent state in `IMPLEMENTATION_PLAN.md` and git commits. Ralph is NOT invoked once — it's an autonomous loop that runs for up to 30 iterations, each spawning a fresh context window. Wrapping this as a provider would mean the provider represents the entire loop run, not a single turn.

- **Team strategies** (`platform/src/team/`): Nine strategies (leader-worker, parallel, pipeline, debate, consensus, plus four composites) coordinate multiple agent IDs via the strategy protocol. An eval of a team isn't an eval of a single agent — it's an eval of the coordination pattern.

- **Jarvis NL→tool loop** (`platform/src/jarvis/loop.lisp`): A conversational multi-turn loop where human input triggers tool dispatch, with optional supervisor checkpoints. The "input" is a sequence of human turns, not a single prompt.

- **SCUD swarming**: An external task manager that spawns work across a DAG of dependencies.

The insight is that the provider abstraction handles the "leaf node" problem (wrapping individual CLI tools) but not the "orchestration pattern" problem. An eval comparing Ralph-loop-with-Claude vs. team-of-three-Claude-agents vs. single-Jarvis-session is comparing fundamentally different shapes of execution.

**What exists to handle this:** The team layer's `strategy-assign-work` / `strategy-collect-results` / `strategy-complete-p` protocol is already a higher-level abstraction over multi-agent execution. The conductor's event queue (`queue-event` → `take!` → `dispatch-event`) is already the orchestration backbone for concurrent work. These could serve as the "eval harness" layer above the provider layer.

### 2. The Metrics Duality Problem

The user wants both "hard data" (time, cost, pass/fail, turn count) and "squishy metrics" (LLM-as-judge quality assessment). These have fundamentally different collection and storage patterns.

#### Hard Metrics: What Exists

**`provider-result`** already captures the core hard metrics per invocation:
- `provider-result-turns` — integer turn count
- `provider-result-cost` — float USD cost
- `provider-result-duration` — float seconds
- `result-success-p` — boolean (exit-code = 0)

**Conductor metrics** (`conductor.lisp:16-37`): in-memory hash table tracking `:tick-count`, `:events-processed`, `:events-failed`, `:timer-errors`, `:task-retries`, `:team-events`, `:team-tasks-completed`, `:swarm-events`, `:swarm-generations`.

**Profiling system** (`core/profiling.lisp`): `with-timing` macro with nanosecond precision, `profile-metric` struct tracking call-count, total/min/max/last time, `benchmark` function for N-iteration measurement. `identify-hot-paths` finds operations exceeding time/call thresholds.

**Monitoring endpoints** (`monitoring/endpoints.lisp`): Prometheus-format metrics with counter, gauge, and histogram types. `record-request-metric`, `record-agent-metric`, `record-snapshot-metric` are defined but notably **not wired** to actual call sites in the codebase. They're available infrastructure waiting for consumers.

**Audit log** (`security/audit.lisp`): JSON-line structured logging with `audit-entry` struct (timestamp, agent-id, action, resource, result, details), rotation at 10MB, queryable by any field combination via `read-audit-log`.

#### Squishy Metrics: What Exists

**Swarm fitness evaluation** (`swarm/fitness.lisp`) is the only existing automated scoring system:

- `fitness-evaluator` class with `eval-fn: (genome, environment) -> float`
- `evaluate-population` with optional `lparallel:pmap` parallelism
- Three composable scalar fitness functions in `persistent-fitness.lisp`:
  - `thought-diversity-fitness` — ratio of unique thought types, bonus for covering all 5 cognitive phases
  - `capability-breadth-fitness` — capability count / max, capped at 1.0
  - `genome-efficiency-fitness` — capabilities per genome form
- `make-standard-pa-evaluator` — weighted composite (0.4 diversity + 0.3 breadth + 0.3 efficiency)

This is a real evaluation framework, but it evaluates agent *configuration* (genome traits), not agent *output quality*. An LLM-as-judge system would need to evaluate the *result* of an agent's work — did the code compile? Does the PR description make sense? Is the research document thorough?

**Experience/learning system** (`agent/learning.lisp`): records outcomes as `:success`/`:failure`/`:partial` with confidence scoring using Bayesian-style decay. `calculate-pattern-confidence` from frequency and outcome type. This is a feedback loop, not an eval, but the confidence-scoring pattern could inform judge calibration.

**Capability test/promote pattern** (`agent/agent-capability.lisp:128-248`): `test-agent-capability` runs test cases returning `(values passed-p results)` with per-case `:status` (`:pass`/`:fail`/`:error`), `:input`, `:expected`, `:actual`. This is structurally identical to a deterministic verifier — the gap is just that it tests capabilities, not arbitrary agent outputs.

#### The LLM-as-Judge Gap

Nothing in the codebase today implements LLM-as-judge evaluation. But the infrastructure to build it exists:

- The `agentic-loop` (`claude-bridge.lisp:163`) already handles multi-turn LLM conversations with tool use — a judge could be an agentic-agent that receives the eval output and returns a structured assessment
- The SKEL/BAML system (`platform/src/skel/`) provides typed LLM functions with JSON schema validation — `define-skel-function` could define a judge function with a structured return type (scores, rationale, pass/fail)
- SAP preprocessing (`skel/sap.lisp`) handles the messy reality of LLM JSON output — `strip-markdown-fences`, `fix-unquoted-keys`, `normalize-json-ish`
- The substrate can store judge assessments as datoms alongside hard metrics, queryable via the same datalog engine

### 3. The Scenario Portability Problem

The user identifies a deep problem: you want reusable test scenarios, but different implementations have different nuances, and "the same test runner" can't apply to all of them. Two implementations might both "meet the spec" while producing very different artifacts.

#### What Exists: Spec and Verification Patterns

**FiveAM test suites** (`platform/test/`): 28 suites with 4,300+ assertions. The assertion patterns — `(is ...)`, `(is-true ...)`, `(signals ...)`, `(finishes ...)` — are all deterministic binary checks. No fuzzy matching.

**E2E tests** (`test/e2e-tests.lisp`): 15 user-story scenarios mapping to `platform/docs/user-stories.md`. These test component APIs directly (no mocks for most), including real threading (Story 3 spawns `bordeaux-threads`). The `with-clean-registries` and `with-temp-store` macros provide per-test isolation.

**Spec documents** (`platform/docs/specs/`): 9 markdown files describing intended behavior with Lisp code blocks showing API shapes. No machine-parseable requirements — the relationship to tests is by convention only.

**Capability testing** (`agent-capability.lisp`): The test/score/promote pattern compares actual output against expected output. But the comparison is equality-based, not semantic.

#### The Core Tension

The user is right that this is a "very tricky problem." Consider evaluating two systems against the spec "implement user authentication":

- System A produces a JWT module with bcrypt hashing in 3 files
- System B produces an OAuth2 integration with session tokens in 5 files

Both may correctly implement authentication. A deterministic verifier (does the auth endpoint return 200 with valid creds?) can check functional correctness, but not quality, maintainability, or architectural fitness. That's where the squishy metrics come in.

The existing infrastructure suggests a two-layer approach:

1. **Functional verification** (hard): use the capability test pattern — define verifier functions per scenario that check concrete postconditions (file exists, tests pass, endpoint responds correctly). This maps to `test-agent-capability`'s `(values passed-p results)` return shape.

2. **Quality assessment** (squishy): use LLM-as-judge — define assessment rubrics per scenario, have a judge agent score the output on dimensions like correctness, completeness, style, efficiency. This would be a new capability built on the SKEL typed function infrastructure.

#### Scenario Definition: What Could the Entity Look Like

Using the substrate's `define-entity-type`:

```lisp
(define-entity-type :eval-scenario
  (name :type string)
  (description :type string)
  (domain :type keyword)        ; :code-gen, :research, :refactoring, etc.
  (difficulty :type keyword)    ; :easy, :medium, :hard
  (spec :type string)           ; natural language specification
  (verifier-fn :type symbol)    ; function name for hard verification
  (rubric :type string)         ; LLM judge rubric for squishy assessment
  (setup-fn :type symbol)       ; optional environment setup
  (teardown-fn :type symbol))   ; optional cleanup
```

The `spec` field is what gets passed to the agent system (possibly reformulated per-harness). The `verifier-fn` checks postconditions. The `rubric` guides the LLM judge. This separates "what to evaluate" from "how to run it."

### 4. The Abstraction Level Problem

The user notes there are "different levels of abstraction with which you might reasonably want to do evals." This is a critical observation. At least four levels are visible:

#### Level 1: Single Turn (Prompt → Response)

Evaluate one LLM call. The `agentic-loop` with `max-turns 1` or `inference-provider` with a single invoke. Metrics: latency, cost, output quality. This is the simplest eval — essentially a prompt benchmark.

**Existing support:** `provider-invoke` returns a `provider-result` with all needed metrics. The `agentic-agent`'s `on-thought` callback captures the exact response.

#### Level 2: Multi-Turn Agentic Task

Evaluate a full agentic loop (tool calls, reasoning, iteration). The `agentic-loop` with default `max-turns 25`. Metrics: total turns, total cost, task completion, trajectory quality.

**Existing support:** The `agentic-agent` records 4 thoughts per turn via `record-provider-exchange`. The thought stream captures the full trajectory. `provider-result` aggregates turns and cost.

#### Level 3: Orchestrated Campaign (Ralph Loop, Team, Pipeline)

Evaluate an entire autonomous campaign — Ralph loop running 30 iterations, a team of 3 agents using debate strategy, a pipeline of specialist agents. Metrics: wall-clock time, total cost across all agents, final artifact quality, intermediate progress trajectory.

**Existing support:** The conductor tracks workers and events. Team strategies track completion state. Ralph loop writes git commits (measurable via `git log`). But there's no unified "campaign metrics" collector that spans these different shapes.

#### Level 4: System-Level Comparison

Compare two completely different approaches to the same goal — e.g., "Ralph loop with Claude Opus" vs. "team of 3 Sonnet agents in debate mode" vs. "single Opus agent with curated skills." This is the SkillsBench level.

**Existing support:** The snapshot system can capture before/after states. Branch comparison (`fork-branch` / `compare-branches` in `integration/builtin-tools.lisp:554-600`) enables structural diff between approaches. The substrate can store parallel eval runs as separate entity graphs. But orchestrating and comparing across levels 1-3 requires a meta-layer that doesn't exist yet.

### 5. The Swarm System as Eval Prototype

The swarm evolution system is the closest existing code to an eval framework. It already implements:

- **Population evaluation**: `evaluate-population` scores every genome in a population, optionally in parallel (`lparallel:pmap`)
- **Composite scoring**: `make-standard-pa-evaluator` combines multiple fitness dimensions with configurable weights
- **Generational tracking**: `population-history` records `(generation best-fitness avg-fitness)` per generation
- **Selection pressure**: Three selection operators (tournament, roulette, elitism) that consume fitness scores
- **Agent↔genome bridge**: `persistent-agent-to-genome` / `genome-to-persistent-agent-patch` for converting between runtime agents and evaluable genomes

The conceptual gap between "evaluate agent genome fitness" and "evaluate agent task performance" is the difference between measuring *what the agent is configured to do* vs. *what it actually did*. But the infrastructure — evaluation functions, population management, history tracking, selection — maps directly.

A key insight: the swarm's `fitness-evaluator` class (`fitness.lisp:12-24`) with its `eval-fn: (genome, environment) -> float` signature could be generalized to `(agent-output, scenario) -> score`. The `evaluate-population` parallelism, history tracking, and selection operators would all still apply.

### 6. Data Storage and Query Infrastructure

The substrate is uniquely suited for eval data because it's schema-free and supports temporal queries:

- **EAV flexibility**: New eval-related attributes can be added to any entity at any time without migration. An eval result could have 5 attributes today and 50 tomorrow.
- **Temporal queries**: `entity-history entity attribute` returns all values across transactions. `entity-as-of entity tx-id` reconstructs state at a past point. This enables "show me how this agent's eval scores changed over time."
- **Datalog**: Pattern matching with variables — `(query '((?e :eval-result/scenario ?s) (?e :eval-result/pass t) (?s :eval-scenario/domain :code-gen)))` finds all passing results in the code-gen domain.
- **Linda coordination**: `take! :eval-trial/status :pending :new-value :running` provides exactly-once task dispatch for concurrent eval runs.
- **Hooks**: `register-hook store name fn` fires after every `transact!` — an eval observer hook could automatically compute running statistics as results flow in.

### 7. Visualization and Reporting Infrastructure

The Command Center frontend already has views that could display eval results:

- **Dashboard** (`dag-explorer/src/components/Dashboard.tsx`): configurable cards showing agent status, events, costs — could show eval run progress
- **Evolution Lab** (`dag-explorer/src/components/EvolutionLab.tsx`): already has fitness history charting, population visualization — directly applicable to eval score tracking
- **Audit Log** (`dag-explorer/src/components/AuditLog.tsx`): filterable event log — could show eval trial results
- **Timeline** (`dag-explorer/src/components/TimelineView.tsx`): temporal view of events — could show eval progress over time

The WebSocket push infrastructure (`connections.lisp`, `wire-format.lisp`) already supports real-time data streaming to the frontend. An eval run could broadcast progress events that the Evolution Lab view (or a new Eval Dashboard view) renders in real-time.

The SSE bridge (`sse.lisp`) automatically forwards all integration events to connected clients — eval events emitted via `emit-integration-event` would be visible immediately.

## Architecture Documentation

### Infrastructure Inventory for Evals

| Infrastructure Piece | Location | Current State | Eval Applicability |
|---|---|---|---|
| Multi-provider abstraction | `src/integration/provider*.lisp` | 6+ providers, working | Wraps harnesses uniformly |
| Provider result capture | `src/integration/provider-result.lisp` | Captures turns/cost/duration | Hard metrics per invocation |
| Substrate datom store | `src/substrate/` | Working, 11 entity types | Schema-free eval data model |
| Datalog queries | `src/substrate/datalog.lisp` | Working | Eval result aggregation |
| Linda coordination | `src/substrate/linda.lisp` | Working | Exactly-once trial dispatch |
| Thought streams | `src/core/thought-stream.lisp` | Working | Trajectory capture |
| Cognitive primitives | `src/core/cognitive-primitives.lisp` | 4 thought types | Structured trajectory data |
| Snapshot diff/compare | `src/snapshot/diff-engine.lisp` | Working | Before/after comparison |
| Branch comparison | `src/integration/builtin-tools.lisp:554-600` | Working | A/B eval comparison |
| Conductor orchestration | `src/orchestration/conductor.lisp` | Working, 100ms tick | Concurrent trial execution |
| Swarm fitness evaluation | `src/swarm/fitness.lisp` | Working, parallel | Scoring framework prototype |
| Composite evaluators | `src/swarm/persistent-fitness.lisp` | 3 functions + composer | Multi-dimensional scoring |
| Population tracking | `src/swarm/population.lisp` | History per generation | Score tracking over time |
| Capability test/promote | `src/agent/agent-capability.lisp:128-248` | Working | Deterministic verifier pattern |
| SKEL typed functions | `src/skel/core.lisp` | Working | Typed LLM judge functions |
| SAP preprocessing | `src/skel/sap.lisp` | Working | Robust LLM output parsing |
| Experience/learning | `src/agent/learning.lisp` | Working | Confidence scoring pattern |
| Monitoring (Prometheus) | `src/monitoring/endpoints.lisp` | Defined, **unwired** | Available for eval metrics |
| Profiling | `src/core/profiling.lisp` | Working | Timing instrumentation |
| Audit logging | `src/security/audit.lisp` | Working | Durable eval event log |
| WebSocket push | `src/api/wire-format.lisp` | Working | Real-time eval progress |
| Evolution Lab UI | `dag-explorer/src/components/EvolutionLab.tsx` | Working | Fitness/score visualization |
| Ralph loop | `platform/ralph/loop.sh` | Working | Example harness to evaluate |
| Team strategies | `src/team/strategies/*.lisp` | 9 strategies | Multi-agent eval targets |
| Jarvis NL loop | `src/jarvis/loop.lisp` | Working | Interactive eval target |

### The Key Architectural Challenges

**1. Harness shape heterogeneity**: The provider abstraction assumes "invoke once, get result." Ralph loops, team campaigns, and multi-turn Jarvis sessions don't fit this shape. Need a "campaign" abstraction above providers.

**2. Metric aggregation across levels**: A team eval's "cost" is the sum of all member agents' costs. A Ralph loop's "duration" is wall-clock across all iterations. Need a hierarchical metric collector.

**3. Scenario portability without shared test runners**: Each harness needs its own invocation logic, but scenarios need a shared definition format. The substrate entity model (spec + verifier-fn + rubric) separates these concerns.

**4. LLM-as-judge reliability**: Judge scores are themselves noisy. Need multiple judge runs, calibration, and statistical analysis. The swarm's parallel evaluation (`lparallel:pmap` in `evaluate-population`) could handle this.

**5. Temporal comparison**: Evals done today should be comparable to evals done next month after code changes. Content-addressed snapshots and substrate temporal queries support this.

## Historical Context (from thoughts/)

- `thoughts/shared/research/2026-02-17-skillsbench-agent-evaluation-platform-feasibility.md` — Previous feasibility study mapping AP to SkillsBench requirements. Concluded "AP has unusually strong foundations" with gaps in task definition, campaign orchestration, and statistical analysis.
- `thoughts/shared/research/2026-02-17-unimplemented-ideas-review.md` — Inventory of unbuilt features including fitness evaluation and benchmark infrastructure.
- `thoughts/shared/plans/ap-substrate-evolution.md` — Substrate evolution plan covering fitness functions and swarm evaluation.
- `thoughts/shared/plans/2026-03-02-team-of-agents-plan.md` — Team agent plan including evaluation and quality metrics.
- `thoughts/shared/plans/2026-02-06-super-agent-implementation.md` — Ralph loop design and scoring mechanisms.
- `thoughts/shared/research/2026-02-03-autopoiesis-real-agent-use-cases.md` — 20 real agent use cases including framework comparisons.

## Related Research

- `thoughts/shared/research/2026-02-17-skillsbench-agent-evaluation-platform-feasibility.md` — The most directly related prior research
- `thoughts/shared/research/2026-02-03-e2e-tests-vs-implementation.md` — Test coverage methodology
- `thoughts/shared/research/2026-03-02-platform-architecture-deep-dive.md` — Architecture deep dive covering swarm fitness

## Open Questions

1. **Campaign abstraction**: What's the right interface for wrapping a Ralph loop, a team debate, and a single-agent task under the same eval harness? The provider protocol handles the leaf; what handles the tree?

2. **Judge calibration**: How do you validate that LLM-as-judge scores are consistent and meaningful? Multiple judge runs with agreement metrics? Calibration against human-scored examples? The swarm's parallel evaluation infrastructure could run multiple judges, but the calibration logic would be new.

3. **Scenario versioning**: As scenarios evolve, how do you maintain comparability? Content-addressed snapshot hashing could version-stamp scenario definitions, but you need a policy for when old results are still "comparable" to new runs.

4. **Isolation model**: SkillsBench uses Docker containers per task. AP has workspace isolation (`src/workspace/`) with ephemeral contexts, but not container-level isolation. Is workspace isolation sufficient, or do evals need stronger boundaries?

5. **What to eval first**: The user mentioned ralph loop, Claude team, and "various systems." What's the minimum viable eval that demonstrates the platform's value? Probably: two different harnesses, one scenario, both hard and squishy metrics.

6. **Statistical rigor**: How many trials per scenario to get meaningful results? SkillsBench uses 5 trials. With LLM-as-judge variance, you might need more. No statistical analysis library exists in the codebase — this would need to be added or delegated externally.
