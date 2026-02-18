# squashd Sandbox Integration Plan

## Overview

Integrate sq-sandbox's Common Lisp runtime (`squashd`) directly into Autopoiesis as a library dependency, providing container-isolated execution for evaluation trials and agent tasks. Both systems share the same SBCL runtime, so the integration is in-process — no HTTP layer, no serialization overhead. AP gains the ability to create isolated Linux sandboxes (overlayfs + namespace + cgroup), execute commands, snapshot/restore state, and track sandbox lifecycle via substrate datoms.

## Current State Analysis

**sq-sandbox (`~/projects/sq-sandbox/impl/cl/`):**
- 3,444 LOC across 20 files in a single `squashd` package
- ASDF system `"squashd"` with 15 dependencies (6 HTTP-only, 9 core)
- Manager API: `manager-create-sandbox`, `manager-exec`, `manager-snapshot`, `manager-restore`, `manager-destroy-sandbox`
- None of the manager functions are exported — all accessed via `squashd::` double-colon
- HTTP server files (`api.lisp`, `main.lisp`) are cleanly separable from core runtime

**autopoiesis (`~/projects/ap/`):**
- ASDF system `"autopoiesis"` with 13 dependencies
- Provider protocol: `provider` base class → `define-cli-provider` macro → `provider-result` → `provider-backed-agent`
- Orchestration: conductor tick loop + timer heap + substrate-backed events/workers
- Integration precedent: `inference-provider` subclasses `provider` and overrides `provider-invoke` directly (bypassing `run-provider-subprocess`)

### Key Discoveries:
- AP and squashd share 6 dependencies: `bordeaux-threads`, `ironclad`, `dexador`, `alexandria`, `local-time`, `cl-ppcre`
- squashd core-only deps not in AP: `cffi`, `jonathan`, `log4cl` (AP already has `log4cl`)
- squashd HTTP-only deps (excludable): `clack`, `woo`, `lack`, `lack/middleware/accesslog`, `ningle`, `trivial-mimes`
- The `inference-provider` pattern (override `provider-invoke` directly) is the right model — sandbox execution doesn't go through CLI subprocesses
- squashd requires Linux (overlayfs, unshare, setns, chroot, cgroups v2)

## Desired End State

After this plan is complete:

1. **sq-sandbox** has a new `squashd-core.asd` that loads only the runtime (no HTTP server)
2. **autopoiesis** has a new `autopoiesis/sandbox` ASDF system that depends on `squashd-core`
3. A `sandbox-provider` class wraps squashd's manager as an AP provider
4. Substrate entity types track sandbox lifecycle (`:sandbox-instance`, `:sandbox-exec`)
5. The conductor can dispatch sandbox-backed work via a new `:sandbox` action type
6. Tests verify the integration without requiring Linux (mock-based unit tests) plus integration tests that run on Linux

### Verification:
- `(asdf:load-system "autopoiesis/sandbox")` succeeds
- `(asdf:test-system "autopoiesis/sandbox-test")` passes all unit tests (any platform)
- On Linux with Docker: integration test creates a sandbox, execs a command, snapshots, restores, and destroys — confirming the full lifecycle through AP's provider protocol

## What We're NOT Doing

- **Evaluation framework**: task definitions, verifiers, campaign orchestration, reporting — all deferred
- **Distributed execution**: the conductor stays single-process; distributed dispatch is a separate concern
- **Docker integration**: we don't orchestrate Docker from AP; the host must already be a privileged Linux container
- **HTTP API**: we don't expose squashd's HTTP endpoints from AP; it's library-only
- **S3 sync**: S3 module sync support is available but not wired into AP's config

## Implementation Approach

Three-phase plan: first make squashd loadable as a library (changes in sq-sandbox), then build the AP integration layer, then add conductor dispatch.

---

## Phase 1: Extract squashd-core from sq-sandbox

### Overview
Create a minimal ASDF system in sq-sandbox that excludes the HTTP server, exports the manager API, and can be loaded as a library by any CL project.

### Changes Required:

#### 1. New ASDF system definition
**File**: `~/projects/sq-sandbox/impl/cl/squashd-core.asd`
**Changes**: New file — stripped system definition

```lisp
(asdf:defsystem "squashd-core"
  :description "sq-sandbox container runtime (library, no HTTP server)"
  :version "4.0.0"
  :depends-on ("cffi"
               "jonathan"
               "ironclad"
               "dexador"
               "bordeaux-threads"
               "alexandria"
               "local-time"
               "cl-ppcre"
               "log4cl")
  :pathname "src"
  :serial t
  :components ((:file "packages")
               (:file "config")
               (:file "validate")
               (:file "conditions")
               (:file "syscalls")
               (:file "mounts")
               (:file "cgroup")
               (:file "netns")
               (:file "exec")
               (:file "sandbox")
               (:file "firecracker")
               (:file "manager")
               (:file "meta")
               (:file "modules")
               (:file "secrets")
               (:file "s3")
               (:file "reaper")
               (:file "init")))
```

Excludes `api.lisp` and `main.lisp`. Drops `clack`, `woo`, `lack`, `lack/middleware/accesslog`, `ningle`, `trivial-mimes` from deps.

#### 2. Export manager API
**File**: `~/projects/sq-sandbox/impl/cl/src/packages.lisp`
**Changes**: Add exports for the manager functions, config, exec-result accessors, and sandbox struct

Add to the `(:export ...)` list:

```lisp
;; Config
#:config
#:make-config
#:config-from-env
#:config-data-dir
#:config-max-sandboxes
#:config-upper-limit-mb
#:config-backend

;; Manager
#:manager
#:make-manager
#:manager-create-sandbox
#:manager-destroy-sandbox
#:manager-exec
#:manager-snapshot
#:manager-restore
#:manager-activate-module
#:manager-sandbox-info
#:manager-sandbox-count
#:list-sandbox-infos
#:manager-exec-logs

;; Exec result
#:exec-result
#:exec-result-exit-code
#:exec-result-stdout
#:exec-result-stderr
#:exec-result-started
#:exec-result-finished
#:exec-result-duration-ms
#:exec-result-seq

;; Sandbox struct
#:sandbox
#:sandbox-id
#:sandbox-state
#:sandbox-created
#:sandbox-last-active
#:sandbox-exec-count

;; Modules
#:list-available-modules
#:module-exists-p

;; Recovery
#:init-recover

;; Reaper
#:reaper-loop
```

#### 3. Register sq-sandbox as ASDF source
**Action**: Ensure `~/projects/sq-sandbox/impl/cl/` is on the ASDF source registry. Add a symlink:

```bash
ln -sf ~/projects/sq-sandbox/impl/cl/squashd-core.asd ~/common-lisp/squashd-core.asd
# or add to ~/.config/common-lisp/source-registry.conf.d/
```

### Success Criteria:

#### Automated Verification:
- [ ] `(ql:quickload "squashd-core")` loads without error on SBCL (any platform where CFFI can find libc)
- [ ] `(find-symbol "MANAGER-CREATE-SANDBOX" :squashd)` returns a symbol with `:external` status
- [ ] `(find-symbol "MAKE-MANAGER" :squashd)` returns a symbol with `:external` status
- [ ] The original `(ql:quickload "squashd")` still works (backward compatible)

#### Manual Verification:
- [ ] On Linux: `(squashd:manager-create-sandbox mgr "test" :layers '("000-base-alpine"))` creates a sandbox
- [ ] On Linux: `(squashd:manager-exec mgr "test" "echo hello")` returns an `exec-result` with exit-code 0

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: AP Sandbox Integration Layer

### Overview
Create an `autopoiesis/sandbox` ASDF system that wraps squashd-core as an AP provider, adds substrate entity types for sandbox tracking, and integrates with the conductor.

### Changes Required:

#### 1. New ASDF system
**File**: `~/projects/ap/autopoiesis.asd` (append to existing file)
**Changes**: Add new system definition after the existing ones

```lisp
;;; Sandbox integration (squashd container runtime)
;;; Separate system requiring Linux + privileged container for full operation
(asdf:defsystem #:autopoiesis/sandbox
  :description "Container sandbox integration via squashd"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:autopoiesis
               #:squashd-core)
  :components
  ((:module "src/sandbox"
    :serial t
    :components
    ((:file "packages")
     (:file "entity-types")
     (:file "sandbox-provider")
     (:file "conductor-dispatch")))))
```

#### 2. Package definition
**File**: `~/projects/ap/src/sandbox/packages.lisp`
**Changes**: New file

```lisp
(defpackage #:autopoiesis.sandbox
  (:use #:cl #:alexandria)
  (:local-nicknames (#:bt #:bordeaux-threads)
                    (#:sq #:squashd))
  (:export
   ;; Provider
   #:sandbox-provider
   #:make-sandbox-provider
   ;; Entity types
   #:sandbox-instance-entity
   #:sandbox-exec-entity
   ;; Lifecycle
   #:start-sandbox-manager
   #:stop-sandbox-manager
   #:*sandbox-manager*
   ;; Conductor integration
   #:dispatch-sandbox-event))
```

#### 3. Substrate entity types
**File**: `~/projects/ap/src/sandbox/entity-types.lisp`
**Changes**: New file — defines `:sandbox-instance` and `:sandbox-exec` entity types

```lisp
(in-package #:autopoiesis.sandbox)

;;; Entity type for tracking sandbox lifecycle in the substrate
(autopoiesis.substrate:define-entity-type :sandbox-instance
  (:required-attributes
   :sandbox-instance/sandbox-id    ; string — maps to squashd sandbox id
   :sandbox-instance/status        ; :creating, :ready, :destroying, :destroyed
   :sandbox-instance/created-at)   ; unix timestamp
  (:optional-attributes
   :sandbox-instance/layers        ; list of layer names
   :sandbox-instance/owner         ; who requested this sandbox
   :sandbox-instance/task          ; what task this sandbox is for
   :sandbox-instance/destroyed-at  ; when it was destroyed
   :sandbox-instance/exec-count    ; total execs run in this sandbox
   :sandbox-instance/error))       ; error string if creation/destroy failed

;;; Entity type for tracking individual exec calls
(autopoiesis.substrate:define-entity-type :sandbox-exec
  (:required-attributes
   :sandbox-exec/sandbox-id        ; references sandbox-instance
   :sandbox-exec/command           ; the command string
   :sandbox-exec/exit-code         ; integer
   :sandbox-exec/started-at)       ; unix timestamp
  (:optional-attributes
   :sandbox-exec/finished-at       ; unix timestamp
   :sandbox-exec/duration-ms       ; integer
   :sandbox-exec/stdout            ; captured stdout (may be truncated)
   :sandbox-exec/stderr            ; captured stderr (may be truncated)
   :sandbox-exec/workdir           ; working directory
   :sandbox-exec/timeout           ; timeout in seconds
   :sandbox-exec/seq))             ; exec sequence number within sandbox
```

#### 4. Sandbox provider
**File**: `~/projects/ap/src/sandbox/sandbox-provider.lisp`
**Changes**: New file — wraps squashd manager as an AP provider

```lisp
(in-package #:autopoiesis.sandbox)

;;; ── Global sandbox manager ──────────────────────────────────────

(defvar *sandbox-manager* nil
  "The global squashd manager instance. Bound by start-sandbox-manager.")

(defun start-sandbox-manager (&key (data-dir "/data")
                                    (max-sandboxes 100)
                                    (upper-limit-mb 512)
                                    (backend :chroot))
  "Initialize the global sandbox manager.
   Must be called before any sandbox operations.
   DATA-DIR must exist and be writable."
  (setf *sandbox-manager*
        (sq:make-manager
         (sq:make-config :data-dir data-dir
                         :max-sandboxes max-sandboxes
                         :upper-limit-mb upper-limit-mb
                         :backend backend)))
  ;; Ensure directories exist
  (ensure-directories-exist
   (format nil "~A/sandboxes/" data-dir))
  (ensure-directories-exist
   (format nil "~A/modules/" data-dir))
  ;; Recover any existing sandboxes from disk
  (sq:init-recover *sandbox-manager*)
  *sandbox-manager*)

(defun stop-sandbox-manager ()
  "Destroy all sandboxes and clear the global manager."
  (when *sandbox-manager*
    (dolist (info (sq:list-sandbox-infos *sandbox-manager*))
      (ignore-errors
        (sq:manager-destroy-sandbox *sandbox-manager*
                                    (getf info :|id|))))
    (setf *sandbox-manager* nil)))

;;; ── Sandbox provider class ──────────────────────────────────────

(defclass sandbox-provider (autopoiesis.integration:provider)
  ((default-layers :initarg :default-layers
                   :accessor sandbox-default-layers
                   :initform '("000-base-alpine")
                   :documentation "Default squashfs layers for new sandboxes")
   (default-memory-mb :initarg :default-memory-mb
                      :accessor sandbox-default-memory-mb
                      :initform 1024
                      :documentation "Default memory limit in MB")
   (default-cpu :initarg :default-cpu
                :accessor sandbox-default-cpu
                :initform 2.0
                :documentation "Default CPU quota")
   (default-max-lifetime-s :initarg :default-max-lifetime-s
                           :accessor sandbox-default-max-lifetime-s
                           :initform 3600
                           :documentation "Default max sandbox lifetime in seconds"))
  (:default-initargs :name "sandbox" :timeout 300)
  (:documentation "Provider that executes commands in squashd container sandboxes.
Overrides provider-invoke to use squashd manager directly (no CLI subprocess)."))

(defun make-sandbox-provider (&key (name "sandbox")
                                    (default-layers '("000-base-alpine"))
                                    (default-memory-mb 1024)
                                    (default-cpu 2.0)
                                    (default-max-lifetime-s 3600)
                                    (timeout 300))
  "Create a sandbox provider instance."
  (make-instance 'sandbox-provider
                 :name name
                 :timeout timeout
                 :default-layers default-layers
                 :default-memory-mb default-memory-mb
                 :default-cpu default-cpu
                 :default-max-lifetime-s default-max-lifetime-s))

;;; ── Provider protocol implementation ────────────────────────────

(defmethod autopoiesis.integration:provider-supported-modes
    ((provider sandbox-provider))
  '(:one-shot))

(defmethod autopoiesis.integration:provider-invoke
    ((provider sandbox-provider) prompt
     &key tools mode agent-id)
  "Execute PROMPT as a shell command inside a sandbox.
   Creates a sandbox, runs the command, captures output, destroys sandbox.
   Returns a provider-result.

   The PROMPT is treated as a shell command string.
   TOOLS, MODE, and AGENT-ID are accepted for protocol compatibility
   but not used by the sandbox provider."
  (declare (ignore tools mode))
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized. Call start-sandbox-manager first."))

  (let* ((sandbox-id (format nil "ap-~A" (autopoiesis.core:make-uuid)))
         (start-time (get-internal-real-time))
         (timeout (autopoiesis.integration:provider-timeout provider))
         (sandbox-eid nil)
         (exec-eid nil))

    ;; Emit provider-request event
    (autopoiesis.integration:emit-integration-event
     :provider-request
     :source (autopoiesis.integration:provider-name provider)
     :agent-id agent-id
     :data (list :prompt (if (> (length prompt) 200)
                             (subseq prompt 0 200)
                             prompt)))

    ;; Track sandbox in substrate
    (setf sandbox-eid (autopoiesis.substrate:intern-id
                       (format nil "sandbox:~A" sandbox-id)))
    (autopoiesis.substrate:transact!
     (list (autopoiesis.substrate:make-datom
            sandbox-eid :sandbox-instance/sandbox-id sandbox-id)
           (autopoiesis.substrate:make-datom
            sandbox-eid :sandbox-instance/status :creating)
           (autopoiesis.substrate:make-datom
            sandbox-eid :sandbox-instance/created-at
            (get-universal-time))
           (autopoiesis.substrate:make-datom
            sandbox-eid :sandbox-instance/layers
            (sandbox-default-layers provider))))

    (unwind-protect
         (handler-case
             (progn
               ;; Create sandbox
               (sq:manager-create-sandbox
                *sandbox-manager* sandbox-id
                :layers (sandbox-default-layers provider)
                :memory-mb (sandbox-default-memory-mb provider)
                :cpu (sandbox-default-cpu provider)
                :max-lifetime-s (sandbox-default-max-lifetime-s provider))

               ;; Update substrate status
               (autopoiesis.substrate:transact!
                (list (autopoiesis.substrate:make-datom
                       sandbox-eid :sandbox-instance/status :ready)))

               ;; Execute the command
               (let ((exec-result (sq:manager-exec
                                   *sandbox-manager* sandbox-id prompt
                                   :timeout timeout)))
                 ;; Track exec in substrate
                 (setf exec-eid (autopoiesis.substrate:intern-id
                                 (format nil "exec:~A:~D"
                                         sandbox-id
                                         (sq:exec-result-seq exec-result))))
                 (autopoiesis.substrate:transact!
                  (list (autopoiesis.substrate:make-datom
                         exec-eid :sandbox-exec/sandbox-id sandbox-id)
                        (autopoiesis.substrate:make-datom
                         exec-eid :sandbox-exec/command prompt)
                        (autopoiesis.substrate:make-datom
                         exec-eid :sandbox-exec/exit-code
                         (sq:exec-result-exit-code exec-result))
                        (autopoiesis.substrate:make-datom
                         exec-eid :sandbox-exec/started-at
                         (sq:exec-result-started exec-result))
                        (autopoiesis.substrate:make-datom
                         exec-eid :sandbox-exec/finished-at
                         (sq:exec-result-finished exec-result))
                        (autopoiesis.substrate:make-datom
                         exec-eid :sandbox-exec/duration-ms
                         (sq:exec-result-duration-ms exec-result))
                        (autopoiesis.substrate:make-datom
                         exec-eid :sandbox-exec/stdout
                         (sq:exec-result-stdout exec-result))
                        (autopoiesis.substrate:make-datom
                         exec-eid :sandbox-exec/stderr
                         (sq:exec-result-stderr exec-result))
                        (autopoiesis.substrate:make-datom
                         exec-eid :sandbox-exec/seq
                         (sq:exec-result-seq exec-result))))

                 ;; Build provider-result
                 (let* ((end-time (get-internal-real-time))
                        (duration (/ (- end-time start-time)
                                     internal-time-units-per-second))
                        (result (autopoiesis.integration:make-provider-result
                                 :text (sq:exec-result-stdout exec-result)
                                 :exit-code (sq:exec-result-exit-code exec-result)
                                 :error-output (sq:exec-result-stderr exec-result)
                                 :raw-output (sq:exec-result-stdout exec-result)
                                 :duration duration
                                 :provider-name
                                 (autopoiesis.integration:provider-name provider)
                                 :metadata (list
                                            :sandbox-id sandbox-id
                                            :sandbox-eid sandbox-eid
                                            :exec-eid exec-eid
                                            :duration-ms
                                            (sq:exec-result-duration-ms
                                             exec-result)))))

                   ;; Emit provider-response event
                   (autopoiesis.integration:emit-integration-event
                    :provider-response
                    :source (autopoiesis.integration:provider-name provider)
                    :agent-id agent-id
                    :data (list :exit-code (sq:exec-result-exit-code exec-result)
                                :duration duration
                                :sandbox-id sandbox-id))

                   result)))

           ;; Handle errors
           (error (e)
             (autopoiesis.substrate:transact!
              (list (autopoiesis.substrate:make-datom
                     sandbox-eid :sandbox-instance/status :error)
                    (autopoiesis.substrate:make-datom
                     sandbox-eid :sandbox-instance/error
                     (format nil "~A" e))))
             (autopoiesis.integration:make-provider-result
              :text (format nil "Sandbox error: ~A" e)
              :exit-code -1
              :error-output (format nil "~A" e)
              :provider-name
              (autopoiesis.integration:provider-name provider))))

      ;; Cleanup: always destroy sandbox
      (ignore-errors
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom
                sandbox-eid :sandbox-instance/status :destroying)))
        (sq:manager-destroy-sandbox *sandbox-manager* sandbox-id)
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom
                sandbox-eid :sandbox-instance/status :destroyed)
               (autopoiesis.substrate:make-datom
                sandbox-eid :sandbox-instance/destroyed-at
                (get-universal-time))))))))
```

#### 5. Conductor dispatch integration
**File**: `~/projects/ap/src/sandbox/conductor-dispatch.lisp`
**Changes**: New file — adds sandbox action type to conductor

```lisp
(in-package #:autopoiesis.sandbox)

;;; ── Conductor sandbox dispatch ──────────────────────────────────
;;;
;;; Extends the conductor to handle :sandbox action types.
;;; This follows the same pattern as :claude actions in conductor.lisp.

(defun dispatch-sandbox-event (conductor action-plist)
  "Handle a :sandbox action from the conductor timer heap.
   Creates a sandbox, executes the command, and reports results
   back via handle-task-result.

   ACTION-PLIST keys:
     :command   - Shell command to execute (required)
     :task-id   - Unique task identifier (auto-generated if missing)
     :layers    - List of squashfs layer names (optional)
     :memory-mb - Memory limit (optional)
     :cpu       - CPU quota (optional)
     :timeout   - Exec timeout in seconds (optional, default 300)
     :workdir   - Working directory inside sandbox (optional, default \"/\")
     :on-complete - Callback (lambda (result)) for success
     :on-error    - Callback (lambda (reason)) for failure"
  (unless *sandbox-manager*
    (error "Sandbox manager not initialized"))

  (let* ((command (getf action-plist :command))
         (task-id (or (getf action-plist :task-id)
                      (format nil "sandbox-~A"
                              (autopoiesis.core:make-uuid))))
         (layers (getf action-plist :layers))
         (memory-mb (getf action-plist :memory-mb 1024))
         (cpu (getf action-plist :cpu 2.0))
         (timeout (getf action-plist :timeout 300))
         (workdir (getf action-plist :workdir "/"))
         (on-complete (getf action-plist :on-complete))
         (on-error (getf action-plist :on-error))
         (sandbox-id (format nil "cond-~A" task-id)))

    ;; Register worker in substrate
    (autopoiesis.orchestration:register-worker conductor task-id
                                               (bt:current-thread))

    ;; Spawn worker thread
    (bt:make-thread
     (lambda ()
       (handler-case
           (progn
             ;; Create sandbox
             (sq:manager-create-sandbox
              *sandbox-manager* sandbox-id
              :layers (or layers '("000-base-alpine"))
              :memory-mb memory-mb
              :cpu cpu
              :max-lifetime-s (+ timeout 60)) ; lifetime > exec timeout

             (unwind-protect
                  (let ((exec-result (sq:manager-exec
                                      *sandbox-manager* sandbox-id
                                      command
                                      :workdir workdir
                                      :timeout timeout)))
                    (if (zerop (sq:exec-result-exit-code exec-result))
                        (when on-complete
                          (funcall on-complete
                                   (list :exit-code 0
                                         :stdout (sq:exec-result-stdout
                                                  exec-result)
                                         :stderr (sq:exec-result-stderr
                                                  exec-result)
                                         :duration-ms
                                         (sq:exec-result-duration-ms
                                          exec-result)
                                         :sandbox-id sandbox-id)))
                        (when on-error
                          (funcall on-error
                                   (list :exit-code
                                         (sq:exec-result-exit-code
                                          exec-result)
                                         :stderr (sq:exec-result-stderr
                                                  exec-result))))))

               ;; Always destroy sandbox
               (ignore-errors
                 (sq:manager-destroy-sandbox *sandbox-manager*
                                             sandbox-id))))
         (error (e)
           (when on-error
             (funcall on-error (list :error (format nil "~A" e)))))))
     :name (format nil "sandbox-worker-~A" task-id))))
```

### Success Criteria:

#### Automated Verification:
- [ ] `(asdf:load-system "autopoiesis/sandbox")` compiles without warnings
- [ ] All symbols in `autopoiesis.sandbox` package are properly exported
- [ ] `(make-sandbox-provider)` creates an instance inheriting from `provider`
- [ ] `(autopoiesis.integration:provider-supported-modes (make-sandbox-provider))` returns `(:one-shot)`
- [ ] Existing AP tests still pass: `(asdf:test-system "autopoiesis/test")`

#### Manual Verification:
- [ ] On a privileged Linux container with squashfs modules available:
  - `(start-sandbox-manager :data-dir "/data")` succeeds
  - `(autopoiesis.integration:provider-invoke (make-sandbox-provider) "echo hello")` returns a `provider-result` with exit-code 0 and text "hello\n"
  - Substrate datoms for `:sandbox-instance` and `:sandbox-exec` are present
  - `(stop-sandbox-manager)` cleans up

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Tests

### Overview
Add a test system for the sandbox integration with mock-based unit tests (any platform) and integration tests (Linux only).

### Changes Required:

#### 1. Test system definition
**File**: `~/projects/ap/autopoiesis.asd` (append)
**Changes**: Add test system

```lisp
;;; Sandbox integration tests
(asdf:defsystem #:autopoiesis/sandbox-test
  :description "Tests for sandbox integration"
  :depends-on (#:autopoiesis/sandbox #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "sandbox-tests"))))
  :perform (test-op (o c)
             (symbol-call :autopoiesis.sandbox.test :run-sandbox-tests)))
```

#### 2. Test file
**File**: `~/projects/ap/test/sandbox-tests.lisp`
**Changes**: New file with unit tests

Tests should cover:
- `make-sandbox-provider` creates a valid provider instance
- Provider has correct default slots (layers, memory, cpu, timeout)
- `provider-supported-modes` returns `(:one-shot)`
- Entity type registration works (`:sandbox-instance`, `:sandbox-exec`)
- `start-sandbox-manager` / `stop-sandbox-manager` lifecycle (mocked — verify `*sandbox-manager*` bindings)
- `provider-invoke` substrate tracking: verify datoms are written for sandbox creation, exec, and destruction (with a mock manager that returns canned exec-results)
- `dispatch-sandbox-event` spawns a thread and calls callbacks (with a mock manager)
- Error handling: provider-invoke returns error result when manager signals `sandbox-error`

The mock strategy: define a `mock-manager` struct that matches the squashd API surface, bind `*sandbox-manager*` to it during tests, and verify calls/results. This avoids requiring Linux for unit tests.

### Success Criteria:

#### Automated Verification:
- [ ] `(asdf:test-system "autopoiesis/sandbox-test")` passes on macOS/Linux
- [ ] All existing AP tests still pass: `(asdf:test-system "autopoiesis/test")`

---

## Testing Strategy

### Unit Tests (any platform):
- Provider class instantiation and protocol compliance
- Substrate entity type registration
- Manager lifecycle (start/stop) with mocked squashd
- Provider-invoke flow with mocked manager (verify datoms, events, result construction)
- Error handling paths (sandbox-error, manager not initialized)
- Conductor dispatch integration with mocked manager

### Integration Tests (Linux + privileged Docker):
- Full lifecycle: create → exec → snapshot → restore → exec → destroy
- Verify `provider-result` fields match actual exec output
- Verify substrate datoms reflect real sandbox state
- Timeout behavior (exec exceeds timeout)
- Multiple concurrent sandboxes via conductor dispatch

### Manual Testing Steps:
1. Build a Docker image with SBCL + Quicklisp + squashd modules
2. Load `autopoiesis/sandbox` inside the container
3. Run `start-sandbox-manager`
4. Execute `provider-invoke` with various commands
5. Verify sandbox cleanup (no orphaned mounts or namespaces)

## Performance Considerations

- Sandbox creation involves disk I/O (mount operations) — expect 100-500ms per sandbox
- Exec overhead is fork + unshare + chroot — minimal after sandbox is created
- For evaluation campaigns with many trials, consider a pool of pre-created sandboxes with snapshot/restore instead of create/destroy per trial
- The `manager-snapshot` → `manager-restore` cycle is faster than full create/destroy because it skips mount/netns/cgroup setup

## References

- SkillsBench paper analysis: `thoughts/shared/research/2026-02-17-skillsbench-agent-evaluation-platform-feasibility.md`
- AP provider system: `src/integration/provider.lisp`, `src/integration/provider-inference.lisp`
- AP conductor: `src/orchestration/conductor.lisp`, `src/orchestration/claude-worker.lisp`
- AP substrate entity types: `src/substrate/builtin-types.lisp`, `src/substrate/entity-type.lisp`
- sq-sandbox CL runtime: `~/projects/sq-sandbox/impl/cl/src/manager.lisp`
- sq-sandbox exec path: `~/projects/sq-sandbox/impl/cl/src/exec.lisp`
- sq-sandbox conditions/restarts: `~/projects/sq-sandbox/impl/cl/src/conditions.lisp`
