# LFE-Supervised Agent Platform Implementation Plan

## Overview

Transform Autopoiesis from a Common Lisp framework into a hybrid **LFE/BEAM + Common Lisp** platform where:
- **LFE (Lisp Flavored Erlang)** provides OTP supervision, the conductor event loop, connectors, and agent lifecycle management
- **Common Lisp (SBCL)** provides the cognitive engine — cognitive loop, thought streams, snapshots, learning, extension compiler

Each **project** is an independent LFE/BEAM application that boots its own conductor and spawns CL cognitive workers via ports. Projects share no runtime state — an infrastructure healer and a crypto strategy bot are completely separate processes.

## Current State Analysis

### What Exists in Autopoiesis Today

The CL codebase has everything needed for the cognitive engine:
- **Cognitive loop** (`src/agent/cognitive-loop.lisp`) — Five-phase perceive→reason→decide→act→reflect cycle
- **Thought stream** (`src/core/thought-stream.lisp`) — Append-only vector with compaction and archiving
- **Snapshot DAG** (`src/snapshot/`) — Content-addressable storage with branching, diffing, time-travel
- **Extension compiler** (`src/core/extension-compiler.lisp`) — Sandboxed compilation of agent-written code
- **Learning system** (`src/agent/learning.lisp`) — Experience recording, pattern extraction, heuristics
- **Provider bridge** (`src/integration/provider*.lisp`) — Claude Code subprocess management
- **Capabilities** (`src/agent/capability.lisp`) — Registry, definitions, invocation
- **Human interface** (`src/interface/blocking.lisp`) — Blocking requests with condition variables

### What Doesn't Exist

- **Supervision trees** — No restart strategies, no crash recovery, no resource limits
- **Event loop** — No long-running conductor; `cognitive-cycle` runs once when called
- **Timer/scheduler** — No cron, no scheduled actions
- **Thread management** — No agent threads; agents are data structures
- **LFE integration** — None; pure CL codebase

### Key Discoveries

- Agent spawning (`src/agent/spawner.lisp:11-19`) creates a data structure only — no thread, no supervision
- Message passing (`src/agent/builtin-capabilities.lisp:53-83`) uses a global hash table with no thread safety
- Provider subprocess management (`src/integration/provider.lisp:237-317`) handles timeout/kill but no restart
- The existing S-expression serialization (`src/core/s-expr.lisp:119-150`) uses `prin1` — perfect for the port protocol

## Desired End State

```
┌────────────────────────────────────────────────────────────────────┐
│                         PROJECT (e.g., infra-healer)                │
│                         Standalone LFE/BEAM Application             │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │              Project Supervisor (top-level)                    │  │
│  │              Strategy: one_for_one                             │  │
│  └──────────┬──────────────────┬──────────────────┬──────────────┘  │
│             │                  │                  │                  │
│  ┌──────────▼────────┐ ┌──────▼────────┐ ┌──────▼────────────────┐  │
│  │   Conductor       │ │ Agent         │ │ Connector             │  │
│  │   (gen_server)    │ │ Supervisor    │ │ Supervisor            │  │
│  │                   │ │               │ │                       │  │
│  │  - Timer heap     │ │  ┌─────────┐  │ │  ┌─────────────────┐  │  │
│  │  - Event routing  │ │  │ Agent   │  │ │  │ Webhook Server  │  │  │
│  │  - Health checks  │ │  │ Worker  │◄─┼─│──│ (cowboy)        │  │  │
│  │  - Work dispatch  │ │  │ (port)  │  │ │  └─────────────────┘  │  │
│  │                   │ │  └────┬────┘  │ │  ┌─────────────────┐  │  │
│  └───────────────────┘ │       │       │ │  │ MCP Server      │  │  │
│                        │  ┌────▼────┐  │ │  │ (stdio)         │  │  │
│                        │  │  SBCL   │  │ │  └─────────────────┘  │  │
│                        │  │ Process │  │ │  ┌─────────────────┐  │  │
│                        │  │         │  │ │  │ External Feed   │  │  │
│                        │  │ Cogni-  │  │ │  │ (hackney)       │  │  │
│                        │  │ tive    │  │ │  └─────────────────┘  │  │
│                        │  │ Engine  │  │ │                       │  │
│                        │  └─────────┘  │ │                       │  │
│                        └───────────────┘ └───────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```

### Verification

To verify the end state is achieved:
1. `rebar3 lfe release` produces a runnable release
2. Starting the release boots the LFE application, spawns the conductor
3. Conductor spawns agent workers via ports to SBCL processes
4. Killing an SBCL process causes LFE supervisor to restart it automatically
5. Agent resumes from last snapshot after restart
6. Project config defines which agents, triggers, and connectors to run

## What We're NOT Doing

- **Not replacing CL cognitive engine** — All CLOS, learning, extension compiler stay in CL
- **Not porting snapshot DAG to LFE** — Snapshots stay on disk, CL reads/writes them
- **Not implementing CL threading** — All concurrency is BEAM processes; CL workers are single-threaded
- **Not building a CL actor library** — We use real OTP instead of reimplementing it
- **Not sharing state between projects** — Each project is fully isolated
- **Not changing the existing CL API** — We add a worker script that wraps it

## Implementation Approach

**Layer 0: CL Worker Script** — A thin CL script that loads Autopoiesis, creates an agent, and enters a read-eval-respond loop on stdin/stdout. This is what the LFE port talks to.

**Layer 1: LFE Core** — The rebar3 project structure with OTP application skeleton, supervisor trees, and the agent-worker gen_server that manages ports.

**Layer 2: Conductor** — The event loop gen_server with timer heap, event routing, and work dispatch.

**Layer 3: Connectors** — HTTP webhook server, MCP server, external feed clients.

**Layer 4: Project Definition** — How projects declare their agents, triggers, and connectors.

---

## Phase 1: CL Worker Script

### Overview

Create a standalone CL script that can be invoked via `sbcl --script` and communicates over stdin/stdout with S-expression messages.

### Changes Required

#### 1. Worker Entry Point
**File**: `scripts/agent-worker.lisp` (new)
**Purpose**: Main entry point for port-spawned CL processes

```lisp
#!/usr/bin/env sbcl --script
;;; agent-worker.lisp — CL cognitive engine worker for LFE supervision
;;;
;;; Invoked via port from LFE. Communicates via stdin/stdout S-expressions.
;;; One instance per agent. Owns all agent state (thought stream, snapshots).

(require :asdf)
(asdf:load-system :autopoiesis)

(defpackage :autopoiesis.worker
  (:use :cl :autopoiesis)
  (:export :main))

(in-package :autopoiesis.worker)

;;; Protocol messages (LFE → CL)
;;; (:init :agent-id "uuid" :profile :infrastructure-watcher :config (...))
;;; (:cognitive-cycle :environment (:prompt "..."))
;;; (:snapshot)
;;; (:inject-observation :content (...))
;;; (:shutdown)

;;; Protocol messages (CL → LFE)
;;; (:ok :type :init :agent-id "uuid")
;;; (:ok :type :cycle-complete :result (...) :thoughts-added 3)
;;; (:ok :type :snapshot-complete :snapshot-id "uuid" :hash "sha256...")
;;; (:error :type :cycle-failed :message "...")
;;; (:blocking-request :id "uuid" :prompt "..." :options (...))
;;; (:heartbeat :thoughts 47 :uptime-seconds 3600)

(defvar *agent* nil "The agent instance for this worker")
(defvar *start-time* nil "When this worker started")

(defun send-response (response)
  "Write response S-expression to stdout, flush."
  (prin1 response *standard-output*)
  (terpri *standard-output*)
  (force-output *standard-output*))

(defun handle-init (msg)
  "Initialize agent from config."
  (let ((agent-id (getf msg :agent-id))
        (profile (getf msg :profile))
        (config (getf msg :config)))
    (declare (ignore profile config))
    ;; Try to restore from snapshot, or create fresh
    (setf *agent* (or (restore-agent-from-snapshot agent-id)
                      (make-agent :name agent-id)))
    (setf *start-time* (get-universal-time))
    (start-agent *agent*)
    (send-response `(:ok :type :init :agent-id ,(agent-id *agent*)))))

(defun handle-cognitive-cycle (msg)
  "Run one cognitive cycle."
  (let ((environment (getf msg :environment)))
    (handler-case
        (let ((thoughts-before (stream-length (agent-thought-stream *agent*)))
              (result (cognitive-cycle *agent* environment))
              (thoughts-after (stream-length (agent-thought-stream *agent*))))
          (send-response `(:ok :type :cycle-complete
                              :result ,result
                              :thoughts-added ,(- thoughts-after thoughts-before))))
      (error (e)
        (send-response `(:error :type :cycle-failed
                                :message ,(princ-to-string e)))))))

(defun handle-snapshot (msg)
  "Create snapshot of current agent state."
  (declare (ignore msg))
  (let ((snapshot (create-snapshot *agent*)))
    (save-snapshot snapshot)
    (send-response `(:ok :type :snapshot-complete
                        :snapshot-id ,(snapshot-id snapshot)
                        :hash ,(snapshot-hash snapshot)))))

(defun handle-inject-observation (msg)
  "Inject an observation into the agent's thought stream."
  (let ((content (getf msg :content)))
    (let ((obs (make-observation content :source :external)))
      (stream-append (agent-thought-stream *agent*) obs)
      (send-response `(:ok :type :observation-injected)))))

(defun handle-shutdown (msg)
  "Clean shutdown."
  (declare (ignore msg))
  (when *agent*
    (stop-agent *agent*)
    (create-snapshot *agent*))  ; Final snapshot before exit
  (send-response `(:ok :type :shutdown))
  (sb-ext:exit :code 0))

(defun handle-command (command)
  "Dispatch command to handler."
  (case (car command)
    (:init (handle-init command))
    (:cognitive-cycle (handle-cognitive-cycle command))
    (:snapshot (handle-snapshot command))
    (:inject-observation (handle-inject-observation command))
    (:shutdown (handle-shutdown command))
    (otherwise (send-response `(:error :type :unknown-command
                                       :command ,(car command))))))

(defun main ()
  "Main worker loop."
  (loop
    (let ((command (read *standard-input* nil :eof)))
      (cond
        ((eq command :eof)
         (when *agent*
           (stop-agent *agent*)
           (create-snapshot *agent*))
         (return))
        (t (handle-command command))))))

;; Run if invoked as script
(main)
```

#### 2. Snapshot Restoration
**File**: `src/snapshot/persistence.lisp`
**Changes**: Add function to restore agent from most recent snapshot

```lisp
(defun restore-agent-from-snapshot (agent-id &key (store *default-store*))
  "Restore agent from most recent snapshot, or return NIL if none exists."
  (let ((latest (find-latest-snapshot-for-agent agent-id :store store)))
    (when latest
      (let ((snapshot (load-snapshot latest :store store)))
        (sexpr-to-agent (snapshot-agent-state snapshot))))))
```

#### 3. Agent Serialization
**File**: `src/agent/agent.lisp`
**Changes**: Add agent-to-sexpr and sexpr-to-agent

```lisp
(defun agent-to-sexpr (agent)
  "Serialize agent to S-expression for snapshot."
  `(:agent
    :id ,(agent-id agent)
    :name ,(agent-name agent)
    :state ,(agent-state agent)
    :capabilities ,(agent-capabilities agent)
    :thought-stream ,(stream-to-sexpr (agent-thought-stream agent))
    :parent ,(agent-parent agent)
    :children ,(agent-children agent)))

(defun sexpr-to-agent (sexpr)
  "Restore agent from S-expression."
  (let ((agent (make-instance 'agent)))
    (setf (agent-id agent) (getf sexpr :id)
          (agent-name agent) (getf sexpr :name)
          (agent-state agent) (getf sexpr :state)
          (agent-capabilities agent) (getf sexpr :capabilities)
          (agent-thought-stream agent) (sexpr-to-stream (getf sexpr :thought-stream))
          (agent-parent agent) (getf sexpr :parent)
          (agent-children agent) (getf sexpr :children))
    agent))
```

### Success Criteria

#### Automated Verification
- [ ] `sbcl --load scripts/agent-worker.lisp` starts without errors
- [ ] Echo test: pipe `(:init :agent-id "test")` and get `(:ok :type :init ...)` back
- [ ] Cognitive cycle: send `(:cognitive-cycle :environment (:prompt "hello"))` and get response
- [ ] Snapshot: send `(:snapshot)` and verify snapshot file created
- [ ] All existing tests still pass: `./scripts/test.sh`

#### Manual Verification
- [ ] Worker survives malformed input (doesn't crash, returns error)
- [ ] Worker creates snapshot on clean shutdown
- [ ] Worker creates snapshot on EOF (pipe closed)

---

## Phase 2: LFE Project Skeleton

### Overview

Create the rebar3/LFE project structure with OTP application, supervision tree, and basic gen_servers.

### Changes Required

#### 1. Top-Level Project Structure
**Files**: New `lfe/` directory at repo root

```
lfe/
├── rebar.config
├── rebar.lock
├── apps/
│   └── autopoiesis/
│       ├── src/
│       │   ├── autopoiesis.app.src
│       │   ├── autopoiesis-app.lfe
│       │   ├── autopoiesis-sup.lfe
│       │   └── agent-worker.lfe
│       └── include/
├── config/
│   └── sys.config
└── rel/
    └── reltool.config
```

#### 2. Application Module
**File**: `lfe/apps/autopoiesis/src/autopoiesis-app.lfe`

```lfe
(defmodule autopoiesis-app
  (behaviour application)
  (export (start 2) (stop 1)))

(defun start (_type _args)
  (autopoiesis-sup:start_link))

(defun stop (_state)
  'ok)
```

#### 3. Top-Level Supervisor
**File**: `lfe/apps/autopoiesis/src/autopoiesis-sup.lfe`

```lfe
(defmodule autopoiesis-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)))

(defun start_link ()
  (supervisor:start_link #(local autopoiesis-sup) 'autopoiesis-sup '()))

(defun init (_args)
  (let ((children
          (list
            ;; Conductor - the event loop
            (child-spec 'conductor
                        'conductor 'start_link '()
                        'permanent 5000 'worker '(conductor))
            ;; Agent supervisor - manages agent workers
            (child-spec 'agent-sup
                        'agent-sup 'start_link '()
                        'permanent 'infinity 'supervisor '(agent-sup))
            ;; Connector supervisor - manages external connections
            (child-spec 'connector-sup
                        'connector-sup 'start_link '()
                        'permanent 'infinity 'supervisor '(connector-sup)))))
    `#(ok #(#(one_for_one 5 10) ,children))))

(defun child-spec (id module func args restart shutdown type modules)
  `#(,id #(,module ,func ,args) ,restart ,shutdown ,type ,modules))
```

#### 4. Agent Supervisor
**File**: `lfe/apps/autopoiesis/src/agent-sup.lfe`

```lfe
(defmodule agent-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1) (spawn-agent 1)))

(defun start_link ()
  (supervisor:start_link #(local agent-sup) 'agent-sup '()))

(defun init (_args)
  ;; simple_one_for_one: dynamic children, all same type
  `#(ok #(#(simple_one_for_one 3 60)
          (#(agent-worker
             #(agent-worker start_link ())
             transient     ;; Only restart on abnormal exit
             5000          ;; 5 second shutdown timeout
             worker
             (agent-worker))))))

(defun spawn-agent (agent-config)
  "Spawn a new agent worker with the given config."
  (supervisor:start_child 'agent-sup (list agent-config)))
```

#### 5. Agent Worker (Port Wrapper)
**File**: `lfe/apps/autopoiesis/src/agent-worker.lfe`

```lfe
(defmodule agent-worker
  (behaviour gen_server)
  (export (start_link 1) (init 1)
          (handle_call 3) (handle_cast 2) (handle_info 2)
          (terminate 2) (code_change 3))
  ;; Client API
  (export (cognitive-cycle 2) (snapshot 1) (inject-observation 2)))

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

;;; ============================================================
;;; gen_server callbacks
;;; ============================================================

(defun init ((list agent-config))
  (let* ((agent-id (mref agent-config 'agent-id))
         (cl-command (build-cl-command agent-config))
         (port (open-cl-port cl-command)))
    ;; Send init command to CL worker
    (port-send port `(:init :agent-id ,agent-id
                           :profile ,(mref agent-config 'profile)
                           :config ,agent-config))
    (case (port-receive port 10000)
      (`(:ok :type init :agent-id ,_)
       `#(ok #m(port ,port
                agent-id ,agent-id
                config ,agent-config
                started ,(erlang:system_time 'second))))
      (`(:error . ,rest)
       `#(stop #(init-failed ,rest)))
      ('timeout
       `#(stop init-timeout)))))

(defun handle_call
  ;; Cognitive cycle
  ((`#(cognitive-cycle ,environment) _from state)
   (let ((port (mref state 'port)))
     (port-send port `(:cognitive-cycle :environment ,environment))
     (case (port-receive port 30000)
       (`(:ok :type cycle-complete :result ,result :thoughts-added ,n)
        `#(reply #(ok ,result ,n) ,state))
       (`(:error :type cycle-failed :message ,msg)
        `#(reply #(error ,msg) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Snapshot
  (('snapshot _from state)
   (let ((port (mref state 'port)))
     (port-send port '(:snapshot))
     (case (port-receive port 10000)
       (`(:ok :type snapshot-complete :snapshot-id ,id :hash ,hash)
        `#(reply #(ok ,id ,hash) ,state))
       (`(:error . ,rest)
        `#(reply #(error ,rest) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Inject observation
  ((`#(inject-observation ,obs) _from state)
   (let ((port (mref state 'port)))
     (port-send port `(:inject-observation :content ,obs))
     (case (port-receive port 5000)
       ('(:ok :type observation-injected)
        `#(reply 'ok ,state))
       (`(:error . ,rest)
        `#(reply #(error ,rest) ,state))
       ('timeout
        `#(reply #(error timeout) ,state)))))

  ;; Unknown
  ((msg _from state)
   `#(reply #(error #(unknown-call ,msg)) ,state)))

(defun handle_cast
  (('stop state)
   `#(stop normal ,state))
  ((_msg state)
   `#(noreply ,state)))

(defun handle_info
  ;; Port closed - CL process died
  ((`#(,port #(exit_status ,code)) state) (when (=:= port (mref state 'port)))
   (lager:warning "CL worker exited with code ~p, agent ~s"
                  (list code (mref state 'agent-id)))
   `#(stop #(port-died ,code) ,state))

  ;; Unexpected message from port (unsolicited)
  ((`#(,port #(data ,data)) state) (when (=:= port (mref state 'port)))
   (handle-unsolicited-message data state)
   `#(noreply ,state))

  ((_msg state)
   `#(noreply ,state)))

(defun terminate (reason state)
  (let ((port (mref state 'port)))
    (when port
      ;; Try graceful shutdown
      (catch (port-send port '(:shutdown)))
      (timer:sleep 1000)
      ;; Force close port
      (catch (erlang:port_close port))))
  'ok)

(defun code_change (_old-vsn state _extra)
  `#(ok ,state))

;;; ============================================================
;;; Internal functions
;;; ============================================================

(defun build-cl-command (config)
  "Build the sbcl command to invoke."
  (let ((script-path (mref config 'cl-worker-script
                           "../scripts/agent-worker.lisp")))
    (++ "sbcl --script " script-path)))

(defun open-cl-port (command)
  "Open a port to the CL worker."
  (erlang:open_port `#(spawn ,command)
                    '(binary #(line 65536) exit_status use_stdio)))

(defun port-send (port msg)
  "Send S-expression message to CL worker."
  (let ((data (++ (lfe_io:print1 msg) "\n")))
    (erlang:port_command port (unicode:characters_to_binary data))))

(defun port-receive (port timeout)
  "Receive S-expression response from CL worker."
  (receive
    (`#(,port #(data ,line))
     (parse-cl-response line))
    (after timeout
      'timeout)))

(defun parse-cl-response (binary)
  "Parse S-expression from binary response."
  (let ((string (unicode:characters_to_list binary)))
    (case (lfe_io:read_string string)
      (`#(ok ,sexpr) sexpr)
      (`#(error ,_) `(:error :parse-failed ,string)))))

(defun handle-unsolicited-message (data state)
  "Handle messages initiated by CL worker (e.g., blocking requests)."
  (case (parse-cl-response data)
    (`(:blocking-request :id ,id :prompt ,prompt :options ,options)
     ;; Route to human interface
     (human-interface:blocking-request id prompt options))
    (`(:log :level ,level :message ,msg)
     (case level
       ('info (lager:info "~s: ~s" (list (mref state 'agent-id) msg)))
       ('warn (lager:warning "~s: ~s" (list (mref state 'agent-id) msg)))
       ('error (lager:error "~s: ~s" (list (mref state 'agent-id) msg)))))
    (_other
     (lager:warning "Unknown unsolicited message: ~p" (list data)))))
```

#### 6. Rebar Config
**File**: `lfe/rebar.config`

```erlang
{erl_opts, [debug_info]}.

{plugins, [
    {rebar3_lfe, "0.5.0"}
]}.

{deps, [
    {lfe, "2.2.0"},
    {lager, "3.9.2"},
    {cowboy, "2.10.0"},
    {jsx, "3.1.0"}
]}.

{relx, [
    {release, {autopoiesis, "0.1.0"}, [
        autopoiesis,
        sasl
    ]},
    {dev_mode, true},
    {include_erts, false}
]}.

{profiles, [
    {prod, [
        {relx, [
            {dev_mode, false},
            {include_erts, true}
        ]}
    ]}
]}.
```

### Success Criteria

#### Automated Verification
- [ ] `cd lfe && rebar3 lfe compile` succeeds
- [ ] `cd lfe && rebar3 lfe repl` starts without errors
- [ ] In REPL: `(application:start 'autopoiesis)` returns `ok`
- [ ] In REPL: `(agent-sup:spawn-agent #m(agent-id "test-1" profile infrastructure-watcher))` spawns worker
- [ ] Worker process appears in `observer:start()`
- [ ] Killing worker causes supervisor to restart it

#### Manual Verification
- [ ] Supervisor restarts worker up to 3 times within 60 seconds before giving up
- [ ] Port closes cleanly when worker terminates
- [ ] CL worker receives init message and responds

---

## Phase 3: Conductor Gen_Server

### Overview

Implement the conductor — the event loop that drives the whole system. It maintains a timer heap, routes events, and dispatches work to agents.

### Changes Required

#### 1. Conductor Module
**File**: `lfe/apps/autopoiesis/src/conductor.lfe`

```lfe
(defmodule conductor
  (behaviour gen_server)
  (export (start_link 0) (init 1)
          (handle_call 3) (handle_cast 2) (handle_info 2)
          (terminate 2))
  ;; Client API
  (export (schedule 1) (queue-event 1) (status 0)))

;;; ============================================================
;;; Client API
;;; ============================================================

(defun start_link ()
  (gen_server:start_link #(local conductor) 'conductor '() '()))

(defun schedule (scheduled-action)
  "Schedule a timer-based action."
  (gen_server:cast 'conductor `#(schedule ,scheduled-action)))

(defun queue-event (event)
  "Queue an external event for processing."
  (gen_server:cast 'conductor `#(event ,event)))

(defun status ()
  "Get conductor status."
  (gen_server:call 'conductor 'status))

;;; ============================================================
;;; gen_server callbacks
;;; ============================================================

(defun init (_args)
  ;; Start the tick timer
  (erlang:send_after 100 (self) 'tick)
  `#(ok #m(timer-heap ,(gb_trees:empty)
           event-queue ()
           agents #m()
           metrics #m(ticks 0 events-processed 0 cycles-run 0))))

(defun handle_call
  (('status _from state)
   `#(reply ,(conductor-status state) ,state))
  ((msg _from state)
   `#(reply #(error #(unknown ,msg)) ,state)))

(defun handle_cast
  ;; Schedule a timer-based action
  ((`#(schedule ,action) state)
   (let* ((next-time (compute-next-run action))
          (timer-heap (mref state 'timer-heap))
          (new-heap (gb_trees:insert next-time action timer-heap)))
     `#(noreply ,(mset state 'timer-heap new-heap))))

  ;; Queue an external event
  ((`#(event ,event) state)
   (let ((queue (mref state 'event-queue)))
     `#(noreply ,(mset state 'event-queue (++ queue (list event))))))

  ((_msg state)
   `#(noreply ,state)))

(defun handle_info
  ;; Main tick - the heartbeat
  (('tick state)
   (let* ((state2 (process-due-timers state))
          (state3 (process-events state2))
          (state4 (update-metrics state3)))
     ;; Schedule next tick
     (erlang:send_after 100 (self) 'tick)
     `#(noreply ,state4)))

  ;; Agent completed work
  ((`#(agent-result ,agent-id ,result) state)
   (let ((state2 (handle-agent-result agent-id result state)))
     `#(noreply ,state2)))

  ;; Agent crashed (via monitor)
  ((`#(DOWN ,_ref process ,pid ,reason) state)
   (let ((state2 (handle-agent-crash pid reason state)))
     `#(noreply ,state2)))

  ((_msg state)
   `#(noreply ,state)))

(defun terminate (_reason _state)
  'ok)

;;; ============================================================
;;; Internal functions
;;; ============================================================

(defun process-due-timers (state)
  "Pop and execute all due timers."
  (let ((now (erlang:system_time 'second))
        (heap (mref state 'timer-heap)))
    (process-due-timers-loop now heap state)))

(defun process-due-timers-loop (now heap state)
  (case (gb_trees:is_empty heap)
    ('true state)
    ('false
     (let ((`#(,time ,action) (gb_trees:smallest heap)))
       (if (=< time now)
           (let* ((heap2 (gb_trees:delete time heap))
                  (state2 (execute-timer-action action state)))
             ;; Reschedule if recurring
             (let ((heap3 (maybe-reschedule action heap2)))
               (process-due-timers-loop now heap3 (mset state2 'timer-heap heap3))))
           state)))))

(defun execute-timer-action (action state)
  "Execute a scheduled action."
  (case (mref action 'requires-llm)
    ('true
     ;; Slow path: spawn an agent
     (spawn-agent-for-action action)
     state)
    ('false
     ;; Fast path: execute directly
     (let ((func (mref action 'action)))
       (catch (funcall func))
       state))))

(defun process-events (state)
  "Process all queued events."
  (let loop ((events (mref state 'event-queue))
             (state state))
    (case events
      ('() (mset state 'event-queue '()))
      ((cons event rest)
       (let ((state2 (process-event event state)))
         (loop rest state2))))))

(defun process-event (event state)
  "Process a single event."
  (let ((work-item (classify-event event)))
    (case (mref work-item 'requires-llm)
      ('true
       ;; Spawn agent for complex work
       (spawn-agent-for-work work-item)
       state)
      ('false
       ;; Handle directly
       (execute-fast-path work-item)
       state))))

(defun classify-event (event)
  "Classify an event as fast-path or slow-path."
  (let ((event-type (mref event 'type)))
    (case event-type
      ;; Known simple events -> fast path
      ('health-check #m(type health-check requires-llm false payload event))
      ('metric-update #m(type metric-update requires-llm false payload event))
      ;; Unknown or complex -> slow path
      (_ #m(type unknown requires-llm true payload event)))))

(defun spawn-agent-for-work (work-item)
  "Spawn an agent to handle complex work."
  (let ((agent-config #m(agent-id (make-agent-id)
                         profile default
                         task work-item)))
    (agent-sup:spawn-agent agent-config)))

(defun spawn-agent-for-action (action)
  "Spawn an agent to execute a scheduled action that needs LLM."
  (spawn-agent-for-work #m(type scheduled-action payload action)))

(defun make-agent-id ()
  "Generate a unique agent ID."
  (binary_to_list (uuid:get_v4)))

(defun compute-next-run (action)
  "Compute the next run time for an action."
  (let ((now (erlang:system_time 'second)))
    (case (mref action 'interval)
      ('undefined
       ;; Cron-based - TODO: implement cron parsing
       (+ now 3600))
      (interval
       (+ now interval)))))

(defun maybe-reschedule (action heap)
  "Reschedule a recurring action."
  (case (mref action 'recurring)
    ('true
     (let ((next-time (compute-next-run action)))
       (gb_trees:insert next-time action heap)))
    ('false heap)))

(defun handle-agent-result (agent-id result state)
  "Handle completion of agent work."
  (lager:info "Agent ~s completed with result: ~p" (list agent-id result))
  state)

(defun handle-agent-crash (pid reason state)
  "Handle agent crash."
  (lager:warning "Agent process ~p crashed: ~p" (list pid reason))
  state)

(defun update-metrics (state)
  "Update conductor metrics."
  (let ((metrics (mref state 'metrics)))
    (mset state 'metrics
          (mset metrics 'ticks (+ 1 (mref metrics 'ticks))))))

(defun conductor-status (state)
  "Return conductor status for monitoring."
  #m(timer-count (gb_trees:size (mref state 'timer-heap))
     event-queue-length (length (mref state 'event-queue))
     metrics (mref state 'metrics)))

(defun execute-fast-path (work-item)
  "Execute a fast-path work item."
  (case (mref work-item 'type)
    ('health-check
     (lager:debug "Health check OK"))
    ('metric-update
     (lager:debug "Metric updated"))
    (_
     (lager:warning "Unknown fast-path item: ~p" (list work-item)))))
```

### Success Criteria

#### Automated Verification
- [ ] Conductor starts with application
- [ ] `(conductor:status)` returns valid status map
- [ ] `(conductor:schedule ...)` adds action to timer heap
- [ ] `(conductor:queue-event ...)` adds event to queue
- [ ] Tick processing runs every 100ms (observable via metrics)
- [ ] Scheduled actions fire at correct times

#### Manual Verification
- [ ] Fast-path events process without spawning agents
- [ ] Slow-path events spawn agent workers
- [ ] Conductor continues running after agent crashes

---

## Phase 4: Connectors (HTTP Webhook, MCP Server)

### Overview

Add connectors for external input: HTTP webhook server and MCP server.

### Changes Required

#### 1. Connector Supervisor
**File**: `lfe/apps/autopoiesis/src/connector-sup.lfe`

```lfe
(defmodule connector-sup
  (behaviour supervisor)
  (export (start_link 0) (init 1)))

(defun start_link ()
  (supervisor:start_link #(local connector-sup) 'connector-sup '()))

(defun init (_args)
  (let ((children
          (list
            ;; HTTP webhook server
            (child-spec 'webhook-server
                        'webhook-server 'start_link '()
                        'permanent 5000 'worker '(webhook-server))
            ;; MCP stdio server
            (child-spec 'mcp-server
                        'mcp-server 'start_link '()
                        'permanent 5000 'worker '(mcp-server)))))
    `#(ok #(#(one_for_one 5 10) ,children))))

(defun child-spec (id module func args restart shutdown type modules)
  `#(,id #(,module ,func ,args) ,restart ,shutdown ,type ,modules))
```

#### 2. Webhook Server
**File**: `lfe/apps/autopoiesis/src/webhook-server.lfe`

```lfe
(defmodule webhook-server
  (behaviour gen_server)
  (export (start_link 0) (init 1)
          (handle_call 3) (handle_cast 2) (handle_info 2)
          (terminate 2)))

(defun start_link ()
  (gen_server:start_link #(local webhook-server) 'webhook-server '() '()))

(defun init (_args)
  ;; Start cowboy HTTP server
  (let* ((dispatch (cowboy_router:compile
                     '(#(_ ((#"/webhook" webhook-handler ()))
                           (#"/health" health-handler ()))))))
         ((port (application:get_env 'autopoiesis 'webhook_port 4007)))
    (cowboy:start_clear 'webhook-listener
                        '#(#(port ,port))
                        #m(env #m(dispatch ,dispatch))))
  `#(ok #m()))

(defun handle_call (msg _from state)
  `#(reply #(error #(unknown ,msg)) ,state))

(defun handle_cast (_msg state)
  `#(noreply ,state))

(defun handle_info (_msg state)
  `#(noreply ,state))

(defun terminate (_reason _state)
  (cowboy:stop_listener 'webhook-listener)
  'ok)
```

#### 3. Webhook Handler
**File**: `lfe/apps/autopoiesis/src/webhook-handler.lfe`

```lfe
(defmodule webhook-handler
  (export (init 2) (handle 2)))

(defun init (req state)
  `#(cowboy_rest ,req ,state))

(defun handle (req state)
  (let* ((method (cowboy_req:method req))
         (body (cowboy_req:read_body req)))
    (case method
      (#"POST"
       (let ((event (jsx:decode body #(return_maps true))))
         ;; Queue event to conductor
         (conductor:queue-event #m(type webhook source external payload event))
         (let ((reply (jsx:encode #m(status "accepted"))))
           `#(#"200 OK" #m(#"content-type" #"application/json") ,reply ,req ,state))))
      (_
       `#(#"405 Method Not Allowed" #m() #"" ,req ,state)))))
```

### Success Criteria

#### Automated Verification
- [ ] HTTP server starts on configured port
- [ ] `curl -X POST localhost:4007/webhook -d '{"test": true}'` returns 200
- [ ] Posted webhook appears in conductor event queue
- [ ] `/health` endpoint returns 200 OK

#### Manual Verification
- [ ] Webhook server survives malformed JSON (returns 400, doesn't crash)
- [ ] Server continues running after cowboy handler errors

---

## Phase 5: Project Definition Format

### Overview

Define how projects configure their agents, triggers, and connectors.

### Changes Required

#### 1. Project Config Schema
**File**: `lfe/config/project.schema.lfe`

```lfe
;;; Project configuration schema
;;;
;;; Projects are defined as S-expression config files that declare:
;;; - agents: which agents to spawn on startup
;;; - triggers: scheduled and event-based triggers
;;; - connectors: external connections (webhooks, feeds)
;;; - profiles: agent profile definitions

(:project
  :name "infrastructure-healer"
  :version "0.1.0"

  :agents
  ((:agent
    :id "watcher-1"
    :profile :infrastructure-watcher
    :autostart true)
   (:agent
    :id "responder-1"
    :profile :incident-responder
    :autostart false))  ; Spawned on demand

  :triggers
  ((:trigger
    :name "health-check"
    :type :scheduled
    :interval 30
    :action :run-health-check
    :requires-llm false)
   (:trigger
    :name "alert-handler"
    :type :event
    :event-type :cortex-alert
    :condition (lambda (e) (>= (mref e 'severity) 'warning))
    :action :spawn-incident-agent
    :requires-llm true))

  :connectors
  ((:connector
    :type :webhook
    :port 4007
    :path "/events")
   (:connector
    :type :cortex
    :subscribe '(alerts metrics)))

  :profiles
  ((:profile
    :name :infrastructure-watcher
    :core-prompt "profiles/infrastructure-watcher/CORE.md"
    :capabilities '(cortex-query shell-readonly notification)
    :human-approval '(restart-pod scale-service))))
```

#### 2. Project Loader
**File**: `lfe/apps/autopoiesis/src/project-loader.lfe`

```lfe
(defmodule project-loader
  (export (load-project 1) (load-project-file 1)))

(defun load-project (project-config)
  "Load and start a project from config."
  ;; Register triggers with conductor
  (lists:foreach
    (lambda (trigger) (conductor:register-trigger trigger))
    (mref project-config 'triggers))
  ;; Start autostart agents
  (lists:foreach
    (lambda (agent-config)
      (when (mref agent-config 'autostart)
        (agent-sup:spawn-agent agent-config)))
    (mref project-config 'agents))
  ;; Start connectors
  (lists:foreach
    (lambda (connector) (start-connector connector))
    (mref project-config 'connectors))
  'ok)

(defun load-project-file (path)
  "Load project from file."
  (case (file:read_file path)
    (`#(ok ,binary)
     (let ((string (binary_to_list binary)))
       (case (lfe_io:read_string string)
         (`#(ok ,config) (load-project config))
         (`#(error ,err) `#(error #(parse-failed ,err))))))
    (`#(error ,err)
     `#(error #(file-read-failed ,err)))))

(defun start-connector (connector)
  "Start a connector based on its type."
  (case (mref connector 'type)
    ('webhook
     ;; Webhook server is already started by connector-sup
     'ok)
    ('cortex
     ;; TODO: Connect to Cortex
     'ok)
    (type
     (lager:warning "Unknown connector type: ~p" (list type)))))
```

### Success Criteria

#### Automated Verification
- [ ] `(project-loader:load-project-file "config/project.lfe")` succeeds
- [ ] Triggers from config appear in conductor
- [ ] Autostart agents spawn on project load
- [ ] Connectors start based on config

#### Manual Verification
- [ ] Invalid config file returns clear error
- [ ] Missing profile gracefully fails agent spawn

---

## Testing Strategy

### Unit Tests (LFE)

Test each gen_server in isolation:
- `agent-worker`: Port open/close, message send/receive, timeout handling
- `conductor`: Timer scheduling, event routing, metrics
- `project-loader`: Config parsing, validation

### Integration Tests

- Full project load → agent spawn → cognitive cycle → result
- Agent crash → supervisor restart → state restoration from snapshot
- Webhook receive → conductor queue → agent spawn → response

### Manual Testing Steps

1. Start the release: `cd lfe && rebar3 lfe release && _build/default/rel/autopoiesis/bin/autopoiesis console`
2. Observe supervisor tree in observer
3. Spawn an agent manually: `(agent-sup:spawn-agent #m(agent-id "test-1" profile default))`
4. Run a cognitive cycle: `(agent-worker:cognitive-cycle pid #m(prompt "hello"))`
5. Kill the SBCL process: `pkill -f agent-worker.lisp`
6. Verify supervisor restarts it within 60 seconds
7. Run another cycle and verify agent resumes from snapshot

## Performance Considerations

- **Port buffer size**: Set to 65536 bytes per line to handle large S-expressions
- **Tick interval**: 100ms balances responsiveness with CPU usage
- **Supervisor restart limits**: 3 restarts per 60 seconds prevents crash loops
- **SBCL startup time**: ~2-3 seconds cold start; keep workers alive when possible

## Migration Notes

This plan adds new code without removing existing CL functionality. The CL codebase remains the cognitive engine. The LFE layer is additive — you can still use Autopoiesis as a pure CL library by loading it directly.

## References

- Research: `thoughts/shared/research/2026-02-04-lfe-beam-agent-supervision.md`
- Synthesis: `thoughts/shared/research/2026-02-04-agent-system-ideas-synthesis.md`
- Original conductor vision: `thoughts/shared/plans/Autopoiesis + Cortex Synthesis Plan.md`
- Workspace architecture: `thoughts/shared/plans/2026-02-04-workspace-architecture-plan.md`
- LFE port examples: https://github.com/lfeutre/port-examples
- LFE OTP tutorials: https://github.com/oubiwann/lfe-otp-tutorials
