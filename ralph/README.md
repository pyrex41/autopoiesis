# Ralph Wiggum Loop for Autopoiesis

This directory contains the Ralph Wiggum implementation for building Autopoiesis autonomously.

## What is the Ralph Wiggum Method?

A bash loop that feeds prompts to opencode repeatedly, with state persisting through files (not LLM context). Each iteration starts fresh to avoid "context rot."

**Core principle:** `while :; do opencode --model xai/grok-4-1-fast run "$(cat PROMPT.md)"; done`

## Quick Start

```bash
# Run a few planning iterations to analyze gaps
./loop.sh plan 3

# Run build iterations (implement tasks one at a time)
./loop.sh build 10

# Run indefinitely until ctrl-c
./loop.sh build
```

## Files

| File | Purpose |
|------|---------|
| `loop.sh` | Main orchestration script |
| `PROMPT_plan.md` | Planning mode instructions (gap analysis, no code) |
| `PROMPT_build.md` | Build mode instructions (implement one task, test, commit) |
| `AGENTS.md` | Build/test commands, project conventions |
| `IMPLEMENTATION_PLAN.md` | Persistent state tracking tasks |

## How It Works

### Planning Mode (`./loop.sh plan`)
1. Reads specs from `docs/specs/`
2. Compares against existing `src/` code
3. Updates `IMPLEMENTATION_PLAN.md` with prioritized tasks
4. Exits (loop restarts)

### Build Mode (`./loop.sh build`)
1. Reads `IMPLEMENTATION_PLAN.md`
2. Picks ONE task from "Next Up"
3. Implements the task
4. Runs tests (must pass)
5. Commits changes
6. Updates plan (marks complete)
7. Exits (loop restarts with fresh context)

## Key Principles

1. **One task per iteration** - Keeps changes focused and context fresh
2. **Backpressure through tests** - Code must pass validation before commit
3. **State in files, not LLM** - Git and markdown are the source of truth
4. **Fresh context each time** - Avoids context window degradation

## Safety

opencode handles permissions interactively or via config. For safer operation:
- Run in a Docker container
- Use a git branch for Ralph's work
- Review commits before merging to main

## Monitoring Progress

```bash
# Watch the implementation plan
watch cat ralph/IMPLEMENTATION_PLAN.md

# Follow git commits
watch git log --oneline -10

# Check test status
./scripts/test.sh
```

## Customization

Edit the prompts to adjust behavior:
- `PROMPT_plan.md` - Change planning strategy
- `PROMPT_build.md` - Change implementation approach
- `AGENTS.md` - Update build/test commands

## References

- [ghuntley/how-to-ralph-wiggum](https://github.com/ghuntley/how-to-ralph-wiggum)
- [Ralph Wiggum Playbook](https://paddo.dev/blog/ralph-wiggum-playbook/)
- [ghuntley.com/ralph](https://ghuntley.com/ralph/)
