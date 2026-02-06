---
date: 2026-02-04T10:00:00-08:00
author: reuben
branch: main
repository: ap
topic: "Workspace Architecture & Agent Projects Plan"
tags: [plan, architecture, workspace, extensions, storage, archil, s3, compliance, infrastructure]
status: draft
last_updated: 2026-02-04
last_updated_by: reuben
last_updated_note: "Initial plan document"
---

# Plan: Workspace Architecture & Agent Projects

**Date**: 2026-02-04
**Author**: reuben
**Status**: Draft

## Executive Summary

This plan establishes the architecture for organizing Autopoiesis as a platform that supports multiple distinct agent projects. It addresses:

1. **Monorepo structure** — Clear separation between framework core, extensions, shared resources, and agent projects
2. **Runtime extension loading** — Dynamic loading with precompiled FASL support
3. **Per-project storage** — Isolated namespaces backed by Archil/S3 for seamless local-to-cloud operation
4. **Initial projects** — Compliance Agent and Infrastructure Healer as first implementations

## Background & Motivation

The research document `2026-02-03-autopoiesis-real-agent-use-cases.md` identified 20 powerful agent use cases. These fall into three categories:

| Category | Description | Examples |
|----------|-------------|----------|
| **Framework Core** | Changes to primitives | Multi-model arbitrage, neuro-symbolic reasoning |
| **Framework Extensions** | New reusable capabilities | Inter-agent messaging, MCP SDK, knowledge graphs |
| **Agent Applications** | Compositions of existing primitives | Compliance, Infra Healer, SOAR, Living Docs |

To support developing these in parallel without interference, we need:
- Clear boundaries between layers
- Per-project isolation (storage, capabilities, branches)
- Shared resources (MCP servers, common capabilities)
- Simple project management

## Architecture Decisions

### Decision 1: Monorepo

**Chosen**: Single repository with clear directory boundaries

**Rationale**:
- Atomic changes across framework and projects
- Easier dependency management
- Single CI/CD pipeline
- Shared tooling (ralph/, scripts/)

**Trade-offs accepted**:
- Larger repository size over time
- Need discipline to maintain boundaries

### Decision 2: Runtime Loading with Precompiled Support

**Chosen**: ASDF-based dynamic loading with automatic FASL caching

**Rationale**:
- ASDF already handles compile-once-load-fast
- No custom build tooling needed
- Extensions can be developed and tested independently
- Precompiled FASLs cached in `~/.cache/common-lisp/`

**Mechanism**:
- First load: Compiles to FASL
- Subsequent loads: Uses cached FASL (fast)
- Source changes: Automatic recompilation
- Force recompile: `(load-extension "name" :force-recompile t)`

### Decision 3: Per-Project Storage with Archil/S3

**Chosen**: Each project gets isolated S3-backed namespace via Archil

**Rationale**:
- SQLite + local files "just work" 
- Seamless local development with cloud persistence
- No code changes to existing snapshot system
- Natural multi-machine sync
- S3 durability without infrastructure complexity

**Layout**:
```
/mnt/archil/                          # Archil mount point
├── projects/
│   ├── compliance-agent/
│   │   ├── state.db                  # Project metadata, agent registry
│   │   ├── snapshots/XX/UUID.sexpr   # Content-addressable snapshots
│   │   ├── agents/{id}/              # Per-agent state
│   │   └── branches/                 # Branch metadata
│   └── infra-healer/
│       └── ...
└── shared/
    ├── capabilities/                 # Shared capability definitions
    └── mcp-cache/                    # MCP server caches
```

### Decision 4: Initial Projects

**Chosen**: Compliance Agent and Infrastructure Healer first

**Rationale**:
- **Compliance**: Read-heavy (scan, detect, report), exercises audit trail
- **Infra Healer**: Write-capable, exercises human-in-the-loop approval gates
- Both need Kubernetes MCP server (shared work)
- Different approval models (report vs. remediate)
- Separate worktree for HVM4/reasoning exploration

---

## Monorepo Directory Structure

```
ap/
├── autopoiesis.asd                    # Main system (core only)
│
├── src/                               # Core framework (EXISTING)
│   ├── core/
│   │   ├── packages.lisp
│   │   ├── s-expr.lisp
│   │   ├── cognitive-primitives.lisp
│   │   ├── thought-stream.lisp
│   │   ├── extension-compiler.lisp
│   │   ├── recovery.lisp
│   │   ├── profiling.lisp
│   │   ├── config.lisp
│   │   ├── conditions.lisp
│   │   ├── extension-loader.lisp      # NEW: Extension/project loading
│   │   └── project-storage.lisp       # NEW: Per-project storage
│   ├── agent/
│   ├── snapshot/
│   ├── interface/
│   ├── viz/
│   ├── holodeck/
│   ├── integration/
│   ├── security/
│   ├── monitoring/
│   └── autopoiesis.lisp
│
├── extensions/                        # Framework extensions (NEW)
│   ├── extensions.asd                 # ASDF system definitions
│   ├── messaging/                     # Inter-agent messaging protocol
│   │   ├── packages.lisp
│   │   ├── protocol.lisp              # Message types, routing
│   │   ├── channels.lisp              # Named channels, pub/sub
│   │   └── serialization.lisp         # S-expr message format
│   ├── mcp-sdk/                       # MCP server development kit
│   │   ├── packages.lisp
│   │   ├── server-base.lisp           # Base server class
│   │   ├── tool-builder.lisp          # Declarative tool definition
│   │   ├── resource-builder.lisp      # Resource definition
│   │   └── templates/                 # Starter templates
│   ├── cost-tracking/                 # Provider cost metering
│   │   ├── packages.lisp
│   │   ├── meters.lisp                # Token/cost tracking
│   │   ├── budgets.lisp               # Budget limits, alerts
│   │   └── reporting.lisp             # Usage reports
│   └── knowledge-graph/               # Graph primitives
│       ├── packages.lisp
│       ├── graph.lisp                 # S-expr graph structure
│       ├── queries.lisp               # Pattern matching
│       └── persistence.lisp           # Graph serialization
│
├── mcp-servers/                       # Shared MCP servers (NEW)
│   ├── mcp-servers.asd
│   ├── common/                        # Shared utilities
│   │   ├── packages.lisp
│   │   ├── json-rpc.lisp              # JSON-RPC helpers
│   │   └── auth.lisp                  # Authentication helpers
│   ├── github/                        # GitHub API
│   │   ├── packages.lisp
│   │   ├── server.lisp
│   │   ├── tools.lisp                 # PRs, issues, commits, etc.
│   │   └── config.json.example
│   ├── kubernetes/                    # Kubernetes API
│   │   ├── packages.lisp
│   │   ├── server.lisp
│   │   ├── tools.lisp                 # Pods, deployments, configmaps
│   │   └── config.json.example
│   ├── prometheus/                    # Prometheus queries
│   │   ├── packages.lisp
│   │   ├── server.lisp
│   │   └── tools.lisp                 # PromQL queries, alerts
│   ├── datadog/                       # Datadog API
│   │   ├── packages.lisp
│   │   ├── server.lisp
│   │   └── tools.lisp                 # Logs, metrics, APM
│   └── policy-engine/                 # OPA/Rego
│       ├── packages.lisp
│       ├── server.lisp
│       └── tools.lisp                 # Policy evaluation
│
├── capabilities/                      # Shared capability library (NEW)
│   ├── capabilities.asd
│   ├── common/                        # Broadly useful
│   │   ├── packages.lisp
│   │   ├── git-ops.lisp               # Git operations
│   │   ├── file-analysis.lisp         # Code analysis
│   │   └── reporting.lisp             # Report generation
│   ├── infra/                         # Infrastructure
│   │   ├── packages.lisp
│   │   ├── k8s-ops.lisp               # K8s read/write ops
│   │   ├── diagnostics.lisp           # System diagnostics
│   │   └── remediation.lisp           # Common fixes
│   └── compliance/                    # Compliance
│       ├── packages.lisp
│       ├── rules-engine.lisp          # Rule evaluation
│       ├── evidence.lisp              # Evidence collection
│       └── reporting.lisp             # Compliance reports
│
├── projects/                          # Agent projects (NEW)
│   ├── compliance-agent/
│   │   ├── project.sexpr              # Project manifest
│   │   ├── compliance-agent.asd       # ASDF system
│   │   ├── src/
│   │   │   ├── packages.lisp
│   │   │   ├── agent.lisp             # Agent class definition
│   │   │   ├── scanner.lisp           # Compliance scanning
│   │   │   └── reporter.lisp          # Report generation
│   │   ├── rules/                     # Compliance rules
│   │   │   ├── soc2/
│   │   │   │   ├── access-control.sexpr
│   │   │   │   ├── change-management.sexpr
│   │   │   │   └── logging.sexpr
│   │   │   ├── hipaa/
│   │   │   │   ├── phi-access.sexpr
│   │   │   │   └── encryption.sexpr
│   │   │   └── gdpr/
│   │   │       ├── data-retention.sexpr
│   │   │       └── consent.sexpr
│   │   ├── capabilities/              # Project-local capabilities
│   │   │   └── custom-checks.lisp
│   │   ├── mcp/                       # MCP server configs
│   │   │   ├── github.json
│   │   │   ├── kubernetes.json
│   │   │   └── policy-engine.json
│   │   ├── config/
│   │   │   ├── dev.sexpr
│   │   │   └── prod.sexpr
│   │   └── test/
│   │       └── compliance-tests.lisp
│   │
│   └── infra-healer/
│       ├── project.sexpr
│       ├── infra-healer.asd
│       ├── src/
│       │   ├── packages.lisp
│       │   ├── agent.lisp             # Agent class definition
│       │   ├── watcher.lisp           # Anomaly detection
│       │   ├── diagnoser.lisp         # Root cause analysis
│       │   └── healer.lisp            # Remediation execution
│       ├── playbooks/                 # Remediation playbooks
│       │   ├── pod-restart.sexpr
│       │   ├── scale-deployment.sexpr
│       │   ├── rollback-deployment.sexpr
│       │   └── clear-pvc.sexpr
│       ├── capabilities/
│       │   └── custom-diagnostics.lisp
│       ├── mcp/
│       │   ├── prometheus.json
│       │   ├── kubernetes.json
│       │   └── pagerduty.json
│       ├── config/
│       │   ├── dev.sexpr
│       │   ├── prod.sexpr
│       │   └── escalation.sexpr       # When to page humans
│       └── test/
│           └── infra-tests.lisp
│
├── test/                              # Existing tests
├── docs/
├── thoughts/
├── ralph/
├── scripts/
├── Dockerfile
└── docker-compose.yml
```

---

## Core Infrastructure Changes

### 1. Extension Loader (`src/core/extension-loader.lisp`)

```lisp
(defpackage :autopoiesis.core.loader
  (:use :cl :autopoiesis.core)
  (:export #:load-extension
           #:load-project
           #:unload-project
           #:list-extensions
           #:list-projects
           #:find-project
           #:*extension-search-paths*
           #:*project-search-paths*))

(in-package :autopoiesis.core.loader)

(defvar *autopoiesis-root* 
  (asdf:system-source-directory :autopoiesis))

(defvar *extension-search-paths* 
  (list (merge-pathnames "extensions/" *autopoiesis-root*)
        (uiop:xdg-data-home "autopoiesis/extensions/")))

(defvar *project-search-paths*
  (list (merge-pathnames "projects/" *autopoiesis-root*)
        (uiop:xdg-data-home "autopoiesis/projects/")))

(defvar *loaded-projects* (make-hash-table :test 'equal)
  "Registry of loaded project workspaces")

;;; Extension Loading

(defun list-extensions ()
  "List available extensions."
  (loop for path in *extension-search-paths*
        when (probe-file path)
        append (mapcar #'pathname-name 
                       (uiop:subdirectories path))))

(defun find-extension-system (name)
  "Find ASDF system name for extension."
  (intern (format nil "AUTOPOIESIS.EXT.~:@(~A~)" name) :keyword))

(defun load-extension (name &key force-recompile)
  "Load an extension by name. Uses cached FASL if available."
  (let ((system-name (find-extension-system name)))
    (when force-recompile
      (asdf:clear-system system-name))
    (asdf:load-system system-name)
    (format t "~&; Loaded extension: ~A~%" name)
    t))

;;; Project Loading

(defun find-project-manifest (name)
  "Find project.sexpr for a project."
  (loop for base in *project-search-paths*
        for manifest = (merge-pathnames 
                        (format nil "~A/project.sexpr" name) base)
        when (probe-file manifest)
        return manifest
        finally (error "Project not found: ~A" name)))

(defun load-project-manifest (path)
  "Load and parse a project manifest."
  (with-open-file (s path :direction :input)
    (read s)))

(defun load-project (name &key (load-dependencies t) (initialize-storage t))
  "Load a project and its dependencies."
  (let* ((manifest-path (find-project-manifest name))
         (manifest (load-project-manifest manifest-path))
         (project-id (getf manifest :id)))
    
    ;; Load extension dependencies
    (when load-dependencies
      (dolist (ext (getf (getf manifest :dependencies) :extensions))
        (load-extension ext)))
    
    ;; Load shared capabilities
    (dolist (cap (getf (getf manifest :capabilities) :shared))
      (load-capability cap))
    
    ;; Load project ASDF system
    (let ((system-name (getf manifest :system-name)))
      (asdf:load-system system-name))
    
    ;; Initialize project storage
    (when initialize-storage
      (let ((storage (make-project-storage project-id)))
        (setf (gethash project-id *loaded-projects*) 
              (list :manifest manifest
                    :storage storage
                    :loaded-at (local-time:now)))))
    
    (format t "~&; Loaded project: ~A~%" name)
    project-id))

(defun find-project (name)
  "Get loaded project info."
  (gethash name *loaded-projects*))

(defun list-projects ()
  "List available projects."
  (loop for path in *project-search-paths*
        when (probe-file path)
        append (loop for dir in (uiop:subdirectories path)
                     for manifest = (merge-pathnames "project.sexpr" dir)
                     when (probe-file manifest)
                     collect (pathname-name dir))))

(defun unload-project (name)
  "Unload a project, closing its storage."
  (let ((project (gethash name *loaded-projects*)))
    (when project
      (close-project-storage (getf project :storage))
      (remhash name *loaded-projects*)
      t)))
```

### 2. Project Storage (`src/core/project-storage.lisp`)

```lisp
(defpackage :autopoiesis.core.storage
  (:use :cl :autopoiesis.core :autopoiesis.snapshot)
  (:export #:project-storage
           #:make-project-storage
           #:close-project-storage
           #:project-snapshot-store
           #:project-state-db
           #:with-project-storage
           #:*archil-mount-point*
           #:*current-project-storage*))

(in-package :autopoiesis.core.storage)

(defvar *archil-mount-point* 
  (pathname (or (uiop:getenv "AUTOPOIESIS_STORAGE_PATH")
                "/mnt/archil/"))
  "Base path for Archil-mounted S3 storage")

(defvar *current-project-storage* nil
  "Currently active project storage")

(defclass project-storage ()
  ((project-id 
    :initarg :project-id 
    :accessor project-id
    :documentation "Unique project identifier")
   (base-path 
    :initarg :base-path
    :accessor base-path
    :documentation "Project root path (Archil-mounted)")
   (snapshot-store 
    :accessor project-snapshot-store
    :documentation "Content-addressable snapshot storage")
   (branch-manager
    :accessor project-branch-manager
    :documentation "Project-scoped branch manager")
   (state-db-path
    :accessor state-db-path
    :documentation "Path to SQLite state database")
   (initialized-p
    :initform nil
    :accessor initialized-p))
  (:documentation "Per-project isolated storage backed by Archil/S3"))

(defun ensure-project-directories (base-path)
  "Create required directory structure for project."
  (dolist (subdir '("snapshots/" "agents/" "branches/" "logs/" "cache/"))
    (ensure-directories-exist (merge-pathnames subdir base-path))))

(defun make-project-storage (project-id &key (base-path *archil-mount-point*))
  "Create storage namespace for a project."
  (let* ((project-path (merge-pathnames 
                        (make-pathname :directory 
                                       (list :relative "projects" project-id))
                        base-path))
         (storage (make-instance 'project-storage
                    :project-id project-id
                    :base-path project-path)))
    
    ;; Ensure directory structure exists
    (ensure-project-directories project-path)
    
    ;; Set up SQLite state database path
    (setf (state-db-path storage)
          (merge-pathnames "state.db" project-path))
    
    ;; Initialize project-scoped snapshot store
    (setf (project-snapshot-store storage)
          (make-instance 'persistence-manager
            :base-path (merge-pathnames "snapshots/" project-path)
            :cache-size 500))
    
    ;; Initialize branch manager for this project
    (setf (project-branch-manager storage)
          (make-instance 'branch-manager
            :persistence (project-snapshot-store storage)))
    
    (setf (initialized-p storage) t)
    storage))

(defun close-project-storage (storage)
  "Clean up project storage resources."
  (when (initialized-p storage)
    ;; Flush any pending writes
    (when (project-snapshot-store storage)
      (flush-persistence (project-snapshot-store storage)))
    (setf (initialized-p storage) nil)))

(defmacro with-project-storage ((var project-id) &body body)
  "Execute body with project storage bound."
  `(let* ((,var (or (find-project-storage ,project-id)
                    (make-project-storage ,project-id)))
          (*current-project-storage* ,var))
     (unwind-protect
         (progn ,@body)
       (when (and ,var (not (find-project-storage ,project-id)))
         (close-project-storage ,var)))))
```

### 3. Project Manifest Schema

```lisp
;; Project manifest format specification

(:project
 ;; Required fields
 :id "string"                    ; Unique identifier (directory name)
 :name "string"                  ; Human-readable name
 :version "semver"               ; Semantic version
 :system-name "keyword"          ; ASDF system name
 
 ;; Dependencies
 :dependencies
 (:extensions ("ext1" "ext2")    ; Framework extensions to load
  :systems ("asdf-system"))      ; External ASDF systems
 
 ;; MCP server configurations
 :mcp-servers
 ((:name "server-name"
   :config "path/to/config.json"
   :required t/nil))             ; Whether server is required
 
 ;; Capability loading
 :capabilities
 (:shared ("cap1" "cap2")        ; From capabilities/ directory
  :local ("./capabilities/"))    ; Project-local capabilities
 
 ;; Agent definitions
 :agents
 ((:id "agent-id"
   :class symbol                 ; Agent class name
   :config "path/to/config.sexpr"
   :auto-spawn t/nil             ; Spawn on project load
   :requires-approval t/nil      ; Human approval for actions
   :escalation-policy "path"))   ; Optional escalation config
 
 ;; Storage configuration
 :storage
 (:type :archil                  ; Storage backend
  :namespace "string"            ; S3 prefix/namespace
  :cache-size 500                ; LRU cache entries
  :backup-interval 3600)         ; Backup frequency in seconds
 
 ;; Optional metadata
 :description "string"
 :author "string"
 :license "string"
 :repository "url"
 :tags ("tag1" "tag2"))
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)

**Goal**: Core infrastructure for extensions and projects

#### Tasks

1. **Create directory structure**
   - [ ] Create `extensions/` with `extensions.asd`
   - [ ] Create `mcp-servers/` with `mcp-servers.asd`
   - [ ] Create `capabilities/` with `capabilities.asd`
   - [ ] Create `projects/` directory
   - [ ] Create scaffold for `compliance-agent/`
   - [ ] Create scaffold for `infra-healer/`

2. **Implement extension loader**
   - [ ] Add `src/core/extension-loader.lisp`
   - [ ] Add `src/core/project-storage.lisp`
   - [ ] Update `src/core/packages.lisp` with exports
   - [ ] Update `autopoiesis.asd` to include new files
   - [ ] Write tests for extension loading

3. **Project manifest parser**
   - [ ] Implement `load-project-manifest`
   - [ ] Implement manifest validation
   - [ ] Write tests for manifest parsing

4. **Storage integration**
   - [ ] Configure Archil disk (manual step)
   - [ ] Test SQLite on Archil mount
   - [ ] Verify snapshot persistence works on Archil
   - [ ] Document Archil setup in `docs/STORAGE.md`

**Deliverables**:
- Working `(load-extension "messaging")` 
- Working `(load-project "compliance-agent")`
- Per-project snapshot isolation verified

---

### Phase 2: MCP Server SDK (Week 2)

**Goal**: Make it easy to build MCP servers for integrations

#### Tasks

1. **MCP SDK core**
   - [ ] `extensions/mcp-sdk/server-base.lisp` — Base server class
   - [ ] `extensions/mcp-sdk/tool-builder.lisp` — Declarative tool DSL
   - [ ] `extensions/mcp-sdk/resource-builder.lisp` — Resource DSL
   - [ ] JSON-RPC 2.0 implementation improvements
   - [ ] Write SDK documentation

2. **First MCP server: Kubernetes**
   - [ ] `mcp-servers/kubernetes/server.lisp`
   - [ ] Tools: list-pods, get-pod, describe-deployment, get-logs
   - [ ] Tools: scale-deployment, restart-pod (with approval guard)
   - [ ] Authentication via kubeconfig
   - [ ] Write tests with mock K8s API

3. **Second MCP server: GitHub**
   - [ ] `mcp-servers/github/server.lisp`
   - [ ] Tools: list-repos, get-file, list-prs, get-pr-diff
   - [ ] Tools: list-commits, get-commit, search-code
   - [ ] Authentication via PAT or GitHub App
   - [ ] Write tests with mock GitHub API

**Deliverables**:
- `defmcp-tool` macro for easy tool definition
- Working Kubernetes MCP server
- Working GitHub MCP server

---

### Phase 3: Shared Capabilities (Week 3)

**Goal**: Build reusable capability library

#### Tasks

1. **Common capabilities**
   - [ ] `capabilities/common/git-ops.lisp` — Git operations
   - [ ] `capabilities/common/file-analysis.lisp` — Code parsing
   - [ ] `capabilities/common/reporting.lisp` — Report generation

2. **Infrastructure capabilities**
   - [ ] `capabilities/infra/k8s-ops.lisp` — K8s helpers
   - [ ] `capabilities/infra/diagnostics.lisp` — Health checks
   - [ ] `capabilities/infra/remediation.lisp` — Fix patterns

3. **Compliance capabilities**
   - [ ] `capabilities/compliance/rules-engine.lisp` — Rule evaluation
   - [ ] `capabilities/compliance/evidence.lisp` — Evidence collection
   - [ ] `capabilities/compliance/reporting.lisp` — Compliance reports

**Deliverables**:
- Capability library usable by both projects
- Tests for all capabilities

---

### Phase 4: Compliance Agent (Weeks 4-5)

**Goal**: First complete agent project

#### Tasks

1. **Agent implementation**
   - [ ] `projects/compliance-agent/src/agent.lisp` — Agent class
   - [ ] `projects/compliance-agent/src/scanner.lisp` — Scanning logic
   - [ ] `projects/compliance-agent/src/reporter.lisp` — Report generation
   - [ ] Cognitive loop specialization for compliance workflow

2. **Compliance rules**
   - [ ] SOC2 rules (access control, change management, logging)
   - [ ] HIPAA rules (PHI access, encryption)
   - [ ] GDPR rules (data retention, consent)
   - [ ] Rule format documentation

3. **MCP integrations**
   - [ ] Policy engine MCP server (OPA/Rego)
   - [ ] Configure GitHub MCP for code scanning
   - [ ] Configure Kubernetes MCP for config scanning

4. **Human-in-the-loop**
   - [ ] Report review workflow
   - [ ] Finding annotation interface
   - [ ] Remediation approval gates

5. **Testing**
   - [ ] Unit tests for rule evaluation
   - [ ] Integration tests with mock infrastructure
   - [ ] E2E test: scan → detect → report flow

**Deliverables**:
- Complete compliance agent
- SOC2/HIPAA/GDPR rule libraries
- Documentation and examples

---

### Phase 5: Infrastructure Healer (Weeks 6-7)

**Goal**: Second complete agent project with write capabilities

#### Tasks

1. **Agent implementation**
   - [ ] `projects/infra-healer/src/agent.lisp` — Agent class
   - [ ] `projects/infra-healer/src/watcher.lisp` — Anomaly detection
   - [ ] `projects/infra-healer/src/diagnoser.lisp` — Root cause analysis
   - [ ] `projects/infra-healer/src/healer.lisp` — Remediation

2. **Remediation playbooks**
   - [ ] Pod restart playbook
   - [ ] Deployment scale playbook
   - [ ] Deployment rollback playbook
   - [ ] PVC cleanup playbook
   - [ ] Playbook format documentation

3. **MCP integrations**
   - [ ] Prometheus MCP server for metrics
   - [ ] Configure Kubernetes MCP (with write access)
   - [ ] PagerDuty MCP for escalation

4. **Approval and escalation**
   - [ ] Blast radius scoring for actions
   - [ ] Escalation policy engine
   - [ ] Human approval workflow
   - [ ] Audit trail for all remediations

5. **Testing**
   - [ ] Unit tests for diagnosis logic
   - [ ] Integration tests with mock metrics
   - [ ] E2E test: detect → diagnose → (approve) → remediate flow

**Deliverables**:
- Complete infrastructure healer agent
- Playbook library
- Escalation policy documentation

---

### Phase 6: Inter-Agent Messaging (Week 8)

**Goal**: Enable multi-agent coordination

#### Tasks

1. **Messaging extension**
   - [ ] `extensions/messaging/protocol.lisp` — Message types
   - [ ] `extensions/messaging/channels.lisp` — Pub/sub channels
   - [ ] `extensions/messaging/serialization.lisp` — S-expr messages
   - [ ] Integration with event bus

2. **Cross-project communication**
   - [ ] Compliance agent → Infra healer alerts
   - [ ] Shared finding/incident objects
   - [ ] Message persistence in snapshot DAG

3. **Testing**
   - [ ] Unit tests for messaging
   - [ ] Integration test: compliance finding triggers infra response

**Deliverables**:
- Messaging extension
- Inter-agent communication demo

---

### Phase 7: CLI and Developer Experience (Week 9)

**Goal**: Streamlined project management

#### Tasks

1. **CLI commands**
   - [ ] `ap project new <name> --template=<template>`
   - [ ] `ap project list`
   - [ ] `ap project load <name>`
   - [ ] `ap agent spawn <agent-id>`
   - [ ] `ap agent attach <agent-id>`
   - [ ] `ap mcp add <server> --config=<path>`
   - [ ] `ap run --steps=N`

2. **Project templates**
   - [ ] Monitor template (read-only agent)
   - [ ] Actor template (read-write with approval)
   - [ ] Researcher template (exploration focused)

3. **Documentation**
   - [ ] Project creation guide
   - [ ] MCP server development guide
   - [ ] Capability development guide

**Deliverables**:
- Full CLI for project management
- Project templates
- Developer documentation

---

## Archil/S3 Setup Guide

### Prerequisites

1. AWS account with S3 bucket
2. Archil installation (https://docs.archil.com/getting-started/quickstart)
3. AWS credentials configured

### Setup Steps

```bash
# 1. Create S3 bucket for Autopoiesis data
aws s3 mb s3://autopoiesis-data-<your-identifier>

# 2. Install Archil CLI
curl -fsSL https://get.archil.com | sh

# 3. Create Archil disk
archil disk create autopoiesis \
  --bucket s3://autopoiesis-data-<your-identifier> \
  --region us-west-2 \
  --cache-size 20GB

# 4. Mount the disk
sudo mkdir -p /mnt/archil
archil mount autopoiesis /mnt/archil

# 5. Verify mount
ls /mnt/archil
touch /mnt/archil/test && rm /mnt/archil/test

# 6. Set environment variable
export AUTOPOIESIS_STORAGE_PATH=/mnt/archil

# 7. (Optional) Add to shell profile
echo 'export AUTOPOIESIS_STORAGE_PATH=/mnt/archil' >> ~/.zshrc
```

### Directory Structure Created on First Use

```
/mnt/archil/
├── projects/
│   ├── compliance-agent/
│   │   ├── state.db
│   │   ├── snapshots/
│   │   ├── agents/
│   │   ├── branches/
│   │   ├── logs/
│   │   └── cache/
│   └── infra-healer/
│       └── ...
└── shared/
    ├── capabilities/
    └── mcp-cache/
```

### Local Development (No Archil)

For local development without Archil:

```bash
# Use local filesystem instead
export AUTOPOIESIS_STORAGE_PATH=~/.autopoiesis/data
mkdir -p ~/.autopoiesis/data
```

The code works identically — just without S3 backing.

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Archil latency for SQLite | High | Medium | Local SSD cache, batch writes |
| MCP server complexity | Medium | Medium | Good SDK, templates, examples |
| Rule library maintenance | Medium | High | Community contributions, versioning |
| Multi-tenant isolation | High | Low | Per-project namespacing, no shared state |
| ASDF dependency conflicts | Medium | Low | Careful versioning, CI testing |

---

## Success Metrics

### Phase 1-3 (Foundation)
- [ ] `(load-project "compliance-agent")` works in < 5 seconds
- [ ] Snapshots persist correctly on Archil mount
- [ ] At least 2 MCP servers operational

### Phase 4-5 (Agent Projects)
- [ ] Compliance agent scans a real Kubernetes cluster
- [ ] Infra healer detects and fixes a simulated incident
- [ ] Full audit trail visible in snapshot history

### Phase 6-7 (Integration)
- [ ] Compliance finding triggers infra healer response
- [ ] Developer can create new project in < 5 minutes
- [ ] Documentation covers all common workflows

---

## Open Questions

1. **Capability versioning**: How do we handle breaking changes to shared capabilities?
   - Option A: SemVer + explicit version pinning in manifests
   - Option B: Immutable capabilities, new versions = new names
   
2. **MCP server lifecycle**: Should MCP servers be per-project or shared?
   - Option A: Per-project (isolation, but resource overhead)
   - Option B: Shared with namespacing (efficient, but coupling)
   
3. **Cross-project branching**: Can we branch across project boundaries?
   - Option A: No, projects are fully isolated
   - Option B: Yes, with explicit cross-project references

4. **HVM4 integration timing**: When to start the reasoning worktree?
   - Option A: After Phase 5 (agents working)
   - Option B: In parallel from Phase 3 (earlier exploration)

---

## References

- Research: `thoughts/shared/research/2026-02-03-autopoiesis-codebase-overview.md`
- Use cases: `thoughts/shared/research/2026-02-03-autopoiesis-real-agent-use-cases.md`
- Archil docs: https://docs.archil.com/getting-started/introduction
- HVM4: https://github.com/HigherOrderCO/HVM4
- MCP spec: https://spec.modelcontextprotocol.io/
