---
date: 2026-03-02
author: Jarvis
status: draft
reviewed: 2026-03-03
tags: [plan, team, agents, coordination, orchestration, multi-agent]
depends_on:
  - thoughts/shared/plans/2026-02-17-coordination-and-provider-lifecycle.md
  - thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md
  - thoughts/shared/research/2026-02-06-super-agent-synthesis.md
---

> **Review Notes (2026-03-03)**
>
> This plan was written before the `swarm/`, `supervisor/`, `jarvis/`, `workspace/`
> modules were added (commit `0bc1dd9`). The architecture is sound but has significant
> overlap with existing code that must be resolved before implementation. Key issues:
>
> **Critical fixes required:**
>
> 1. **Incorrect substrate API** — Phase 0 calls `register-store-hook` / `unregister-store-hook`
>    which do not exist. The correct API is `(register-hook *store* name fn priority)` and
>    `(unregister-hook *store* name)`.
>
> 2. **Missing pre-flight checks** — `await-agent-cv` and `await-all-agents` install hooks
>    then wait, but if agents have already completed before hook installation, the CV never
>    fires. Must check `(entity-attr eid :agent/status)` before installing hooks.
>
> 3. **`team-status` name clash** — Phase 1 defines both a CLOS accessor `(team-status)` on
>    the `status` slot and a `(defun team-status ...)` query function. The `defun` will
>    clobber the accessor. Rename the query to `query-team-status` or `get-team-status`.
>
> 4. **Unlocked `*team-registry*`** — Phase 1 creates a bare hash table with no lock, the
>    same concurrency hazard Phase 0 is fixing. Use the pattern from `*workspace-registry-lock*`
>    in `workspace/workspace.lisp`.
>
> **Duplicate code that must be eliminated:**
>
> 5. **Phase 1 workspace** — `platform/src/team/workspace.lisp` would duplicate the existing
>    `autopoiesis.workspace` module (`workspace/workspace.lisp`) which already has a `workspace`
>    class, substrate tracking, registry, and lifecycle functions. Instead, extend the existing
>    module with team-aware attributes (`:workspace/task-queue`, `:workspace/shared-memory`, etc.).
>
> 6. **Phase 5 Jarvis** — `platform/src/team/jarvis.lisp` would duplicate the existing
>    `autopoiesis.jarvis` module (`jarvis/loop.lisp`) which already implements Jarvis with
>    Pi-provider-backed NL-to-tool dispatch. Instead, add team management tools to the existing
>    Jarvis session's tool context.
>
> 7. **Phase 2 "Swarm Strategy"** — Naming collision with `autopoiesis.swarm` (evolutionary
>    engine). Rename to `:parallel` or `:fan-out` strategy to avoid confusion.
>
> **Minor issues:**
>
> 8. **`defcapability` syntax** — Phase 4 tool definitions use `:permissions` and `:body`
>    keywords that may not match `parse-defcapability-body`. Verify against
>    `agent/capability.lisp` before implementation.
>
> 9. **Phase 3 event types** — Adding keywords to `integration-event-type` requires editing
>    the `deftype`/`member` form in `integration/events.lisp`, not an additive registration call.
>
> 10. **`workspace-put`/`workspace-get` performance** — Every shared memory write goes through
>     full `transact!` pipeline. For high-frequency coordination (consensus rounds, pipeline
>     hand-offs), consider batching or an in-memory coordination structure with periodic
>     substrate flush.
>
> **What's valuable and should be kept:**
>
> - Substrate-first team representation (datoms + `take!` for task claiming)
> - Strategy-as-CLOS-generics protocol (`strategy-initialize`, `strategy-assign-work`, etc.)
> - Phase 0 concurrency fixes (mailbox locks, CV-based await) — correct diagnosis
> - "Agents are unaware of teams" isolation principle
> - Team event bus integration (with corrected event type extension)
> - Five coordination patterns are well-designed (after renaming Swarm to Parallel)

# Team of Agents: Comprehensive Implementation Plan

## Executive Summary

Build a first-class **team coordination layer** on top of Autopoiesis's existing agent, orchestration, and substrate primitives. Teams are collections of agents with defined roles, shared workspaces, structured task delegation, and observable coordination patterns — all represented as immutable S-expressions in the substrate.

**What exists today:**
- Single agents with cognitive loops (perceive-reason-decide-act-reflect)
- Parent/child spawn hierarchy with agent registry
- Message passing via `*agent-mailboxes*` (unlocked, in-memory only)
- `spawn-agent`, `query-agent`, `await-agent` tools (await uses 2s polling)
- Multi-provider agentic loops (Claude, OpenAI, Codex, OpenCode, Cursor)
- Substrate-backed event queue with Linda coordination
- Conductor tick loop (100ms) with timer heap and worker management
- Event bus with typed handlers
- Snapshot DAG with branching, diffing, time-travel

**What we're building:**
- Team class with roles, strategies, shared workspace, and lifecycle
- Five coordination patterns: Leader/Worker, Swarm, Pipeline, Debate, Consensus
- Substrate-backed shared memory (replacing in-memory mailboxes)
- Condition-variable coordination (replacing polling)
- Team-aware conductor extensions
- Team event types on the event bus
- Team visualization in the Holodeck
- Jarvis as the meta-orchestrator across teams

**Scale target:** Single machine, 1-50 concurrent agents across 1-10 teams.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Jarvis (Meta-Orchestrator)                     │
│    Natural language → team operations → result composition        │
├──────────────────────────────────────────────────────────────────┤
│                    Team Coordination Layer                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │  Leader/  │  │  Swarm   │  │ Pipeline │  │  Debate  │  ...   │
│  │  Worker   │  │          │  │          │  │          │        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
├──────────────────────────────────────────────────────────────────┤
│                 Shared Workspace (Substrate)                      │
│  Team datoms · Shared memory · Task queue · Message log          │
├──────────────────────────────────────────────────────────────────┤
│                 Agent Layer (Existing)                            │
│  Cognitive loop · Capabilities · Learning · Thought streams      │
├──────────────────────────────────────────────────────────────────┤
│              Orchestration Layer (Extended)                       │
│  Conductor · Timer heap · Event queue · Workers · CV signals     │
├──────────────────────────────────────────────────────────────────┤
│                 Substrate Layer (Existing)                        │
│  Datom store · EAV triples · Linda take! · Value index · LMDB   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Phase 0: Foundation Fixes (Prerequisite)

**Goal:** Fix the concurrency hazards and polling inefficiencies documented in `2026-02-17-coordination-and-provider-lifecycle.md`.

### 0.1 Thread-Safe Mailboxes

**File:** `platform/src/agent/builtin-capabilities.lisp`

The current `*agent-mailboxes*` hash table has no lock. Replace with a per-agent locked mailbox:

```lisp
(defstruct agent-mailbox
  (lock (bt:make-lock "mailbox"))
  (cv (bt:make-condition-variable :name "mailbox-cv"))
  (messages nil :type list))

(defun deliver-message (message)
  "Thread-safe delivery with CV notification."
  (let ((mb (ensure-mailbox (message-to message))))
    (bt:with-lock-held ((agent-mailbox-lock mb))
      (push message (agent-mailbox-messages mb))
      (bt:condition-notify (agent-mailbox-cv mb)))
    message))
```

### 0.2 Condition-Variable Coordination

**File:** `platform/src/integration/builtin-tools.lisp`

Replace `await-agent`'s 2-second polling with substrate hook + CV:

```lisp
(defun await-agent-cv (agent-id &key (timeout 300))
  "Block until agent completes, using substrate hooks + CV."
  (let ((cv (bt:make-condition-variable))
        (lock (bt:make-lock "await"))
        (done nil))
    (let ((hook (lambda (datoms)
                  (dolist (d datoms)
                    (when (and (eq (datom-eid d)
                                   (intern-id agent-id))
                               (eq (datom-attr d) :agent/status)
                               (member (datom-value d) '(:complete :failed)))
                      (bt:with-lock-held (lock)
                        (setf done t)
                        (bt:condition-notify cv)))))))
      (register-store-hook hook)
      (unwind-protect
           (bt:with-lock-held (lock)
             (unless done
               (bt:condition-wait cv lock :timeout timeout)))
        (unregister-store-hook hook)))))
```

### 0.3 Fan-In Primitive: `await-all-agents`

```lisp
(defun await-all-agents (agent-ids &key (timeout 300))
  "Block until ALL agents in AGENT-IDS have completed.
   Returns alist of (agent-id . status)."
  (let ((remaining (length agent-ids))
        (results nil)
        (cv (bt:make-condition-variable))
        (lock (bt:make-lock "await-all")))
    (let ((hook (lambda (datoms)
                  (dolist (d datoms)
                    (when (and (member (resolve-id (datom-eid d)) agent-ids
                                       :test #'string=)
                               (eq (datom-attr d) :agent/status)
                               (member (datom-value d) '(:complete :failed)))
                      (bt:with-lock-held (lock)
                        (push (cons (resolve-id (datom-eid d))
                                    (datom-value d))
                              results)
                        (decf remaining)
                        (when (zerop remaining)
                          (bt:condition-notify cv))))))))
      (register-store-hook hook)
      (unwind-protect
           (bt:with-lock-held (lock)
             (unless (zerop remaining)
               (bt:condition-wait cv lock :timeout timeout)))
        (unregister-store-hook hook))
      results)))
```

### Estimated Size
~150 lines. No new files — edits to existing `builtin-capabilities.lisp` and `builtin-tools.lisp`.

---

## Phase 1: Team Data Model

**Goal:** Define the `team` abstraction as substrate entities with proper serialization.

### 1.1 Team Entity Schema

**File:** New `platform/src/team/team.lisp`

Teams are substrate entities with the following datom attributes:

| Attribute | Type | Description |
|---|---|---|
| `:entity/type` | `:team` | Entity type marker |
| `:team/name` | string | Human-readable team name |
| `:team/strategy` | keyword | Coordination strategy (`:leader-worker`, `:swarm`, `:pipeline`, `:debate`, `:consensus`) |
| `:team/leader` | entity-id | Leader agent entity (for leader/worker strategy) |
| `:team/members` | list | List of agent entity IDs |
| `:team/status` | keyword | `:forming`, `:active`, `:paused`, `:completed`, `:failed` |
| `:team/workspace` | entity-id | Shared workspace entity |
| `:team/task` | string | Team-level task description |
| `:team/created-at` | integer | Creation timestamp |
| `:team/completed-at` | integer | Completion timestamp |
| `:team/config` | plist | Strategy-specific configuration |

```lisp
(defclass team ()
  ((id :initarg :id :accessor team-id
       :initform (make-uuid)
       :documentation "Team entity ID in the substrate")
   (name :initarg :name :accessor team-name)
   (strategy :initarg :strategy :accessor team-strategy
             :initform :leader-worker
             :type (member :leader-worker :swarm :pipeline :debate :consensus))
   (leader :initarg :leader :accessor team-leader :initform nil)
   (members :initarg :members :accessor team-members :initform nil)
   (status :initarg :status :accessor team-status :initform :forming)
   (workspace :initarg :workspace :accessor team-workspace :initform nil)
   (task :initarg :task :accessor team-task :initform nil)
   (config :initarg :config :accessor team-config :initform nil))
  (:documentation "A coordinated team of agents."))
```

### 1.2 Team Lifecycle Functions

```lisp
(defun create-team (name &key strategy leader-config member-configs task config)
  "Create a team, spawn its agents, and register in substrate.
   LEADER-CONFIG - Plist for leader agent (:name :provider :system-prompt :capabilities)
   MEMBER-CONFIGS - List of plists for member agents
   Returns team entity ID.")

(defun start-team (team-id)
  "Transition team to :active, start all member agents.")

(defun pause-team (team-id)
  "Pause all team members, save team state.")

(defun resume-team (team-id)
  "Resume all paused team members.")

(defun disband-team (team-id)
  "Stop all members, mark team :completed, archive workspace.")

(defun team-status (team-id)
  "Return comprehensive team status: member states, task progress, metrics.")
```

### 1.3 Shared Workspace

**File:** New `platform/src/team/workspace.lisp`

A shared workspace is a substrate entity that team members can read/write to:

| Attribute | Type | Description |
|---|---|---|
| `:entity/type` | `:workspace` | Entity type marker |
| `:workspace/team` | entity-id | Owning team |
| `:workspace/shared-memory` | plist | Key-value shared state |
| `:workspace/task-queue` | list | Ordered task list |
| `:workspace/artifacts` | list | Produced artifacts (files, results, etc.) |
| `:workspace/log` | list | Append-only coordination log |

```lisp
(defun workspace-put (workspace-id key value)
  "Write KEY=VALUE to shared memory. Thread-safe via transact!.")

(defun workspace-get (workspace-id key)
  "Read KEY from shared memory.")

(defun workspace-push-task (workspace-id task-plist)
  "Push a task onto the workspace task queue.")

(defun workspace-claim-task (workspace-id)
  "Atomically claim the next task from the queue via take!.")

(defun workspace-log (workspace-id entry)
  "Append an entry to the workspace coordination log.")
```

### 1.4 Team Registry

```lisp
(defvar *team-registry* (make-hash-table :test 'equal))

(defun register-team (team) ...)
(defun find-team (id) ...)
(defun list-teams () ...)
(defun active-teams () ...)
```

### 1.5 Serialization

```lisp
(defun team-to-sexpr (team) ...)
(defun sexpr-to-team (sexpr) ...)
```

### Estimated Size
~350 lines across 3 new files: `team.lisp`, `workspace.lisp`, `packages.lisp`.

---

## Phase 2: Coordination Strategies

**Goal:** Implement five coordination patterns as pluggable strategies.

### 2.1 Strategy Protocol

**File:** New `platform/src/team/strategy.lisp`

```lisp
(defgeneric strategy-initialize (strategy team)
  (:documentation "Set up initial team structure for this strategy."))

(defgeneric strategy-assign-work (strategy team task)
  (:documentation "Delegate TASK according to this strategy's pattern."))

(defgeneric strategy-collect-results (strategy team)
  (:documentation "Gather and synthesize results from team members."))

(defgeneric strategy-handle-failure (strategy team agent-id error)
  (:documentation "Handle a member agent's failure."))

(defgeneric strategy-complete-p (strategy team)
  (:documentation "Return T if the team's work is done."))
```

### 2.2 Leader/Worker Strategy

The default pattern. One agent (the leader) decomposes work into subtasks and assigns them to worker agents. The leader synthesizes results.

```lisp
(defclass leader-worker-strategy ()
  ((max-workers :initarg :max-workers :initform 5)
   (assignment-mode :initarg :assignment-mode :initform :round-robin
                    :type (member :round-robin :load-balanced :capability-matched))))
```

**Flow:**
1. Leader receives task → decomposes into subtasks using its LLM
2. Subtasks are pushed to workspace task queue
3. Workers claim tasks atomically via `workspace-claim-task` (Linda `take!`)
4. Workers execute tasks, write results to workspace shared memory
5. Leader awaits all workers via `await-all-agents`
6. Leader synthesizes results into final output

**Key implementation detail:** The leader's decomposition step is itself an agentic loop call — the leader LLM decides how to split the work, outputting a structured list of subtasks.

### 2.3 Swarm Strategy

All agents work independently on the same problem with different approaches or parameters. Best result wins.

```lisp
(defclass swarm-strategy ()
  ((evaluation-fn :initarg :evaluation-fn :initform nil
                  :documentation "Function to score results: (result) -> number")
   (selection-mode :initarg :selection-mode :initform :best
                   :type (member :best :vote :merge))))
```

**Flow:**
1. All agents receive the same task (potentially with tweaks/variations)
2. Each agent works independently in parallel
3. Results are collected via `await-all-agents`
4. Evaluation function scores each result
5. Selection mode determines final output:
   - `:best` — highest-scoring result wins
   - `:vote` — agents vote on each other's results
   - `:merge` — a synthesizer agent merges top results

### 2.4 Pipeline Strategy

Sequential processing chain where each agent's output becomes the next agent's input.

```lisp
(defclass pipeline-strategy ()
  ((stages :initarg :stages :initform nil
           :documentation "Ordered list of (agent-id . transform-spec)")
   (pass-mode :initarg :pass-mode :initform :full
              :type (member :full :summary :structured))))
```

**Flow:**
1. Stage 1 agent receives initial input
2. Stage 1 output is formatted according to `:pass-mode` and fed to Stage 2
3. Each stage processes and passes forward
4. Final stage output is the team result

**Use cases:** Research → Analysis → Synthesis, Code → Review → Test, Draft → Edit → Polish

### 2.5 Debate Strategy

Two or more agents argue opposing positions. A judge agent evaluates.

```lisp
(defclass debate-strategy ()
  ((rounds :initarg :rounds :initform 3
           :documentation "Number of debate rounds")
   (debaters :initarg :debaters :initform 2)
   (judge :initarg :judge :initform nil
          :documentation "Judge agent ID (or leader if nil)")))
```

**Flow:**
1. Each debater receives the question + an assigned position
2. Round 1: Initial arguments (parallel)
3. Round 2..N: Rebuttals — each debater sees opponent's previous argument
4. Judge evaluates all rounds, selects winner or synthesizes

**Use cases:** Security audits (attacker vs. defender), architecture decisions, risk assessment

### 2.6 Consensus Strategy

Agents iteratively refine a shared artifact until agreement is reached.

```lisp
(defclass consensus-strategy ()
  ((threshold :initarg :threshold :initform 0.8
              :documentation "Agreement threshold (0.0-1.0)")
   (max-rounds :initarg :max-rounds :initform 5)
   (voting-mode :initarg :voting-mode :initform :approval
                :type (member :approval :ranked :weighted))))
```

**Flow:**
1. First agent produces initial draft
2. All other agents review and propose changes
3. Changes are aggregated and applied
4. Agreement is measured (e.g., ratio of agents approving the current version)
5. If threshold met → done. Otherwise → next round.

### Estimated Size
~500 lines across `strategy.lisp` and individual strategy files.

---

## Phase 3: Team-Aware Orchestration

**Goal:** Extend the conductor and event bus to support team operations.

### 3.1 Team Event Types

**File:** `platform/src/integration/events.lisp`

Add team-specific events to `integration-event-type`:

```lisp
:team-created          ; New team formed
:team-started          ; Team began execution
:team-completed        ; Team finished all work
:team-failed           ; Team encountered unrecoverable failure
:team-member-joined    ; Agent joined team
:team-member-left      ; Agent left team
:team-task-assigned    ; Task assigned to member
:team-task-completed   ; Member completed assigned task
:team-message          ; Inter-team message
:team-consensus-round  ; Consensus round completed
:team-debate-round     ; Debate round completed
```

### 3.2 Conductor Team Extensions

**File:** `platform/src/orchestration/conductor.lisp`

Add team dispatch to `dispatch-event`:

```lisp
(defun dispatch-event (conductor event-type event-data)
  (case event-type
    (:task-result ...)        ; existing
    (:team-created
     (let ((team-id (getf event-data :team-id)))
       (increment-metric conductor :teams-created)
       (log-team-event conductor :created team-id)))
    (:team-task-completed
     (let ((team-id (getf event-data :team-id))
           (agent-id (getf event-data :agent-id)))
       (check-team-completion conductor team-id)))
    (otherwise nil)))
```

### 3.3 Team Scheduling

Add a `:team` action type to the timer heap so teams can be scheduled:

```lisp
(:team
 (let ((team-id (getf action-plist :team-id))
       (task (getf action-plist :task)))
   (start-team team-id)
   ;; Strategy handles the rest via events
   ))
```

### 3.4 Team Metrics

Add to conductor metrics:
- `:teams-created`, `:teams-completed`, `:teams-failed`
- `:team-tasks-assigned`, `:team-tasks-completed`
- `:team-avg-completion-time`

### Estimated Size
~200 lines of additions to existing files.

---

## Phase 4: Team Capabilities (Agent-Callable Tools)

**Goal:** Expose team operations as capabilities that agents (especially Jarvis) can invoke.

### 4.1 Team Management Tools

**File:** `platform/src/integration/builtin-tools.lisp`

```lisp
(defcapability create-team (&key name strategy task members config)
  "Create a new agent team.
   NAME - Team name
   STRATEGY - :leader-worker, :swarm, :pipeline, :debate, :consensus
   TASK - Team-level task description
   MEMBERS - List of member configs, each: (:name N :provider P :system-prompt S)
   CONFIG - Strategy-specific config plist
   Returns team-id."
  :permissions (:orchestration)
  :body ...)

(defcapability add-team-member (&key team-id name provider capabilities)
  "Add a new member to an existing team."
  :permissions (:orchestration)
  :body ...)

(defcapability remove-team-member (&key team-id agent-id)
  "Remove a member from a team."
  :permissions (:orchestration)
  :body ...)

(defcapability start-team-work (&key team-id task)
  "Start the team working on TASK."
  :permissions (:orchestration)
  :body ...)

(defcapability query-team (&key team-id)
  "Get comprehensive team status."
  :permissions (:orchestration)
  :body ...)

(defcapability await-team (&key team-id timeout)
  "Wait for team to complete. Returns synthesized results."
  :permissions (:orchestration)
  :body ...)

(defcapability disband-team (&key team-id)
  "Stop and clean up a team."
  :permissions (:orchestration)
  :body ...)
```

### 4.2 Workspace Tools (for team members)

```lisp
(defcapability workspace-read (&key key)
  "Read from the team's shared workspace."
  :permissions ()
  :body ...)

(defcapability workspace-write (&key key value)
  "Write to the team's shared workspace."
  :permissions ()
  :body ...)

(defcapability workspace-claim-task ()
  "Claim the next available task from the team queue."
  :permissions ()
  :body ...)

(defcapability workspace-submit-result (&key task-id result)
  "Submit a completed task result to the workspace."
  :permissions ()
  :body ...)

(defcapability team-broadcast (&key message)
  "Send a message to all team members."
  :permissions ()
  :body ...)
```

### Estimated Size
~350 lines.

---

## Phase 5: Jarvis Meta-Orchestrator

**Goal:** Make Jarvis the intelligent control surface that translates natural language into team operations.

### 5.1 Jarvis Agent Configuration

**File:** New `platform/src/team/jarvis.lisp`

```lisp
(defun make-jarvis (&key provider)
  "Create the Jarvis meta-orchestrator agent.
   Jarvis has all team management + standard capabilities."
  (make-agentic-agent
   :name "jarvis"
   :provider (or provider (make-default-provider))
   :system-prompt *jarvis-system-prompt*
   :capabilities '(;; Team management
                   create-team add-team-member remove-team-member
                   start-team-work query-team await-team disband-team
                   ;; Agent management
                   spawn-agent query-agent await-agent
                   ;; Introspection
                   list-capabilities-tool inspect-thoughts
                   ;; Branching
                   fork-branch compare-branches
                   ;; File operations
                   read-file write-file list-directory glob-files grep-files
                   ;; Shell
                   run-command git-status git-diff git-log
                   ;; Session
                   save-session resume-session)
   :max-turns 50))
```

### 5.2 Jarvis System Prompt

```lisp
(defvar *jarvis-system-prompt*
  "You are Jarvis, the orchestrator of the Autopoiesis agent platform.

You manage teams of agents to accomplish complex tasks. You have these coordination strategies:

1. LEADER/WORKER - You decompose work, assign to specialists, synthesize results
2. SWARM - Run multiple agents in parallel on the same problem, pick the best
3. PIPELINE - Chain agents: each one's output feeds the next
4. DEBATE - Agents argue opposing positions, you judge
5. CONSENSUS - Agents iteratively refine a shared artifact until agreement

For each task, decide:
- Does this need a team, or can a single agent handle it?
- Which strategy fits best?
- How many agents, with what specializations?
- What does the shared workspace need?

Always prefer the simplest approach. A single focused agent beats a team for straightforward tasks.

After team completion, synthesize results clearly and suggest next steps.")
```

### 5.3 CLI Entry Point

**File:** New `platform/bin/jarvis`

```bash
#!/bin/bash
# Launch Jarvis from the command line
sbcl --load platform/scripts/jarvis-boot.lisp \
     --eval "(jarvis:repl)" "$@"
```

```lisp
;; jarvis-boot.lisp
(ql:quickload :autopoiesis)
(autopoiesis:start-system)
(defvar *jarvis* (autopoiesis.team:make-jarvis))

(defun jarvis:repl ()
  "Interactive Jarvis REPL."
  (format t "~&Jarvis online. Autopoiesis persistent core loaded.~%")
  (format t "How can I assist you today?~%~%")
  (loop
    (format t "> ")
    (force-output)
    (let ((input (read-line *standard-input* nil)))
      (when (or (null input) (string= input "exit") (string= input "quit"))
        (format t "~&Jarvis signing off.~%")
        (autopoiesis:stop-system)
        (return))
      (let ((response (agentic-agent-prompt *jarvis* input)))
        (format t "~&~a~%~%" response)))))
```

### 5.4 REST API Integration

Extend `platform/src/api/rest-server.lisp` with team endpoints:

```
POST /api/teams                  → create-team
GET  /api/teams                  → list-teams
GET  /api/teams/:id              → query-team
POST /api/teams/:id/start        → start-team-work
POST /api/teams/:id/pause        → pause-team
POST /api/teams/:id/resume       → resume-team
DELETE /api/teams/:id            → disband-team
GET  /api/teams/:id/workspace    → workspace contents
POST /api/teams/:id/members      → add-team-member
DELETE /api/teams/:id/members/:aid → remove-team-member
```

### Estimated Size
~400 lines across jarvis.lisp, jarvis-boot.lisp, and REST endpoint additions.

---

## Phase 6: Team Visualization

**Goal:** Extend the Holodeck and 2D timeline to show team topology and coordination.

### 6.1 Team Topology View (Holodeck)

**File:** `platform/src/holodeck/` additions

New ECS components:
- `team-node` — rendered as a cluster boundary (translucent sphere or box)
- `agent-node` — existing snapshot entity, colored by role (leader=gold, worker=blue, etc.)
- `message-edge` — animated particle flowing between connected agents
- `task-progress` — progress bar HUD element per agent

```lisp
(defun visualize-team (team-id &key mode)
  "Render team in Holodeck.
   MODE:
   - :topology — agents as nodes, messages as edges
   - :timeline — temporal view of task execution
   - :flow — data flow through pipeline stages")
```

### 6.2 2D Terminal Team View

**File:** `platform/src/viz/` additions

```
┌─ Team: security-audit (Leader/Worker) ──────────────────┐
│                                                          │
│  [LEADER] jarvis ████████████████░░░░ 80% synthesizing   │
│                                                          │
│  [WORKER] scanner-1  ████████████████████ 100% DONE ✓   │
│  [WORKER] scanner-2  ██████████████░░░░░░  70% running   │
│  [WORKER] scanner-3  ████████████████████ 100% DONE ✓   │
│  [WORKER] reviewer   ░░░░░░░░░░░░░░░░░░░░   0% waiting  │
│                                                          │
│  Tasks: 12/15 complete   Messages: 47   Elapsed: 2m 34s │
└──────────────────────────────────────────────────────────┘
```

### Estimated Size
~300 lines.

---

## Phase 7: Advanced Features

**Goal:** Higher-order patterns that compose the basic strategies.

### 7.1 Hierarchical Teams (Teams of Teams)

A team leader can itself create sub-teams, forming a tree:

```
Jarvis (meta)
├── Research Team (swarm: 5 agents)
├── Implementation Team (leader/worker: 4 agents)
│   ├── Frontend Sub-team (pipeline: 3 agents)
│   └── Backend Sub-team (pipeline: 3 agents)
└── Review Team (debate: 3 agents)
```

### 7.2 Dynamic Team Scaling

```lisp
(defun auto-scale-team (team-id &key min-workers max-workers load-metric)
  "Automatically add/remove workers based on queue depth.
   When task queue > threshold → spawn worker.
   When workers idle > timeout → remove worker.")
```

### 7.3 Team Snapshots and Time-Travel

Since teams are substrate entities, they participate in the snapshot system:

```lisp
(defun snapshot-team (team-id)
  "Create a snapshot of the entire team state:
   team entity + all member agent states + workspace + task queue.")

(defun restore-team (snapshot-id)
  "Restore a team from a snapshot, recreating all agents.")

(defun team-replay (team-id &key speed)
  "Replay team execution in the Holodeck at adjustable speed.")
```

### 7.4 Inter-Team Communication

Teams can communicate with other teams via the event bus:

```lisp
(defun team-send (from-team-id to-team-id message)
  "Send a message between teams. Delivered to the recipient team's leader.")
```

### 7.5 Learning from Team Outcomes

Extend the existing learning system to extract team-level patterns:

```lisp
(defun extract-team-patterns (team-id)
  "Analyze completed team execution to learn:
   - Which strategy worked best for this task type
   - Optimal team size
   - Which agent configurations performed well
   - Common failure modes")
```

### Estimated Size
~400 lines.

---

## Implementation Order and Dependencies

```
Phase 0 ──→ Phase 1 ──→ Phase 2 ──→ Phase 3
(CV fix)     (team       (strategies) (conductor
              model)                   integration)
                   │
                   └──→ Phase 4 ──→ Phase 5 ──→ Phase 6 ──→ Phase 7
                        (tools)     (Jarvis)    (viz)       (advanced)
```

**Phase 0** is prerequisite — without CV coordination, team fan-in is broken.

**Phases 1-3** build the core team runtime.

**Phases 4-5** make it usable via tools and Jarvis.

**Phases 6-7** add visualization and advanced features.

Phases 4-5 can overlap with Phase 3 since the tools layer doesn't depend on conductor integration being complete.

---

## File Structure

```
platform/src/team/
├── packages.lisp          ; Package definition: autopoiesis.team
├── team.lisp              ; Team class, lifecycle, registry
├── workspace.lisp         ; Shared workspace (substrate-backed)
├── strategy.lisp          ; Strategy protocol (generic functions)
├── strategies/
│   ├── leader-worker.lisp ; Leader/Worker implementation
│   ├── swarm.lisp         ; Swarm implementation
│   ├── pipeline.lisp      ; Pipeline implementation
│   ├── debate.lisp        ; Debate implementation
│   └── consensus.lisp     ; Consensus implementation
├── jarvis.lisp            ; Jarvis meta-orchestrator
└── visualization.lisp     ; Team visualization helpers

platform/test/
└── team-tests.lisp        ; Team test suite
```

ASDF additions to `autopoiesis.asd`:

```lisp
(:module "team"
  :depends-on ("core" "agent" "substrate" "orchestration" "integration")
  :serial t
  :components
  ((:file "packages")
   (:file "team")
   (:file "workspace")
   (:file "strategy")
   (:module "strategies"
     :serial t
     :components
     ((:file "leader-worker")
      (:file "swarm")
      (:file "pipeline")
      (:file "debate")
      (:file "consensus")))
   (:file "jarvis")
   (:file "visualization")))
```

---

## Estimated Total Size

| Phase | Lines | Description |
|-------|-------|-------------|
| 0 | ~150 | CV coordination, thread-safe mailboxes |
| 1 | ~350 | Team data model, workspace, registry |
| 2 | ~500 | Five coordination strategies |
| 3 | ~200 | Conductor + event bus extensions |
| 4 | ~350 | Team + workspace capabilities (tools) |
| 5 | ~400 | Jarvis orchestrator, CLI, REST |
| 6 | ~300 | Holodeck + terminal visualization |
| 7 | ~400 | Advanced features (hierarchical, scaling, learning) |
| **Total** | **~2,650** | New code on top of ~15,000+ existing |

Plus ~500 lines of tests per phase = ~4,000 lines of tests.

---

## Test Strategy

Each phase includes its own test suite within `team-tests.lisp`:

### Phase 0 Tests
- Thread-safe mailbox delivery under concurrent writes
- CV await completes immediately when agent already done
- CV await times out correctly
- `await-all-agents` with mix of fast/slow agents

### Phase 1 Tests
- Team creation with substrate persistence
- Team lifecycle transitions (forming → active → completed)
- Workspace read/write under concurrent access
- Task queue claim atomicity (Linda `take!`)
- Team serialization round-trip

### Phase 2 Tests
- Leader/Worker: task decomposition, distribution, synthesis
- Swarm: parallel execution, result evaluation, selection
- Pipeline: stage ordering, data passing, error propagation
- Debate: round management, rebuttal delivery, judge evaluation
- Consensus: convergence detection, round limiting

### Phase 3 Tests
- Team events emitted correctly on lifecycle transitions
- Conductor dispatches team-related events
- Team metrics update on conductor status

### Phase 4 Tests
- All team capabilities callable from agentic loop
- Workspace tools enforce team membership
- Error handling for invalid team/agent IDs

### Phase 5 Tests
- Jarvis creates appropriate team for task type
- End-to-end: natural language → team creation → execution → result
- CLI entry point integration test

---

## Key Design Decisions

### 1. Substrate-first, not in-memory

All team state lives in the substrate as datoms. This means:
- Teams survive process restarts
- Team state is snapshotable and time-travelable
- Coordination uses `take!` (Linda) for atomicity
- No lost state from crashes

### 2. Strategy as generic functions, not conditionals

Each coordination pattern is a CLOS class with generic function specializations. Adding a new strategy is:
1. Define a class
2. Specialize the 5 strategy generic functions
3. Register the strategy name

No `case` statements, no central dispatcher.

### 3. Agents are unaware of teams

An agent doesn't need to know it's on a team. From the agent's perspective, it receives tasks (via its cognitive loop), executes them, and produces results. The team layer orchestrates above.

This means any existing agent — including `agentic-agent` instances with any LLM provider — can participate in a team without modification.

### 4. Jarvis is just an agent with team tools

Jarvis isn't special infrastructure — it's an `agentic-agent` with the team management capabilities added to its tool list. Its "intelligence" comes from its system prompt and the LLM behind it. This means Jarvis can be snapshotted, branched, time-traveled, and even replaced.

### 5. Teams compose

A team member can be another team's leader (hierarchical teams). A swarm can contain pipeline sub-teams. This composability emerges naturally from the substrate representation — teams and agents are both entities.

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| CV coordination bugs under load | Medium | High | Extensive stress tests in Phase 0 |
| Substrate performance with 50 agents | Low | Medium | Value index already optimized; benchmark early |
| LLM-driven task decomposition quality | Medium | High | Fallback to explicit decomposition; human-in-the-loop |
| Strategy selection by Jarvis LLM | Medium | Low | Default to leader/worker; let user override |
| Deadlocks in team coordination | Medium | High | Timeout on all waits; conductor health checks |
| Message queue overflow | Low | Low | Bounded workspace log; event history already capped |

---

## Success Criteria

The implementation is complete when:

1. A user can say "Audit this codebase for security vulnerabilities" and Jarvis:
   - Creates a team with the right strategy
   - Spawns specialized agents (scanner, analyzer, reviewer)
   - Coordinates their work
   - Synthesizes a unified report
   - Cleans up resources

2. The entire team execution is observable:
   - Every agent's thoughts are recorded
   - The Holodeck shows team topology in real-time
   - Any point in the execution can be replayed via time-travel

3. Teams are fault-tolerant:
   - A crashed agent is detected and reported
   - The team can continue with remaining members
   - State survives process restart

4. Everything is an S-expression:
   - Teams, agents, tasks, results, workspace — all serializable
   - Structural sharing means minimal memory overhead
   - Branching a team is O(1)
