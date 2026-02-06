---
date: 2026-02-04T21:00:00Z
researcher: Claude
git_commit: ce02d6e563435d408a5eef84ebe465937f443d97
branch: main
repository: ap
topic: "LFE/BEAM for Agent Supervision: S-Expression Compatibility and OTP Integration"
tags: [research, lfe, erlang, beam, otp, supervision, agent-systems, s-expressions, architecture]
status: complete
last_updated: 2026-02-04
last_updated_by: Claude
---

# Research: LFE/BEAM for Agent Supervision

**Date**: 2026-02-04T21:00:00Z
**Researcher**: Claude
**Git Commit**: ce02d6e563435d408a5eef84ebe465937f443d97
**Branch**: main
**Repository**: ap

## Research Question

Can LFE (Lisp Flavored Erlang) be used for OTP-style agent supervision in Autopoiesis? How compatible are the S-expression formats? What does the architecture look like when each project is an independent process with its own conductor, and agents are supervised BEAM processes?

## Context

The architectural vision clarified by the user:
- **Projects are standalone applications** — each loads Autopoiesis as a framework, boots its own conductor, manages its own agents. An infrastructure healer and a crypto strategy bot are completely separate processes.
- **Each project has its own conductor** — the conductor is a per-project event loop/heartbeat, not a global orchestrator.
- **OTP for agent supervision** — Erlang/BEAM-style supervision trees for spawned agents, possibly via LFE.

---

## What is LFE

LFE (Lisp Flavored Erlang) is a Lisp dialect that compiles to BEAM bytecode and runs on the Erlang VM. Created by Robert Virding (co-creator of Erlang itself), it's described as "a proper lisp based on the features and limitations of the Erlang VM."

**Current version**: 2.2.0
**Requirements**: Erlang 21+, rebar3
**Build tool**: rebar3 with `rebar3_lfe` plugin
**Docker**: `docker run -it lfex/lfe` for quick experimentation

LFE is a **Lisp-2** (like Common Lisp — separate namespaces for functions and variables). It has full access to OTP, all Erlang standard libraries, and any BEAM-compatible package. Calling Erlang from LFE is zero-cost — it's just a normal function call since both compile to the same bytecode.

Sources:
- [LFE Official Site](https://lfe.io/)
- [LFE on Wikipedia](https://en.wikipedia.org/wiki/LFE_(programming_language))
- [Interview with Robert Virding](https://blog.lambdaclass.com/interview-with-robert-virding-creator-lisp-flavored-erlang-an-alien-technology-masterpiece/)

---

## LFE S-Expression Syntax

### Basics

```lfe
;; Function definition
(defun factorial
  ((0) 1)
  ((n) (* n (factorial (- n 1)))))

;; Multiple clauses via pattern matching in function head
(defun handle-message
  (('ok result)    (io:format "Success: ~p~n" (list result)))
  (('error reason) (io:format "Failed: ~p~n" (list reason)))
  ((other)         (io:format "Unknown: ~p~n" (list other))))

;; Let bindings
(let ((x 10)
      (y 20))
  (+ x y))

;; Lambda
(lambda (x y) (+ x y))

;; Lambda with pattern matching
(match-lambda
  (('ok msg)   (handle-success msg))
  (('err msg)  (handle-error msg)))

;; Case
(case data
  ((tuple 'ok result)   (process result))
  ((tuple 'err reason)  (log-error reason))
  (_                    'unknown))
```

### Data Types

| LFE Syntax | What It Is | Common Lisp Equivalent |
|-----------|-----------|----------------------|
| `'atom` | Atom (Erlang atom) | `'symbol` (keyword symbols) |
| `"string"` | String (list of integers) | `"string"` (character array) |
| `#"binary"` | Binary string (bytes) | No direct equivalent |
| `(list 1 2 3)` | List | `(list 1 2 3)` |
| `#(1 2 3)` | Tuple (fixed-size, ordered) | No direct equivalent (could use vectors) |
| `#m(key val)` | Map | Hash table |
| `(cons h t)` | Cons cell | `(cons h t)` |

### Key Syntactic Differences from Common Lisp

| Feature | Common Lisp | LFE |
|---------|------------|-----|
| `nil` / `()` | Same thing | Different (`()` is empty list, no CL-style nil) |
| Mutability | `setf`, `setq` available | Immutable (BEAM constraint) |
| Arithmetic | Variadic `(+ 1 2 3 4)` | Binary `(+ (+ 1 2) (+ 3 4))` |
| Pattern matching | Not built-in | Native in function heads, `case`, `receive`, `let` |
| Macros | Reader macros, `defmacro` | `defmacro` (unhygienic), no reader macros |
| CLOS | Full object system | None (use records, maps, protocols) |
| Conditions/restarts | Full condition system | Erlang exceptions (`try`/`catch`) |
| Multiple return values | `(values a b c)` | Tuples `#(a b c)` |
| Packages | `defpackage` / `in-package` | Modules `(defmodule name ...)` |
| Dynamic variables | `*special-vars*` | Process dictionary (`erlang:put`/`erlang:get`) — per-process |

Sources:
- [Learn LFE in Y Minutes](https://learnxinyminutes.com/docs/lfe/)
- [LFE Hyperpolyglot](https://lfex.github.io/hyperpolyglot/)
- [LFE Pattern Matching](http://docs.lfe.io/current/user-guide/diving/5.html)

---

## LFE OTP Patterns

### gen_server

```lfe
(defmodule my-agent-server
  (behaviour gen_server)
  (export all))

;; Client API
(defun start-link (agent-config)
  (gen_server:start_link
    `#(local ,(agent-name agent-config))
    'my-agent-callback
    agent-config
    '()))

(defun send-prompt (name prompt)
  (gen_server:call name `#(prompt ,prompt)))

(defun stop (name)
  (gen_server:cast name 'stop))
```

```lfe
(defmodule my-agent-callback
  (export all))

;; Callbacks
(defun init (agent-config)
  `#(ok ,agent-config))

(defun handle_call
  ((`#(prompt ,prompt) _from state)
   (let ((result (process-prompt prompt state)))
     `#(reply ,result ,state)))
  ((msg _from state)
   `#(reply #(error unknown-message) ,state)))

(defun handle_cast
  (('stop state)
   `#(stop normal ,state))
  ((msg state)
   `#(noreply ,state)))

(defun terminate (reason state)
  (log-shutdown reason state)
  'ok)
```

### Supervisor

```lfe
(defmodule my-project-supervisor
  (behaviour supervisor)
  (export (start_link 0) (init 1)))

(defun start_link ()
  (supervisor:start_link
    `#(local my-project-supervisor)
    'my-project-supervisor
    '()))

(defun init (_args)
  `#(ok #(#(one_for_one 5 10)    ;; Strategy: one_for_one, 5 restarts in 10s
          (,(child-spec 'conductor-server
                        'conductor-server 'start_link '()
                        'permanent 5000 'worker)
           ,(child-spec 'agent-manager
                        'agent-manager 'start_link '()
                        'permanent 5000 'worker)))))

(defun child-spec (id module func args restart shutdown type)
  `#(,id #(,module ,func ,args)
     ,restart ,shutdown ,type (,module)))
```

### Supervision Strategies

| Strategy | Behavior |
|----------|----------|
| `one_for_one` | Only restart the crashed child |
| `one_for_all` | Restart all children when one crashes |
| `rest_for_one` | Restart the crashed child and all children started after it |
| `simple_one_for_one` | Dynamic child specs, all children are same type |

Each strategy configures `MaxRestarts` in `MaxTime` seconds. If exceeded, the supervisor itself crashes (escalating to its parent supervisor).

### Process Spawning and Message Passing

```lfe
;; Spawn a process
(let ((pid (spawn 'module 'function '(args))))

;; Send a message
(! pid #(request "do-something"))

;; Receive with pattern matching
(receive
  (#(response result)
   (handle-result result))
  (#(error reason)
   (handle-error reason))
  (after 5000
   (handle-timeout)))

;; Linking (bidirectional crash propagation)
(link pid)

;; Monitoring (unidirectional crash notification)
(erlang:monitor 'process pid)
;; Receives #(DOWN ref process pid reason) on crash
```

### Process Characteristics on BEAM

- **Overhead**: ~1.5KB per process (32-bit), ~2.7KB (64-bit)
- **Capacity**: Millions of processes per node (default 262,144, configurable to ~134 million)
- **Scheduling**: Preemptive, reduction-based (each process gets ~4000 reductions before yielding)
- **GC**: Per-process garbage collection (no stop-the-world)
- **Isolation**: Each process has its own heap — crash in one cannot corrupt another
- **Distribution**: Processes can be on different nodes transparently

Sources:
- [Creating LFE Servers with OTP](https://blog.lfe.io/tutorials/2015/05/26/1112-creating-servers-with-the-gen_server-behaviour/)
- [LFE OTP Tutorials](https://github.com/oubiwann/lfe-otp-tutorials)
- [Learn You Some Erlang: Errors and Processes](https://learnyousomeerlang.com/errors-and-processes)
- [Message Passing | LFE Tutorial](https://lfe.gitbooks.io/tutorial/content/concurrent/msgpass.html)

---

## BEAM ↔ External Process Communication

This is the critical integration point: how does an LFE supervisor communicate with Common Lisp processes?

### Ports (Recommended for This Use Case)

Ports spawn an external OS process and communicate via stdin/stdout:

```lfe
;; Open a port to a CL process
(let ((port (erlang:open_port
              #(spawn "sbcl --script agent-worker.lisp")
              '(binary #(line 65536) exit_status use_stdio))))
  ;; Send data
  (! port `#(,self ,#(command #"(cognitive-cycle agent-1)")))
  ;; Receive response
  (receive
    (`#(,port #(data ,response))
     (process-response response))
    (`#(,port #(exit_status ,code))
     (handle-exit code))))
```

**Port characteristics**:
- External process runs in separate OS process — full isolation
- Communication via stdin/stdout (byte streams)
- Port closes automatically if either side crashes
- Supervisor can detect port closure and restart

**gen_server wrapping a port** — The proven pattern (from `lfeutre/port-examples`):

```lfe
(defmodule agent-port-server
  (behaviour gen_server)
  (export all))

(defun init (agent-config)
  (let ((port (open-agent-port agent-config)))
    `#(ok #m(port ,port config ,agent-config))))

(defun handle_call
  ((`#(prompt ,prompt) _from state)
   (let ((port (mref state 'port)))
     ;; Send to CL process via port
     (erlang:port_command port (encode-message prompt))
     ;; Wait for response
     (receive
       (`#(,port #(data ,response))
        `#(reply ,(decode-response response) ,state)))))

(defun handle_info
  ((`#(,port #(exit_status ,code)) state)
   ;; Port closed — CL process died
   ;; Returning 'stop triggers supervisor restart
   `#(stop #(port_died ,code) ,state)))
```

When the CL process crashes, the port closes, `handle_info` receives the exit status, and the gen_server returns `#(stop ...)`. The supervisor detects this and restarts the gen_server (which reopens the port, spawning a new CL process).

### NIFs (Not Recommended)

NIFs (Native Implemented Functions) load C shared libraries directly into the BEAM. A crash in a NIF can take down the entire VM. Not suitable for running agent code.

### Erlang Distribution Protocol

BEAM nodes can connect to each other over TCP. LFE processes on different nodes communicate transparently. Not directly useful for CL integration, but relevant for multi-node agent clusters.

Sources:
- [Port Examples Repository](https://github.com/lfeutre/port-examples)
- [Ports and NIFs Comparison](https://softwarepatternslexicon.com/patterns-elixir/14/2/)
- [Erlang External Process Communication WG](https://erlef.org/wg/epc)

---

## What Autopoiesis Has Today for Agent Lifecycle

### Current Agent Model (No Threads, No Supervision)

Agents are CLOS objects with state flags. They do not run autonomously.

**Agent spawning** (`src/agent/spawner.lisp:11-19`):
```lisp
(defun spawn-agent (parent &key name capabilities)
  (let ((child (make-agent :name name
                           :capabilities (or capabilities (agent-capabilities parent))
                           :parent (agent-id parent))))
    (push (agent-id child) (agent-children parent))
    child))
```
- Creates data structure only
- No thread, no process, no supervision
- Returns the object — caller must drive the cognitive loop

**Cognitive cycle** (`src/agent/cognitive-loop.lisp:50-58`):
```lisp
(defun cognitive-cycle (agent environment)
  (when (agent-running-p agent)
    (let* ((observations (perceive agent environment))
           (understanding (reason agent observations))
           (decision (decide agent understanding))
           (result (act agent decision)))
      (reflect agent result)
      result)))
```
- Runs ONE iteration
- Caller must invoke repeatedly
- No error recovery — exception propagates to caller

**Message passing** (`src/agent/builtin-capabilities.lisp:53-83`):
- Global hash table of mailboxes
- `send-message` pushes to list (fire-and-forget)
- `receive-messages` returns immediately (no blocking receive)
- Not thread-safe
- No delivery guarantees

**Provider subprocess lifecycle** (`src/integration/provider.lisp:237-317`):
- `sb-ext:run-program` spawns external process
- Separate threads for stdout/stderr reading
- Timeout handling: SIGTERM → 5s → SIGKILL
- Provider lock ensures one invocation at a time
- No automatic restart on failure

### What the Current S-Expression Format Looks Like

Thought serialization (`src/core/cognitive-primitives.lisp:59-67`):
```lisp
(:thought
 :id "550e8400-e29b-41d4-a716-446655440000"
 :timestamp 1234567890.123456
 :type :reasoning
 :confidence 0.85
 :content (if (> x 10) :high :low)
 :provenance (:triggered-by "human-input"))
```

Snapshot format (`src/snapshot/persistence.lisp:69-78`):
```lisp
(snapshot
 :version 1
 :id "snap-uuid"
 :timestamp 1234567890.123456
 :parent "parent-snap-uuid"
 :agent-state (:agent-data ...)
 :metadata (:branch "main")
 :hash "sha256hex...")
```

Content-addressable hashing (`src/core/s-expr.lisp:81-113`):
- SHA256 via Ironclad
- Type-prefixed bytes: `"S"` for symbols, `"I"` for integers, `"("` for conses
- Structural identity — same structure = same hash

---

## S-Expression Compatibility Analysis

### What Transfers Directly

| Concept | Common Lisp | LFE Equivalent | Transfer Difficulty |
|---------|------------|----------------|-------------------|
| Lists | `(a b c)` | `(list 'a 'b 'c)` or `'(a b c)` | Trivial |
| Keyword plists | `(:key1 val1 :key2 val2)` | Proplists `'(#(key1 val1) #(key2 val2))` or maps `#m(key1 val1)` | Medium — different idiom |
| Quoted data | `'(thought :type :reasoning)` | `'(thought type reasoning)` | Trivial for data, atoms differ |
| Cons cells | `(cons 'a 'b)` | `(cons 'a 'b)` | Trivial |
| Nested structures | `((:a 1) (:b (:c 2)))` | `(list (tuple 'a 1) (tuple 'b (tuple 'c 2)))` | Medium — tuples vs lists |
| Symbols | `'my-symbol` | `'my-symbol` | Trivial (but case-sensitive in LFE) |

### What Doesn't Transfer

| CL Feature | Why It Doesn't Map | LFE Alternative |
|-----------|-------------------|----------------|
| CLOS classes | No object system on BEAM | Records, maps, protocols |
| `setf` / mutation | BEAM is immutable | Return new state from gen_server callbacks |
| Hash tables | Mutable hash tables | ETS tables or maps |
| `*special-variables*` | No dynamic binding | Process dictionary or gen_server state |
| Multiple values | `(values a b c)` | Tuples `#(a b c)` |
| Adjustable vectors | Mutable arrays | ETS tables or `array` module |
| Conditions/restarts | CL condition system | `try`/`catch`/`after` + supervision |
| Reader macros | No reader extensibility | Parse transforms |

### The Practical S-Expression Bridge

For cross-runtime communication (LFE supervisor ↔ CL cognitive engine), the S-expression format needs a wire protocol. Two approaches:

**Approach A: S-Expression Text Protocol**

Both CL and LFE can read/write S-expressions natively. Use a simple text protocol over stdio:

```
;; CL sends to LFE (via stdout):
(:thought-complete :id "uuid" :result (:action :file-read "path"))

;; LFE receives and parses:
(lfe_io:read_string data)
;; => (thought-complete id "uuid" result (action file-read "path"))
```

Caveats:
- CL keywords (`:foo`) become LFE atoms (`foo`) — need convention
- CL `nil` vs LFE `()` / `'false` — need normalization
- CL hash tables need explicit serialization (they're already plists in the codebase)

**Approach B: JSON Protocol**

Both have JSON libraries. More universal but loses some expressiveness:

```json
{"type": "thought-complete", "id": "uuid", "result": {"action": "file-read", "path": "..."}}
```

CL side: `cl-json:encode-json` / `cl-json:decode-json`
LFE side: `jsx:encode` / `jsx:decode`

**Approach C: ETF (Erlang Term Format)**

BEAM's native binary serialization. Would require a CL library to encode/decode. Most efficient for high-throughput scenarios but adds a dependency.

**Recommendation**: Approach A (S-expression text) preserves the homoiconic philosophy and both runtimes handle it natively. The existing serialization format in `src/core/s-expr.lisp:119-150` already uses `prin1` for readable output — that's exactly what would flow over the port.

---

## Architecture: LFE as Supervisor, CL as Cognitive Engine

### Per-Project Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   LFE/BEAM Application                    │
│                   (one per project)                        │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │          Project Supervisor (top-level)              │  │
│  │          Strategy: one_for_one                       │  │
│  └─────────┬──────────────┬──────────────┬─────────────┘  │
│            │              │              │                 │
│  ┌─────────▼───────┐ ┌───▼──────────┐ ┌▼──────────────┐  │
│  │   Conductor      │ │ Agent        │ │ Connector     │  │
│  │   (gen_server)   │ │ Supervisor   │ │ Supervisor    │  │
│  │                  │ │ (supervisor) │ │ (supervisor)  │  │
│  │  - Event loop    │ │              │ │               │  │
│  │  - Timer heap    │ │  ┌─────┐    │ │  ┌────────┐   │  │
│  │  - Health checks │ │  │Agent│    │ │  │Webhook │   │  │
│  │  - Work routing  │ │  │  1  │    │ │  │Server  │   │  │
│  │                  │ │  └─────┘    │ │  └────────┘   │  │
│  │                  │ │  ┌─────┐    │ │  ┌────────┐   │  │
│  │                  │ │  │Agent│    │ │  │MCP     │   │  │
│  │                  │ │  │  2  │    │ │  │Server  │   │  │
│  │                  │ │  └─────┘    │ │  └────────┘   │  │
│  │                  │ │  ┌─────┐    │ │  ┌────────┐   │  │
│  │                  │ │  │Agent│    │ │  │External│   │  │
│  │                  │ │  │  N  │    │ │  │Feed    │   │  │
│  │                  │ │  └─────┘    │ │  └────────┘   │  │
│  └──────────────────┘ └────────────┘  └───────────────┘  │
│                                                           │
│  Each Agent gen_server wraps a PORT to a CL process:      │
│                                                           │
│  ┌──────────────┐    stdio    ┌──────────────────────┐    │
│  │ Agent        │◄──────────►│ SBCL Process          │    │
│  │ gen_server   │  S-exprs   │                       │    │
│  │ (LFE/BEAM)  │            │ - Cognitive loop      │    │
│  │              │            │ - Thought stream      │    │
│  │ Supervision: │            │ - Extension compiler  │    │
│  │ - Restart    │            │ - Snapshot DAG        │    │
│  │ - Monitor    │            │ - Learning system     │    │
│  │ - Timeout    │            │ - Provider bridge     │    │
│  └──────────────┘            └──────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

### What Runs Where

| Component | Runtime | Why |
|-----------|---------|-----|
| Project supervisor | LFE/BEAM | OTP supervision trees, "let it crash" |
| Conductor (event loop) | LFE/BEAM | Long-running gen_server, timer management, health checks |
| Agent supervisor | LFE/BEAM | Dynamic child spawning (`simple_one_for_one`), restart strategies |
| Agent gen_server | LFE/BEAM | Wraps port to CL process, manages lifecycle, detects crashes |
| Connectors (webhook, MCP, feeds) | LFE/BEAM | Network I/O, Erlang's strength |
| Cognitive loop | CL/SBCL | Core Autopoiesis logic, CLOS, extension compiler |
| Thought stream | CL/SBCL | Vector-based storage, content-addressable hashing |
| Snapshot DAG | CL/SBCL | SHA256 hashing, file persistence |
| Learning system | CL/SBCL | Pattern extraction, heuristic generation |
| Provider bridge | CL/SBCL | Claude/Codex CLI subprocess management |

### Message Flow Example

1. **External event arrives** (e.g., webhook) → LFE Connector gen_server
2. Connector **sends message** to Conductor gen_server
3. Conductor **classifies** work item (fast path or slow path)
4. Fast path: Conductor handles directly (update counter, log, route)
5. Slow path: Conductor sends to **Agent Supervisor** to spawn/delegate
6. Agent Supervisor selects or spawns **Agent gen_server**
7. Agent gen_server **writes to port** (S-expression over stdio to CL process)
8. CL process runs **cognitive cycle**, writes result to stdout
9. Agent gen_server **reads from port**, receives result
10. Agent gen_server reports result to Conductor via message
11. If CL process crashes → port closes → gen_server returns `#(stop ...)` → **supervisor restarts**

### Conductor as gen_server

```lfe
(defmodule conductor
  (behaviour gen_server)
  (export all))

(defun init (project-config)
  ;; Initialize state with timer heap and event queue
  `#(ok #m(config ,project-config
            timers ,(init-timer-heap project-config)
            queue  ())))

(defun handle_info
  ;; Timer tick
  (('tick state)
   (let ((state2 (process-due-timers state)))
     (schedule-next-tick)
     `#(noreply ,state2)))

  ;; Agent completed work
  ((`#(agent-result ,agent-id ,result) state)
   (let ((state2 (handle-agent-result agent-id result state)))
     `#(noreply ,state2)))

  ;; Agent crashed (via monitor)
  ((`#(DOWN ,_ref process ,pid ,reason) state)
   (let ((state2 (handle-agent-crash pid reason state)))
     `#(noreply ,state2))))

(defun handle_cast
  ;; External event queued
  ((`#(event ,event) state)
   (let ((state2 (route-event event state)))
     `#(noreply ,state2))))
```

### Agent Supervisor with Dynamic Children

```lfe
(defmodule agent-supervisor
  (behaviour supervisor)
  (export all))

(defun init (_args)
  ;; simple_one_for_one: all children are same type, spawned dynamically
  `#(ok #(#(simple_one_for_one 3 60)  ;; 3 restarts per 60s per child
          (#(agent-worker
             #(agent-worker start_link ())
             transient  ;; Only restart if abnormal exit
             5000       ;; 5s shutdown timeout
             worker
             (agent-worker))))))

;; Spawn a new agent dynamically
(defun spawn-agent (agent-config)
  (supervisor:start_child 'agent-supervisor (list agent-config)))
```

---

## What BEAM Gives You That's Hard to Build in CL

### 1. Preemptive Scheduling

BEAM preempts processes after ~4000 reductions. A runaway agent can't starve others. In CL with bordeaux-threads, a CPU-bound thread blocks the entire OS thread — you'd need cooperative yielding or multiple OS threads.

### 2. Per-Process GC

Each BEAM process has its own heap and GC. One agent's garbage collection doesn't pause others. CL's SBCL has stop-the-world GC that pauses all threads.

### 3. Crash Isolation

A BEAM process crash is contained — other processes are unaffected. In CL with threads, an unhandled error in one thread can corrupt shared state (the entire heap is shared).

### 4. Supervision Trees (OTP)

Decades of battle-tested supervision logic: restart strategies, escalation, max restart intensity. Building equivalent in CL from scratch would be significant work and unlikely to match OTP's maturity.

### 5. Distribution

BEAM nodes can cluster transparently. Processes on different machines communicate identically to local processes. Enables scaling agent systems across machines.

### 6. Hot Code Swapping

Update agent behavior without stopping the system. BEAM supports running two versions of a module simultaneously for graceful migration.

### 7. Lightweight Processes

1.5-2.7KB per process means you can have millions of agents. CL threads are OS threads (~1-8MB stack each), limiting you to thousands at most.

---

## What CL Has That's Hard to Replicate on BEAM

### 1. CLOS (Common Lisp Object System)

The agent class hierarchy, capability system, extension compiler, and cognitive primitives all use CLOS. BEAM has no object system — you'd need records, maps, and protocols.

### 2. Mutable State

The thought stream is an adjustable vector with O(1) indexed access. BEAM's immutability means you'd use ETS tables or rebuild state on each message. The content-addressable store uses mutable hash tables internally.

### 3. Condition/Restart System

CL's condition system allows recovery strategies at call sites. BEAM's `try/catch` is simpler but less powerful. OTP supervision compensates by handling failure at the process level instead.

### 4. Extension Compiler Safety

The sandbox validator (`src/core/extension-compiler.lisp:232-383`) walks CL S-expressions checking symbol packages and forbidden operations. This would need to be reimplemented for LFE S-expressions if agents write LFE code. (But if agents write CL code that runs in the CL subprocess, the existing validator works.)

### 5. Content-Addressable Hashing

`sexpr-hash` (`src/core/s-expr.lisp:81-113`) produces SHA256 hashes from CL S-expression structure. The exact hash depends on CL type prefixes. A compatible hasher would need to exist in LFE for any state shared between runtimes, or hashing stays in CL.

---

## The Port Protocol in Detail

The critical design piece is the protocol between LFE gen_servers and CL cognitive engine processes.

### Proposed Protocol

Each message is a single line of S-expression text, terminated by newline:

**LFE → CL (commands)**:
```
(:cognitive-cycle :agent-id "uuid" :environment (:prompt "analyze this data"))
(:snapshot :agent-id "uuid")
(:inject-observation :agent-id "uuid" :content (:data "new information"))
(:shutdown)
```

**CL → LFE (responses)**:
```
(:cycle-complete :agent-id "uuid" :result (:action :file-read :path "/tmp/x") :thoughts 3)
(:snapshot-complete :agent-id "uuid" :snapshot-id "snap-uuid" :hash "sha256...")
(:observation-injected :agent-id "uuid")
(:error :agent-id "uuid" :type "division-by-zero" :message "...")
(:heartbeat :agent-id "uuid" :thoughts 47 :uptime 3600)
```

**CL → LFE (unsolicited)**:
```
(:blocking-request :id "req-uuid" :agent-id "uuid" :prompt "Approve restart?" :options ("yes" "no"))
(:log :level :info :agent-id "uuid" :message "Processing complete")
```

### CL Worker Process

The CL side would be a script that:
1. Loads Autopoiesis framework
2. Creates agent from config
3. Enters a read-eval-respond loop on stdin/stdout

```lisp
;; agent-worker.lisp (sketch)
(ql:quickload :autopoiesis)

(defun main ()
  (let ((agent (setup-agent-from-stdin)))
    (loop
      (let ((command (read *standard-input* nil :eof)))
        (when (eq command :eof) (return))
        (let ((response (handle-command agent command)))
          (prin1 response *standard-output*)
          (terpri *standard-output*)
          (force-output *standard-output*))))))
```

---

## Alternatives to LFE for the Supervision Layer

### Elixir

More popular than LFE on BEAM. Same OTP access. But uses Ruby-like syntax, not S-expressions. Loses the homoiconic connection to the CL codebase.

### Plain Erlang

The original. Most documentation and community support. But verbose syntax, no macro system, no S-expressions.

### Gleam

Type-safe BEAM language. But it's not a Lisp at all — no macros, no S-expressions.

### CL-native OTP

Implement supervision trees in Common Lisp with bordeaux-threads. Stays in one runtime but doesn't get BEAM's preemptive scheduling, per-process GC, or crash isolation. Libraries like `cl-actors` exist but are far less mature than OTP.

### LFE's Advantage

LFE is the only option that gives you both S-expressions AND OTP. The S-expression syntax means:
- Configuration can flow between runtimes with minimal translation
- Macros can generate both the supervisor structure and the CL worker protocol
- The philosophical alignment with "code as data" is maintained
- Agent state can be printed/read in a format both runtimes understand

---

## Open Questions

1. **How many CL processes per project?** One long-lived CL process per agent (port per agent)? Or a pool of CL worker processes shared by agents? The former is simpler; the latter is more resource-efficient.

2. **State ownership**: Does the CL process own agent state (thought stream, snapshots) and the LFE gen_server just supervises? Or does the LFE side maintain state and pass it to CL on each cognitive cycle?

3. **Provider delegation**: When a CL cognitive engine needs to invoke Claude Code (a subprocess itself), is that subprocess-within-subprocess viable? The CL process would `sb-ext:run-program` inside a process managed by a port managed by a gen_server.

4. **Hot code swapping**: BEAM supports swapping running code. Can the LFE supervisor trigger a CL process to reload its Autopoiesis framework (e.g., after an extension is installed)?

5. **Shared storage**: The snapshot DAG lives on disk. Both the LFE supervisor and CL workers need access. Is this just a shared filesystem path, or does it need a storage service?

6. **Development workflow**: How do you develop and test a project? Start the LFE application and it boots CL workers? Or develop CL-side independently and only bring in LFE for production supervision?

7. **LFE maturity for this use case**: LFE has been running in production since 2016, but the community is small. Is the tooling sufficient for this architecture?

## Related Research

- `thoughts/shared/research/2026-02-04-agent-system-ideas-synthesis.md` — Vision documents synthesis
- `thoughts/shared/research/2026-02-03-autopoiesis-codebase-overview.md` — Full codebase overview
- `thoughts/shared/plans/Autopoiesis + Cortex Synthesis Plan.md` — Conductor pattern vision
- `thoughts/shared/plans/2026-02-04-workspace-architecture-plan.md` — Workspace architecture

## Sources

- [LFE Official Site](https://lfe.io/)
- [LFE Learn](https://lfe.io/learn/)
- [LFE Use](https://lfe.io/use/)
- [Learn LFE in Y Minutes](https://learnxinyminutes.com/docs/lfe/)
- [LFE Hyperpolyglot](https://lfex.github.io/hyperpolyglot/)
- [LFE GitHub Repository](https://github.com/lfe/lfe)
- [Creating LFE Servers with OTP](https://blog.lfe.io/tutorials/2015/05/26/1112-creating-servers-with-the-gen_server-behaviour/)
- [LFE and rebar3](https://blog.lfe.io/tutorials/2016/03/25/0858-lfe-and-rebar3/)
- [LFE OTP Tutorials](https://github.com/oubiwann/lfe-otp-tutorials)
- [Port Examples (LFE ↔ Go, CL)](https://github.com/lfeutre/port-examples)
- [rebar3_lfe Plugin](https://github.com/lfe/rebar3)
- [LFE Pattern Matching](http://docs.lfe.io/current/user-guide/diving/5.html)
- [Message Passing | LFE Tutorial](https://lfe.gitbooks.io/tutorial/content/concurrent/msgpass.html)
- [Learn You Some Erlang: Errors and Processes](https://learnyousomeerlang.com/errors-and-processes)
- [LFE InfoQ Article](https://www.infoq.com/news/2016/04/lfe-lisp-erlang/)
- [Interview with Robert Virding (LFE creator)](https://blog.lambdaclass.com/interview-with-robert-virding-creator-lisp-flavored-erlang-an-alien-technology-masterpiece/)
- [Ports and NIFs Comparison](https://softwarepatternslexicon.com/patterns-elixir/14/2/)
- [BEAM in Plain English](https://dev.to/adamanq/beam-in-plain-english-2n1o)
- [Designing Concurrent Systems on BEAM](https://www.happihacking.com/blog/posts/2024/designing_concurrency/)
- [Distributed Erlang Documentation](https://www.erlang.org/doc/system/distributed.html)
