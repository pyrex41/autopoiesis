---
date: 2026-03-11T12:00:00-07:00
researcher: claude
git_commit: 566f197
branch: main
repository: ap
topic: "SLY/Slynk rewrite to expose full Autopoiesis platform"
tags: [research, codebase, emacs, sly, slynk, jarvis, integration, agent, orchestration, team, swarm]
status: complete
last_updated: 2026-03-11
last_updated_by: claude
---

# Research: SLY/Slynk Rewrite — Full Platform Exposure

**Date**: 2026-03-11
**Git Commit**: 566f197
**Branch**: main

## Research Question

Map the public API surface of 6 platform directories (jarvis, integration, agent, orchestration, team, swarm) to inform a rewrite of `emacs/slynk-autopoiesis.lisp` and `emacs/sly-autopoiesis.el` that exposes the full platform through Emacs.

## Summary

Research completed across all 6 directories via parallel sub-agents. The findings drove a complete rewrite of both files:

- **slynk-autopoiesis.lisp**: Expanded from 186 lines / 10 exports to ~370 lines / 32 exports covering system lifecycle, providers, agent CRUD, capabilities, provider-aware chat, conductor orchestration, agentic loops, teams, swarm evolution, snapshots, and events.

- **sly-autopoiesis.el**: Expanded from 394 lines / 3 commands to ~680 lines / 14 interactive commands with dedicated buffers for system status, conductor dashboard, team list, event log, evolution results, and agentic responses. Chat now supports provider selection.

## Key API Findings by Area

### Jarvis (5 files)
- `start-jarvis &key agent provider provider-config tools` — provider-config plist accepts `:type` (`:rho` or `:pi`) and `:model`
- `start-jarvis-with-team` — same signature, appends 10 team+workspace tools
- `jarvis-prompt session text` — full dispatch cycle with tool call detection
- `stop-jarvis session`
- Provider auto-detection: probes PATH for `rho-cli` then `pi`

### Integration (31 files)
- 13 provider files: claude-code, rho, pi, codex, cursor, opencode, nanobot, nanosquash, inference
- `make-agentic-agent &key api-key model name system-prompt capabilities max-turns provider`
- `agentic-agent-prompt agent prompt-string` — convenience one-shot
- `provider-invoke provider prompt &key tools mode agent-id` → provider-result
- Event bus: `emit-integration-event`, `subscribe-to-event`, `get-event-history`, `count-events`
- Provider registry: `list-providers`, `find-provider`, `register-provider`

### Agent (16 files)
- `make-agent &key name capabilities parent` + `register-agent`/`find-agent`/`list-agents`
- State: `start-agent`, `stop-agent`, `pause-agent`, `resume-agent`
- Capability registry: `list-capabilities` returns capability objects with `capability-name` and `capability-description`
- Persistent agents: `make-persistent-agent`, `persistent-fork`, `persistent-cognitive-cycle`
- Dual-agent bridge: `upgrade-to-dual`, `agent-to-persistent`
- Mailbox: `send-message`, `receive-messages` with blocking/timeout

### Orchestration (4 files)
- `start-system &key monitoring-port start-conductor` / `stop-system`
- `start-conductor` / `stop-conductor &key conductor`
- `conductor-status &key conductor` → plist with :running, :tick-count, :events-processed, etc.
- `schedule-action conductor delay-seconds action-plist` — action-plist needs `:action-type`
- `queue-event event-type data`
- `*conductor*` dynamic variable holds the active instance

### Team (12 files)
- `create-team name &key strategy task members leader config`
- `start-team team` / `pause-team` / `resume-team` / `disband-team`
- `query-team-status team` → plist
- 9 strategies: leader-worker, parallel, pipeline, debate, consensus, hierarchical-leader-worker, leader-parallel, rotating-leader, debate-consensus
- `make-strategy keyword &optional config` — factory function
- Registry: `list-teams`, `find-team`, `active-teams`

### Swarm (11 files)
- `evolve-persistent-agents agents evaluator environment &key generations mutation-rate elite-count tournament-size`
- `make-standard-pa-evaluator &key diversity-weight breadth-weight efficiency-weight`
- `persistent-agent-to-genome agent` / `genome-to-persistent-agent-patch genome original`
- Genome: `genome-fitness`, `genome-capabilities`, `genome-id`
- Population: `population-history` returns `(generation best-fitness avg-fitness)` tuples

## Architecture Decisions in the Rewrite

1. **Session-keyed chat** instead of agent-id-keyed — sessions can exist without pre-existing agents since `start-jarvis` creates its own agent
2. **Provider-aware chat** — rho/pi use `provider-config` plist, other providers looked up in registry by name
3. **`try-call` helper** — returns NIL instead of signaling, used for optional features (events, providers)
4. **`conductor-var` helper** — safely resolves `*conductor*` dynamic variable
5. **C-c x prefix** — avoids org-mode's C-c a conflict
6. **All operations async** via `sly-eval-async` except completion list population
