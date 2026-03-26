# Monorepo Modularization Plan

## Reference: Pi Monorepo (badlogic/pi-mono)

Pi uses a `packages/` directory where each package is self-contained with its own
build config, src, and tests. Dependencies form a strict tiered hierarchy:

```
Tier 1 (Foundation):  pi-ai, pi-tui           (zero internal deps)
Tier 2 (Infra):       pi-agent-core           (depends on pi-ai)
Tier 3 (Apps):        pi-coding-agent, pi-mom  (depends on lower tiers)
```

Extensions are trivially easy to add — drop a file, export a function, register
tools/capabilities. A root build script orchestrates everything in dependency order.

We adopt the same philosophy, adapted for Common Lisp + polyglot.

---

## Current State

```
autopoiesis/
  platform/              # ALL Common Lisp code
    substrate.asd        # Already standalone ASDF system
    autopoiesis.asd      # 670-line file with 15+ ASDF system definitions
    src/                 # 25 subdirectories, flat
    test/                # All tests in one directory
    scripts/             # build.sh, test.sh
    docs/                # specs, layers.md
    vendor/              # vendored CL deps
  dag-explorer/          # SolidJS web frontend (Command Center)
  holodeck/              # Rust 3D holodeck
  nexus/                 # Rust workspace (5 crates)
  sdk/                   # Go SDK
  tui/                   # Go TUI
  e2e/                   # Shell integration tests
```

Problems:
1. Everything CL lives in `platform/` with a single monolithic `.asd`
2. Extensions are defined as subsystems of the main .asd, not self-contained
3. No clear "here's how to add an extension" pattern
4. Tests are all in one directory, not co-located with their package
5. Not obvious which pieces are standalone vs. coupled

---

## Proposed Structure

Following Pi's `packages/` convention:

```
autopoiesis/
  packages/
    substrate/                    # Tier 1: Standalone datom store
      substrate.asd
      src/
        packages.lisp
        conditions.lisp
        context.lisp
        intern.lisp
        encoding.lisp
        datom.lisp
        entity.lisp
        query.lisp
        store.lisp
        linda.lisp
        datalog.lisp
        entity-type.lisp
        system.lisp
        lmdb-backend.lisp
        blob.lisp
        builtin-types.lisp        # (from core's substrate module)
        migration.lisp            # (from core's substrate module)
      test/
        substrate-tests.lisp
      README.md

    core/                         # Tier 2: Core platform
      autopoiesis.asd
      src/
        core/                     # S-expr, cognitive primitives, persistent structs
        agent/                    # Agent runtime, capabilities, persistent agents
        snapshot/                 # Content-addressable storage, branching, time-travel
        orchestration/            # Conductor, event queue, workers
        conversation/             # Turn-based context
        integration/              # Claude bridge, MCP, providers, agentic loops
        skel/                     # Typed LLM functions, BAML
        interface/                # Navigator, viewport, CLI session
        viz/                      # 2D terminal timeline
        security/                 # Permissions, audit
        monitoring/               # Metrics, health
        api/                      # REST server, MCP server, SSE
        autopoiesis.lisp          # Reexport package
      test/
        packages.lisp
        core-tests.lisp
        agent-tests.lisp
        snapshot-tests.lisp
        orchestration-tests.lisp
        conversation-tests.lisp
        integration-tests.lisp
        interface-tests.lisp
        viz-tests.lisp
        security-tests.lisp
        monitoring-tests.lisp
        rest-api-tests.lisp
        provider-tests.lisp
        prompt-registry-tests.lisp
        agentic-tests.lisp
        bridge-protocol-tests.lisp
        meta-agent-tests.lisp
        skel-tests.lisp
        persistent-agent-tests.lisp
        learning-integration-tests.lisp
        mailbox-integration-tests.lisp
        e2e-tests.lisp
        live-llm-tests.lisp
        run-tests.lisp
      README.md

    api-server/                   # Tier 3: WebSocket API server (Clack/Woo)
      api-server.asd
      src/
        packages.lisp
        wire-format.lisp
        serializers.lisp
        connections.lisp
        handlers.lisp
        team-handlers.lisp
        chat-handlers.lisp
        agent-runtime.lisp
        holodeck-sync.lisp
        events.lisp
        activity-tracker.lisp
        holodeck-bridge.lisp
        web-console.lisp
        server.lisp
      test/
        api-tests.lisp
      README.md

    # --- Extensions (Tier 3, each depends only on core) ---

    jarvis/                       # NL->tool conversational loop
      jarvis.asd
      src/
      test/
      README.md

    swarm/                        # Genome evolution, persistent evolution
      swarm.asd
      src/
      test/
      README.md

    team/                         # Multi-agent coordination + workspace
      team.asd
      src/
      test/
      README.md

    supervisor/                   # Checkpoint/revert
      supervisor.asd
      src/
      test/
      README.md

    crystallize/                  # Runtime->source emission
      crystallize.asd
      src/
      test/
      README.md

    holodeck-ecs/                 # CL-side ECS for 3D viz
      holodeck-ecs.asd
      src/
      test/
      README.md

    sandbox/                      # Container runtime (squashd)
      sandbox.asd
      src/
      test/
      README.md

    research/                     # Parallel campaigns
      research.asd
      src/
      test/
      README.md

    eval/                         # Agent evaluation platform
      eval.asd
      src/
      test/
      README.md

    paperclip/                    # BYOA adapter
      paperclip.asd
      src/
      test/
      README.md

  # --- Frontends (consume the API, no CL dependency) ---

  frontends/
    command-center/               # SolidJS web UI (renamed from dag-explorer)
      package.json
      src/
      README.md
    tui/                          # Go TUI
      go.mod
      cmd/
      internal/
      README.md

  # --- Standalone applications ---

  holodeck/                       # Rust 3D holodeck (unchanged)
  nexus/                          # Rust workspace (unchanged)
  sdk/                            # Go SDK (unchanged)

  # --- Cross-cutting ---

  e2e/                            # Integration tests
  docs/                           # Moved from platform/docs
    specs/
    layers.md
    DEPLOYMENT.md
  scripts/                        # Root build/test orchestration
    build.sh
    test.sh
  vendor/                         # Vendored CL deps (moved from platform/vendor)

  CLAUDE.md
  README.md
  shell.nix
  Tiltfile
  lefthook.yml
```

---

## Dependency Tiers

```
Tier 1 (Foundation):
  substrate                     (zero internal deps, standalone datom store)

Tier 2 (Core Platform):
  core/autopoiesis              (depends on: substrate)

Tier 3 (Extensions + Apps):
  jarvis                        (depends on: autopoiesis)
  swarm                         (depends on: autopoiesis, lparallel)
  team                          (depends on: autopoiesis)
  supervisor                    (depends on: autopoiesis)
  crystallize                   (depends on: autopoiesis)
  holodeck-ecs                  (depends on: autopoiesis, 3d-vectors, 3d-matrices, cl-fast-ecs)
  sandbox                       (depends on: autopoiesis, squashd-core)
  research                      (depends on: autopoiesis, sandbox)
  eval                          (depends on: autopoiesis)
  paperclip                     (depends on: autopoiesis)
  api-server                    (depends on: autopoiesis, clack, woo, websocket-driver)

Tier 4 (Frontends — no CL deps):
  command-center                (SolidJS, consumes REST/WS API)
  tui                           (Go, consumes REST/WS API)
  holodeck                      (Rust, consumes REST/WS API)
  nexus                         (Rust, consumes REST/WS API)
```

---

## ASDF Configuration

### How ASDF finds packages

Root `build.sh` and `test.sh` push all package directories onto
`asdf:*central-registry*`:

```lisp
;; Auto-discover all packages
(dolist (asd (directory "packages/*/"))
  (push asd asdf:*central-registry*))
```

Each package has its own `.asd` at its root. No more monolithic file.

### Extension template

Adding a new extension is as simple as:

```
packages/
  my-extension/
    my-extension.asd
    src/
      packages.lisp
      my-extension.lisp
    test/
      my-extension-tests.lisp
    README.md
```

With `my-extension.asd`:
```lisp
(asdf:defsystem #:autopoiesis/my-extension
  :description "My extension for Autopoiesis"
  :depends-on (#:autopoiesis)
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "my-extension"))))
  :in-order-to ((test-op (test-op #:autopoiesis/my-extension-test))))

(asdf:defsystem #:autopoiesis/my-extension-test
  :depends-on (#:autopoiesis/my-extension #:fiveam)
  :components
  ((:module "test"
    :components
    ((:file "my-extension-tests"))))
  :perform (test-op (o c)
    (symbol-call :autopoiesis.my-extension.test :run-tests)))
```

And `packages.lisp`:
```lisp
(defpackage #:autopoiesis.my-extension
  (:use #:cl #:alexandria #:autopoiesis.core)
  (:export
   ;; Public API symbols
   ))
```

### Runtime extension registration (existing mechanism, unchanged)

The existing `*extension-registry*` in `core/extension-compiler.lisp` already
supports runtime registration:

```lisp
(register-extension agent-id code)
(find-extension name)
(list-extensions)
(install-extension extension)    ; checks deps before installing
(invoke-extension extension-id)  ; with checkpoint wrapping if supervisor loaded
```

---

## Build Orchestration

### Root build.sh

```bash
#!/bin/bash
# Build all packages in dependency order
PACKAGES=(
  packages/substrate
  packages/core
  # Extensions (alphabetical, all depend only on core)
  packages/api-server
  packages/crystallize
  packages/eval
  packages/holodeck-ecs
  packages/jarvis
  packages/paperclip
  packages/research
  packages/sandbox
  packages/supervisor
  packages/swarm
  packages/team
)

# Push all package dirs to ASDF registry, then load
sbcl --noinform --non-interactive \
  --eval "(dolist (p '(${PACKAGES[@]/#/\"}))
            (push (truename p) asdf:*central-registry*))" \
  --eval "(ql:quickload :autopoiesis :silent t)" \
  --eval "(format t \"~&Build successful.~%\")"
```

### Root test.sh

```bash
#!/bin/bash
# Test all packages
# Core tests
sbcl ... --eval "(asdf:test-system :autopoiesis)"

# Extension tests (each independent, can run in parallel)
for ext in packages/jarvis packages/swarm packages/team ...; do
  name=$(basename $ext)
  sbcl ... --eval "(asdf:test-system :autopoiesis/$name)" &
done
wait
```

---

## Migration Steps

### Phase 1: Scaffold (no file moves yet)
1. Create `packages/` directory
2. Create branch `claude/modularize-monorepo-structure-BMsza`

### Phase 2: Extract substrate
1. Move `platform/substrate.asd` -> `packages/substrate/substrate.asd`
2. Move `platform/src/substrate/*.lisp` -> `packages/substrate/src/`
3. Move `platform/src/substrate/builtin-types.lisp` and `migration.lisp`
   from core's substrate module into `packages/substrate/src/`
4. Move `platform/test/substrate-tests.lisp` -> `packages/substrate/test/`
5. Update `substrate.asd` pathnames
6. Verify: `(ql:quickload :substrate)` works standalone

### Phase 3: Extract core
1. Create `packages/core/autopoiesis.asd` with just the core system + test system
2. Move `platform/src/{core,agent,snapshot,orchestration,conversation,integration,skel,interface,viz,security,monitoring,api}` -> `packages/core/src/`
3. Move `platform/src/autopoiesis.lisp` -> `packages/core/src/`
4. Move relevant test files -> `packages/core/test/`
5. Update pathnames in `.asd`
6. Verify: `(ql:quickload :autopoiesis)` works

### Phase 4: Extract extensions (one by one)
For each of {jarvis, swarm, team, supervisor, crystallize, holodeck-ecs, sandbox, research, eval, paperclip}:
1. Create `packages/<name>/<name>.asd` (extracted from monolithic file)
2. Move `platform/src/<name>/` -> `packages/<name>/src/`
3. Move `platform/test/<name>-tests.lisp` -> `packages/<name>/test/`
4. Verify: `(asdf:test-system :autopoiesis/<name>)` passes

### Phase 5: Extract api-server
1. Create `packages/api-server/api-server.asd`
2. Move WebSocket API files -> `packages/api-server/src/`
3. Move `platform/test/api-tests.lisp` -> `packages/api-server/test/`

### Phase 6: Reorganize frontends
1. Move `dag-explorer/` -> `frontends/command-center/`
2. Move `tui/` -> `frontends/tui/`
3. Update any references (Tiltfile, docker-compose, e2e scripts)

### Phase 7: Move cross-cutting files
1. Move `platform/docs/` -> `docs/`
2. Move `platform/vendor/` -> `vendor/`
3. Move `platform/scripts/` -> `scripts/` (rewrite for new paths)
4. Update `Dockerfile`, `docker-compose.yml`, `Tiltfile`
5. Remove empty `platform/` directory

### Phase 8: Documentation
1. Write per-package READMEs
2. Rewrite top-level README as monorepo guide
3. Update CLAUDE.md with new paths and structure
4. Add `CONTRIBUTING.md` with "how to add an extension" guide
5. Add `packages/EXTENSION_TEMPLATE/` as a copyable starting point

### Phase 9: Verify
1. Run full test suite
2. Verify Docker build
3. Verify e2e tests
4. Verify frontends still connect

---

## Extension Developer Experience

### Adding a new extension

1. Copy `packages/EXTENSION_TEMPLATE/` to `packages/my-thing/`
2. Rename files and update package names
3. Implement your extension in `src/`
4. Write tests in `test/`
5. Run `(asdf:test-system :autopoiesis/my-thing)`

### Using just the substrate

```lisp
;; In your .asd:
:depends-on (#:substrate)

;; In your code:
(substrate:with-store (:path "/tmp/my-store")
  (substrate:transact! '((:e 1 :name "hello"))))
```

### Using core without extensions

```lisp
;; In your .asd:
:depends-on (#:autopoiesis)

;; Full agent platform, no extensions loaded
```

### Cherry-picking extensions

```lisp
;; Load just what you need
(ql:quickload '(:autopoiesis :autopoiesis/jarvis :autopoiesis/team))
```

---

## What Does NOT Change

- All CL package names (`autopoiesis.substrate`, `autopoiesis.core`, etc.)
- All function signatures and public APIs
- The ASDF dependency graph between systems
- `nexus/`, `holodeck/` (Rust), `sdk/` (Go) stay at top level
- Test logic — only file locations change
- The extension registry mechanism in core
- Docker deployment model (just path updates)
