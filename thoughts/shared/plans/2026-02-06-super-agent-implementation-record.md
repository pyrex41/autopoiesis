# Super Agent Implementation Record

**Date**: 2026-02-06
**Status**: Complete (all 5 phases implemented, E2E verified)
**Plan**: `thoughts/shared/plans/2026-02-06-super-agent-implementation.md`

## What Was Built

A long-running infrastructure monitoring agent ("Super Agent") that combines the LFE/BEAM conductor (Ralph loop pattern) with Claude Code CLI for investigation/reasoning and Cortex MCP tools for infrastructure perception. The system runs indefinitely via OTP supervision.

### Architecture

```
                        autopoiesis-sup (one_for_one)
                       /      |        |        \
                conductor  agent-sup  connector-sup  claude-sup
                (worker)   (s1f1)     (1f1)          (s1f1)
                   |          |          |               |
               100ms tick  CL workers  cowboy/4007    claude-worker(s)
                   |                     |               |
               timer heap             /health         open_port(spawn)
               event queue           /webhook            |
                                                    claude -p ... </dev/null
                                                         |
                                                    stream-json → jsx:decode
                                                         |
                                                    report to conductor
```

### Data Flow

1. **Conductor** schedules a periodic infra-watcher timer (every 5 min)
2. Timer fires → conductor checks rate limiting → spawns `claude-worker` via `claude-sup`
3. `claude-worker` builds a shell command: `claude -p '<prompt>' --output-format stream-json --verbose --max-turns 20 --dangerously-skip-permissions --mcp-config cortex-mcp.json --allowedTools <tools> </dev/null`
4. Erlang port captures streaming JSON lines from Claude's stdout
5. Each line parsed with `jsx:decode` → accumulated in `output-buffer`
6. On exit status 0: extract `"result"` type message, cast `#(task-result ...)` to conductor
7. Conductor increments `tasks-completed`, resets `consecutive-failures` on success
8. On failure: increment `consecutive-failures`, log warning, exponential backoff after 3

## Files Created

### `lfe/apps/autopoiesis/src/claude-worker.lfe` (257 LOC)

Gen_server managing a Claude Code CLI subprocess via Erlang port.

**Key design decisions:**
- Uses `{spawn, ShellCmd}` (not `spawn_executable`) because Claude CLI hangs when stdin is an Erlang pipe. The shell command includes `</dev/null` to redirect stdin from /dev/null.
- `--verbose` flag is required when using `--output-format stream-json` with `-p`
- Prompts are single-quoted with proper shell escaping (single quotes replaced with `'\''`)
- All config values go through `ensure-string/1` which converts binaries and atoms to lists — necessary because Erlang callers pass binaries, LFE callers pass list strings

**State map:**
```
#M(port <port>              ; Erlang port to claude process
   task-id <string>         ; Unique task identifier
   config <map>             ; Task configuration
   started <integer>        ; System time when started (seconds)
   output-buffer <list>     ; Accumulated parsed JSON maps
   status <atom>            ; running | complete | failed
   timer-ref <reference>    ; Timeout timer reference
   timeout <integer>)       ; Max runtime in ms (default 300000)
```

**Exported functions:**
| Function | Description |
|----------|-------------|
| `start_link/1` | Start a worker with task-config map |
| `get-status/1` | Get worker status (task-id, status, uptime) |
| `build-claude-command/1` | Build shell command string (pure, exported for testing) |
| `parse-result/1` | Extract result from message list (pure, exported for testing) |

**Config map keys:**
| Key | Default | Description |
|-----|---------|-------------|
| `prompt` | `""` | Prompt text (string or binary) |
| `claude-path` | auto-detect | Path to claude executable |
| `mcp-config` | `undefined` | Path to MCP server config JSON |
| `allowed-tools` | `""` | Comma-separated tool names |
| `max-turns` | `50` | Maximum agent turns |
| `timeout` | `300000` | Max runtime in milliseconds |
| `task-id` | auto-generated | Unique task identifier |

### `lfe/apps/autopoiesis/src/claude-sup.lfe` (37 LOC)

`simple_one_for_one` supervisor for dynamic Claude worker spawning.

- Intensity 3, period 60 (max 3 restarts per minute)
- Child restart: `transient` (only restart if abnormal exit)
- Shutdown timeout: 10000ms (allows Claude process cleanup)

**API:**
| Function | Description |
|----------|-------------|
| `spawn-claude-agent/1` | Start a new worker with config map |
| `stop-claude-agent/1` | Terminate a worker by pid |
| `list-claude-agents/0` | List all running workers |

### `lfe/apps/autopoiesis/test/claude-worker-tests.lfe` (136 LOC)

Pure function tests for `build-claude-command` and `parse-result`.

**build-claude-command tests (9):**
- Basic command construction (includes -p, stream-json, --verbose, --dangerously-skip-permissions, </dev/null)
- With/without MCP config
- With/without custom max-turns (default 50)
- With/without allowed tools
- Custom claude path
- Prompt quoting (single quotes for shell safety)

**parse-result tests (5):**
- Empty buffer returns error map
- Extracts `"result"` type message from list
- Returns last message if no result type found
- Returns last result when multiple result messages exist
- Handles single message buffer

**Test helpers:**
- `assert-contains/2` — string:find based substring check
- `assert-not-contains/2` — inverse of above

### `lfe/config/cortex-mcp.json` (9 LOC)

MCP server configuration for Cortex. Invokes `uv run` to start the Cortex Python MCP server.

### `lfe/config/infra-watcher-prompt.md` (32 LOC)

Structured prompt for infrastructure monitoring. Instructs Claude to:
1. Check Cortex status
2. Review entity schema
3. Query recent events (limit 50)
4. Investigate concerning events
5. Return structured JSON with status/anomalies/summary

## Files Modified

### `lfe/apps/autopoiesis/src/conductor.lfe`

**New exports:** `schedule-infra-watcher/0`

**New metrics in init:** `tasks-completed`, `consecutive-failures`, `last-failure-time`

**New handle_cast clause** — `#(task-result ...)`:
- Increments `tasks-completed`
- On success: logs, calls `process-task-result`, resets `consecutive-failures`
- On failure: increments `consecutive-failures`, logs with count, warns after 3 consecutive

**Modified `execute-timer-action`**: checks `action-type` key:
- `'claude` → check rate limiting via `claude-task-running-p`, then `spawn-claude-for-work`
- anything else → existing `spawn-agent-for-work` behavior

**New functions:**

| Function | Lines | Description |
|----------|-------|-------------|
| `spawn-claude-for-work/1` | 344-363 | Async spawn wrapper (same pattern as spawn-agent-for-work) |
| `build-prompt-for-work/1` | 365-371 | Build prompt string from work-item map |
| `schedule-infra-watcher/0` | 377-391 | Schedule recurring 5-min infra watcher with Cortex MCP |
| `process-task-result/1` | 393-405 | Severity-based result logging (critical/warning/clear) |
| `read-prompt-file/1` | 411-417 | Read prompt file, fallback to default string |
| `mcp-config-path/1` | 419-423 | Resolve MCP config to absolute path or undefined |
| `claude-task-running-p/1` | 429-443 | Rate limiting — check if task type already running |

**Updated `build-status`**: includes `tasks-completed` and `consecutive-failures`

### `lfe/apps/autopoiesis/src/autopoiesis-sup.lfe`

Added `claude-sup` as 4th child in the supervision tree. Uses `claude-sup-spec/0` which returns a permanent supervisor child spec with infinite shutdown timeout.

### `lfe/apps/autopoiesis/src/autopoiesis.app.src`

Added `'claude-sup'` to the `registered` list.

### `lfe/apps/autopoiesis/src/health-handler.lfe`

Added to health JSON response:
- `claude_agents` — count of running Claude workers
- `tasks_completed` — total completed tasks from conductor metrics

### `lfe/apps/autopoiesis/test/boot-tests.lfe`

- Added `assert-supervisor-running 'claude-sup` to supervisors test
- Added `(catch (unregister 'claude-sup))` to clean state helper
- Changed supervisor children count assertion: 3 → 4
- Added `has-child-id 'claude-sup` check
- Added claude-sup strategy test (`simple_one_for_one`)

### `lfe/apps/autopoiesis/test/conductor-tests.lfe`

Two new tests:
- `task_result_handling_test` — verifies task-result cast doesn't crash conductor, increments tasks-completed
- `task_result_failure_tracking_test` — verifies consecutive-failures increments on failure and resets on success

### `scripts/agent-worker.lisp`

Fixed CL worker loading:
- Added Quicklisp init from `~/quicklisp/setup.lisp`
- Added project root push to `asdf:*central-registry*` (derived from `*load-truename*`)
- These run before `(asdf:load-system :autopoiesis)` so dependencies resolve

## Bugs Found and Fixed

### 1. Claude CLI hangs on Erlang port stdin

**Problem**: Claude CLI hangs indefinitely when launched via `spawn_executable` or `spawn` because Erlang ports provide a pipe for stdin. Claude CLI enters interactive mode waiting for terminal input.

**Fix**: Use `{spawn, ShellCmd}` with `</dev/null` appended to the shell command string. This redirects stdin from /dev/null, causing Claude to see EOF on stdin and run in non-interactive mode.

**Commit**: `834b7e5`

### 2. `--verbose` required for stream-json with `-p`

**Problem**: `claude -p "..." --output-format stream-json` fails with: `Error: When using --print, --output-format=stream-json requires --verbose`

**Fix**: Add `"--verbose"` to the args list in `build-claude-command`.

**Commit**: `834b7e5`

### 3. Binary strings crash shell-escape

**Problem**: When calling `claude-sup:spawn-claude-agent` from Erlang (e.g., `erl -eval`), map values like `prompt` arrive as binaries (`<<"hello">>`) instead of LFE list strings (`"hello"`). The `shell-escape-single-quotes` function pattern-matches on `cons` (list) patterns and crashes with `no case clause matching` on binaries.

**Fix**: Added `ensure-string/1` utility that converts binaries (`binary_to_list`) and atoms (`atom_to_list`) to list strings. Applied to `prompt`, `claude-path`, `allowed-tools`, and `mcp-config` in `build-claude-command`.

**Commit**: `1916c60`

### 4. LFE `when` guard syntax

**Problem**: LFE doesn't support standalone `when` guards in the same way Erlang does. Patterns like `(when (is_port port) ...)` outside of function head guards cause compilation errors: `illegal guard expression` and `function when/2 undefined`.

**Fix**: Replace `when` guards in function bodies with `case`/`if` expressions. E.g., in `handle_info`, use `(case (maps:get 'status state) ('running ...))` instead of `(when (=:= (maps:get 'status state) 'running))`.

### 5. LFE binary string syntax

**Problem**: `<<"type">>` is Erlang binary syntax. In LFE, this causes `unbound symbol <<` errors.

**Fix**: Use LFE binary string syntax: `#"type"` instead of `<<"type">>`.

## Test Results

```
$ cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests,claude-worker-tests
75 tests, 0 failures

$ ./scripts/test.sh
Tests complete! (all CL tests pass)
```

### Test breakdown by module:
| Module | Tests | Description |
|--------|-------|-------------|
| boot-tests | 9 | App boot, supervisors, children, strategies, metadata |
| conductor-tests | 17 | Pure functions, standalone, integration, task-result |
| agent-worker-tests | 13 | CL worker protocol, parse response |
| connector-tests | 5 | HTTP endpoints (health, webhook) |
| claude-worker-tests | 14 | Command building, result parsing |
| **Total** | **75** | **0 failures** |

## E2E Verification

Confirmed the full lifecycle works end-to-end:

```erlang
erl -pa _build/test/lib/*/ebin -eval "
  application:ensure_all_started(autopoiesis),
  {ok, Pid} = 'claude-sup':'spawn-claude-agent'(
    #{prompt => <<\"Say only the word PONG\">>,
      'max-turns' => 1, timeout => 60000}),
  timer:sleep(30000),
  %% Worker completed, conductor state shows:
  %% tasks-completed => 1
"
```

Result: `tasks-completed => 1` — confirmed the full pipeline:
1. Erlang port spawns Claude CLI with `</dev/null`
2. Claude CLI runs, produces stream-json output on stdout
3. Worker receives `{Port, {data, {eol, Line}}}` messages
4. `jsx:decode` parses each JSON line
5. On `exit_status 0`, worker extracts result message
6. Worker casts `#(task-result ...)` to conductor
7. Conductor increments `tasks-completed` metric
8. Worker stops normally, supervisor cleans up

## LFE Patterns Documented

### Map literal gotcha
`#M(key val)` does NOT evaluate expressions in value positions. Use backtick-unquote:
```lfe
;; WRONG: stores the atom 'variable' literally
#M(key variable)

;; RIGHT: evaluates variable
`#M(key ,variable)
```

### Binary vs list strings
- LFE strings are Erlang charlists: `"hello"` = `[104,101,108,108,111]`
- LFE binary strings: `#"hello"` = `<<"hello">>`
- Erlang callers pass binaries; LFE code expects lists
- Always use `ensure-string/1` at API boundaries

### No standalone `when` in LFE
Unlike Erlang, `when` is only valid in function head guards in LFE:
```lfe
;; WRONG — doesn't compile
(defun foo (x)
  (when (is_integer x) (+ x 1)))

;; RIGHT — use if/case in body
(defun foo (x)
  (if (is_integer x) (+ x 1) 'error))
```

## Commit History

```
1916c60 [super-agent] Handle binary strings in claude-worker command building
834b7e5 [super-agent] Fix Claude CLI port communication: shell spawn with /dev/null
5120009 [lfe] Add Claude worker subsystem for Super Agent infrastructure monitoring
```

## What's Next

The system is ready for live testing. To activate:

```lfe
%% In LFE REPL or after app boot:
(conductor:schedule-infra-watcher)

%% This schedules a recurring 5-minute timer that:
%% 1. Spawns a claude-worker with Cortex MCP config
%% 2. Claude queries Cortex for infrastructure events
%% 3. Reports findings back to conductor
%% 4. Reschedules for next interval
```

Future extensions:
- **Self-extension loop**: Claude writes LFE code that conductor hot-loads
- **Agent teams**: Multiple Claude workers coordinating on complex tasks
- **Webhook triggers**: External events triggering Claude investigations
- **Result persistence**: Store findings in CL snapshot DAG
- **Alerting**: Escalate critical findings via webhook/notification
