---
date: 2026-02-03T18:00:00-08:00
researcher: reuben
git_commit: 392c43a
branch: main
repository: ap
topic: "20 Powerful Real-World Agent System Use Cases for Autopoiesis"
tags: [research, agent-systems, use-cases, integrations, architecture, common-lisp, homoiconic, self-modification]
status: complete
last_updated: 2026-02-03
last_updated_by: reuben
last_updated_note: "Initial research document — 20 use cases with integration requirements"
---

# Research: 20 Powerful Ways to Use Autopoiesis as a Real Agent System

**Date**: 2026-02-03
**Researcher**: reuben
**Git Commit**: 392c43a
**Branch**: main
**Repository**: ap

## Research Question

What are 20 powerful, practical ways to use Autopoiesis as a real agent system? What integrations, bolt-ons, or additional work would be needed to make each viable?

## Methodology

- Deep codebase introspection (68+ source files across 8 layers, all phases 0-10 complete) 
- Analysis of existing integration surface (Claude bridge, MCP client, 4 CLI provider abstractions, 13 built-in tools, event bus)
- Web research on current agent framework landscape (LangGraph, CrewAI, AutoGen, CoALA cognitive architectures)
- Review of neuro-symbolic AI research (arxiv 2506.10021 — LLMs + Lisp metaprogramming)
- Analysis of existing platform capabilities vs. gaps for real-world deployment

## Platform Capabilities Summary

Before the use cases, here's what Autopoiesis already has:

| Capability | Status | Key Files |
|-----------|--------|-----------|
| Cognitive loop (perceive/reason/decide/act/reflect) | Complete | `src/agent/cognitive-loop.lisp` |
| Self-modification engine | Complete | `src/core/extension-compiler.lisp` |
| Content-addressable snapshot DAG | Complete | `src/snapshot/store.lisp` |
| Branch/fork/merge of cognitive state | Complete | `src/snapshot/branch-manager.lisp` |
| Time-travel debugging | Complete | `src/snapshot/time-travel.lisp` |
| Human-in-the-loop (pause, inject, redirect) | Complete | `src/interface/navigator.lisp`, `src/interface/blocking-input.lisp` |
| Claude API bridge | Complete | `src/integration/claude-bridge.lisp` |
| MCP server client | Complete | `src/integration/mcp-server.lisp` |
| Provider abstraction (Claude Code, Codex, OpenCode, Cursor) | Complete | `src/integration/providers/` |
| 13 built-in tools (file, web, shell) | Complete | `src/integration/tools.lisp` |
| Event bus (13 event types) | Complete | `src/integration/event-bus.lisp` |
| 2D terminal visualization | Complete | `src/viz/` |
| 3D holodeck ECS visualization | Complete | `src/holodeck/` |
| Security (permissions, audit, sandbox) | Complete | `src/security/` |
| Monitoring (metrics, health) | Complete | `src/monitoring/` |
| Agent spawning and forking | Complete | `src/agent/spawner.lisp` |
| defcapability macro | Complete | `src/agent/capability.lisp` |
| Docker/K8s deployment | Complete | `docs/DEPLOYMENT.md` |

---

## The 20 Use Cases

---

### 1. Self-Healing Infrastructure Agent

**What it does**: An agent that monitors production infrastructure, detects anomalies, diagnoses root causes, and applies fixes — with full cognitive audit trail for post-incident review.

**Why Autopoiesis is uniquely suited**: The snapshot DAG means every diagnostic step is preserved. If a fix makes things worse, time-travel to the pre-fix state and fork a different approach. The human-in-the-loop system lets an SRE pause the agent before it applies a destructive fix.

**Leverages**: Cognitive loop, snapshot DAG, human-in-the-loop blocking, event bus, built-in shell tools

**Needs**:
- **MCP server for Prometheus/Grafana** — query metrics and alerts as tool calls
- **MCP server for Kubernetes API** — read/write pod state, deployments, configmaps
- **Runbook capability library** — `defcapability` definitions wrapping common remediation playbooks
- **Escalation policy engine** — when to auto-fix vs. page a human (integrates with PagerDuty/OpsGenie MCP)
- **Cost/risk scoring** — annotate each proposed action with blast radius estimate

**Difficulty**: Medium. The core loop exists; the work is writing MCP servers for infra tools and defining the escalation policy.

---

### 2. Adversarial Red Team Agent with Branching Attack Trees

**What it does**: A security testing agent that explores attack surfaces by forking at each decision point, building a full attack tree. Each branch tries a different exploit path. Successful branches are merged into a comprehensive vulnerability report.

**Why Autopoiesis is uniquely suited**: No other agent framework has native branching/forking of cognitive state. The agent can literally try SQL injection on branch A while trying SSRF on branch B, with full state isolation. The diff engine can compare what worked vs. what didn't.

**Leverages**: Branch manager, fork/merge, diff engine, agent spawning, security sandbox, cognitive loop

**Needs**:
- **Pentesting tool MCP servers** — Burp Suite, Nuclei, or nmap wrappers
- **Scope/authorization guard** — hard limits on what the agent can target (existing security layer helps)
- **Attack taxonomy knowledge base** — OWASP/MITRE ATT&CK as S-expression capability definitions
- **Report generator capability** — transforms the attack tree DAG into a structured pentest report

**Difficulty**: Medium. The branching infrastructure is the hard part and it's already built.

---

### 3. Multi-Model Arbitrage Agent

**What it does**: Routes inference requests across multiple LLM providers based on cost, latency, capability, and task complexity. Uses the provider abstraction to dynamically switch between Claude, GPT, local models, etc.

**Why Autopoiesis is uniquely suited**: The provider abstraction layer already supports 4 CLI backends. The cognitive loop's reflect phase can evaluate which model performed best on similar past tasks (via snapshot history). The self-modification engine can tune routing heuristics at runtime.

**Leverages**: Provider abstraction (`src/integration/providers/`), cognitive loop reflect phase, self-modification engine, learning system

**Needs**:
- **Additional provider implementations** — OpenAI API direct, Anthropic API direct (not just CLI wrappers), local model (llama.cpp/vLLM) provider
- **Cost tracking module** — record token usage and cost per provider per request
- **Benchmark capability** — periodically test providers on standardized tasks to update routing table
- **Prompt caching integration** — Anthropic's prompt caching (90% cost reduction on cache hits) as first-class concept

**Difficulty**: Low-Medium. The abstraction layer exists; add providers and the routing logic.

---

### 4. Autonomous Codebase Archaeologist

**What it does**: Given a large, unfamiliar codebase, the agent systematically explores it — reading code, tracing call graphs, identifying patterns, building a mental model. The cognitive state is fully navigable, so a human can see exactly how the agent built its understanding.

**Why Autopoiesis is uniquely suited**: The thought stream captures the agent's evolving understanding as S-expressions. A developer can jump to the moment the agent "realized" something about the architecture. Fork to explore a different subsystem. Annotate with corrections.

**Leverages**: Cognitive loop, thought streams, snapshot DAG, annotations, 2D/3D visualization, built-in file tools

**Needs**:
- **Language-aware code analysis tools** — tree-sitter MCP server for AST parsing, symbol resolution
- **Call graph builder capability** — `defcapability` that builds and queries dependency graphs
- **Documentation generator** — transforms the agent's cognitive model into human-readable docs
- **Embedding-based code search** — vector DB MCP server for semantic code search

**Difficulty**: Low. This is close to what the platform already does with minimal additions.

---

### 5. Cognitive Digital Twin for Decision Making

**What it does**: Creates a "digital twin" of a decision-making process. Feed it historical decisions and outcomes. It builds a cognitive model, then when a new decision arises, it forks multiple branches — one per strategic option — and simulates outcomes based on learned patterns.

**Why Autopoiesis is uniquely suited**: The fork/branch system is literally designed for exploring alternative realities. Each branch maintains full cognitive state. The diff engine shows exactly where decisions diverged and what the downstream effects were. The merge capability lets you combine insights from multiple exploration branches.

**Leverages**: Branch manager, fork/merge, diff engine, learning system, snapshot DAG, 3D holodeck visualization

**Needs**:
- **Domain knowledge ingestion** — capability to load structured domain data (market data, historical records)
- **Monte Carlo simulation tools** — MCP server wrapping simulation engines
- **Outcome scoring framework** — define success metrics as S-expressions that the agent evaluates
- **Visualization overlays** — holodeck extensions to show decision trees spatially with probability annotations
- **Calibration system** — track prediction accuracy over time, feed back into agent's self-modification

**Difficulty**: High. The infrastructure exists but the domain modeling and calibration are substantial work.

---

### 6. Self-Improving Test Generation Agent

**What it does**: Writes tests for a codebase, runs them, analyzes failures, and iteratively improves both the tests and its own test-writing strategies. Uses the reflect phase to learn what makes good tests.

**Why Autopoiesis is uniquely suited**: The self-modification engine means the agent literally rewrites its own test-generation heuristics based on what works. The snapshot history preserves every iteration, so you can see how the agent's approach evolved. Fork to try property-based testing on one branch and example-based on another.

**Leverages**: Self-modification engine, cognitive loop (especially reflect), learning system, snapshot DAG, built-in shell/file tools

**Needs**:
- **Test runner MCP servers** — language-specific test execution and coverage reporting
- **Mutation testing integration** — check test quality by mutating code and verifying tests catch it
- **Coverage analysis capability** — parse coverage reports, identify untested paths
- **Quality metrics** — define what makes a "good" test as evaluable S-expression criteria

**Difficulty**: Low-Medium. Straightforward application of existing capabilities.

---

### 7. Regulatory Compliance Agent with Audit Trail

**What it does**: Monitors codebases, configurations, and deployments for regulatory compliance (SOC2, HIPAA, GDPR, PCI-DSS). Every finding, assessment, and remediation recommendation is captured in the snapshot DAG — providing a cryptographically-verifiable audit trail.

**Why Autopoiesis is uniquely suited**: The content-addressable snapshot store (SHA256 hashed) provides tamper-evident records. The full cognitive history shows not just what was found, but how the agent reasoned about it. The annotation system lets compliance officers add notes. The event bus can trigger alerts.

**Leverages**: Snapshot store (content-addressable), audit logging (`src/security/audit.lisp`), event bus, annotations, human-in-the-loop

**Needs**:
- **Compliance rule library** — regulatory requirements as S-expression patterns/checks
- **Policy-as-code engine** — OPA/Rego integration via MCP server
- **Evidence collector** — automated screenshot, log capture, config dump capabilities
- **Report templating** — generate compliance reports from the snapshot DAG in auditor-friendly formats
- **Scheduled scanning** — cron-like trigger for periodic compliance sweeps

**Difficulty**: Medium. The audit infrastructure is strong; domain-specific rule libraries are the main work.

---

### 8. Collaborative Multi-Agent Research Team

**What it does**: A team of specialized agents — Literature Reviewer, Hypothesis Generator, Experiment Designer, Data Analyst, Paper Writer — that collaborate on research tasks. Each agent has its own cognitive state but they share findings via the event bus.

**Why Autopoiesis is uniquely suited**: Agent spawning with capability inheritance means you can create specialized agents from a base researcher template. The event bus enables publish/subscribe communication. Each agent's thought stream is independently navigable. A human researcher can enter any agent's cognition, redirect focus, or inject domain knowledge.

**Leverages**: Agent spawner, event bus, capability registry, human-in-the-loop, thought streams, 3D holodeck (spatial layout of agent network)

**Needs**:
- **Inter-agent message protocol** — formalize how agents share findings (beyond raw events)
- **Shared knowledge base** — a persistent S-expression store that all agents can read/write
- **Academic tool MCP servers** — Semantic Scholar, ArXiv, Google Scholar APIs
- **Experiment execution framework** — capability to design, run, and analyze experiments
- **Consensus mechanism** — how agents resolve conflicting findings

**Difficulty**: Medium-High. Multi-agent coordination is inherently complex, but the spawner and event bus provide a solid foundation.

---

### 9. Lisp Metaprogramming Agent (Self-Writing Agent Factory)

**What it does**: An agent that writes new agents. Given a task description, it generates the appropriate `defcapability` definitions, cognitive patterns, and tool configurations — then spawns the new agent and evaluates its performance. Based on the arxiv 2506.10021 concept of LLMs in a Lisp metaprogramming loop.

**Why Autopoiesis is uniquely suited**: This is literally the platform's design goal — "self-extension where agents can write new tools, capabilities, and even new agent types." The extension compiler validates and installs agent-written code. The snapshot system means failed agent designs can be rolled back. The security sandbox constrains what generated code can do.

**Leverages**: Extension compiler, self-modification engine, agent spawner, security sandbox, capability registry, defcapability macro

**Needs**:
- **Agent template library** — curated starting points for common agent types
- **Performance evaluation framework** — benchmark newly-created agents against acceptance criteria
- **Capability composition rules** — formal rules about which capabilities can be combined safely
- **Human approval gate for new agents** — blocking input before a generated agent gets real-world access

**Difficulty**: Medium. The infrastructure exists; the challenge is making the agent-creation loop reliable.

---

### 10. Interactive Debugging Agent for Production Systems

**What it does**: When a production incident occurs, this agent connects to the affected system, gathers diagnostics, forms hypotheses, and tests them — all while a human watches in real-time via the 2D/3D visualization. The human can steer the investigation, inject context ("this happened after the last deploy"), or pause to prevent risky diagnostic actions.

**Why Autopoiesis is uniquely suited**: The SWANK-inspired protocol means you can literally watch the agent think, like connecting a debugger to a running Lisp image. The timeline view shows the investigation as it unfolds. The blocking input system ensures the agent asks before running anything destructive.

**Leverages**: Human-in-the-loop (all modes), 2D visualization, 3D holodeck, blocking input, built-in shell/file tools, event bus

**Needs**:
- **Log aggregation MCP server** — query Datadog, Splunk, CloudWatch, ELK
- **APM integration** — trace analysis via Honeycomb, New Relic, Jaeger MCP servers
- **Database query capability** — read-only SQL/NoSQL query execution with timeout guards
- **Deployment history integration** — correlate incidents with recent deploys (GitHub, ArgoCD)
- **Safe diagnostic commands** — pre-approved command library with blast-radius annotations

**Difficulty**: Medium. High value, well-aligned with existing capabilities.

---

### 11. Neuro-Symbolic Reasoning Engine

**What it does**: Combines LLM-based natural language understanding with formal symbolic reasoning in Lisp. The LLM handles ambiguity, context, and natural language; the Lisp engine handles logical deduction, constraint satisfaction, and proof verification. This is the convergence point identified in neuro-symbolic AI research.

**Why Autopoiesis is uniquely suited**: The homoiconic foundation means the LLM's outputs (S-expressions) are directly executable by the symbolic reasoner. No translation layer needed. The cognitive primitives (`make-observation`, `make-decision`) already bridge informal and formal reasoning.

**Leverages**: S-expression foundation, cognitive primitives, extension compiler, Claude bridge

**Needs**:
- **Formal logic library** — first-order logic, description logic, or answer set programming in CL
- **Constraint solver integration** — CL-based or MCP-wrapped constraint satisfaction
- **Proof assistant capability** — verify logical deductions, flag unsound reasoning
- **Ontology management** — load and query domain ontologies as S-expression knowledge bases
- **Confidence calibration** — bridge between LLM probability and symbolic certainty

**Difficulty**: High. Intellectually ambitious but technically feasible given the homoiconic foundation.

---

### 12. Autonomous Code Migration Agent

**What it does**: Migrates codebases between frameworks, languages, or API versions. Forks branches to try different migration strategies in parallel. Uses the diff engine to compare results. Merges the best approaches.

**Why Autopoiesis is uniquely suited**: Large migrations have many valid approaches. The branching system lets the agent try multiple strategies simultaneously without interference. The snapshot history shows every transformation step. If a migration path hits a dead end, abandon the branch — no wasted work.

**Leverages**: Branch manager, fork/merge, diff engine, built-in file tools, agent spawning (parallel migration workers)

**Needs**:
- **Language parser MCP servers** — tree-sitter for source and target languages
- **AST transformation capabilities** — pattern-matching code transformations
- **Test execution integration** — run target project's tests after each transformation step
- **Migration rule library** — common patterns (e.g., React class → hooks, Python 2 → 3, REST → GraphQL)
- **Incremental verification** — check correctness after each transformation, not just at the end

**Difficulty**: Medium-High. The exploration infrastructure is ideal; migration logic is domain-heavy.

---

### 13. Personalized Learning Tutor with Cognitive Modeling

**What it does**: A tutoring agent that builds a model of the student's understanding, identifies misconceptions, and adapts its teaching strategy. The student (or a teacher) can inspect the agent's model of their knowledge via the visualization layer.

**Why Autopoiesis is uniquely suited**: The agent's model of the student is stored as S-expressions in the thought stream — fully inspectable and modifiable. A teacher can see exactly what the agent thinks the student knows, correct it, and see the teaching strategy change. Fork to try different pedagogical approaches.

**Leverages**: Cognitive loop, thought streams, human-in-the-loop, annotations, 2D/3D visualization, self-modification (adapts teaching strategy)

**Needs**:
- **Knowledge graph capability** — represent domain knowledge and student mastery as navigable graph
- **Assessment generation** — create questions that target specific knowledge gaps
- **Pedagogical strategy library** — teaching approaches as swappable cognitive patterns
- **Progress tracking** — persistent student model across sessions
- **Content delivery integration** — serve exercises, explanations, multimedia via web interface

**Difficulty**: Medium. Educational technology is well-understood; the unique value is cognitive transparency.

---

### 14. Continuous Architecture Decision Record (ADR) Agent

**What it does**: Monitors a development team's codebase, PRs, and discussions. When it detects an architectural decision being made (explicitly or implicitly), it captures it as a structured ADR with context, alternatives considered, rationale, and consequences.

**Why Autopoiesis is uniquely suited**: The agent's perception of the codebase evolves over time, captured in snapshots. It can literally "remember" what the architecture looked like before a change. The diff engine can show what changed between any two points. The annotation system adds human context.

**Leverages**: Cognitive loop (perceive/reflect), snapshot DAG, diff engine, annotations, event bus, built-in file/web tools

**Needs**:
- **GitHub/GitLab MCP server** — watch PRs, commits, discussions, issues
- **Slack/Teams MCP server** — capture architecture discussions from chat
- **ADR template system** — structured format for decision records
- **Change detection heuristics** — `defcapability` definitions for identifying architectural changes vs. routine code changes
- **Knowledge base integration** — link ADRs to affected code regions

**Difficulty**: Low-Medium. High value, leverages existing capabilities well.

---

### 15. Autonomous Data Pipeline Orchestrator

**What it does**: Designs, builds, monitors, and self-heals data pipelines. When a pipeline fails, the agent diagnoses the issue, applies a fix, and updates its own pipeline-building heuristics to prevent similar failures.

**Why Autopoiesis is uniquely suited**: The self-modification engine means the agent literally gets better at building pipelines over time. Failed pipeline runs are preserved in the snapshot history for post-mortem analysis. Fork to test pipeline modifications without affecting production.

**Leverages**: Self-modification engine, learning system, cognitive loop, snapshot DAG, event bus (for pipeline events), built-in shell tools

**Needs**:
- **Data tool MCP servers** — dbt, Airflow, Dagster, or Prefect API wrappers
- **Database connectors** — PostgreSQL, BigQuery, Snowflake, S3 query capabilities
- **Data quality checks** — Great Expectations or similar as capability definitions
- **Pipeline DSL** — S-expression representation of pipeline topology for agent manipulation
- **Scheduling integration** — trigger pipeline runs on schedule or event

**Difficulty**: Medium. Significant integration surface but well-structured problem.

---

### 16. Legal Document Analysis Agent with Precedent Threading

**What it does**: Analyzes legal documents (contracts, regulations, case law), identifies relevant precedents, flags risks, and suggests revisions. The snapshot DAG preserves the full analysis chain, critical for legal work where you need to show your reasoning.

**Why Autopoiesis is uniquely suited**: Legal analysis requires showing your work. The cognitive history is a complete record of how the agent arrived at each conclusion. Fork to analyze a contract under different jurisdictional interpretations. The annotation system lets lawyers add notes and corrections.

**Leverages**: Cognitive loop, snapshot DAG (audit trail), annotations, fork/branch, human-in-the-loop, diff engine

**Needs**:
- **Legal database MCP servers** — Westlaw, LexisNexis, or open case law APIs
- **Document parsing capability** — PDF/DOCX extraction with section/clause identification
- **Citation network builder** — link precedents, statutes, and contract clauses
- **Clause library** — common contract clauses as S-expression templates for comparison
- **Redlining capability** — suggest and track contract revisions

**Difficulty**: Medium-High. Domain expertise requirements are significant, but the audit trail value is enormous.

---

### 17. Swarm Intelligence Agent Network

**What it does**: Deploys dozens of lightweight agents that collectively explore a problem space using swarm intelligence patterns (stigmergy, pheromone trails, consensus). Each agent is simple; the intelligence emerges from their interactions via the event bus.

**Why Autopoiesis is uniquely suited**: The agent spawner can create many agents from templates. The event bus is the stigmergic communication channel. Each agent's cognitive state is independently inspectable. The holodeck visualization shows the swarm's behavior spatially in 3D.

**Leverages**: Agent spawner, event bus, 3D holodeck, capability registry, monitoring (track swarm metrics)

**Needs**:
- **Swarm coordination primitives** — S-expression protocols for stigmergy, voting, consensus
- **Lightweight agent profiles** — minimal cognitive loop for swarm members (reduce overhead)
- **Aggregation agent** — collects and synthesizes swarm findings
- **Spatial problem representation** — map problem dimensions to 3D space for holodeck visualization
- **Resource budget management** — prevent swarm from consuming unbounded resources (existing resource budgets help)

**Difficulty**: Medium. Novel application of existing infrastructure.

---

### 18. Autonomous Security Monitoring and Incident Response (SOAR)

**What it does**: A Security Orchestration, Automation and Response agent that monitors security events, correlates alerts, investigates potential incidents, and executes response playbooks — all with human approval gates for high-severity actions.

**Why Autopoiesis is uniquely suited**: The blocking input system ensures a human approves before the agent isolates a server or revokes credentials. The snapshot DAG provides a forensically-sound investigation record. Fork to investigate multiple hypotheses about an attack simultaneously.

**Leverages**: Human-in-the-loop (blocking), event bus, fork/branch, security sandbox, audit logging, cognitive loop

**Needs**:
- **SIEM MCP server** — query Splunk, Elastic SIEM, Sentinel, or CrowdStrike
- **EDR integration** — endpoint detection and response actions via API
- **Threat intelligence feeds** — STIX/TAXII integration as capability
- **Response playbook library** — `defcapability` definitions for containment, eradication, recovery
- **Evidence preservation** — forensic image capture and chain-of-custody tracking
- **Severity scoring** — CVSS-like scoring as S-expression evaluator

**Difficulty**: Medium-High. Critical application with strong alignment to platform strengths.

---

### 19. Living Documentation Agent

**What it does**: Maintains documentation that stays in sync with code. When code changes, the agent detects the change (via git hooks or CI events), understands its implications, and updates relevant documentation. Importantly, it doesn't just diff — it understands the semantic impact.

**Why Autopoiesis is uniquely suited**: The cognitive loop means the agent builds and maintains a semantic understanding of the codebase, not just a file listing. The snapshot history shows how the agent's understanding evolved alongside the code. The annotation system lets developers mark documentation as human-reviewed.

**Leverages**: Cognitive loop, learning system, event bus (git events), built-in file tools, annotations, snapshot DAG

**Needs**:
- **Git webhook receiver** — trigger agent on push/merge events
- **Documentation format capabilities** — Markdown, JSDoc, Sphinx, API doc generation
- **Semantic diff capability** — understand what a code change means, not just what changed
- **Documentation quality metrics** — coverage, freshness, accuracy scoring
- **CI integration** — run as part of the deployment pipeline

**Difficulty**: Low-Medium. High value, close to existing capabilities.

---

### 20. Agent-as-a-Service Platform (Meta-Platform)

**What it does**: Exposes Autopoiesis itself as a service where users define agent behaviors via S-expression configurations, deploy them, monitor them via the visualization layer, and pay per cognitive cycle. Essentially, Autopoiesis becomes an agent PaaS.

**Why Autopoiesis is uniquely suited**: The entire platform is designed around introspectable, serializable agent state. Multi-tenancy is supported by the security layer (per-agent permissions). The monitoring system provides usage metrics. Docker/K8s deployment is already documented. The self-extension capability means customers can add capabilities without platform changes.

**Leverages**: Everything — all 8 layers, security, monitoring, Docker/K8s, provider abstraction, extension compiler, holodeck

**Needs**:
- **Multi-tenant isolation** — strengthen existing security for true multi-tenancy (separate namespaces, resource quotas per tenant)
- **API gateway** — REST/GraphQL API for agent CRUD, execution, and monitoring
- **Billing integration** — metering on cognitive cycles, token usage, tool calls
- **Agent marketplace** — registry for sharing agent templates and capabilities
- **Web-based holodeck** — port the 3D visualization to WebGL/Three.js for browser access
- **SLA management** — uptime guarantees, rate limiting, priority queuing

**Difficulty**: High. This is a product, not a feature — but the platform is uniquely positioned for it.

---

## Cross-Cutting Integration Priorities

Based on the 20 use cases above, here are the highest-leverage integrations to build:

### Tier 1: Unlocks the most use cases

| Integration | Use Cases Enabled | Effort |
|------------|-------------------|--------|
| **MCP server SDK/template** | All 20 (every use case needs MCP servers) | Low |
| **Git/GitHub MCP server** | #4, #6, #12, #14, #19 | Low |
| **Database query capability** | #5, #10, #15, #16 | Low-Medium |
| **Inter-agent messaging protocol** | #8, #17, #20 | Medium |

### Tier 2: High value, moderate effort

| Integration | Use Cases Enabled | Effort |
|------------|-------------------|--------|
| **Log/APM MCP servers** (Datadog, etc.) | #1, #10, #18 | Medium |
| **Additional LLM providers** | #3, #20 | Low-Medium |
| **Web-based visualization** | #13, #20 | High |
| **Kubernetes API MCP server** | #1, #15, #20 | Medium |

### Tier 3: Domain-specific, high impact

| Integration | Use Cases Enabled | Effort |
|------------|-------------------|--------|
| **Legal database connectors** | #16 | Medium |
| **Academic search APIs** | #8 | Low |
| **Security tool integrations** | #2, #18 | Medium |
| **Formal logic/constraint solvers** | #11 | High |

## Key Architectural Insight

The single most powerful thing about Autopoiesis for real agent work is **the combination of homoiconicity + snapshot DAG + self-modification**. No other agent framework has all three:

- **LangGraph** has structured state but no self-modification or homoiconicity
- **CrewAI** has multi-agent but no branching/forking or cognitive introspection
- **AutoGen** has conversational agents but no time-travel or state snapshots
- **Autopoiesis** has all of these as first-class primitives

The branching system alone is a killer feature. Every use case benefits from the ability to explore multiple approaches simultaneously and merge the best results. This is not "running two prompts" — it's forking full cognitive state including accumulated context, learned heuristics, and tool results.

## Recommended Next Steps

1. **Build an MCP server template/SDK** — this is the gateway to every integration
2. **Implement use case #4 (Codebase Archaeologist)** — lowest difficulty, most immediately useful, demonstrates the platform's value
3. **Implement use case #9 (Agent Factory)** — this is the platform's thesis statement made real
4. **Build the inter-agent messaging protocol** — unlocks multi-agent use cases (#8, #17, #20)
5. **Port the holodeck to WebGL** — unlocks use cases that need non-terminal users (#13, #20)

## Sources

- Codebase analysis: 68+ source files across `src/core/`, `src/agent/`, `src/snapshot/`, `src/interface/`, `src/viz/`, `src/holodeck/`, `src/integration/`, `src/security/`, `src/monitoring/`
- Platform specs: `docs/specs/00-overview.md` through `docs/specs/08-specification-addendum.md`
- User stories: `docs/user-stories.md` (15 stories with acceptance criteria)
- Web research: LangGraph/CrewAI/AutoGen comparison, CoALA cognitive architecture framework, arxiv 2506.10021 (LLMs + Lisp metaprogramming), Anthropic prompt caching documentation
- Existing research: `thoughts/shared/research/2026-02-03-autopoiesis-codebase-overview.md`
