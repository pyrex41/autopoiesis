# Ralph Wiggum Loop for Autopoiesis

This directory contains the Ralph Wiggum implementation for building Autopoiesis autonomously.

## What is the Ralph Wiggum Method?

A bash loop that feeds prompts to opencode repeatedly, with state persisting through files (not LLM context). Each iteration starts fresh to avoid "context rot."

**Core principle:** `while :; do opencode --model xai/grok-4-1-fast run "$(cat PROMPT.md)"; done`

## Quick Start
 
```bash
# Run a few planning iterations to analyze gaps
./loop.sh plan -n 3

# Run build iterations (implement tasks one at a time)
./loop.sh build -n 10

# Run with default cap (30 iterations, or until agent writes ralph/.stop)
./loop.sh build
```

### CLI Selection
```
./loop.sh build -c opencode    # Uses opencode (default model: grok-4-1-fast)
./loop.sh build -c claude      # Uses claude CLI (strong reasoning)
./loop.sh build -c cursor      # Uses cursor-agent binary (--force for auto-run)
```


## Files

| File | Purpose |
|------|---------|
| `loop.sh` | Main orchestration script (supports claude/cursor/opencode CLIs) |
| `supervised.sh` | Human-approval variant — pauses after each iteration |
| `run-once.sh` | Single iteration runner (no loop, useful for testing) |
| `stream_display.py` | TUI that reads streaming JSON and renders tool calls + text |
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

## Stream Display

When running the loop, raw CLI output is streaming JSON — not human-readable. The display script (`stream_display.py`) sits between the CLI and your terminal, turning the JSON stream into something you can actually follow.

### What it shows

```
┌─ Iteration 3 ──────────────────────────── build | opus 4.5 ─┐

Agent text output appears here...

  > Read  src/core/packages.lisp
  > Edit  src/core/sexpr.lisp
  > Bash  sbcl --noinform --non-interactive --load scripts/test.sh

More agent text...

  Files changed:
    M src/core/sexpr.lisp
    A test/core/sexpr-test.lisp

└───────────────── 1m23s | 8 tool calls | 2 files changed ────┘
```

- Tool calls are always visible, color-coded by type (blue=read, yellow=edit, green=bash, magenta=task)
- Press `v` during streaming to collapse text output — only tool calls remain visible, with a spinner status bar
- Git diff before/after each iteration shown in the footer

### Architecture

The display is a stdin filter. The CLI writes `--output-format stream-json` and you pipe it:

```bash
claude --output-format stream-json -p "$PROMPT" | python3 stream_display.py --iteration 1 --mode build
```

It processes these event types from the JSON stream:
- `assistant` — message content arrays containing `text` and `tool_use` blocks
- `content_block_start/delta/stop` — streaming mode (accumulates tool input JSON, prints on stop)
- `tool_call` — fallback for CLIs that send tool events separately

Per-block dedup tracks by `(message_id, content_index)` to avoid reprinting text when partial messages arrive.

### Debugging the stream

If tools show as `?` or text is missing, dump the raw JSON to see what the CLI actually sends:

```bash
./loop.sh build --dump /tmp/stream.jsonl
# Then inspect:
cat /tmp/stream.jsonl | python3 -m json.tool | less
```

## Scaffolding a New Ralph Setup

To add a Ralph loop to a different project, copy the scaffolding files and customize the prompts. The loop scripts and display are project-agnostic; only the prompt and agent files need project-specific content.

### Minimum viable setup

```
your-project/
└── ralph/
    ├── loop.sh              # Copy as-is
    ├── stream_display.py    # Copy as-is (or write your own — see below)
    ├── PROMPT_plan.md       # Write for your project
    ├── PROMPT_build.md      # Write for your project
    ├── AGENTS.md            # Write for your project
    └── IMPLEMENTATION_PLAN.md  # Start empty with section headers
```

**What to copy unchanged:** `loop.sh`, `supervised.sh`, `run-once.sh`, `stream_display.py`. These discover paths relative to themselves (`SCRIPT_DIR`, `PROJECT_ROOT`) and don't contain project-specific logic.

**What to write per project:**

1. **AGENTS.md** — Build/test commands, directory structure, code conventions, git commit format. This is the reference card agents read every iteration.

2. **PROMPT_plan.md** — Instructions for planning mode. Tell the agent where specs live, how to do gap analysis, and to update `IMPLEMENTATION_PLAN.md` without writing code.

3. **PROMPT_build.md** — Instructions for build mode. Tell the agent to pick ONE task, implement it, run tests, commit, and mark the task complete.

4. **IMPLEMENTATION_PLAN.md** — Seed it with section headers:
   ```markdown
   ## Completed
   ## In Progress
   ## Next Up
   ## Blocked / Needs Human Input
   ```

### Exit criteria and the stop file

The loop has two stop conditions that always apply:

1. **Max iterations** (default 30, always enforced) — a hard cap so the loop never runs forever
2. **Stop file** (`ralph/.stop`) — the agent writes this file when there's nothing left to do, and the loop checks for it before each iteration

The stop file is the clean shutdown mechanism. Your prompts must tell the agent when to create it:

```bash
# Agent writes this when the task queue is empty
echo "no tasks remaining" > ralph/.stop

# Or when planning is done
echo "planning complete - all specs covered" > ralph/.stop

# Or when everything is blocked
echo "all tasks blocked" > ralph/.stop
```

The loop reads the file contents as a reason, logs it, deletes the file, and stops. The file is also cleaned up on loop startup so a stale stop file from a previous run doesn't block a fresh start.

**Your prompts also need clear exit criteria for each iteration** (separate from stopping the whole loop). Each iteration should exit cleanly so the next one starts with fresh context. If your prompts don't make this explicit, agents will either do multiple tasks in one iteration (burning context) or exit before committing state.

The pattern in each prompt should be:
1. Do the work (one task / one planning pass)
2. Validate (tests pass / plan is coherent)
3. Commit state to files (git commit / update plan markdown)
4. If nothing left to do → write `ralph/.stop` with a reason
5. Exit

Every code path should end with "exit." Success exits, failure exits, empty-queue exits (after writing the stop file). The loop handles retries — individual iterations should not.

### Writing your own display

The `stream_display.py` included here is ~480 lines of Python, but you don't need all of it. A minimal display only needs to:

1. Read lines from stdin
2. Parse each line as JSON
3. Handle `assistant` events: walk `message.content[]`, print `text` blocks and extract `tool_use` blocks
4. Handle `content_block_delta` events: print `text_delta`, accumulate `input_json_delta`
5. Handle `content_block_stop`: parse accumulated tool input, print tool name + key arg

That's the core — maybe 80 lines in any language. Everything else (colors, spinners, `[v]` toggle, git snapshots, dedup) is polish. You could write it in bash with `jq`, in Node, in Go, whatever fits your project.

The key architectural point: **pipe the CLI's `--output-format stream-json` into your display**. Don't try to parse terminal escape codes from the CLI's normal output.

```bash
# The pattern
$CLI --output-format stream-json -p "$PROMPT" | your-display-script
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
