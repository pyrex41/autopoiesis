# Persistent Agent Architecture Demo

*2026-03-04T05:17:31Z by Showboat 0.6.1*
<!-- showboat-id: bb125c78-257e-43bb-a0e4-1faceb95f9f7 -->

Autopoiesis is a self-configuring agent platform built on Common Lisp. This demo walks through the persistent agent architecture: immutable agents backed by FSet's balanced trees, O(1) forking via structural sharing, an immutable cognitive loop, evolutionary swarm integration, and a dual-agent bridge between mutable CLOS agents and persistent roots.

All demos are self-contained Lisp scripts in `platform/docs/demo/`.

## 1. Persistent Data Structures (fset wrappers)

The core layer wraps FSet with pmap/pvec/pset APIs. Updates return new collections; originals remain unchanged.

```bash
sbcl --noinform --non-interactive --load platform/docs/demo/pstructs-demo.lisp 2>&1 | grep -v "^$"
```

```output
m1: ((:NAME . "scout") (:ROLE . "analyzer"))
m2: ((:NAME . "scout") (:ROLE . "analyzer") (:STATUS . :ACTIVE))
m1 unchanged after m2 created: T
v1 length: 2, v2 length: 3
v1 contents: (:THOUGHT-1 :THOUGHT-2)
v2 contents: (:THOUGHT-1 :THOUGHT-2 :THOUGHT-3)
s1: (:SEARCH :ANALYZE)
s2: (:REPORT :SEARCH :ANALYZE)
s3 (union): (:REPORT :SEARCH :ANALYZE :SUMMARIZE)
```

## 2. Persistent Agent: Create, Perceive, Fork

Persistent agents are immutable structs. Every cognitive operation returns a new agent. Forking is O(1) — child and parent share all data via structural sharing.

```bash
sbcl --noinform --non-interactive --load platform/docs/demo/agent-demo.lisp 2>&1 | grep -v "^$" | grep -v "^;"
```

```output
=== Create a persistent agent ===
Name: scout
Capabilities: (:REPORT :SEARCH :ANALYZE)
Thoughts: 0
=== Cognitive cycle (perceive -> reason) ===
After perceive — thoughts: 1
After reason  — thoughts: 2
Original unchanged — thoughts: 0
=== O(1) Fork ===
Child name: scout-alpha
Thoughts shared (eq): T
Parent tracks child: T
=== Independent evolution ===
Child after work — thoughts: 3
Original child unchanged — thoughts: 2
Parent still unchanged — thoughts: 2
```

## 3. Evolutionary Swarm Integration

Persistent agents bridge to genome-based evolution. Extract genomes, run selection/crossover/mutation, patch evolved traits back. Originals stay unmodified.

```bash
sbcl --noinform --non-interactive --load platform/docs/demo/swarm-demo.lisp 2>&1 | grep -v "^$" | grep -v "^;"
```

```output
=== Create population ===
Population size: 10
Agent-0 caps: (:CAP-0 :CAP-1)
Agent-3 caps: (:CAP-0 :CAP-1 :CAP-2 :CAP-3 :CAP-4)
=== Fitness functions ===
Capability breadth (agent-3): 0.250
Genome efficiency  (agent-3): 1.000
=== Evolve 5 generations ===
Evolved population size: 10
All persistent-agents: T
Original agent-0 caps unchanged: T
```

## 4. Dual-Agent Bridge

Wraps a mutable CLOS agent with a persistent root. State changes auto-sync via `:after` methods. Thread-safe (recursive lock). Undo reverts to previous version.

```bash
sbcl --noinform --non-interactive --load platform/docs/demo/dual-demo.lisp 2>&1 | grep -v "^$" | grep -v "^;"
```

```output
=== Upgrade mutable agent to dual-agent ===
Type: DUAL-AGENT
Has persistent root: T
Root name: worker
=== Auto-sync on mutation ===
Mutable name: worker-v2
Persistent root name: worker-v2
Version history depth: 1
After second rename — name: worker-v3, history: 2
=== Undo ===
After undo — name: worker-v2
```

## 5. Test Suite — 103/103 Passing

```bash
sbcl --noinform --non-interactive --load platform/docs/demo/test-demo.lisp 2>&1 | grep -E "^(=|Running| Did|    Pass|    Fail)"
```

```output
=== Persistent Agent Tests ===
Running test suite PERSISTENT-AGENT-TESTS
 Did 80 checks.
    Pass: 80 (100%)
    Fail: 0 ( 0%)
=== Swarm Integration Tests ===
Running test suite SWARM-INTEGRATION-TESTS
 Did 23 checks.
    Pass: 23 (100%)
    Fail: 0 ( 0%)
```
