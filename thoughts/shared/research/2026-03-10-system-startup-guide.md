---
date: "2026-03-10T22:46:55Z"
researcher: reuben
git_commit: 19c615c6328a69b9b08f95e5f69cc5e3a9b22316
branch: main
repository: autopoiesis
topic: "How to start the system and try it out"
tags: [research, codebase, startup, repl, interactive, quickstart]
status: complete
last_updated: "2026-03-10"
last_updated_by: reuben
---

# Research: How to Start the Autopoiesis System and Try It Out

**Date**: 2026-03-10T22:46:55Z
**Researcher**: reuben
**Git Commit**: 19c615c
**Branch**: main
**Repository**: autopoiesis

## Research Question
How do I start the autopoiesis system, run it interactively, and try it out?

## Summary

All prerequisites (SBCL 2.5.10, Quicklisp, fset) are installed on this machine. The system can be started in several ways: REPL (simplest), one-liner shell command, Docker Compose, or standalone demo scripts. The core startup sequence is: load ASDF system → open substrate store → start conductor → optionally start API server.

## Quick Start Options

### Option 1: REPL (Simplest — Recommended First Try)

```bash
cd /Users/reuben/projects/ap
sbcl --load ~/quicklisp/setup.lisp
```

Then at the SBCL REPL:

```lisp
;; Load the system
(push #P"platform/" asdf:*central-registry*)
(ql:quickload :autopoiesis :silent t)

;; Open an in-memory store and start the conductor
(autopoiesis.substrate:with-store ()
  (autopoiesis.orchestration:start-system)

  ;; Create and run an agent
  (let ((agent (autopoiesis.agent:make-agent
                :name "explorer"
                :capabilities '(:planning :code-review))))
    (autopoiesis.agent:start-agent agent)

    ;; Run a cognitive cycle
    (autopoiesis.agent:cognitive-cycle agent
      '(:task "Analyze the system architecture"))

    ;; Check thoughts
    (format t "Thoughts: ~a~%"
      (autopoiesis.core:stream-length
        (autopoiesis.agent:agent-thought-stream agent)))

    ;; Interactive CLI session (read-eval-print loop)
    ;; Commands: start, stop, step, thoughts, inject, status, quit
    (autopoiesis.interface:cli-interact agent))

  (autopoiesis.orchestration:stop-system))
```

### Option 2: One-Liner (Backend + API Server)

```bash
cd /Users/reuben/projects/ap
sbcl --load ~/quicklisp/setup.lisp --eval '
  (push #P"platform/" asdf:*central-registry*)
  (ql:quickload :autopoiesis/api :silent t)
  (autopoiesis.substrate:with-store ()
    (autopoiesis.orchestration:start-system :monitoring-port 8081)
    (autopoiesis.api:start-api-server)
    (format t "~&Ready. REST on :8081, WebSocket on :8080~%")
    (loop (sleep 60)))'
```

Verify with: `curl http://localhost:8081/healthz | python3 -m json.tool`

### Option 3: Docker Compose

```bash
cd /Users/reuben/projects/ap/platform
docker-compose up -d
docker attach autopoiesis   # interactive REPL
```

### Option 4: Standalone Demo Scripts

Five runnable demos in `platform/docs/demo/`:

```bash
cd /Users/reuben/projects/ap
sbcl --noinform --non-interactive --load platform/docs/demo/agent-demo.lisp
sbcl --noinform --non-interactive --load platform/docs/demo/pstructs-demo.lisp
sbcl --noinform --non-interactive --load platform/docs/demo/dual-demo.lisp
sbcl --noinform --non-interactive --load platform/docs/demo/swarm-demo.lisp
sbcl --noinform --non-interactive --load platform/docs/demo/test-demo.lisp
```

## Interactive Interfaces

### CLI Session (`cli-interact`)

Once you have an agent, `(autopoiesis.interface:cli-interact agent)` starts a command loop:

| Command | Action |
|---------|--------|
| `start` / `stop` / `pause` / `resume` | Agent lifecycle |
| `step` | Run one cognitive cycle |
| `thoughts` | Print full thought stream |
| `inject <text>` | Push an observation into the agent |
| `status` | Show capabilities + recent thoughts |
| `pending` | List blocking human-input requests |
| `respond <id-prefix> <value>` | Unblock a pending request |
| `viz` / `v` | Launch terminal timeline visualization |
| `quit` / `q` | End session |

### Jarvis NL→Tool Loop

```lisp
;; Start a Jarvis conversational session (NL → tool dispatch)
(defvar *session* (autopoiesis.jarvis:start-jarvis))

;; Prompt it
(autopoiesis.jarvis:jarvis-prompt *session* "Search the codebase for memory leaks")

;; Stop
(autopoiesis.jarvis:stop-jarvis *session*)
```

### LLM-Backed Agents (requires ANTHROPIC_API_KEY or Claude CLI)

```lisp
;; Register a Claude Code provider (uses `claude` CLI subprocess)
(let ((claude (autopoiesis.integration:make-claude-code-provider
               :name "claude"
               :default-model "claude-sonnet-4-20250514"
               :skip-permissions t)))
  (autopoiesis.integration:register-provider claude))

;; Create and prompt a provider-backed agent
(let ((agent (autopoiesis.integration:make-provider-backed-agent
              :name "claude-dev"
              :provider (autopoiesis.integration:find-provider "claude")
              :system-prompt "You are a senior Common Lisp developer.")))
  (autopoiesis.integration:provider-agent-prompt agent
    "Write a function that computes the Fibonacci sequence using memoization."))
```

## Startup Architecture

```
(ql:quickload :autopoiesis)
  └─► (autopoiesis.orchestration:start-system)
        ├─► open-store              ; in-memory datom store
        ├─► start-monitoring-server ; Hunchentoot on :8081 (/healthz, /metrics)
        ├─► register-conductor-endpoints  ; /conductor/webhook, /conductor/status
        └─► start-conductor         ; background thread, 100ms tick loop

;; Separately (for WebSocket API):
(autopoiesis.api:start-api-server)
        ├─► start-event-bridge      ; substrate → WebSocket forwarding
        ├─► start-blocking-notifier ; 250ms poll thread
        └─► clack:clackup           ; Woo server on :8080
```

## Running Tests

```bash
# Full suite (4,300+ assertions)
./platform/scripts/test.sh

# Or from REPL for specific suites:
(ql:quickload :autopoiesis/test :silent t)
(5am:run! 'autopoiesis.test::core-tests)
(5am:run! 'autopoiesis.test::agent-tests)
(5am:run! 'autopoiesis.test::e2e-tests)
```

## Code References

- `platform/src/orchestration/endpoints.lisp:45` — `start-system` function
- `platform/src/orchestration/conductor.lisp:256` — `start-conductor` function
- `platform/src/substrate/store.lisp:261` — `with-store` macro
- `platform/src/api/server.lisp:215` — `start-api-server` function
- `platform/src/monitoring/endpoints.lisp:405` — `start-monitoring-server`
- `platform/src/interface/session.lisp` — `cli-interact`, `run-cli-session`
- `platform/src/jarvis/loop.lisp:13` — `start-jarvis`, `jarvis-prompt`
- `platform/src/integration/provider-agent.lisp` — `make-provider-backed-agent`
- `platform/docs/demo/` — 5 standalone demo scripts
- `platform/docs/QUICKSTART.md` — comprehensive quickstart guide
- `platform/docs/VALIDATION.md` — layer-by-layer validation checklist
