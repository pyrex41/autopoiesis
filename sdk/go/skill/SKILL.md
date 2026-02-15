---
name: autopoiesis
description: Connect to an Autopoiesis cognitive backend for agent state management, branching, time-travel, and human-in-the-loop control
---

# Autopoiesis Integration

Autopoiesis is a cognitive backend that gives you persistent agents with full state snapshots, branching exploration, time-travel debugging, and self-extension. Use `apcli` to interact with a running Autopoiesis instance.

## Setup

Set these environment variables or pass flags:

```bash
export AP_URL=http://your-autopoiesis-host:8080
export AP_KEY=your-api-key   # optional if auth is disabled
```

## Quick Reference

### Agent Management

```bash
# List all agents
apcli agents

# Create a new cognitive agent
apcli create-agent "research-assistant"

# Start, pause, resume, stop
apcli start-agent <agent-id>
apcli pause-agent <agent-id>
apcli resume-agent <agent-id>
apcli stop-agent <agent-id>

# Get agent details
apcli get-agent <agent-id>
```

### Cognitive Operations

```bash
# Run one perceive-reason-decide-act-reflect cycle
apcli cycle <agent-id> "analyze this problem"

# See what the agent is thinking
apcli thoughts <agent-id> 10

# List available capabilities
apcli capabilities <agent-id>
```

### Snapshots (State Capture)

```bash
# Take a snapshot of the agent's cognitive state
apcli snapshot <agent-id>

# List all snapshots
apcli snapshots

# Compare two snapshots to see what changed
apcli diff <snapshot-a> <snapshot-b>
```

### Branching (Alternative Exploration)

Use branches to explore different approaches without losing the original path:

```bash
# List branches
apcli branches

# Create a branch to try an alternative approach
apcli create-branch "experiment" <from-snapshot-id>

# Switch to a branch
apcli checkout "experiment"

# Switch back to main
apcli checkout "main"
```

### Human-in-the-Loop

When an agent needs human input, it creates a pending request:

```bash
# Check for pending requests
apcli pending

# Respond to a request
apcli respond <request-id> "approved"
```

### System Status

```bash
apcli system
```

## Common Workflows

### 1. Create and run an agent

```bash
# Create
AGENT=$(apcli create-agent "analyzer" | jq -r .id)

# Start it
apcli start-agent $AGENT

# Feed it a task
apcli cycle $AGENT "Analyze the deployment logs for anomalies"

# Check its thinking
apcli thoughts $AGENT 5
```

### 2. Try two approaches and compare

```bash
# Take snapshot before branching
SNAP=$(apcli snapshot $AGENT | jq -r .id)

# Create two branches
apcli create-branch "approach-a" $SNAP
apcli create-branch "approach-b" $SNAP

# Run approach A
apcli checkout "approach-a"
apcli cycle $AGENT "Use statistical analysis"
SNAP_A=$(apcli snapshot $AGENT | jq -r .id)

# Run approach B
apcli checkout "approach-b"
apcli cycle $AGENT "Use machine learning"
SNAP_B=$(apcli snapshot $AGENT | jq -r .id)

# Compare
apcli diff $SNAP_A $SNAP_B
```

### 3. Handle a human-in-the-loop request

```bash
# Check for pending requests periodically
apcli pending

# When you see one, respond
apcli respond "request-id-here" "Go with option B"
```

## Output Format

All commands output JSON. Use `jq` to extract specific fields:

```bash
# Get just agent IDs
apcli agents | jq '.[].id'

# Get agent state
apcli get-agent $ID | jq .state

# Get thought content
apcli thoughts $ID 1 | jq '.[0].content'
```
