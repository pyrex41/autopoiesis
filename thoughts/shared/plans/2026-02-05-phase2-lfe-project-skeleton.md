# Phase 2: LFE Project Skeleton — Detailed Implementation Plan

## Parent Plan

`thoughts/shared/plans/2026-02-04-lfe-supervised-agent-platform.md` — Phase 2

## Goal

Create a working rebar3/LFE project that compiles, boots an OTP application with a supervision tree, and can spawn agent-worker gen_servers that communicate with CL cognitive engine processes via ports.

## Prerequisites

- Phase 1 complete: `scripts/agent-worker.lisp` exists with working stdin/stdout S-expression protocol
- Erlang/OTP and rebar3 installed on the system
- LFE available as a rebar3 dependency

## Corrections from Research

The master plan has several inaccuracies that this detailed plan corrects:

### 1. Port message format with `{line, N}`

The master plan's `port-receive` matches on `#(,port #(data ,line))`, but with the `{line, N}` option, Erlang delivers messages as:
```
{Port, {data, {eol, Line}}}     %% complete line (newline stripped)
{Port, {data, {noeol, Line}}}   %% line exceeded max length or EOF
```

Not `{Port, {data, Line}}`. The `port-receive` function must handle the `eol`/`noeol` wrapper.

### 2. Logging: OTP logger instead of lager

For new projects on OTP 24+, `logger` is built-in and preferred over `lager`. This removes a dependency and uses the standard approach. Replace all `lager:info/warning/error` calls with `logger:info/warning/error`.

### 3. Dependency versions

- cowboy: `2.14.2` (not `2.10.0`)
- rebar3_lfe: `0.4.x` for stability (not `0.5.0` — 0.5.x is experimental rewrite)
- lager: removed (use OTP logger)

### 4. Map syntax

LFE supports maps with `#M(key val ...)` syntax. The plan uses lowercase `#m(...)` which should work but `#M` is the canonical form. We'll use `#M` consistently.

### 5. `mref` 3-arg form doesn't exist

The master plan uses `(mref config 'cl-worker-script "../scripts/agent-worker.lisp")` as a default-value lookup. Standard `mref` / `maps:get` takes 2 args. Use `(maps:get 'cl-worker-script config #"../scripts/agent-worker.lisp")` for default values.

### 6. `lfe_io:print1` and `lfe_io:read_string` need verification

These are internal LFE functions. For S-expression serialization we should use:
- `lfe_io:print1/1` — prints LFE term to string (returns iolist)
- `lfe_io:read_string/1` — parses LFE string to term (returns `{ok, Term}` or `{error, ...}`)

If these aren't stable public API, fall back to `io_lib:format("~w", [Term])` for writing and a custom parser for reading. However, since our protocol is S-expressions and LFE *is* S-expressions, `lfe_io` is the right choice.

---

## Directory Structure

```
lfe/
├── rebar.config                              # Build config, deps, release
├── apps/
│   └── autopoiesis/
│       ├── src/
│       │   ├── autopoiesis.app.src           # OTP application descriptor
│       │   ├── autopoiesis-app.lfe           # Application callback
│       │   ├── autopoiesis-sup.lfe           # Top-level supervisor
│       │   ├── agent-sup.lfe                 # Agent supervisor (simple_one_for_one)
│       │   ├── agent-worker.lfe              # Port wrapper gen_server
│       │   └── connector-sup.lfe             # Connector supervisor (placeholder)
│       └── include/
│           └── autopoiesis.lfe               # Common macros/records (if needed)
├── config/
│   ├── sys.config                            # Application env config
│   └── vm.args                               # BEAM VM args
└── test/
    ├── agent-worker-tests.lfe                # Agent worker unit tests
    └── supervision-tests.lfe                 # Supervisor behavior tests
```

---

## Task Breakdown

### Task 0: Install Erlang/OTP and rebar3

**Why**: Nothing else works without the runtime.

**Steps**:
1. Install Erlang/OTP via `brew install erlang` (or nix)
2. Install rebar3 via `brew install rebar3` (or nix)
3. Verify: `erl -eval 'io:format("~s~n", [erlang:system_info(otp_release)])' -noshell -s init stop` prints OTP version
4. Verify: `rebar3 version` prints version

**Note**: LFE itself is a rebar3 dependency — no separate install needed.

**Success**: `erl` and `rebar3` are on PATH and working.

---

### Task 1: Create rebar.config and project structure

**File**: `lfe/rebar.config`

```erlang
{erl_opts, [debug_info]}.

{plugins, [
    {rebar3_lfe, "0.4.9"}
]}.

{deps, [
    {lfe, "2.2.0"}
]}.

{relx, [
    {release, {autopoiesis, "0.1.0"}, [
        autopoiesis,
        sasl
    ]},
    {mode, dev},
    {dev_mode, true},
    {include_erts, false},
    {extended_start_script, true},
    {sys_config, "./config/sys.config"},
    {vm_args, "./config/vm.args"}
]}.

{profiles, [
    {prod, [
        {relx, [
            {mode, prod},
            {dev_mode, false},
            {include_erts, true}
        ]}
    ]},
    {test, [
        {deps, [
            {ltest, "0.13.8"}
        ]}
    ]}
]}.
```

**Notes**:
- cowboy/jsx NOT included yet — those are Phase 4 (connectors). Keep deps minimal.
- `ltest` is the LFE testing framework (wraps EUnit).
- Mode `dev` uses symlinks, faster iteration.

**File**: `lfe/config/sys.config`
```erlang
[
  {autopoiesis, [
    {cl_worker_script, "../scripts/agent-worker.lisp"},
    {sbcl_path, "sbcl"}
  ]}
].
```

**File**: `lfe/config/vm.args`
```
-sname autopoiesis
-setcookie autopoiesis_dev
+K true
+A 4
```

**Depends on**: Task 0

**Success**: Directory structure exists. `cd lfe && rebar3 lfe compile` downloads deps and compiles (even if no source files yet).

---

### Task 2: Create .app.src (OTP application descriptor)

**File**: `lfe/apps/autopoiesis/src/autopoiesis.app.src`

```erlang
{application, autopoiesis,
 [{description, "LFE supervision layer for Autopoiesis agent platform"},
  {vsn, "0.1.0"},
  {modules, []},
  {registered, [autopoiesis_sup, conductor, agent_sup, connector_sup]},
  {applications, [kernel, stdlib]},
  {mod, {autopoiesis-app, []}},
  {env, [
    {cl_worker_script, "../scripts/agent-worker.lisp"},
    {sbcl_path, "sbcl"}
  ]}
]}.
```

**Notes**:
- `modules` left empty — rebar3 auto-populates during build.
- `mod` specifies the application callback module that gets `start/2` called.
- `registered` lists process names for clash detection.
- `applications` only lists stdlib deps for now (cowboy added in Phase 4).
- Module name in `mod` uses hyphen (`autopoiesis-app`) which LFE translates to `autopoiesis-app` atom. Need to verify this is valid — Erlang atoms can contain hyphens when quoted.

**Depends on**: Task 1

**Success**: rebar3 can read the .app.src without errors.

---

### Task 3: Create autopoiesis-app.lfe (application callback)

**File**: `lfe/apps/autopoiesis/src/autopoiesis-app.lfe`

```lfe
(defmodule autopoiesis-app
  (behaviour application)
  (export (start 2) (stop 1)))

(defun start (_type _args)
  (logger:info "Autopoiesis starting...")
  (autopoiesis-sup:start_link))

(defun stop (_state)
  (logger:info "Autopoiesis stopping...")
  'ok)
```

**Depends on**: Task 2

**Success**: Module compiles.

---

### Task 4: Create autopoiesis-sup.lfe (top-level supervisor)

**File**: `lfe/apps/autopoiesis/src/autopoiesis-sup.lfe`

The top-level supervisor manages three children:
1. **conductor** (gen_server) — Phase 3, but we need a placeholder
2. **agent-sup** (supervisor) — manages agent workers
3. **connector-sup** (supervisor) — Phase 4, but we need a placeholder

For Phase 2, conductor and connector-sup will be minimal placeholders that just start and do nothing.

```lfe
(defmodule autopoiesis-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)))

(defun start_link ()
  (supervisor:start_link #(local autopoiesis-sup) 'autopoiesis-sup '()))

(defun init (_args)
  (let* ((sup-flags #M(strategy one_for_one
                       intensity 5
                       period 10))
         (children (list (agent-sup-spec)
                         (connector-sup-spec))))
    `#(ok #(,sup-flags ,children))))

(defun agent-sup-spec ()
  #M(id agent-sup
     start #(agent-sup start_link ())
     restart permanent
     shutdown infinity
     type supervisor
     modules (agent-sup)))

(defun connector-sup-spec ()
  #M(id connector-sup
     start #(connector-sup start_link ())
     restart permanent
     shutdown infinity
     type supervisor
     modules (connector-sup)))
```

**Notes**:
- Uses map-based child specs (OTP 21+ modern format) instead of the old tuple format from the master plan.
- Conductor is **excluded** from Phase 2 — it's Phase 3's job. The supervisor starts without it.
- If we need conductor as a placeholder, add it later.

**Depends on**: Task 3

**Success**: Module compiles. Supervisor can describe its children.

---

### Task 5: Create agent-sup.lfe (dynamic agent supervisor)

**File**: `lfe/apps/autopoiesis/src/agent-sup.lfe`

```lfe
(defmodule agent-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)
          (spawn-agent 1) (stop-agent 1) (list-agents 0)))

(defun start_link ()
  (supervisor:start_link #(local agent-sup) 'agent-sup '()))

(defun init (_args)
  (let ((sup-flags #M(strategy simple_one_for_one
                      intensity 3
                      period 60))
        (child-spec #M(id agent-worker
                       start #(agent-worker start_link ())
                       restart transient
                       shutdown 5000
                       type worker
                       modules (agent-worker))))
    `#(ok #(,sup-flags (,child-spec)))))

;;; Client API

(defun spawn-agent (agent-config)
  "Spawn a new agent worker under this supervisor."
  (supervisor:start_child 'agent-sup (list agent-config)))

(defun stop-agent (pid)
  "Stop an agent worker."
  (supervisor:terminate_child 'agent-sup pid))

(defun list-agents ()
  "List all running agent workers."
  (supervisor:which_children 'agent-sup))
```

**Notes**:
- `simple_one_for_one`: all children are same type (agent-worker), added dynamically.
- `transient` restart: only restart on abnormal exit (not on normal shutdown).
- `intensity 3, period 60`: max 3 restarts per 60 seconds before supervisor gives up.
- `start_child` passes the agent-config as argument to `agent-worker:start_link/1`.

**Depends on**: Task 4

**Success**: Module compiles.

---

### Task 6: Create connector-sup.lfe (placeholder)

**File**: `lfe/apps/autopoiesis/src/connector-sup.lfe`

```lfe
(defmodule connector-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)))

(defun start_link ()
  (supervisor:start_link #(local connector-sup) 'connector-sup '()))

(defun init (_args)
  ;; No children yet — connectors added in Phase 4
  (let ((sup-flags #M(strategy one_for_one
                      intensity 5
                      period 10)))
    `#(ok #(,sup-flags ()))))
```

**Depends on**: Task 4

**Success**: Module compiles.

---

### Task 7: Create agent-worker.lfe (port wrapper gen_server)

This is the most complex module. It wraps the CL cognitive engine process.

**File**: `lfe/apps/autopoiesis/src/agent-worker.lfe`

```lfe
(defmodule agent-worker
  (behaviour gen_server)
  (export
    ;; gen_server callbacks
    (start_link 1) (init 1)
    (handle_call 3) (handle_cast 2) (handle_info 2)
    (terminate 2) (code_change 3)
    ;; Client API
    (cognitive-cycle 2) (snapshot 1) (inject-observation 2)
    (get-status 1)))

;;; ============================================================
;;; Client API
;;; ============================================================

(defun start_link (agent-config)
  (gen_server:start_link 'agent-worker (list agent-config) '()))

(defun cognitive-cycle (pid environment)
  "Run one cognitive cycle on the agent."
  (gen_server:call pid `#(cognitive-cycle ,environment) 30000))

(defun snapshot (pid)
  "Create a snapshot of the agent's state."
  (gen_server:call pid 'snapshot 10000))

(defun inject-observation (pid observation)
  "Inject an observation into the agent."
  (gen_server:call pid `#(inject-observation ,observation) 5000))

(defun get-status (pid)
  "Get agent worker status."
  (gen_server:call pid 'status 5000))

;;; ============================================================
;;; gen_server callbacks
;;; ============================================================

(defun init
  (((list agent-config))
   (let* ((agent-id (maps:get 'agent-id agent-config))
          (command (build-cl-command agent-config))
          (port (open-cl-port command)))
     ;; Send init command to CL worker
     (port-send port `(:init :agent-id ,agent-id
                             :name ,(maps:get 'name agent-config agent-id)))
     (case (port-receive port 10000)
       (`#(ok ,response)
        (logger:info "Agent ~s initialized (restored: ~p)"
                     (list agent-id (proplists:get_value ':restored response)))
        `#(ok #M(port ,port
                 agent-id ,agent-id
                 config ,agent-config
                 started ,(erlang:system_time 'second))))
       (`#(error ,reason)
        (catch (erlang:port_close port))
        `#(stop #(init-failed ,reason)))
       ('timeout
        (catch (erlang:port_close port))
        `#(stop init-timeout))))))

(defun handle_call
  ;; Cognitive cycle
  ((`#(cognitive-cycle ,environment) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:cognitive-cycle :environment ,environment))
     (case (port-receive port 30000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Snapshot
  (('snapshot _from state)
   (let ((port (maps:get 'port state)))
     (port-send port '(:snapshot))
     (case (port-receive port 10000)
       (`#(ok ,response)
        `#(reply #(ok ,response) ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Inject observation
  ((`#(inject-observation ,obs) _from state)
   (let ((port (maps:get 'port state)))
     (port-send port `(:inject-observation :content ,obs))
     (case (port-receive port 5000)
       (`#(ok ,_response)
        `#(reply 'ok ,state))
       (`#(error ,reason)
        `#(reply #(error ,reason) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Status
  (('status _from state)
   (let ((uptime (- (erlang:system_time 'second)
                    (maps:get 'started state))))
     `#(reply #M(agent-id ,(maps:get 'agent-id state)
                 uptime ,uptime
                 port-alive ,(erlang:port_info (maps:get 'port state)))
              ,state)))

  ;; Unknown
  ((msg _from state)
   `#(reply #(error #(unknown-call ,msg)) ,state)))

(defun handle_cast
  (('stop state)
   `#(stop normal ,state))
  ((_msg state)
   `#(noreply ,state)))

(defun handle_info
  ;; Port closed — CL process died
  ((`#(,_port #(exit_status ,code)) state)
   (logger:warning "CL worker exited with code ~p, agent ~s"
                   (list code (maps:get 'agent-id state)))
   `#(stop #(port-died ,code) ,state))

  ;; Data from port (unsolicited message from CL)
  ((`#(,_port #(data ,data)) state)
   (handle-unsolicited-message data state)
   `#(noreply ,state))

  ((_msg state)
   `#(noreply ,state)))

(defun terminate (_reason state)
  (let ((port (maps:get 'port state 'undefined)))
    (when (is_port port)
      ;; Try graceful shutdown
      (catch (port-send port '(:shutdown)))
      (timer:sleep 1000)
      ;; Force close
      (catch (erlang:port_close port))))
  'ok)

(defun code_change (_old-vsn state _extra)
  `#(ok ,state))

;;; ============================================================
;;; Port communication
;;; ============================================================

(defun build-cl-command (config)
  "Build the sbcl command to invoke the CL worker."
  (let* ((sbcl (maps:get 'sbcl-path config
                  (application:get_env 'autopoiesis 'sbcl_path "sbcl")))
         (script (maps:get 'cl-worker-script config
                   (application:get_env 'autopoiesis 'cl_worker_script
                     "../scripts/agent-worker.lisp"))))
    (lists:flatten (io_lib:format "~s --script ~s" (list sbcl script)))))

(defun open-cl-port (command)
  "Open a port to a CL worker process."
  (erlang:open_port `#(spawn ,command)
                    '(#(line 65536) binary exit_status use_stdio)))

(defun port-send (port msg)
  "Send an S-expression message to the CL worker via port."
  (let ((data (list (lfe_io:print1 msg) "\n")))
    (erlang:port_command port (unicode:characters_to_binary data))))

(defun port-receive (port timeout)
  "Receive and parse an S-expression response from the CL worker.
   Returns #(ok parsed-term) | #(error reason) | timeout"
  (receive
    ;; Complete line received
    (`#(,p #(data #(eol ,line))) (when (=:= p port))
     (parse-cl-response line))
    ;; Line exceeded buffer — shouldn't happen with 64KB limit
    (`#(,p #(data #(noeol ,line))) (when (=:= p port))
     (logger:warning "Received partial line from CL worker: ~p" (list line))
     `#(error #(partial-line ,line)))
    (after timeout
      'timeout)))

(defun parse-cl-response (binary)
  "Parse an S-expression from binary port data."
  (let ((string (unicode:characters_to_list binary)))
    (case (lfe_io:read_string string)
      (`#(ok ,sexpr)
       (case sexpr
         (`(:ok . ,_rest) `#(ok ,sexpr))
         (`(:error . ,rest) `#(error ,rest))
         (`(:heartbeat . ,_rest) `#(ok ,sexpr))
         (`(:blocking-request . ,_rest) `#(ok ,sexpr))
         (other `#(ok ,other))))
      (`#(error ,err)
       (logger:error "Failed to parse CL response: ~s (error: ~p)"
                     (list string err))
       `#(error #(parse-failed ,string))))))

(defun handle-unsolicited-message (data state)
  "Handle messages initiated by CL worker (heartbeats, blocking requests)."
  (case (parse-cl-response data)
    (`#(ok (:heartbeat . ,_info))
     ;; Just log for now — conductor will use these in Phase 3
     'ok)
    (`#(ok (:blocking-request :id ,id :prompt ,prompt :options ,opts))
     ;; TODO: Route to human interface in Phase 4
     (logger:info "Blocking request from ~s: ~s"
                  (list (maps:get 'agent-id state) prompt))
     'ok)
    (`#(error ,reason)
     (logger:warning "Unparseable unsolicited message from ~s: ~p"
                     (list (maps:get 'agent-id state) reason))
     'ok)
    (_other
     'ok)))
```

**Key differences from master plan**:
1. `port-receive` correctly handles `#(eol ,line)` / `#(noeol ,line)` wrapper from `{line, N}` option
2. Uses `logger` instead of `lager`
3. Uses `maps:get/2` and `maps:get/3` instead of `mref`
4. `parse-cl-response` returns `#(ok ...)` / `#(error ...)` tuples for clean pattern matching
5. Guard on port identity: `(when (=:= p port))` to avoid matching messages from other ports
6. `build-cl-command` uses `application:get_env` for config with fallback defaults
7. `terminate` checks `is_port` before trying to close

**Depends on**: Tasks 4, 5

**Success**: Module compiles. Can be instantiated by agent-sup.

---

### Task 8: Integration test — compile and boot

Verify the whole thing works together.

**Steps**:
1. `cd lfe && rebar3 lfe compile` — all modules compile
2. `cd lfe && rebar3 lfe repl` — REPL starts
3. In REPL: `(application:ensure_all_started 'autopoiesis)` — returns `#(ok ...)` with app list
4. `(supervisor:which_children 'autopoiesis-sup)` — shows agent-sup and connector-sup
5. `(agent-sup:list-agents)` — returns empty list

**Depends on**: Tasks 1-7

**Success**: Application boots with supervision tree intact. No children spawned yet (agent spawning requires SBCL which is a separate test).

---

### Task 9: Agent spawn integration test (requires SBCL)

Test spawning an actual agent worker that talks to the CL cognitive engine.

**Steps**:
1. Ensure SBCL is available and `scripts/agent-worker.lisp` exists
2. In LFE REPL with application running:
   ```lfe
   (agent-sup:spawn-agent #M(agent-id "test-1" name "test-agent"))
   ```
3. Verify worker process exists: `(agent-sup:list-agents)`
4. Try status: `(agent-worker:get-status <pid>)`
5. Kill the SBCL process externally: `pkill -f agent-worker.lisp`
6. Observe supervisor restart behavior

**Depends on**: Task 8, Phase 1 complete

**Success**: Worker spawns, communicates with CL, supervisor restarts on crash.

---

### Task 10: Write LFE unit tests

**File**: `lfe/test/agent-worker-tests.lfe`

Test the port communication functions in isolation (mock port if needed) and verify the gen_server interface.

```lfe
(defmodule agent-worker-tests
  (behaviour ltest-unit)
  (export all))

(include-lib "ltest/include/ltest-macros.lfe")

(deftest build-cl-command-default
  (let ((cmd (agent-worker:build-cl-command #M(agent-id "test"))))
    (is (is_list cmd))
    (is (=/= (string:find cmd "sbcl") 'nomatch))
    (is (=/= (string:find cmd "agent-worker.lisp") 'nomatch))))

(deftest build-cl-command-custom
  (let ((cmd (agent-worker:build-cl-command
               #M(agent-id "test"
                  sbcl-path "/usr/local/bin/sbcl"
                  cl-worker-script "/custom/worker.lisp"))))
    (is (=/= (string:find cmd "/usr/local/bin/sbcl") 'nomatch))
    (is (=/= (string:find cmd "/custom/worker.lisp") 'nomatch))))
```

Run with: `cd lfe && rebar3 lfe test`

**Depends on**: Task 7

**Success**: Tests pass.

---

## Task Dependency Graph

```
Task 0: Install Erlang/rebar3
  └─► Task 1: rebar.config + directories
       └─► Task 2: .app.src
            └─► Task 3: autopoiesis-app.lfe
                 └─► Task 4: autopoiesis-sup.lfe
                      ├─► Task 5: agent-sup.lfe ──────────┐
                      └─► Task 6: connector-sup.lfe       │
                                                           ▼
                                                    Task 7: agent-worker.lfe
                                                           │
                                              ┌────────────┼────────────┐
                                              ▼            ▼            ▼
                                      Task 8: Boot    Task 10:     Task 9: Spawn
                                      test             Unit tests   integration test
```

## SCUD Waves

If using SCUD swarm for parallel execution:

- **Wave 1**: Task 0 (install tooling) — must be first, can't parallelize
- **Wave 2**: Tasks 1 + 2 (project structure) — sequential dependency but simple
- **Wave 3**: Tasks 3 + 4 (app + supervisor)
- **Wave 4**: Tasks 5 + 6 (agent-sup + connector-sup) — parallel, no dependency between them
- **Wave 5**: Task 7 (agent-worker) — depends on 5
- **Wave 6**: Tasks 8 + 9 + 10 (testing) — parallel

## What We're NOT Doing in Phase 2

- **Conductor**: No event loop yet — that's Phase 3
- **Connectors**: No HTTP/webhook — that's Phase 4
- **Project definition format**: No config files — that's Phase 5
- **Named agent registration**: Workers aren't registered by name yet; addressed by PID
- **Hot code reload**: `code_change` is a stub
- **Clustering**: Single-node only

## Verification Checklist

- [ ] `erl` and `rebar3` available on PATH
- [ ] `cd lfe && rebar3 lfe compile` succeeds with no errors
- [ ] `cd lfe && rebar3 lfe repl` starts REPL
- [ ] `(application:ensure_all_started 'autopoiesis)` returns `#(ok ...)`
- [ ] `(supervisor:which_children 'autopoiesis-sup)` shows agent-sup and connector-sup
- [ ] `(agent-sup:list-agents)` returns empty list `()`
- [ ] `(agent-sup:spawn-agent #M(agent-id "test-1" name "test"))` returns `#(ok <pid>)`
- [ ] Worker process communicates with CL via port (init handshake)
- [ ] Killing SBCL process triggers supervisor restart
- [ ] Supervisor gives up after 3 crashes in 60 seconds
- [ ] `rebar3 lfe test` passes unit tests
- [ ] All existing CL tests still pass: `./scripts/test.sh`
