# Autopoiesis: Self-Configuring Agent Platform

## Specification Document 00: Overview

**Version:** 0.1.0-draft
**Status:** Specification
**Last Updated:** 2026-02-02

---

## Executive Summary

Autopoiesis is a self-configuring, self-extending agent platform built on Common Lisp's homoiconic foundation. By representing agent cognition, conversation, and configuration as S-expressions (code-as-data, data-as-code), Autopoiesis enables capabilities impossible in traditional agent frameworks:

- **Agents that modify their own behavior** by rewriting their cognitive patterns
- **Full state snapshots** allowing time-travel debugging and fork-based exploration
- **Human-in-the-loop at any point** with seamless entry/exit from agent cognition
- **3D visualization** of agent state in an intuitive "Jarvis-style" interface
- **Self-extension** where agents can write new tools, capabilities, and even new agent types

---

## Vision Statement

> *"What if an AI agent had the same relationship to its own cognition that a Lisp developer has to their running system via SWANK?"*

Autopoiesis answers this question by creating an environment where:

1. **Everything is introspectable** - Agent thoughts, decisions, and state are first-class data
2. **Everything is modifiable** - Agents can rewrite themselves at runtime
3. **Everything is navigable** - Humans can explore agent cognition like exploring a codebase
4. **Everything is forkable** - Try alternative approaches without losing progress

---

## Core Principles

### 1. Homoiconicity as Foundation

```lisp
;; In Autopoiesis, a conversation IS a program
(defvar *conversation*
  '((user-says "Find security vulnerabilities in auth.py")
    (agent-thinks
      (decompose-task
        :into '(read-file analyze-patterns report-findings)))
    (agent-does
      (spawn-agent 'security-analyzer
        :target "auth.py"
        :capabilities '(code-read pattern-match)))))

;; The agent can manipulate its own conversation
(defun learn-from-success (conversation)
  (let ((pattern (extract-successful-pattern conversation)))
    (install-heuristic pattern)))  ; Becomes part of agent's cognition
```

The same representation is used for:
- Agent thoughts and reasoning
- Tool definitions and capabilities
- Configuration and state
- Inter-agent communication
- Human-agent interaction

### 2. SWANK-Inspired Agent Protocol

Just as SWANK allows a developer to connect to a running Lisp image and inspect/modify anything, Autopoiesis provides an "Agent-SWANK" that allows:

- **Introspection**: See what an agent is "thinking"
- **Modification**: Inject new context or change agent state
- **Extension**: Add new capabilities while running
- **Debugging**: Step through agent cognition

### 3. Time as a First-Class Dimension

Every agent action creates a **snapshot** - a complete capture of cognitive state. This enables:

- **Time travel**: Jump to any previous moment
- **Branching**: Fork from any point to explore alternatives
- **Comparison**: Diff between any two states
- **Replay**: Re-execute from any snapshot with modifications

### 4. Human Always in Control

Humans can:
- Pause agent execution at any moment
- Navigate the entire history of agent cognition
- Fork and explore "what if" scenarios
- Inject context or redirect agent focus
- Merge successful branches back together

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AUTOPOIESIS PLATFORM                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     VISUALIZATION LAYER                              │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │ 3D Holodeck │  │  Timeline   │  │  Inspector  │                  │   │
│  │  │   (ECS)     │  │   View      │  │    Panel    │                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    HUMAN INTERFACE LAYER                             │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │  Navigator  │  │  Viewport   │  │  Annotator  │                  │   │
│  │  │  (jumps,    │  │  (what      │  │  (tags,     │                  │   │
│  │  │   forks)    │  │   human     │  │   notes)    │                  │   │
│  │  │             │  │   sees)     │  │             │                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     SNAPSHOT LAYER                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │  Snapshot   │  │  Branch     │  │   Diff      │                  │   │
│  │  │   Store     │  │  Manager    │  │   Engine    │                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      AGENT LAYER                                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │   Agent     │  │ Capability  │  │   Agent     │                  │   │
│  │  │   Runtime   │  │  Registry   │  │   Spawner   │                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                       CORE LAYER                                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │ S-expr      │  │  Cognitive  │  │  Extension  │                  │   │
│  │  │ Foundation  │  │  Primitives │  │   Compiler  │                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    INTEGRATION LAYER                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │   │
│  │  │ Claude Code │  │    MCP      │  │  External   │                  │   │
│  │  │   Bridge    │  │  Servers    │  │   Tools     │                  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. Core Layer
- **S-expression Foundation**: All data structures as Lisp forms
- **Cognitive Primitives**: Basic building blocks for agent thought
- **Extension Compiler**: Transforms agent-written code into executable extensions

### 2. Agent Layer
- **Agent Runtime**: Execution environment for agents
- **Capability Registry**: Available tools and their metadata
- **Agent Spawner**: Dynamic creation of specialized agents

### 3. Snapshot Layer
- **Snapshot Store**: Content-addressable storage for cognitive states
- **Branch Manager**: Git-like branching and merging of agent timelines
- **Diff Engine**: Compare any two cognitive states

### 4. Human Interface Layer
- **Navigator**: Jump, fork, merge, and explore agent history
- **Viewport**: Contextual view of agent state at any snapshot
- **Annotator**: Human-added tags, notes, and bookmarks

### 5. Visualization Layer
- **3D Holodeck**: ECS-based spatial visualization of cognitive spacetime
- **Timeline View**: Linear view of agent history
- **Inspector Panel**: Deep inspection of any snapshot

### 6. Integration Layer
- **Claude Code Bridge**: Integration with Claude Code paradigm and tooling
- **MCP Servers**: Connect to external capabilities via Model Context Protocol
- **External Tools**: File system, web, databases, etc.

---

## Document Index

| Document | Description |
|----------|-------------|
| [01-core-architecture.md](./01-core-architecture.md) | Core Lisp foundation and agent system |
| [02-cognitive-model.md](./02-cognitive-model.md) | Agent cognition, capabilities, self-modification |
| [03-snapshot-system.md](./03-snapshot-system.md) | Snapshots, forks, and time travel |
| [04-human-interface.md](./04-human-interface.md) | Human-in-the-loop protocol |
| [05-visualization.md](./05-visualization.md) | 3D ECS Jarvis interface |
| [06-integration.md](./06-integration.md) | External system integrations |
| [07-implementation-roadmap.md](./07-implementation-roadmap.md) | Phased implementation plan |

---

## Key Differentiators

### vs. Traditional Agent Frameworks (LangChain, AutoGPT, etc.)

| Aspect | Traditional | Autopoiesis |
|--------|-------------|--------|
| State | Opaque, in-memory | Transparent, serializable S-expressions |
| History | Lost or limited | Full snapshot DAG |
| Modification | Restart required | Live, hot-swappable |
| Debugging | Print statements | Full introspection |
| Extension | Plugin architecture | Self-writing code |
| Human control | Start/stop | Enter anywhere, fork, explore |

### vs. Traditional Development Environments

| Aspect | IDE | Autopoiesis |
|--------|-----|--------|
| Target | Code | Cognition |
| Debug unit | Line/function | Thought/decision |
| Version control | Files | Cognitive states |
| Branching | Code branches | Reality branches |
| Collaboration | Merge code | Merge understanding |

---

## Use Cases

### 1. Autonomous Software Development
Agents that can write, test, and deploy code - with human oversight at any critical decision point.

### 2. Research Assistance
Explore multiple research directions simultaneously via forking, compare results, merge insights.

### 3. Complex Problem Solving
Decompose problems across specialized agents, track all solution paths, backtrack when needed.

### 4. Learning and Education
Students can explore AI decision-making, see how agents reason, intervene to guide.

### 5. Enterprise Automation
Mission-critical workflows with full auditability, human approval gates, and rollback capability.

---

## Success Metrics

1. **Transparency**: Every agent decision is explainable and navigable
2. **Control**: Humans can intervene at any point with zero friction
3. **Extensibility**: Agents can add new capabilities without platform changes
4. **Performance**: Snapshot overhead < 5% of agent execution time
5. **Usability**: New users productive within 30 minutes

---

## Next Steps

Proceed to [01-core-architecture.md](./01-core-architecture.md) for detailed technical specifications of the core system.
