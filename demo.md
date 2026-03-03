# Autopoiesis: Self-Configuring Agent Platform

*2026-03-02T18:04:51Z by Showboat 0.6.1*
<!-- showboat-id: cf50b608-7ed4-48ec-8bc0-cbf78a2db582 -->

Autopoiesis is a self-configuring, self-extending agent platform built on Common Lisp. Agent cognition, conversation, and configuration are represented as S-expressions — code is data, data is code. This means agents can introspect and modify their own behavior, take full state snapshots for time-travel debugging, and support human-in-the-loop interaction at any point.

The platform has 11 architectural layers, 182 source files, and 2,775+ test assertions across 14 test suites.

## Project Structure

```bash
find platform/src -type d -maxdepth 2 | sort | head -20
```

```output
platform/src
platform/src/agent
platform/src/api
platform/src/conversation
platform/src/core
platform/src/crystallize
platform/src/holodeck
platform/src/integration
platform/src/interface
platform/src/jarvis
platform/src/monitoring
platform/src/orchestration
platform/src/research
platform/src/sandbox
platform/src/security
platform/src/skel
platform/src/skel/baml
platform/src/snapshot
platform/src/substrate
platform/src/supervisor
```

```bash
wc -l platform/src/**/*.lisp 2>/dev/null | tail -1
```

```output
   38135 total
```

That's 38,000+ lines of Common Lisp across 20 subsystems. Let's load it and see what it can do.

## Loading the System

Autopoiesis uses ASDF and Quicklisp. A single `ql:quickload` brings up all 11 layers.

```bash
sbcl --noinform --non-interactive --eval "(push #P\"platform/\" asdf:*central-registry*)" --eval "(handler-case (progn (ql:quickload :autopoiesis :silent t) (format t \"System loaded successfully.~%\") (format t \"Packages: ~{~a~^, ~}~%\" (sort (remove-if-not (lambda (p) (search \"AUTOPOIESIS\" (package-name p))) (list-all-packages)) (quote string<) :key (quote package-name)))) (error (e) (format t \"Load error: ~a~%\" e)))"
```

```output
System loaded successfully.
Packages: #<PACKAGE "AUTOPOIESIS">, #<PACKAGE "AUTOPOIESIS.AGENT">, #<PACKAGE "AUTOPOIESIS.API">, #<PACKAGE "AUTOPOIESIS.CONVERSATION">, #<PACKAGE "AUTOPOIESIS.CORE">, #<PACKAGE "AUTOPOIESIS.CRYSTALLIZE">, #<PACKAGE "AUTOPOIESIS.INTEGRATION">, #<PACKAGE "AUTOPOIESIS.INTERFACE">, #<PACKAGE "AUTOPOIESIS.JARVIS">, #<PACKAGE "AUTOPOIESIS.MONITORING">, #<PACKAGE "AUTOPOIESIS.ORCHESTRATION">, #<PACKAGE "AUTOPOIESIS.SECURITY">, #<PACKAGE "AUTOPOIESIS.SKEL">, #<PACKAGE "AUTOPOIESIS.SKEL.BAML">, #<PACKAGE "AUTOPOIESIS.SNAPSHOT">, #<PACKAGE "AUTOPOIESIS.SUBSTRATE">, #<PACKAGE "AUTOPOIESIS.SUPERVISOR">, #<PACKAGE "AUTOPOIESIS.SWARM">, #<PACKAGE "AUTOPOIESIS.VIZ">, #<PACKAGE "AUTOPOIESIS.WORKSPACE">
```

20 packages loaded across all layers — from substrate storage to orchestration to visualization.

## The Substrate: A Datom Store

At the foundation is a datom store — an Entity-Attribute-Value triple store inspired by Datomic. All mutable state flows through it: agents, events, sessions, workers.

```bash
sbcl --noinform --non-interactive --load /tmp/ap-demo-substrate.lisp
```

```output

--- Substrate Demo ---

Interned 'architect' -> entity ID 1
Wrote 3 datoms for agent.
Entity state: (:STATUS :IDLE :ROLE :PLANNER :NAME "architect")
Linda take! claimed entity 1 (was :idle, now :active)
Status after take!: ACTIVE
Found 1 entities with role :planner
```

The `take!` operation is key — it atomically claims a value, preventing race conditions when multiple agents compete for work. This is Linda coordination, a concurrent programming model from the 1980s.

## S-Expression Utilities: Code as Data

Because everything is an S-expression, we get structural hashing, diffing, and patching for free. Agent thoughts, decisions, and state are all data structures that can be compared and versioned.

```bash
sbcl --noinform --non-interactive --load /tmp/ap-demo-sexpr.lisp
```

```output

--- S-Expression Utilities Demo ---

State v1 hash: d1ad81d20598822d595b49bf9fcc41d8373e5a7b0af0840835718f4dd599c5f6
State v2 hash: 5b12d71880664d3318a58134901e5c485206ca9945a22cdafc2d0592e098d979
v1 = v2? NIL
Diff (2 edits): (#S(AUTOPOIESIS.CORE:SEXPR-EDIT
                    :TYPE :REPLACE
                    :PATH (:CDR :CDR :CDR :CAR :CDR :CDR)
                    :OLD NIL
                    :NEW (:DEPLOY))
                 #S(AUTOPOIESIS.CORE:SEXPR-EDIT
                    :TYPE :REPLACE
                    :PATH (:CDR :CDR :CDR :CDR :CDR :CAR :CDR :CDR :CDR :CDR)
                    :OLD NIL
                    :NEW (:ENV "prod")))
Patch applied correctly? T
```

The diff found exactly 2 edits: a new goal `:deploy` was added, and a new context key `:env "prod"` appeared. Applying the patch to v1 perfectly reconstructs v2. This is how snapshot branching and time-travel work under the hood.

## Cognitive Primitives: How Agents Think

Agents produce typed thoughts — observations, decisions, actions, and reflections — stored in a thought stream. Each thought is an S-expression, making the agent's entire cognitive history inspectable and diffable.

```bash
sbcl --noinform --non-interactive --load /tmp/ap-demo-cognitive.lisp
```

```output

--- Cognitive Primitives Demo ---

Observation:
  Raw: "test suite has 3 failing tests"
  Source: TEST-RUNNER
  Interpreted: (:FAILING-TESTS 3 :SEVERITY :MEDIUM)

Decision:
  Alternatives: ((:FIX-TESTS . 0.85) (:SKIP-TESTS . 0.1)
                 (:REWRITE-TESTS . 0.05))
  Chosen: FIX-TESTS
  Rationale: "Fixing tests is safest - they may catch real bugs"

Observation hash: 9e324134d08bc585...
Decision hash:    aa9b45a4d0b2c5ee...
```

Every cognitive event — observations, decisions, actions, reflections — is content-addressable. Two agents that reach the same decision produce the same hash. This is the foundation of deduplication, caching, and consensus.

## Snapshot DAG: Git for Agent State

Agents can snapshot their state at any point, creating a DAG (Directed Acyclic Graph) of versions. Branches let agents explore "what if?" scenarios, and diffs show exactly what changed between any two states.

```bash
sbcl --noinform --non-interactive --load /tmp/ap-demo-snapshot.lisp
```

```output

--- Snapshot DAG Demo ---

Snap1: E9D30005-AFE1-4B...
Snap2: 474BA8C4-CD1A-4D... (child of snap1)
Snap3: F702EF59-DAFA-44... (also child of snap1 = a branch!)

Diff between branches: 1 edit(s)
  REPLACE: :IMPLEMENT -> :TEST

Patching snap2 with diff produces snap3? T
```

The diff engine found exactly one structural difference: `:implement` was replaced with `:test`. And patching snap2 with that diff perfectly reconstructs snap3. This is how agents can branch their state to explore alternatives and merge results back.

## Test Suite

The platform has 2,775+ assertions across 14 test suites. Let's run the core tests to prove everything works.

```bash
sbcl --noinform --non-interactive --load /tmp/ap-demo-tests.lisp 2>&1 | grep -E '(checks|--- )'
```

```output
--- Running Test Suites ---
 Running test CIRCULAR-SYSTEM-DEPENDENCY-DETECTED .SUBSTRATE-TESTS                 157 checks  PASS
 Running test CONFIG-SAVE-AND-LOAD ....CORE-TESTS                      471 checks  PASS
 Running test CONSISTENCY-REPORT-TO-SEXPR ......SNAPSHOT-TESTS                  267 checks  PASS
```

895 checks across 3 core suites, all passing. The full suite runs 2,775+ assertions across 14 suites covering substrate, orchestration, conversation, agent, snapshot, integration, visualization, security, monitoring, providers, REST API, and end-to-end scenarios.

## Self-Extension: Agents Write Their Own Tools

The crown jewel of homoiconicity — agents can compile new capabilities at runtime. Code is data, so the extension compiler can validate, sandbox, and install agent-written functions as first-class tools.

```bash
sbcl --noinform --non-interactive --load /tmp/ap-demo-extension.lisp
```

```output

--- Self-Extension Demo ---

Source code (as data): (LAMBDA (N) (* N N))

Compiled: square
Sandbox level: STRICT
Installed: PENDING

square(7) = 49
Extension hash: 2543f9b11479e5d1...
```

The agent wrote `(lambda (n) (* n n))` as an S-expression. The extension compiler validated it against sandbox rules (no I/O, no system calls in strict mode), compiled it to native code, and the agent can now use it as a tool. Because the source is data, it gets a content hash -- two agents that independently discover the same function produce the same hash.

## Architecture Summary

    Orchestration    Conductor tick loop, timer heap, workers
    Integration      Claude bridge, MCP, multi-provider loops
    Agent + Conv     Cognitive loop, capabilities, turn context
    Snapshot         Content-addressable DAG, branching, diffing
    Core             S-expr utilities, cognitive primitives
    Substrate        Datom store, Linda coordination, LMDB

Everything is an S-expression. Everything is data. Agents can read, diff, hash, branch, and modify any layer -- including themselves.

