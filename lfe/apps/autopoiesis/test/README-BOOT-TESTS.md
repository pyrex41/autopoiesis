# Boot Tests - SCUD Task 10.1

## Overview

Comprehensive test suite for verifying the Autopoiesis LFE application boot process and initial state.

## Task Requirements

SCUD Task 10.1 requires:
1. ✅ Compile and boot the app using `rebar3 lfe repl`
2. ✅ Call `ensure_all_started`
3. ✅ Check that supervisors are running
4. ✅ Check that agent list is empty

## Test Suite

The test suite (`boot-tests.lfe`) includes **11 passing tests** organized into the following categories:

### Application Boot Tests

1. **application_started_test** - Verifies application starts via `application:ensure_all_started/1` and appears in running applications list
2. **supervisors_running_test** - Verifies all three supervisors (autopoiesis-sup, agent-sup, connector-sup) are running after boot
3. **agent_list_empty_test** - Verifies no agents are running at boot (agent list is empty)

### Individual Component Tests

4. **start_link_autopoiesis_sup_test** - Tests starting the main supervisor directly
5. **start_link_agent_sup_test** - Tests starting the agent supervisor directly and verifies empty children list
6. **start_link_connector_sup_test** - Tests starting the connector supervisor directly

### Supervisor Hierarchy Tests

7. **supervisor_children_test** - Verifies main supervisor has exactly 2 children (agent-sup, connector-sup)
8. **supervisor_strategy_test** - Verifies supervisor restart strategies:
   - autopoiesis-sup: one_for_one
   - agent-sup: simple_one_for_one
   - connector-sup: one_for_one

### Application Metadata Tests

9. **application_metadata_test** - Verifies application resource metadata (description, version, mod callback)

### Boot Edge Cases

10. **double_boot_test** - Verifies starting an already-running application is handled gracefully
11. **stop_and_restart_test** - Verifies application can be stopped and restarted cleanly

## Running the Tests

```bash
# Run all boot tests
rebar3 eunit --module=boot-tests

# Run with verbose output
rebar3 eunit --module=boot-tests --verbose
```

## Manual Verification

The boot process can also be verified manually:

```erlang
# Start LFE REPL
rebar3 lfe repl

# In the REPL:
(application:ensure_all_started 'autopoiesis)
; => #(ok ())

(whereis 'autopoiesis-sup)  ; => <0.xxx.0>
(whereis 'agent-sup)        ; => <0.xxx.0>
(whereis 'connector-sup)    ; => <0.xxx.0>

(agent-sup:list-agents)     ; => ()

(application:stop 'autopoiesis)  ; => ok
```

## Key Findings and Fixes

During test development, the following issues were discovered and fixed:

1. **Module naming mismatch**: The `.app.src` file referenced `autopoiesis_app` (with underscores), but LFE modules use hyphens. Fixed by updating `.app.src` to use `'autopoiesis-app'`.

2. **Process linking**: Direct supervisor tests needed to `unlink` before calling `exit` to prevent test process termination.

3. **Application state cleanup**: Tests properly handle already-loaded and already-running application states.

## Test Results

```
Finished in 0.047 seconds
11 tests, 0 failures
```

All tests are passing and verify that:
- Application boots successfully via `ensure_all_started`
- All three supervisors are running with correct PIDs
- Agent list is initially empty
- Supervisor hierarchy is correct
- Restart strategies are properly configured
- Application can be stopped and restarted cleanly
