---
date: 2026-02-17
author: Claude
status: draft
tags: [plan, orchestration, coordination, provider, substrate]
---

# Coordination Primitives and Provider Lifecycle

## Overview

Two improvements inspired by the Spacebot comparison (see
`thoughts/shared/research/2026-02-17-spacebot-comparison.md`):

- **Phase 1**: Replace polling-based agent coordination with condition-variable
  notification, add fan-in (`await-all-agents`), add a coalesce window to the
  conductor, and fix unsafe mailbox access.
- **Phase 2**: Implement persistent provider sessions for Claude Code
  (`--resume`) and OpenCode (`opencode serve` HTTP+SSE), replacing one-shot
  subprocess spawning with long-lived, reattachable processes.

These phases are independent but Phase 2 benefits from Phase 1's notification
primitives — the persistent-session read loop uses the same CV pattern.

---

## Current State Analysis

### Coordination (Q2)

`await-agent` (`platform/src/integration/builtin-tools.lisp:518-548`) uses a
hardcoded 2-second `(sleep 2)` polling loop to check `:agent/status` datoms.
Maximum wait is 300 seconds = 150 sleep cycles, all wasted if the agent
finishes in 0.5 seconds.

The substrate hooks system (`platform/src/substrate/store.lisp:190-194`) fires
post-lock, synchronously after every `transact!`. Sub-agent threads write their
completion status via `transact!` (not `take!`, which bypasses hooks). This
means hooks are already the correct notification point for agent completion —
they just aren't wired to any condition variable today.

`*agent-mailboxes*` (`platform/src/agent/builtin-capabilities.lisp:53-54`) is
a global `hash-table` with no lock. `deliver-message` does `push` with no
synchronization. A sub-agent thread delivering to a mailbox while the main
agent reads it is a data race.

The conductor (`platform/src/orchestration/conductor.lisp:131-145`) drains
events with a `take!` loop but processes them sequentially, one per dispatch.
There is no primitive for "accumulate events arriving within N ms, then
dispatch them together" — useful for fan-out patterns where multiple sub-agents
finish near-simultaneously.

### Provider Lifecycle (Q1)

The `provider` base class already has `process`, `input-stream`,
`output-stream`, `session-id` slots and `provider-start-session` /
`provider-send` / `provider-stop-session` generic functions
(`platform/src/integration/provider.lisp:48-63`, `158-185`). All three default
methods signal `"does not support streaming sessions"`.

`provider-claude-code.lisp` declares `(:modes (:one-shot :streaming))` but
the `:streaming` mode is never implemented — there's no `provider-start-session`
specializer on `claude-code-provider`.

`provider-opencode.lisp` has `use-server` and `server-port` extra slots and
even declares `(:modes (:one-shot :streaming))` conditionally — but again no
`provider-start-session` specializer exists.

`run-provider-subprocess` (`provider.lisp:237-317`) itself has a `(sleep 0.1)`
polling loop (line 298-308) waiting for `sb-ext:process-alive-p` to return
nil. This is the same pattern as `await-agent` and similarly wasteful.

---

## Desired End State

### After Phase 1

- `await-agent` uses a condition variable signaled by a substrate hook. It
  wakes within milliseconds of agent completion instead of up to 2 seconds
  late. The `sleep 2` loop is gone.
- `await-all-agents` is a new tool that takes a list of agent IDs and blocks
  until all are complete (or any fail, or timeout expires), collecting all
  results in one call.
- A `with-coalesce-window` macro in the conductor accumulates events arriving
  within a configurable window (default 50ms) and dispatches them as a list.
  Used by conductor dispatch handlers that want to batch near-simultaneous
  events.
- `*agent-mailboxes*` is protected by a lock. `deliver-message` and
  `receive-messages` are thread-safe.
- All existing orchestration tests pass. New tests cover CV notification timing
  and await-all semantics.

### After Phase 2

- `claude-code-provider` supports a `:persistent` invocation mode where it:
  1. Starts `claude --resume <session-id>` as a long-lived process OR reuses an
     existing session ID from a previous invocation.
  2. Accepts follow-up prompts mid-session via `provider-send`.
  3. Streams `stream-json` events in real time, emitting
     `:provider-partial-result` integration events per text chunk.
  4. Can be reattached after a restart by storing `session-id` in the substrate.
- `opencode-provider` supports a `:server` invocation mode where it:
  1. Starts `opencode serve --port N` as a long-lived HTTP+SSE process OR
     reattaches to an already-running one via health check.
  2. Creates/resumes sessions via `POST /session`.
  3. Streams SSE events, emitting `:provider-partial-result` per `MessagePart`.
  4. Sends follow-up messages via additional `POST /session/{id}/message` calls.
- A `provider-pool` manages these persistent processes (keyed by working
  directory + port), handles health checks, and reattaches after restart.
- `run-provider-subprocess`'s `(sleep 0.1)` polling loop is replaced with a
  CV-based wait using the primitives from Phase 1.
- All existing provider tests pass. New tests cover session lifecycle,
  reattach, follow-up sends, and SSE event parsing.

### Key Discoveries

- `take!` bypasses `%transact-immediate!` and does **not** fire hooks
  (`linda.lisp:76-80`). Sub-agent completion is written via `transact!` (in
  `builtin-tools.lisp:484-491`), so hooks will fire. This is the correct
  notification path.
- The hooks snapshot at `store.lisp:186-187` uses `stable-sort` by priority —
  a new "agent-cv-notifier" hook can be registered at priority 10 (after
  default hooks at priority 0) to fire last and avoid interfering.
- `provider-backed-agent.act` already acquires `provider-lock` before
  `provider-invoke` (`provider-agent.lisp:97`). The persistent-session
  `provider-send` must also acquire this lock.
- OpenCode `opencode serve` is confirmed in Spacebot source — deterministic
  port from `hash(directory)`. We can use a simpler approach: fixed port per
  provider instance from `server-port` slot (already exists).
- Claude Code `--resume <session-id>` is the reattach mechanism. The session ID
  is already in `provider-result` from the `:json-object` parser
  (`provider-claude-code.lisp:52`). Store it in the provider's `session-id`
  slot after first invocation.

---

## What We're NOT Doing

- **No Rig/framework adoption** — staying pure CL with bordeaux-threads and
  SBCL primitives.
- **No WebSocket support** — OpenCode HTTP+SSE is sufficient; no need for
  bidirectional WS.
- **No rate-limit routing** — Spacebot's 4-level model routing is out of scope.
- **No conductor-level coalescing for existing event types** — the coalesce
  window is a new opt-in primitive, not applied retroactively to `:task-result`
  dispatch.
- **No automatic retry scheduling** — the existing `handle-task-result` backoff
  logic (logs but doesn't reschedule) is not changed.
- **No Codex or Cursor persistent sessions** — only Claude Code and OpenCode.

---

## Implementation Approach

Phase 1 is purely additive to the substrate and orchestration layers, with no
changes to provider code. It adds one hook, one new global for CV storage, and
rewrites `await-agent` + adds `await-all-agents`.

Phase 2 adds specializer methods on existing CLOS generic functions. The
`define-cli-provider` macro is not changed — provider-specific session logic
lives in hand-written `defmethod` forms in the provider files, since the macro
is designed for the one-shot path.

---

## Phase 1: Condition Variable Coordination

### Overview

Add CV-based notification for agent completion, safe mailboxes, fan-in
`await-all-agents`, and a coalesce window in the conductor.

### Changes Required

#### 1. New: Agent completion condition variable table

**File**: `platform/src/agent/builtin-capabilities.lisp`

Add a global table mapping `agent-eid` → `(lock . condition-variable)` pair.
Register a substrate hook that fires when `:agent/status` datoms are written,
signals the CV for the matching entity.

```lisp
;; New globals (after *agent-mailboxes* at line 54)
(defvar *agent-completion-cvs* (make-hash-table :test 'eql)
  "Maps agent-eid -> (lock . cv) for condition-variable-based await.")

(defvar *agent-completion-cvs-lock* (bt:make-lock "agent-completion-cvs")
  "Lock protecting *agent-completion-cvs* table itself.")

(defun get-or-create-agent-cv (agent-eid)
  "Return the (lock . cv) pair for AGENT-EID, creating if absent."
  (bt:with-lock-held (*agent-completion-cvs-lock*)
    (or (gethash agent-eid *agent-completion-cvs*)
        (setf (gethash agent-eid *agent-completion-cvs*)
              (cons (bt:make-lock "agent-cv")
                    (bt:make-condition-variable :name "agent-cv"))))))

(defun cleanup-agent-cv (agent-eid)
  "Remove the CV entry for AGENT-EID after it has been awaited."
  (bt:with-lock-held (*agent-completion-cvs-lock*)
    (remhash agent-eid *agent-completion-cvs*)))
```

#### 2. Register the completion notification hook

**File**: `platform/src/agent/builtin-capabilities.lisp`

Add a substrate hook registration call in `register-builtin-capabilities`.
The hook fires after every `transact!` — it filters for `:agent/status` datoms
whose new value is `:complete` or `:failed`, then signals the matching CV.

```lisp
;; Called from register-builtin-capabilities
(defun register-agent-completion-hook ()
  "Register a substrate hook that signals CVs when agent status changes."
  (when autopoiesis.substrate:*store*
    (autopoiesis.substrate:register-hook
     autopoiesis.substrate:*store*
     :agent-completion-notifier
     (lambda (datoms tx-id)
       (declare (ignore tx-id))
       (dolist (datom datoms)
         (when (and (eq (autopoiesis.substrate:d-attribute datom)
                        (autopoiesis.substrate:intern-id :agent/status))
                    (member (autopoiesis.substrate:d-value datom)
                            '(:complete :failed))
                    (autopoiesis.substrate:d-added datom))
           (let ((pair (bt:with-lock-held (*agent-completion-cvs-lock*)
                         (gethash (autopoiesis.substrate:d-entity datom)
                                  *agent-completion-cvs*))))
             (when pair
               (bt:with-lock-held ((car pair))
                 (bt:condition-notify (cdr pair))))))))
     :priority 10)))
```

**Note**: The hook receives raw datom structs. `d-attribute` is an integer aid.
We need to compare against the interned id for `:agent/status`. Use
`(autopoiesis.substrate:intern-id :agent/status)` once at hook registration
time and capture it in the closure.

Revised version capturing the aid at registration:

```lisp
(defun register-agent-completion-hook ()
  (when autopoiesis.substrate:*store*
    (let ((status-aid (autopoiesis.substrate:intern-id :agent/status)))
      (autopoiesis.substrate:register-hook
       autopoiesis.substrate:*store*
       :agent-completion-notifier
       (lambda (datoms tx-id)
         (declare (ignore tx-id))
         (dolist (datom datoms)
           (when (and (= (autopoiesis.substrate:d-attribute datom) status-aid)
                      (member (autopoiesis.substrate:d-value datom)
                              '(:complete :failed))
                      (autopoiesis.substrate:d-added datom))
             (let ((pair (bt:with-lock-held (*agent-completion-cvs-lock*)
                           (gethash (autopoiesis.substrate:d-entity datom)
                                    *agent-completion-cvs*))))
               (when pair
                 (bt:with-lock-held ((car pair))
                   (bt:condition-notify (cdr pair))))))))
       :priority 10))))
```

#### 3. Rewrite `await-agent` to use CV

**File**: `platform/src/integration/builtin-tools.lisp`

Replace the `(sleep 2)` polling loop (lines 537-547) with a CV wait. Create
the CV entry before checking status to avoid the race where the agent
completes between the status check and the CV creation.

```lisp
;; New await-agent body (replaces lines 518-548):
(defun %await-agent-impl (agent-id &key timeout)
  (let* ((max-wait (or timeout 300))
         (agent-eid (autopoiesis.substrate:intern-id agent-id))
         ;; Create CV entry BEFORE reading status (no race)
         (pair (get-or-create-agent-cv agent-eid))
         (cv-lock (car pair))
         (cv (cdr pair)))
    (unwind-protect
        (let ((status (autopoiesis.substrate:entity-attr agent-eid :agent/status)))
          (cond
            ((not status)
             (format nil "Error: Agent ~a not found" agent-id))
            ((member status '(:complete :failed))
             ;; Already done before we started waiting
             (%format-agent-result agent-eid agent-id status))
            (t
             ;; Wait for completion notification
             (let ((deadline (+ (get-universal-time) max-wait)))
               (loop
                 (bt:with-lock-held (cv-lock)
                   (let ((remaining (- deadline (get-universal-time))))
                     (when (<= remaining 0)
                       (return (format nil "Timeout: agent ~a did not complete within ~as"
                                       agent-id max-wait)))
                     (bt:condition-wait cv cv-lock :timeout remaining)))
                 (let ((current-status (autopoiesis.substrate:entity-attr
                                        agent-eid :agent/status)))
                   (when (member current-status '(:complete :failed))
                     (return (%format-agent-result agent-eid agent-id current-status)))))))))
      (cleanup-agent-cv agent-eid))))
```

The `(get-universal-time)` deadline arithmetic uses integer seconds (same as
the old `elapsed` counter). `bt:condition-wait` accepts `:timeout` in seconds
as a real number — pass `remaining` directly.

#### 4. Add `await-all-agents` tool

**File**: `platform/src/integration/builtin-tools.lisp`

New tool after `await-agent`. Accepts a space-separated string of agent IDs
(matching the pattern used by other multi-value tool inputs), calls
`%await-agent-impl` for each concurrently via `bt:make-thread`, collects
results.

```lisp
(defcapability await-all-agents
    (&key agent-ids timeout)
    (:permissions (:orchestration)
     :description "Wait for multiple agents to complete, collecting all results.
AGENT-IDS - space-separated list of agent IDs (as returned by spawn_agent)
TIMEOUT - seconds to wait for each agent (default 300)
Returns a formatted report of all agent outcomes.")
  (let* ((ids (split-sequence:split-sequence #\Space agent-ids
                                              :remove-empty-subseqs t))
         (results (make-array (length ids) :initial-element nil))
         (threads (loop for id in ids
                        for i from 0
                        collect (let ((id id) (i i))
                                  (bt:make-thread
                                   (lambda ()
                                     (setf (aref results i)
                                           (cons id (%await-agent-impl id :timeout timeout))))
                                   :name (format nil "await-~a" id))))))
    (dolist (thread threads)
      (bt:join-thread thread))
    (with-output-to-string (s)
      (format s "await-all-agents results (~a agents):~%" (length ids))
      (loop for (id . result) across results
            do (format s "  ~a: ~a~%" id result)))))
```

**Note**: `split-sequence` is available via the `split-sequence` quicklisp
package which is already a transitive dependency. If not available directly,
use `(loop for start = 0 then (1+ end) ...)` inline split.

#### 5. Fix `*agent-mailboxes*` thread safety

**File**: `platform/src/agent/builtin-capabilities.lisp`

Add a lock protecting the per-mailbox list. The existing pattern of a global
hash-table with list values can be protected with a single global lock (low
contention — mailbox access is rare relative to substrate operations).

```lisp
;; Add after *agent-mailboxes* declaration:
(defvar *agent-mailboxes-lock* (bt:make-lock "agent-mailboxes")
  "Lock protecting *agent-mailboxes* hash table.")

;; Rewrite deliver-message:
(defun deliver-message (message)
  (let ((to-id (message-to message)))
    (bt:with-lock-held (*agent-mailboxes-lock*)
      (push message (gethash to-id *agent-mailboxes*)))
    message))

;; Rewrite receive-messages:
(defun receive-messages (agent-id &key clear)
  (bt:with-lock-held (*agent-mailboxes-lock*)
    (let ((msgs (reverse (gethash agent-id *agent-mailboxes*))))
      (when clear
        (setf (gethash agent-id *agent-mailboxes*) nil))
      msgs)))
```

#### 6. Add `with-coalesce-window` to conductor

**File**: `platform/src/orchestration/conductor.lisp`

Add a macro that accumulates events with the same `:event/type` that arrive
within a time window, then calls the body with the full list. This is purely
opt-in — existing `dispatch-event` is unchanged.

```lisp
(defmacro with-coalesce-window ((events-var event-type &key (window-ms 50)) &body body)
  "Accumulate all pending events of EVENT-TYPE within WINDOW-MS milliseconds,
   bind them to EVENTS-VAR as a list, then execute BODY.
   Claims all matching events via take! in a burst, waits WINDOW-MS for more."
  (let ((deadline-var (gensym "deadline"))
        (acc-var (gensym "acc")))
    `(let ((,acc-var nil)
           (,deadline-var (+ (get-internal-real-time)
                             (* ,window-ms (/ internal-time-units-per-second 1000)))))
       ;; Drain any already-pending events of this type
       (loop for eid = (autopoiesis.substrate:take! :event/type ,event-type
                                                    :new-value :coalescing)
             while eid
             do (push eid ,acc-var))
       ;; Wait for the window to expire, picking up stragglers
       (loop while (< (get-internal-real-time) ,deadline-var)
             do (sleep 0.01)
                (loop for eid = (autopoiesis.substrate:take! :event/type ,event-type
                                                             :new-value :coalescing)
                      while eid
                      do (push eid ,acc-var)))
       (let ((,events-var (nreverse ,acc-var)))
         ,@body))))
```

**Usage example in a handler**:
```lisp
;; Instead of dispatching :agent-batch-results one at a time:
(with-coalesce-window (events :agent-batch-result :window-ms 50)
  (when events
    (process-batch-agent-results conductor events)))
```

This is not wired into `dispatch-event` by default — it's a building block for
future handlers that want to batch multiple near-simultaneous events.

### New Tests

**File**: `platform/test/orchestration-tests.lisp` (add to existing suite)

```
- await-agent-cv-notification: spawn agent, verify await-agent returns within
  100ms of completion (not up to 2s late)
- await-agent-already-complete: agent already done before await-agent called
- await-agent-timeout: agent never completes, verify timeout string returned
- await-all-agents-all-succeed: 3 agents, all complete, verify all results
- await-all-agents-partial-failure: one fails, others succeed
- deliver-message-thread-safety: 10 threads deliver concurrently, no lost msgs
- coalesce-window-drains-burst: queue 5 events, coalesce window returns all 5
```

### Success Criteria

#### Automated Verification

- [ ] `./platform/scripts/test.sh` passes all existing suites
- [ ] New orchestration-tests assertions pass (CV notification, await-all,
      mailbox safety, coalesce window)
- [ ] `(5am:run! 'autopoiesis.test::orchestration-tests)` — 0 failures
- [ ] `(5am:run! 'autopoiesis.test::integration-tests)` — 0 failures

#### Manual Verification

- [ ] Start a sub-agent from the CLI, observe `await_agent` returns promptly
      (under 100ms of actual completion) rather than up to 2s late
- [ ] Verify `await_all_agents` with 3 concurrent sub-agents returns all three
      results in one call

**Implementation Note**: After Phase 1 automated verification passes, pause for
manual confirmation before proceeding to Phase 2.

---

## Phase 2: Persistent Provider Sessions

### Overview

Implement `provider-start-session`, `provider-send`, and `provider-stop-session`
for Claude Code (via `--resume`) and OpenCode (via HTTP+SSE). Add a provider
pool for reattach-after-restart. Replace `run-provider-subprocess`'s polling
loop with the CV notification from Phase 1.

### Changes Required

#### 1. Fix `run-provider-subprocess` polling loop

**File**: `platform/src/integration/provider.lisp`

Replace the `(sleep 0.1)` loop at lines 298-308 with a CV-based wait. The
stdout/stderr reader threads already exist — signal a CV when they finish.

```lisp
;; Replace the poll loop (lines 297-308) with:
(let ((done-lock (bt:make-lock "provider-done"))
      (done-cv (bt:make-condition-variable :name "provider-done"))
      (done-p nil))
  ;; Wrap each reader thread to signal on exit
  (flet ((make-reader-thread (stream name)
           (bt:make-thread
            (lambda ()
              (prog1
                  (with-output-to-string (s)
                    (loop for line = (read-line stream nil nil)
                          while line
                          do (write-line line s)))
                (bt:with-lock-held (done-lock)
                  (setf done-p t)
                  (bt:condition-notify done-cv))))
            :name name)))
    (let ((stdout-thread (make-reader-thread stdout-stream "provider-stdout"))
          (stderr-thread (make-reader-thread stderr-stream "provider-stderr")))
      ;; Wait for process exit or timeout using CV
      (bt:with-lock-held (done-lock)
        (loop until (or done-p (> (get-internal-real-time) deadline))
              do (let ((remaining (/ (- deadline (get-internal-real-time))
                                     internal-time-units-per-second)))
                   (when (> remaining 0)
                     (bt:condition-wait done-cv done-lock :timeout remaining)))))
      ;; Timeout handling (same as before)
      (when (sb-ext:process-alive-p process)
        (ignore-errors (sb-ext:process-kill process sb-unix:sigterm))
        (sleep 5)
        (when (sb-ext:process-alive-p process)
          (ignore-errors (sb-ext:process-kill process sb-unix:sigkill))))
      (values (bt:join-thread stdout-thread)
              (bt:join-thread stderr-thread)
              (sb-ext:process-exit-code process)))))
```

#### 2. Add `:provider-partial-result` integration event type

**File**: `platform/src/integration/events.lisp`

Add `:provider-partial-result` and `:provider-session-reattached` to the
`deftype` member list (line ~14). These fire during streaming to allow
subscribers to see incremental output.

```lisp
;; In the (deftype event-type ...) member list, add:
;;   :provider-partial-result   ; streaming text chunk received
;;   :provider-session-reattached ; existing session reused after restart
```

#### 3. Add provider pool

**New file**: `platform/src/integration/provider-pool.lisp`

```lisp
;;;; provider-pool.lisp - Pool of persistent provider processes

(in-package #:autopoiesis.integration)

(defvar *provider-pool* (make-hash-table :test 'equal)
  "Maps (provider-name . working-directory) -> provider instance with live session.")

(defvar *provider-pool-lock* (bt:make-lock "provider-pool")
  "Lock protecting *provider-pool*.")

(defun pool-key (provider)
  "Compute the pool key for PROVIDER."
  (cons (provider-name provider)
        (provider-working-directory provider)))

(defun pool-get (provider)
  "Return a live pooled provider instance, or NIL."
  (bt:with-lock-held (*provider-pool-lock*)
    (let* ((key (pool-key provider))
           (pooled (gethash key *provider-pool*)))
      (when (and pooled (provider-alive-p pooled))
        pooled))))

(defun pool-put (provider)
  "Register PROVIDER in the pool."
  (bt:with-lock-held (*provider-pool-lock*)
    (setf (gethash (pool-key provider) *provider-pool*) provider)))

(defun pool-remove (provider)
  "Remove PROVIDER from the pool."
  (bt:with-lock-held (*provider-pool-lock*)
    (remhash (pool-key provider) *provider-pool*)))

(defun pool-shutdown-all ()
  "Stop all pooled providers. Call on system shutdown."
  (bt:with-lock-held (*provider-pool-lock*)
    (loop for provider being the hash-values of *provider-pool*
          do (ignore-errors (provider-stop-session provider)))
    (clrhash *provider-pool*)))
```

#### 4. Implement Claude Code persistent session

**File**: `platform/src/integration/provider-claude-code.lisp`

Add three method specializations. The session lifecycle:

1. `provider-start-session`: If `provider-session-id` is set, run
   `claude --resume <id>` with stdin open for follow-up messages. Otherwise
   start fresh and parse the `session_id` from the first response to store it.
2. `provider-send`: Write the follow-up message to the process stdin.
3. `provider-stop-session`: Close stdin gracefully (Claude Code exits when
   stdin closes), wait briefly, SIGTERM if still alive.

The streaming output is `--output-format stream-json` lines — emit
`:provider-partial-result` events for `"type":"text"` events, and
`:provider-response` when `"type":"result"` is seen.

```lisp
(defmethod provider-start-session ((provider claude-code-provider))
  "Start a persistent Claude Code session, reusing session-id if present."
  (let* ((args (list "--output-format" "stream-json" "--verbose"
                     "--max-turns" (format nil "~a" (provider-max-turns provider))
                     "--dangerously-skip-permissions"))
         (args (if (provider-session-id provider)
                   (append (list "--resume" (provider-session-id provider)) args)
                   args))
         (args (if (provider-default-model provider)
                   (append args (list "--model" (provider-default-model provider)))
                   args))
         (process (sb-ext:run-program (provider-command provider) args
                                      :input :stream
                                      :output :stream
                                      :error :output
                                      :wait nil
                                      :search t
                                      :directory (provider-working-directory provider))))
    (unless process
      (error 'autopoiesis.core:autopoiesis-error
             :message "Failed to start Claude Code session"))
    (setf (provider-process provider) process
          (provider-input-stream provider) (sb-ext:process-input process)
          (provider-output-stream provider) (sb-ext:process-output process))
    (emit-integration-event :provider-session-started :claude-code
                            (list :session-id (provider-session-id provider)))
    provider))

(defmethod provider-send ((provider claude-code-provider) message)
  "Send a follow-up message to the running Claude Code session."
  (unless (provider-alive-p provider)
    (error 'autopoiesis.core:autopoiesis-error
           :message "Claude Code session is not running"))
  (let ((stdin (provider-input-stream provider)))
    (write-line message stdin)
    (force-output stdin))
  message)

(defmethod provider-stop-session ((provider claude-code-provider))
  "Stop the Claude Code session by closing stdin and waiting."
  (when (provider-process provider)
    (ignore-errors
      (when (provider-input-stream provider)
        (close (provider-input-stream provider))))
    (sleep 2)
    (when (provider-alive-p provider)
      (ignore-errors
        (sb-ext:process-kill (provider-process provider) sb-unix:sigterm)))
    (setf (provider-process provider) nil
          (provider-input-stream provider) nil
          (provider-output-stream provider) nil))
  (pool-remove provider))

;; Streaming invoke specializer (used when :mode :persistent)
(defmethod provider-invoke ((provider claude-code-provider) prompt
                            &key tools mode agent-id)
  (if (eq mode :persistent)
      (%claude-code-persistent-invoke provider prompt :tools tools :agent-id agent-id)
      (call-next-method)))

(defun %claude-code-persistent-invoke (provider prompt &key tools agent-id)
  "Invoke Claude Code in persistent session mode."
  (declare (ignore tools)) ; tools handled by the running session's allowed-tools config
  ;; Get or start session
  (unless (provider-alive-p provider)
    (provider-start-session provider)
    (pool-put provider))
  (emit-integration-event :provider-request :claude-code
                          (list :prompt (truncate-string (format nil "~a" prompt) 200)
                                :mode :persistent)
                          :agent-id agent-id)
  ;; Send the prompt
  (provider-send provider prompt)
  ;; Read streaming response until result event
  (let* ((output-stream (provider-output-stream provider))
         (text-parts nil)
         (result-text nil)
         (start-time (get-internal-real-time)))
    (loop for line = (read-line output-stream nil nil)
          while line
          do (ignore-errors
               (let* ((json (cl-json:decode-json-from-string line))
                      (type (cdr (assoc :type json))))
                 (cond
                   ((string= type "text")
                    (let ((text (cdr (assoc :text json))))
                      (when text
                        (push text text-parts)
                        (emit-integration-event :provider-partial-result :claude-code
                                                (list :text text)
                                                :agent-id agent-id))))
                   ((string= type "result")
                    (setf result-text (cdr (assoc :result json)))
                    ;; Capture session-id for resume
                    (let ((sid (cdr (assoc :session-id json))))
                      (when sid (setf (provider-session-id provider) sid)))
                    (return)))))
          until result-text)
    (let* ((duration (/ (- (get-internal-real-time) start-time)
                        internal-time-units-per-second))
           (result (make-instance 'provider-result
                                  :text (or result-text
                                            (format nil "~{~a~}" (nreverse text-parts)))
                                  :provider-name (provider-name provider)
                                  :duration duration
                                  :exit-code 0
                                  :session-id (provider-session-id provider))))
      (emit-integration-event :provider-response :claude-code
                              (list :duration duration :mode :persistent)
                              :agent-id agent-id)
      result)))
```

#### 5. Implement OpenCode HTTP+SSE session

**File**: `platform/src/integration/provider-opencode.lisp`

OpenCode's server mode is fundamentally HTTP-based. The CL side uses
`dexador` (already a dependency) for `POST /session` and `GET /session/events`
SSE streaming.

```lisp
(defmethod provider-start-session ((provider opencode-provider))
  "Start opencode serve and wait for it to be healthy."
  (let* ((port (opencode-server-port provider))
         (base-url (format nil "http://localhost:~a" port)))
    ;; Try to reattach to existing server first
    (unless (%opencode-healthy-p base-url)
      ;; Start the server
      (let ((process (sb-ext:run-program (provider-command provider)
                                         (list "serve" "--port" (format nil "~a" port))
                                         :input nil
                                         :output :stream
                                         :error :output
                                         :wait nil
                                         :search t
                                         :directory (provider-working-directory provider))))
        (unless process
          (error 'autopoiesis.core:autopoiesis-error
                 :message "Failed to start OpenCode server"))
        (setf (provider-process provider) process))
      ;; Wait for health (30 attempts x 1s)
      (loop repeat 30
            until (%opencode-healthy-p base-url)
            do (sleep 1)
            finally (unless (%opencode-healthy-p base-url)
                      (error 'autopoiesis.core:autopoiesis-error
                             :message (format nil "OpenCode server did not start on port ~a" port)))))
    (setf (provider-session-id provider) nil) ; will be set on first invoke
    (emit-integration-event :provider-session-started :opencode
                            (list :port port
                                  :reattached (provider-process provider)))
    provider))

(defun %opencode-healthy-p (base-url)
  "Return T if the OpenCode server is responding."
  (ignore-errors
    (dex:get (format nil "~a/health" base-url)
             :connect-timeout 1)
    t))

(defmethod provider-send ((provider opencode-provider) message)
  "Send a follow-up message to the active OpenCode session."
  (unless (provider-session-id provider)
    (error 'autopoiesis.core:autopoiesis-error
           :message "No active OpenCode session"))
  (let ((url (format nil "http://localhost:~a/session/~a/message"
                     (opencode-server-port provider)
                     (provider-session-id provider))))
    (dex:post url
              :headers '(("Content-Type" . "application/json"))
              :content (cl-json:encode-json-to-string
                        (list (cons "content" message)))))
  message)

(defmethod provider-stop-session ((provider opencode-provider))
  "Stop the OpenCode server process."
  (when (provider-process provider)
    (ignore-errors
      (sb-ext:process-kill (provider-process provider) sb-unix:sigterm))
    (setf (provider-process provider) nil
          (provider-session-id provider) nil))
  (pool-remove provider))

;; SSE streaming invoke
(defmethod provider-invoke ((provider opencode-provider) prompt
                            &key tools mode agent-id)
  (declare (ignore tools))
  (if (and (eq mode :server) (opencode-use-server provider))
      (%opencode-server-invoke provider prompt :agent-id agent-id)
      (call-next-method)))

(defun %opencode-server-invoke (provider prompt &key agent-id)
  "Invoke OpenCode via HTTP+SSE server mode."
  (unless (provider-alive-p provider)
    (provider-start-session provider)
    (pool-put provider))
  (let* ((port (opencode-server-port provider))
         (base-url (format nil "http://localhost:~a" port)))
    ;; Create or resume session
    (let ((session-id (or (provider-session-id provider)
                          (let ((resp (dex:post (format nil "~a/session" base-url)
                                                :headers '(("Content-Type" . "application/json"))
                                                :content "{}")))
                            (cdr (assoc :id (cl-json:decode-json-from-string resp)))))))
      (setf (provider-session-id provider) session-id)
      ;; Send the prompt
      (dex:post (format nil "~a/session/~a/message" base-url session-id)
                :headers '(("Content-Type" . "application/json"))
                :content (cl-json:encode-json-to-string
                          (list (cons "content" prompt))))
      (emit-integration-event :provider-request :opencode
                              (list :prompt (truncate-string (format nil "~a" prompt) 200)
                                    :session session-id)
                              :agent-id agent-id)
      ;; Stream SSE events
      (let ((text-parts nil)
            (start-time (get-internal-real-time)))
        (dex:get (format nil "~a/session/~a/events" base-url session-id)
                 :headers '(("Accept" . "text/event-stream"))
                 :want-stream t
                 :callback
                 (lambda (chunk)
                   (let ((line (string-trim '(#\Space #\Newline #\Return) chunk)))
                     (when (and (> (length line) 6)
                                (string= (subseq line 0 6) "data: "))
                       (let* ((data (subseq line 6))
                              (json (ignore-errors (cl-json:decode-json-from-string data)))
                              (type (and json (cdr (assoc :type json)))))
                         (cond
                           ((string= type "MessagePartUpdated")
                            (let* ((part (cdr (assoc :part json)))
                                   (text (and part (cdr (assoc :text part)))))
                              (when text
                                (push text text-parts)
                                (emit-integration-event :provider-partial-result :opencode
                                                        (list :text text)
                                                        :agent-id agent-id))))
                           ((string= type "SessionCompleted")
                            ;; Signal done — raise a non-local exit
                            (return-from %opencode-server-invoke
                              (let* ((duration (/ (- (get-internal-real-time) start-time)
                                                  internal-time-units-per-second))
                                     (result (make-instance 'provider-result
                                                            :text (format nil "~{~a~}" (nreverse text-parts))
                                                            :provider-name (provider-name provider)
                                                            :duration duration
                                                            :exit-code 0
                                                            :session-id session-id)))
                                (emit-integration-event :provider-response :opencode
                                                        (list :duration duration)
                                                        :agent-id agent-id)
                                result)))))))))
        ;; Fallback if SSE callback didn't return
        (let* ((duration (/ (- (get-internal-real-time) start-time)
                            internal-time-units-per-second)))
          (make-instance 'provider-result
                         :text (format nil "~{~a~}" (nreverse text-parts))
                         :provider-name (provider-name provider)
                         :duration duration
                         :session-id session-id))))))
```

**Note on dexador SSE**: `dex:get` with `:want-stream t` returns a stream.
The `:callback` parameter shown above is a simplification — actual dexador
streaming API may require reading from the returned stream in a loop. The
implementation should use `(dex:get url :want-stream t)` → stream, then
`(read-line stream nil nil)` in a loop, parsing SSE `data:` lines. The callback
pattern is illustrative; the actual implementation should use the loop approach
for clarity.

#### 6. Register provider-pool shutdown on system stop

**File**: `platform/src/integration/packages.lisp` (or wherever `stop-system`
is defined)

Add `(pool-shutdown-all)` to the `stop-system` function to clean up persistent
processes on shutdown.

#### 7. Add provider-pool to ASDF system definition

**File**: `platform/autopoiesis.asd`

Add `provider-pool` to the `:components` list after `provider` and before
`provider-claude-code`.

### New Tests

**File**: `platform/test/provider-tests.lisp` (add to existing suite)

- `claude-code-session-lifecycle`: start session, send a follow-up,
  stop session — all without real subprocess (mock `sb-ext:run-program`)
- `claude-code-reattach`: set `session-id`, verify `--resume` appears in args
- `opencode-server-healthy-check`: verify `%opencode-healthy-p` with mocked
  HTTP response
- `opencode-sse-event-parsing`: parse fixture `SessionCompleted` and
  `MessagePartUpdated` events from string, verify text accumulation
- `provider-pool-get-put-remove`: round-trip pool operations
- `provider-pool-dead-process-not-returned`: pool returns nil for dead provider

### Success Criteria

#### Automated Verification

- [ ] `./platform/scripts/test.sh` passes all suites
- [ ] `(5am:run! 'autopoiesis.test::provider-tests)` — 0 failures including
      new session lifecycle tests
- [ ] `(5am:run! 'autopoiesis.test::orchestration-tests)` — 0 failures
- [ ] `(5am:run! 'autopoiesis.test::integration-tests)` — 0 failures
- [ ] `(ql:quickload :autopoiesis)` completes without errors (provider-pool
      in system definition)

#### Manual Verification

- [ ] `(make-claude-code-provider :working-directory "/tmp/test")` +
      `(provider-start-session p)` + `(provider-send p "list files")` —
      observe streaming output
- [ ] Kill and restart SBCL, re-call `provider-start-session` — verify
      `--resume` flag is used and session continues
- [ ] `(make-opencode-provider :use-server t :server-port 4096)` +
      `(provider-start-session p)` — verify `opencode serve` process starts
      and health check passes
- [ ] Send a follow-up via `(provider-send p "what files are there?")` and
      observe SSE events streaming back

---

## Testing Strategy

### Unit Tests

- CV notification fires within 10ms of agent status write
- `await-agent` returns `:complete` result immediately (no sleep) when agent
  already done
- Mailbox `push`/`receive` under 10 concurrent threads — no lost messages
- Pool `get` returns nil for dead process, non-nil for live one
- Provider command builder includes `--resume <id>` when `session-id` set

### Integration Tests

- Full `spawn-agent` → `await-agent` round trip with real substrate store
- `await-all-agents` with 3 agents finishing at different times
- Provider pool reattach after `provider-stop-session` then `provider-start-session`

### Manual Testing Steps

1. `(asdf:test-system :autopoiesis)` — full suite passes
2. REPL: create agent, await it, verify latency is < 100ms
3. REPL: start Claude Code session, send "list files in /tmp", observe partial
   results streaming via event bus subscription

---

## Performance Considerations

- CV notification adds one `maphash` over `*agent-completion-cvs*` per
  `transact!`. This table is expected to have at most a handful of entries at
  any time (one per active `await-agent` call). Cost is negligible.
- The coalesce window adds a fixed 50ms latency for event types that opt into
  it. This is intentional and only applies when explicitly used.
- Provider pool eliminates subprocess startup overhead (~200-500ms) on repeat
  invocations. The persistent process stays warm.

## Migration Notes

- No substrate schema changes. All new state (CV table, pool) is in-memory.
- `await-agent` API is unchanged — same parameters, same return format.
  The internal mechanism changes transparently.
- `with-coalesce-window` is additive. Existing `dispatch-event` is unchanged.
- Persistent provider mode requires explicit `:mode :persistent` (Claude Code)
  or `:mode :server` (OpenCode) in `provider-invoke` calls. Default `:one-shot`
  behavior is completely unchanged.

## References

- Research: `thoughts/shared/research/2026-02-17-spacebot-comparison.md`
- Substrate hooks: `platform/src/substrate/store.lisp:190-194`
- await-agent current implementation: `platform/src/integration/builtin-tools.lisp:518-548`
- Provider base class stubs: `platform/src/integration/provider.lisp:158-185`
- Claude Code provider: `platform/src/integration/provider-claude-code.lisp`
- OpenCode provider: `platform/src/integration/provider-opencode.lisp`
- Spacebot OpenCode server: `src/opencode/server.rs` (spacedriveapp/spacebot)
- Spacebot channel coalescing: `src/agent/channel.rs` (spacedriveapp/spacebot)
