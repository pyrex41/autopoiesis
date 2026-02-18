---
date: 2026-02-17T12:00:00-08:00
researcher: claude
git_commit: e826774713fbe6c3f730474c1a059f638927a2ae
branch: main
repository: autopoiesis
topic: "Can Autopoiesis serve as a platform for agent framework evaluation (SkillsBench-style)?"
tags: [research, evaluation, benchmarking, skillsbench, agent-frameworks, multi-provider, orchestration]
status: complete
last_updated: 2026-02-17
last_updated_by: claude
---

# Research: Can Autopoiesis Serve as an Agent Evaluation Platform?

**Date**: 2026-02-17
**Researcher**: claude
**Git Commit**: e826774713fbe6c3f730474c1a059f638927a2ae
**Branch**: main
**Repository**: autopoiesis

## Research Question

The user wants to evaluate multiple agent harnesses (Claude Code, Human Layer / Code Layer, hand-rolled implementations, SCUD CLI swarming, various Ralph loop implementations) against baselines using a SkillsBench-style methodology. The question is whether Autopoiesis would be a good platform to build this evaluation framework on.

## Summary

**Short answer: Yes, AP has unusually strong foundations for this.**

Autopoiesis already has most of the infrastructure pieces that an agent evaluation framework requires. The SkillsBench paper (2602.12670v1) identifies six key requirements for an agent evaluation framework: (1) harness abstraction across multiple agent systems, (2) task specification with deterministic verifiers, (3) trajectory capture for analysis, (4) metrics collection (pass rates, turn counts, cost, duration), (5) controlled experimental conditions (Skills vs. no-Skills, different models), and (6) result comparison. AP's existing architecture maps to all six, though each would need an evaluation-specific extension layer on top.

The strongest fits are the multi-provider architecture (already wraps Claude Code, Codex, OpenCode, and Cursor as CLI providers plus Anthropic/OpenAI/Ollama as direct API providers), the substrate's EAV datom store (flexible enough to model evaluation runs, task definitions, and results as entities), and the thought-stream trajectory capture (every observation, decision, action, and reflection is already recorded as an S-expression in the agent's cognitive stream).

The main gaps are: no existing "task definition + verifier" abstraction, no "evaluation run" entity type that ties together a set of tasks run under a specific configuration, and no reporting/aggregation layer for computing pass rates and normalized gains across runs. These would all need to be built, but the primitives to build them on are solid.

## The SkillsBench Paper

**Source**: [SkillsBench: Benchmarking How Well Agent Skills Work Across Diverse Tasks](https://arxiv.org/html/2602.12670v1)

SkillsBench evaluates 84 tasks across 11 domains, testing 7 agent-model configurations across 3 commercial harnesses (Claude Code, Gemini CLI, Codex CLI) under 3 conditions (no Skills, curated Skills, self-generated Skills). It produced 7,308 trajectories and found curated Skills improved pass rates by +16.2pp on average, but effects varied dramatically by domain (+51.9pp in Healthcare, +4.5pp in Software Engineering).

Key design elements relevant to AP:
1. **Task specification**: instruction + containerized environment + oracle solution + deterministic verifier
2. **Evaluation conditions**: same task run with/without Skills, across different agent-model pairs
3. **Primary metric**: binary pass/fail per task, averaged across 5 trials
4. **Secondary metric**: normalized gain (Hake's g) to account for ceiling effects
5. **Quality control**: automated structural checks + human review + leakage prevention
6. **Finding**: 2-3 Skills are optimal; self-generated Skills provide -1.3pp (models can't reliably author the procedural knowledge they benefit from consuming)

## Detailed Findings

### 1. Multi-Provider Architecture: Harness Abstraction

AP's integration layer already implements the core abstraction SkillsBench needs: a uniform interface for invoking different agent harnesses and capturing their outputs.

**CLI Provider Protocol** (`src/integration/provider.lisp`):
- Base `provider` class with generic functions: `provider-invoke`, `provider-build-command`, `provider-parse-output`
- `define-cli-provider` macro generates a complete provider class from a declarative spec
- 4 concrete providers already defined:
  - `claude-code-provider` (`src/integration/provider-claude-code.lisp`) — wraps `claude` CLI
  - `codex-provider` (`src/integration/provider-codex.lisp`) — wraps `codex` CLI
  - `opencode-provider` (`src/integration/provider-opencode.lisp`) — wraps `opencode` CLI
  - `cursor-provider` (`src/integration/provider-cursor.lisp`) — wraps `cursor-agent` CLI

**Direct API Providers** (`src/integration/provider-inference.lisp`):
- `inference-provider` runs `agentic-loop` directly via HTTP
- Constructors: `make-anthropic-provider`, `make-openai-provider`, `make-ollama-provider`
- The `*claude-complete-function*` dynamic variable allows swapping the backend (Anthropic vs OpenAI format)

**Provider Result** (`src/integration/provider-result.lisp`):
- `provider-result` class captures: `text`, `tool-calls`, `turns`, `cost` (USD), `duration` (seconds), `exit-code`, `raw-output`, `error-output`, `session-id`, `metadata`
- `result-success-p` checks `exit-code = 0`

**Provider Registry** (`src/integration/provider.lisp:204`):
- `*provider-registry*` hash table with `register-provider`, `find-provider`, `list-providers`

**Relevance to evaluation**: Your Claude Code, hand-rolled loops, and Ralph implementations can each be wrapped as a `provider`. SCUD swarming would need a different integration path (likely a custom provider that spawns SCUD tasks and collects results). The `provider-result` already captures turns, cost, and duration — the core metrics SkillsBench tracks.

### 2. Substrate: Flexible Data Model for Evaluation State

The datom store (`src/substrate/`) provides a schema-flexible EAV triple store that can model evaluation entities without predefined schemas.

**Data Primitives**:
- `make-datom` — creates `(entity, attribute, value, tx, added)` tuples; entity/attribute positions auto-intern from keywords
- `transact!` — atomic write with monotonic tx-id, index updates, LMDB persistence, and post-commit hooks
- `entity-attr` — O(1) read of current value for `(entity, attribute)`
- `entity-state` — full plist reconstruction of an entity
- `find-entities` — O(1) lookup via inverted value index: given `(attribute, value)`, returns all matching entity IDs
- `take!` — Linda-style atomic claim-and-transition for queue processing

**Entity Types Already Defined** (`src/substrate/builtin-types.lisp`):
- `:event`, `:worker`, `:agent`, `:session`, `:snapshot`, `:turn`, `:context`

**New Entity Types Needed for Evaluation** (not yet defined but trivial to add):
- `:eval-task` — task definition with instruction, verifier reference, domain, difficulty
- `:eval-run` — configuration (provider, model, skills condition, run ID)
- `:eval-trial` — single task execution within a run (links to `:eval-task` + `:eval-run`)
- `:eval-result` — pass/fail outcome, turn count, cost, duration, trajectory reference

The substrate's `define-entity-type` macro would create CLOS wrappers for lazy attribute access. Or these could be stored as raw datoms without type declarations — the type system is advisory, not enforced. The `defsystem` reactive system could automatically compute aggregates (e.g., update pass-rate when a trial result is written).

**Temporal Queries**: `entity-history` retrieves all values of an attribute across all transactions, sorted by tx-id. `entity-as-of` reconstructs full entity state at a past transaction. These enable retrospective analysis of evaluation runs.

**Datalog Queries** (`src/substrate/datalog.lisp`): Full datalog with variable binding, negation, and O(1) value-index-backed first-clause resolution. Could express: "find all trials for provider X where pass=true and domain=Healthcare."

### 3. Trajectory Capture: Agent Thought Streams

AP's cognitive primitives already model the full trajectory that SkillsBench needs to capture.

**Thought Types** (`src/core/cognitive-primitives.lisp`):
- `observation` — what the agent perceived (`:source`, `:raw`, `:interpreted`)
- `decision` — what the agent chose (`:alternatives` with scores, `:chosen`, `:rationale`, `:confidence`)
- `action` — what the agent did (`:capability`, `:arguments`, `:result`, `:side-effects`)
- `reflection` — what the agent concluded (`:target`, `:insight`, `:modification`)

**Thought Stream** (`src/core/thought-stream.lisp`):
- Adjustable vector with O(1) ID lookup
- `stream-append`, `stream-find`, `stream-last`, `stream-since`, `stream-by-type`, `stream-range`
- `stream-to-sexpr` / `sexpr-to-stream` for full serialization
- `compact-thought-stream` with archival for long-running agents

**Recording in Provider Agents** (`src/integration/provider-result.lisp:129`):
- `record-provider-exchange` writes exactly 4 thoughts per invocation: observation of prompt, action per tool call, observation of result, reflection summary
- For the agentic-agent path, `on-thought` callbacks capture every LLM response, tool execution, and tool result as they happen

**Snapshot System** (`src/snapshot/`):
- Content-addressed snapshots include the full agent state (including thought stream) as an S-expression
- `snapshot-diff` computes structural diffs between two agent states via `sexpr-diff`
- DAG branching enables comparing different evaluation conditions as branches from the same root
- `dag-distance` quantifies how far apart two trajectories diverged

### 4. Orchestration: Running Multiple Evaluation Trials

The conductor (`src/orchestration/conductor.lisp`) manages concurrent work via a tick loop + timer heap + substrate-backed event queue.

**Conductor Capabilities**:
- 100ms tick loop processes timer-scheduled actions and substrate events
- `schedule-action` queues work with configurable delays
- `queue-event` creates substrate-backed events (survive restarts)
- `register-worker` / `unregister-worker` track concurrent workers with substrate datoms
- `handle-task-result` processes completions/failures with exponential backoff tracking
- No concurrency cap — each scheduled `:claude` action spawns an independent thread

**How Evaluation Runs Would Work**:
1. Define an evaluation run configuration as a substrate entity (provider, model, skills condition)
2. For each task in the evaluation set, `queue-event` with type `:eval-trial`
3. The conductor's `dispatch-event` would be extended to handle `:eval-trial` events
4. Each trial spawns a worker via `run-claude-cli` or `provider-invoke`
5. Results flow back via `handle-task-result` → substrate datoms
6. `take!` ensures no double-processing of trials

**Concurrent Runs**: Multiple evaluation configurations can run simultaneously. Each worker is an independent thread. The substrate serializes writes via `store-lock`. The conductor tracks all active workers via `find-entities :worker/status :running`.

### 5. Event Bus: Observing Agent Behavior

The integration event bus (`src/integration/events.lisp`) captures 16 event types including `:provider-request`, `:provider-response`, `:tool-called`, `:tool-result`, `:claude-request`, `:claude-response`.

**Event Capabilities**:
- `emit-integration-event` creates timestamped events with source, agent-id, and data plist
- `subscribe-to-event` / `subscribe-to-all-events` for real-time observation
- `get-event-history` with filtering by type, source, agent-id, and limit
- `count-events` with type, source, and since-timestamp filters
- Events are capped at 1000 in history (configurable via `*max-event-history*`)

**Relevance**: An evaluation observer could subscribe to all events to build a detailed timeline of what each agent did during a trial, separate from the thought-stream trajectory.

### 6. Monitoring and Metrics

**HTTP Monitoring** (`src/monitoring/endpoints.lisp`):
- `/metrics` endpoint in Prometheus exposition format
- `/health`, `/healthz`, `/readyz` endpoints
- `record-metric`, `increment-counter`, `set-gauge`, `observe-histogram`
- Histogram buckets with cumulative semantics

**Core Profiling** (`src/core/profiling.lisp`):
- `with-timing` macro with zero-overhead when disabled
- `benchmark` function for N-iteration measurement returning ops/sec, avg/min/max timing
- `with-memory-tracking` for allocation measurement (SBCL-specific)
- `profile-report` returning sorted operations with call count and timing statistics

**Audit Trail** (`src/security/audit.lisp`):
- JSON-line audit log with rotation (10MB default, 5 files)
- `with-audit` macro wraps operations with success/failure/error recording
- Filterable by agent-id, action, resource, result, time range

### 7. Existing Evaluation-Adjacent Patterns

AP already has several patterns that directly parallel SkillsBench's evaluation methodology:

**Capability Test/Score/Promote** (`src/agent/agent-capability.lisp:128-248`):
- `test-agent-capability` runs test cases, returns `(values passed-p results)`
- Each result has `:status` (`:pass`, `:fail`, `:error`), `:input`, `:expected`, `:actual`
- `promote-capability` gates on all-pass: `(every (lambda (r) (eq (getf r :status) :pass)) ...)`
- This is structurally identical to SkillsBench's deterministic verifier pattern

**Mock Infrastructure** (`test/agentic-tests.lisp:24-95`):
- `with-mock-claude` replaces the API with scripted responses
- `mock-provider` captures `invoke-count` and `last-prompt`
- Enables running controlled experiments without real API calls

**Experience/Heuristic Learning** (`src/agent/learning.lisp`):
- `experience` records `(task-type, context, actions, outcome)` — outcome is `:success`/`:failure`/`:partial`
- `extract-action-sequences` does n-gram analysis with frequency scoring
- `calculate-pattern-confidence` computes confidence from frequency and outcome type
- `update-heuristic-confidence` applies Bayesian-style decay (0.9 for failure, 0.95 for partial)

**Branch Comparison** (`src/integration/builtin-tools.lisp:554-600`):
- `fork-branch` creates evaluation branches; `compare-branches` diffs two branch heads
- `dag-distance` quantifies divergence between two snapshot paths
- This maps directly to comparing agent trajectories under different conditions

### 8. What Would Need to Be Built

**Task Definition Layer**:
- An `:eval-task` entity type with attributes for instruction, domain, difficulty, verifier-fn, environment-spec
- A task loader that reads task definitions (from files or substrate)
- Verifier functions that return binary pass/fail — could reuse `test-agent-capability`'s pattern

**Evaluation Run Orchestration**:
- A higher-level abstraction over the conductor that manages "evaluation campaigns"
- Configuration entity: `(:eval-run/provider :claude-code :eval-run/model "opus-4.6" :eval-run/skills-condition :curated :eval-run/num-trials 5)`
- A dispatch loop that creates `:eval-trial` events for each (task, run) pair
- Result collection callbacks that write `:eval-result` datoms

**Skills/Prompt Injection System**:
- A mechanism to inject "Skills" (procedural knowledge packages) into the agent's context before a trial
- For CLI providers: could be prepended to the prompt or passed as files
- For direct API providers: could be added to the system prompt

**Aggregation and Reporting**:
- Compute pass rate: count trials where verifier returned true / total trials
- Compute normalized gain (Hake's g): `(pass_skill - pass_vanilla) / (1 - pass_vanilla)`
- Group by domain, difficulty, provider, model, skills condition
- The substrate's `find-entities` and datalog queries can drive this, but a dedicated reporting layer would be cleaner

**Provider Extensions for Your Specific Harnesses**:
- Human Layer / Code Layer: would need a new `define-cli-provider` or a custom provider class
- SCUD swarming: likely a custom provider that spawns SCUD tasks and polls for results
- Ralph loop variants: each variant would be wrapped as a distinct provider
- Hand-rolled implementations: each wraps as a provider

## Architecture Documentation

### How AP's Layers Map to SkillsBench Requirements

| SkillsBench Requirement | AP Layer | Existing Support | Gap |
|---|---|---|---|
| Harness abstraction | Integration (multi-provider) | 4 CLI + 3 API providers | Need custom providers for your harnesses |
| Task specification | Substrate (entity types) | Entity type system exists | Need `:eval-task` type + verifiers |
| Deterministic verifiers | Agent (capability testing) | `test-agent-capability` pattern | Need task-specific verifier fns |
| Trajectory capture | Core (thought stream) + Snapshot | Full trajectory as S-expressions | Already works; need evaluation-specific tagging |
| Controlled conditions | Snapshot (branching) | Branch/fork/compare infrastructure | Need skills injection mechanism |
| Metrics (pass rate, cost, turns) | Integration (provider-result) + Monitoring | `provider-result` captures all four | Need aggregation layer |
| Multiple trials | Orchestration (conductor) | Concurrent worker management | Need evaluation campaign orchestrator |
| Result comparison | Snapshot (diff) + Core (sexpr-diff) | Structural diff of agent states | Need statistical comparison (t-tests, etc.) |
| Leakage prevention | Security (permissions, sandbox) | Permission system + validation | Need task-specific isolation |

### Strengths of AP for This Use Case

1. **Homoiconic state**: Every agent thought, decision, action, and result is an S-expression. This means evaluation data is automatically introspectable, diffable, and serializable without any additional instrumentation.

2. **Content-addressed snapshots**: Each evaluation trial naturally produces a snapshot that can be compared to others via `sexpr-diff`. The DAG structure enables branching experiments.

3. **Substrate flexibility**: The EAV datom store doesn't require schema migrations. New entity types and attributes can be added at any time. `define-entity-type` is optional — raw datoms work for prototyping.

4. **Multi-provider architecture**: The `define-cli-provider` macro makes it straightforward to add new CLI-based agent harnesses. The `inference-provider` class handles direct API backends.

5. **Event bus + audit trail**: Real-time observation of agent behavior during trials, plus durable audit logging for post-hoc analysis.

6. **Linda coordination**: `take!` provides exactly-once processing guarantees for evaluation task dispatch, preventing double-processing in concurrent evaluation runs.

7. **Temporal queries**: `entity-history` and `entity-as-of` enable retrospective analysis of how evaluation state evolved over time.

### Challenges and Considerations

1. **No containerized environment isolation**: SkillsBench uses Docker containers per task for state isolation. AP doesn't have container orchestration built in — this would need to be added or delegated to an external system.

2. **Single-machine concurrency**: The conductor runs threads, not distributed workers. For large evaluation campaigns (7,308 trajectories in SkillsBench), you'd want to either run multiple conductor instances or add distributed dispatch.

3. **No statistical analysis**: AP has profiling and basic metrics but no statistical testing (t-tests, confidence intervals). You'd either add a statistics library or export results to an external analysis tool.

4. **CLI provider observability**: For CLI-based providers (Claude Code, Codex), AP only sees the final result, not the internal trajectory. SkillsBench had the same limitation with its harness approach.

## Historical Context (from thoughts/)

The thoughts directory contains extensive documentation of the architectural evolution that led to the current state:

- `thoughts/shared/research/2026-02-06-super-agent-synthesis.md` — Identifies the Conductor as a "Ralph loop" and describes the architectural insight behind substrate-backed orchestration
- `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — Feasibility study for a meta-agent that could orchestrate evaluation campaigns
- `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md` — The finalized pure-CL architecture that the current codebase implements
- `thoughts/shared/research/2026-02-03-autopoiesis-real-agent-use-cases.md` — 20 real agent use cases including agent framework comparisons
- `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — 5-phase plan including self-extension tools and provider generalization

## Related Research

- `thoughts/shared/research/2026-02-16-thinking-repo-ideas-evaluation.md` — Evaluation scoring of ideas from a thinking repo
- `thoughts/shared/research/2026-02-03-e2e-tests-vs-implementation.md` — Analysis of E2E test coverage methodology

## Code References

- `src/integration/provider.lisp` — Base provider class and `define-cli-provider` macro
- `src/integration/provider-claude-code.lisp` — Claude Code CLI provider
- `src/integration/provider-codex.lisp` — Codex CLI provider
- `src/integration/provider-result.lisp` — Result capture with turns, cost, duration
- `src/integration/agentic-agent.lisp` — Direct API agentic agent with thought recording
- `src/integration/provider-agent.lisp` — CLI-backed agent with thought recording
- `src/integration/events.lisp` — Event bus with 16 event types
- `src/substrate/store.lisp` — `transact!` and index management
- `src/substrate/linda.lisp` — `take!` atomic coordination
- `src/substrate/entity-type.lisp` — `define-entity-type` macro
- `src/substrate/datalog.lisp` — Datalog query engine
- `src/core/cognitive-primitives.lisp` — Thought types (observation, decision, action, reflection)
- `src/core/thought-stream.lisp` — Trajectory accumulator
- `src/core/profiling.lisp` — `benchmark` function and `with-timing` macro
- `src/snapshot/diff-engine.lisp` — `snapshot-diff` for comparing agent states
- `src/snapshot/time-travel.lisp` — DAG traversal and `dag-distance`
- `src/agent/agent-capability.lisp` — Test/score/promote pattern (proto-verifier)
- `src/agent/learning.lisp` — Experience recording with outcome scoring
- `src/orchestration/conductor.lisp` — Tick loop, timer heap, worker tracking
- `src/monitoring/endpoints.lisp` — Prometheus metrics and health checks

## Open Questions

1. **Container isolation**: Should AP integrate with Docker/Podman for task environments, or delegate isolation to an external system?
2. **Distributed execution**: For large evaluation campaigns, should the conductor be extended with distributed dispatch, or should multiple independent conductors share a substrate?
3. **Statistical analysis**: Should a CL statistics library be integrated, or should results be exported to Python/R for analysis?
4. **Skills representation**: Should Skills be S-expressions (native to AP), markdown files (SkillsBench convention), or both?
5. **Which harnesses first?**: The user mentioned Claude Code, Human Layer/Code Layer, hand-rolled implementations, SCUD swarming, and Ralph loop variants. Which should be wrapped as providers first?
