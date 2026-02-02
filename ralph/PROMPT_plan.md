# Autopoiesis Planning Mode

You are in PLANNING MODE. Your job is to analyze the gap between specifications and current implementation, then update the implementation plan. DO NOT write any implementation code.

## Context Loading

First, read these files to understand the project:

1. Read `ralph/AGENTS.md` for build/test commands and project conventions
2. Read all files in `docs/specs/` to understand requirements
3. Read `ralph/IMPLEMENTATION_PLAN.md` to see current progress
4. Scan `src/` directory (if it exists) to see what's already implemented

## Your Task

Perform gap analysis:

1. **Compare specs to implementation**
   - What does the spec require?
   - What exists in `src/`?
   - What's missing?

2. **Update IMPLEMENTATION_PLAN.md**
   - Mark completed tasks as `[x]`
   - Add new tasks discovered during analysis
   - Prioritize: foundation first, then layers that depend on it
   - Keep tasks small and atomic (one concept per task)

3. **Identify blockers**
   - What decisions need human input?
   - What dependencies are unclear?

## Output Format

Update `ralph/IMPLEMENTATION_PLAN.md` with this structure:

```markdown
# Autopoiesis Implementation Plan

Last updated: [timestamp]
Phase: [current phase number]

## Completed
- [x] Task description

## In Progress
- [ ] Task description (started: date, notes: ...)

## Next Up (Priority Order)
- [ ] Task 1 - brief description
- [ ] Task 2 - brief description
...

## Blocked / Needs Human Input
- [ ] Task - reason blocked

## Future (Not Yet Ready)
- [ ] Task - waiting for: dependency
```

## Rules

1. DO NOT write implementation code
2. DO NOT create source files
3. ONLY update IMPLEMENTATION_PLAN.md
4. Keep tasks atomic and testable
5. Follow the phase order from `docs/specs/07-implementation-roadmap.md`
6. Exit when planning is complete for this iteration

When done, simply exit. The loop will restart for the next iteration.
