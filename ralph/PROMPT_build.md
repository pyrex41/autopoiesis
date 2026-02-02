# Autopoiesis Build Mode

You are in BUILD MODE. Your job is to implement exactly ONE task from the implementation plan, validate it works, and commit.

## Context Loading

First, read these files:

1. Read `ralph/AGENTS.md` for build/test commands and conventions
2. Read `ralph/IMPLEMENTATION_PLAN.md` to find your task
3. Read relevant specs from `docs/specs/` for the task you're implementing
4. Read any existing source files related to your task

## Your Task

1. **Select ONE task** from "Next Up" in IMPLEMENTATION_PLAN.md
   - Pick the first uncompleted task (they're priority ordered)
   - If the list is empty, exit - planning mode needed

2. **Implement the task**
   - Write clean, idiomatic Common Lisp
   - Follow conventions in AGENTS.md
   - Keep changes focused on the single task
   - Add tests for new functionality

3. **Validate your work**
   - Run the build command from AGENTS.md
   - Run the test command from AGENTS.md
   - Fix any errors before proceeding
   - All tests must pass

4. **Update state**
   - Mark task as `[x]` completed in IMPLEMENTATION_PLAN.md
   - Add any discovered subtasks to "Next Up"

5. **Commit changes**
   - Stage all modified/new files
   - Write a clear commit message describing what was implemented
   - Do NOT push (human will review)

6. **Exit**
   - Your iteration is complete
   - The loop will restart with fresh context

## Rules

1. ONE task per iteration - no more
2. ALL tests must pass before committing
3. If stuck for >5 minutes, add blocker to IMPLEMENTATION_PLAN.md and exit
4. Never commit broken code
5. Never skip validation
6. Keep commits atomic and focused

## Common Lisp Conventions

- Use SBCL as the implementation
- Follow package structure from `docs/specs/01-core-architecture.md`
- Use CLOS with proper slot documentation
- Define conditions with restarts
- Write FiveAM tests

## If Validation Fails

1. Read the error message carefully
2. Fix the issue
3. Re-run validation
4. If you can't fix after 3 attempts, mark as blocked and exit

When your ONE task is complete and committed, exit. The loop handles the next task.
