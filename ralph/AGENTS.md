# Autopoiesis Agent Operations Guide

This file contains operational context for AI agents working on Autopoiesis.

## Project Overview

Autopoiesis is a self-configuring agent platform built in Common Lisp. See `docs/specs/00-overview.md` for full vision.

## Build Commands

```bash
# Load the system (from REPL)
sbcl --load quicklisp/setup.lisp --eval '(ql:quickload :autopoiesis)'

# Or use the build script
./scripts/build.sh

# Quick syntax check
sbcl --noinform --non-interactive --load src/core/packages.lisp
```

## Test Commands

```bash
# Run all tests
sbcl --noinform --non-interactive \
  --load quicklisp/setup.lisp \
  --eval '(ql:quickload :autopoiesis/test)' \
  --eval '(asdf:test-system :autopoiesis)' \
  --eval '(quit)'

# Or use the test script
./scripts/test.sh

# Run specific test suite
sbcl --eval '(fiveam:run! :autopoiesis.core.test)'
```

## Validation Checklist

Before committing, ensure:
1. [ ] Code loads without errors
2. [ ] All tests pass
3. [ ] No compiler warnings (except known acceptable ones)
4. [ ] New code has corresponding tests

## Directory Structure

```
autopoiesis/
├── autopoiesis.asd        # System definition
├── src/
│   ├── core/              # S-expressions, primitives, conditions
│   ├── agent/             # Agent runtime, capabilities
│   ├── snapshot/          # Event log, checkpoints, branching
│   ├── interface/         # Human-in-the-loop
│   ├── viz/               # Visualization (optional)
│   └── integration/       # Claude, MCP, external tools
├── test/
│   ├── core/
│   ├── agent/
│   └── ...
├── docs/specs/            # Specification documents
└── ralph/                 # Ralph Wiggum loop files
```

## Package Naming

- `autopoiesis.core` - Core utilities
- `autopoiesis.agent` - Agent runtime
- `autopoiesis.snapshot` - Persistence
- `autopoiesis.interface` - Human interface
- `autopoiesis.viz` - Visualization
- `autopoiesis.integration` - External integrations
- `autopoiesis` - Top-level re-exports

## Code Style

- Use `defclass` with `:documentation` on all slots
- Use `defgeneric` before `defmethod` definitions
- Prefer pure functions where possible
- Use condition/restart for error handling
- Document with docstrings, not comments

## Subagent Usage

- Use subagents for parallel file reading/searching
- Keep main agent for sequential build/test operations
- Max 3 concurrent subagents to avoid rate limits

## Common Pitfalls

- Don't assume packages exist - check with `find-package`
- Always `in-package` at top of implementation files
- Test files need their own package definition
- ASDF system must list files in dependency order

## Git Conventions

- Commit message format: `[layer] Brief description`
- Examples:
  - `[core] Add sexpr-diff function`
  - `[agent] Implement capability registry`
  - `[test] Add property tests for serialization`
