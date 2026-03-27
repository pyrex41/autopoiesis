# Autopoiesis Complete Validation Plan

This document provides a **complete, step-by-step validation plan** to fire up the full Autopoiesis system (core + all extensions), explore every layer, and verify it's ready as a base for agentic development. It replaces tools like OpenClaw/Cursor with homoiconic agents, self-extension, and time-travel debugging.

**Time:** ~30-60 min  
**Prerequisites:** SBCL + Quicklisp (see [QUICKSTART.md](QUICKSTART.md)). Run from repo root (`/Users/reuben/projects/ap`).  
**Success Criteria:** All tests pass + all snippets execute without errors.

## 1. Setup & Core Load (5 min)

```bash
cd platform
./scripts/build.sh  # Builds core system + deps
./scripts/test.sh   # Full core tests (4,300+ assertions) - MUST PASS ALL
```

In **SBCL REPL**:
```lisp
(ql:quickload :autopoiesis/api)  # Core + API server

;; Load optional extensions (Swarm, Supervisor, etc.)
(ql:quickload '(:autopoiesis/swarm :autopoiesis/supervisor 
                :autopoiesis/crystallize :autopoiesis/team 
                :autopoiesis/jarvis :autopoiesis/holodeck))
```

## 2. Start Full System (2 min)

```lisp
;; Persistent LMDB store + monitoring + API
(autopoiesis.substrate:with-store (:path "test-store")
  (autopoiesis.orchestration:start-system :monitoring-port 8081)
  (autopoiesis.api:start-api-server :ws-port 8080 :rest-port 8081))
```

**Verify endpoints** (new terminal):
```bash
curl http://localhost:8081/healthz | jq  # {\"status\":\"healthy\",...}
curl http://localhost:8081/metrics       # Prometheus metrics OK
```

## 3. Core Agent Workflow (5 min)

```lisp
;; Basic agent + cognitive cycle
(let ((agent (autopoiesis.agent:make-agent :name "test-agent" 
                                           :capabilities '(:introspect))))
  (autopoiesis.agent:start-agent agent)
  (autopoiesis.agent:cognitive-cycle agent '(:task "Hello world"))
  (length (autopoiesis.agent:agent-thought-stream agent)))  ; >0 thoughts?

;; Snapshot + time-travel
(let ((snap (autopoiesis.snapshot:make-snapshot)))
  (autopoiesis.snapshot:snapshot-id snap))  ; SHA-256 content hash
```

## 4. Validate Core Layers (10 min)

| Layer | Snippet | Expected Output |
|-------|---------|-----------------|
| **Substrate** | `(transact! (list (list "eid1" :attr1 "val1"))) (entity-attr "eid1" :attr1)` | `"val1"` |
| **Core** | `(compile-extension "test" '(lambda (x) (+ x 1)) :sandbox-level :strict)` | Compiled lambda func |
| **Agent** | `(autopoiesis.agent:spawn-agent agent :name "child")` | New child agent |
| **Snapshot** | `(autopoiesis.snapshot:create-branch "test-branch")` | Branch entity created |
| **Orchestration** | `(autopoiesis.orchestration:queue-event :test '(:data "foo"))` | Event queued & taken on tick |
| **Integration/API** | `curl -X POST http://localhost:8081/api/agents -H "Content-Type: application/json" -d '{"name":"api-agent"}'` | `{"id":"...","name":"api-agent"}` |
| **Interface** | `(autopoiesis.interface:cli-interact agent)` | Interactive CLI session starts |

## 5. Validate Optional Extensions (10 min)

| Extension | Snippet | Expected |
|-----------|---------|----------|
| **Swarm** | `(autopoiesis.swarm:evolve-persistent-agents (list agent) (autopoiesis.swarm:make-standard-pa-evaluator) '(:env) :generations 2)` | List of evolved agents |
| **Supervisor** | `(autopoiesis.supervisor:with-checkpoint (agent :label "test") (error "boom"))` | Agent state reverted |
| **Crystallize** | `(autopoiesis.crystallize:crystallize-capabilities agent)` | Lisp source files emitted |
| **Team** | `(autopoiesis.team:create-team "test-team" :strategy :parallel :members (list agent1 agent2))` | Team entity + workspace |
| **Jarvis** | `(autopoiesis.jarvis:start-jarvis-session)` | NL conversational loop starts |
| **Holodeck** | `(autopoiesis.holodeck:launch-holodeck)` | 3D viz window launches (GPU req) |

## 6. LLM Integration & Agentic Loops (5 min)

Set env: `export ANTHROPIC_API_KEY=sk-ant-your-key`

```lisp
(let ((claude (autopoiesis.integration:make-claude-code-provider :name "claude")))
  (autopoiesis.integration:register-provider claude)
  (let ((agent (autopoiesis.integration:make-provider-backed-agent 
                :name "claude-agent" :provider claude)))
    (autopoiesis.integration:provider-agent-prompt agent "Write Lisp fib(10)")))
```
Expected: Agent thoughts with fib code + result `55`.

## 7. Visualizations & Frontends (5 min)

**Backend running** (from step 2).

**Terminal 2:** Nexus TUI
```bash
cd nexus && cargo run --release  # Auto-connects to ws://localhost:8080/ws
```
- `Space a c`: Create agent
- `Space a t`: Step cognitive cycle
- `Space h`: Help overlay
- `Space d`: Toggle Holodeck viewport

**Terminal 3:** Standalone Holodeck
```bash
cd holodeck && cargo run --release  # Bevy 3D window with agent embodiment
```

## 8. Security, Monitoring & Production (3 min)

```bash
curl http://localhost:8081/security/permissions  # Permission matrix JSON
curl http://localhost:8081/audit/log             # Recent audit entries
curl http://localhost:8081/conductor/status      # Conductor health
```

**Docker Production Test:**
```bash
docker-compose up -d  # Full stack (REPL + API)
docker logs autopoiesis  # Conductor ticking, no errors
docker-compose down
```

## 9. Full E2E Agentic Workflow (5 min)

```lisp
;; Self-extending team swarm w/ checkpointing & crystallize
(let* ((lead (autopoiesis.agent:make-agent :name "lead" :capabilities '(:spawn)))
       (team (autopoiesis.team:create-team "dev-team" :strategy :pipeline :leader lead))
       (swarm (autopoiesis.swarm:make-population :size 5 :from lead)))
  (autopoiesis.supervisor:with-checkpoint (lead :label "swarm-evolve")
    (autopoiesis.swarm:evolve-generation swarm :generations 3)
    (autopoiesis.crystallize:export-to-git team "test-repo/")))  # Git export
```

## 10. Cleanup & Persistence Verification

```lisp
(autopoiesis.orchestration:stop-system)  # Graceful shutdown
```
```bash
ls -la test-store/  # LMDB files persist (datoms, blobs, indexes)
rm -rf test-store/  # Cleanup
```

## Validation Checklist

- [ ] `./scripts/test.sh` passes (core tests)
- [ ] All REPL snippets succeed
- [ ] Endpoints respond correctly
- [ ] Nexus/Holodeck connect & show agents
- [ ] LLM agent generates code
- [ ] Persistence: Restart REPL, reload store, agents restored
- [ ] Extensions load independently: `(ql:quickload :autopoiesis/swarm)`

## As Agentic Base (OpenClaw/Cursor Replacement)

- **NL→Tool:** Jarvis + provider-backed agents (Claude/Codex/OpenCode)
- **Self-Extend:** `defcapability`, compile-extension, swarm evolution
- **Team:** 5 strategies (pipeline for dev workflows)
- **Debug:** Snapshot branches, `sexpr-diff`, time-travel
- **Scale:** Substrate sharding, Docker/K8s (DEPLOYMENT.md)
- **Custom:** Fork repo, add caps/tools, `scud next` for tasks

**Issues?** Check `CLAUDE.md` signatures, logs, or `scud warmup`. System is production-ready for agentic dev! 🚀