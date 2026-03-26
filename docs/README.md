# Autopoiesis Documentation

## Start Here

**[QUICKSTART.md](QUICKSTART.md)** — One-command setup, first agent swarm, Nexus TUI cockpit, Holodeck 3D, self-extension walkthrough, scaling guidance, and multi-language navigation.

## Reference

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](QUICKSTART.md) | Getting started guide (setup, first agents, TUI, self-extension) |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Docker, Kubernetes, production configuration |
| [user-stories.md](user-stories.md) | 15 practical user stories with examples |
| [specs/](specs/) | Architecture specifications (8 documents) |

## Specification Documents

| Spec | Topic |
|------|-------|
| [00-overview.md](specs/00-overview.md) | Vision, architecture overview, key differentiators |
| [01-core-architecture.md](specs/01-core-architecture.md) | Core layer design, packages, S-expression foundation |
| [02-cognitive-model.md](specs/02-cognitive-model.md) | Agent architecture, thought representation, cognitive loop |
| [03-snapshot-system.md](specs/03-snapshot-system.md) | Snapshot DAG model, branching, diffing |
| [04-human-interface.md](specs/04-human-interface.md) | Human-in-the-loop protocol, entry points |
| [05-visualization.md](specs/05-visualization.md) | ECS architecture, 3D holodeck design |
| [06-integration.md](specs/06-integration.md) | Claude bridge, MCP integration |
| [07-implementation-roadmap.md](specs/07-implementation-roadmap.md) | Phased implementation plan |
| [08-specification-addendum.md](specs/08-specification-addendum.md) | Event sourcing, security, resource management |

## Code Conventions

See [`/CLAUDE.md`](../../CLAUDE.md) for complete function signatures, package hierarchy, test suites, and development commands.
