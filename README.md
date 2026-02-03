# Autopoiesis

A self-configuring, self-extending agent platform built on Common Lisp's homoiconic foundation.

## Overview

Autopoiesis enables AI agents to:
- **Modify their own behavior** through S-expression code-as-data representation
- **Time-travel debug** with full state snapshots and branching
- **Human-in-the-loop** interaction at any point in the cognitive cycle
- **Integrate with Claude API** for LLM-powered reasoning

## Status

**Phases 0-6 Complete** | Phase 7 (2D Visualization) in progress

All core functionality is implemented and tested with 801+ passing checks across 7 test suites.

## Quick Start

### Prerequisites

- [SBCL](http://www.sbcl.org/) (Steel Bank Common Lisp)
- [Quicklisp](https://www.quicklisp.org/beta/)

### Installation

```bash
# Clone the repository
git clone <repo-url> autopoiesis
cd autopoiesis

# Run tests
./scripts/test.sh
```

### Usage

```lisp
;; Load the system
(ql:quickload :autopoiesis)

;; Create an agent
(defvar *agent*
  (autopoiesis.agent:make-agent
    :name "my-agent"
    :capabilities '(read-file analyze-code)))

;; Start a CLI session
(autopoiesis.interface:start-session "user" *agent*)

;; Create and save a snapshot
(let ((snap (autopoiesis.snapshot:make-snapshot '(:state :example))))
  (autopoiesis.snapshot:save-snapshot snap store))
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Integration Layer                      │
│         Claude API  •  MCP Servers  •  Tools            │
├─────────────────────────────────────────────────────────┤
│                  Visualization Layer                     │
│           2D Timeline  •  3D Holodeck (planned)         │
├─────────────────────────────────────────────────────────┤
│                Human Interface Layer                     │
│        Navigator  •  Viewport  •  Annotator             │
├─────────────────────────────────────────────────────────┤
│                   Snapshot Layer                         │
│      Content Store  •  Branch Manager  •  Diff Engine   │
├─────────────────────────────────────────────────────────┤
│                    Agent Layer                           │
│       Agent Runtime  •  Capabilities  •  Spawner        │
├─────────────────────────────────────────────────────────┤
│                     Core Layer                           │
│     S-expressions  •  Cognitive Primitives  •  Compiler │
└─────────────────────────────────────────────────────────┘
```

## Test Results

```
Core tests:        35/35   (100%)
Agent tests:       94/94   (100%)
Snapshot tests:    83/83   (100%)
Interface tests:   40/40   (100%)
Integration tests: 404/404 (100%)
E2E tests:         134/134 (100%)
Viz tests:         11/11   (100%)
```

## Documentation

- [User Stories](docs/user-stories.md) - 15 practical examples
- [Specification Documents](docs/specs/) - Detailed architecture specs
- [Implementation Plan](ralph/IMPLEMENTATION_PLAN.md) - Current development status

## Key Features

### Cognitive Primitives
S-expression based thoughts, decisions, actions, observations, and reflections.

### Snapshot System
Content-addressable storage with DAG-based branching for time-travel debugging.

### Human-in-the-Loop
Blocking requests, annotations, and real-time intervention capabilities.

### Claude Integration
Bidirectional tool mapping between Lisp capabilities and Claude API tools.

### MCP Support
Model Context Protocol integration for external tool servers.

## License

[License TBD]

## Contributing

See [CLAUDE.md](CLAUDE.md) for development guidelines and code conventions.
