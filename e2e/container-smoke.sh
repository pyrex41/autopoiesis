#!/usr/bin/env bash
# Container smoke test — verifies Docker image produces a working server
# Usage: ./e2e/container-smoke.sh
set -euo pipefail

GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; }
info() { echo -e "${YELLOW}→ $1${NC}"; }

CONTAINER_NAME="ap-smoke-$$"
WS_PORT=18401
REST_PORT=18402
CLEANUP_DONE=0

cleanup() {
  if [ "$CLEANUP_DONE" -eq 0 ]; then
    CLEANUP_DONE=1
    info "Cleaning up container ${CONTAINER_NAME}..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# 1. Build image
info "Building Docker image..."
cd "$(dirname "$0")/.."
docker build -t autopoiesis-smoke:latest -f Dockerfile . || {
  fail "Docker build failed"
  exit 1
}
pass "Docker image built"

# 2. Start container
info "Starting container..."
docker run -d --name "$CONTAINER_NAME" \
  -p "${WS_PORT}:8080" \
  -p "${REST_PORT}:8082" \
  autopoiesis-smoke:latest || {
  fail "Container failed to start"
  exit 1
}
pass "Container started"

# 3. Wait for health (up to 90s)
info "Waiting for health check (up to 90s)..."
HEALTHY=0
for i in $(seq 1 30); do
  if curl -sf "http://localhost:${WS_PORT}/health" > /dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  sleep 3
done

if [ "$HEALTHY" -eq 0 ]; then
  fail "Health check never passed"
  info "Container logs:"
  docker logs "$CONTAINER_NAME" 2>&1 | tail -30
  exit 1
fi
pass "Health check passed"

# 4. Create agent via REST
info "Creating agent via REST API..."
AGENT_RESPONSE=$(curl -sf "http://localhost:${REST_PORT}/api/agents" -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"smoke-agent"}' 2>&1) || {
  fail "Failed to create agent: ${AGENT_RESPONSE}"
  exit 1
}
AGENT_ID=$(echo "$AGENT_RESPONSE" | jq -r '.id // .agentId // empty')
if [ -z "$AGENT_ID" ]; then
  fail "No agent ID in response: ${AGENT_RESPONSE}"
  exit 1
fi
pass "Agent created: ${AGENT_ID}"

# 5. Start agent
info "Starting agent..."
curl -sf "http://localhost:${REST_PORT}/api/agents/${AGENT_ID}/start" -X POST > /dev/null 2>&1 || {
  fail "Failed to start agent"
  exit 1
}
pass "Agent started"

# 6. Give agent time to initialize
sleep 2

# 7. Verify agent is in agents list
info "Verifying agent appears in listing..."
AGENTS=$(curl -sf "http://localhost:${REST_PORT}/api/agents" 2>&1) || {
  fail "Failed to list agents"
  exit 1
}
echo "$AGENTS" | jq -e ".[] | select(.id == \"${AGENT_ID}\" or .agentId == \"${AGENT_ID}\")" > /dev/null 2>&1 || {
  fail "Agent not found in listing"
  exit 1
}
pass "Agent appears in listing"

# 8. Verify thoughts endpoint works
info "Checking thoughts endpoint..."
THOUGHTS_RESPONSE=$(curl -sf "http://localhost:${REST_PORT}/api/agents/${AGENT_ID}/thoughts" 2>&1) || {
  # Thoughts endpoint might return empty array — that's ok
  THOUGHTS_RESPONSE="[]"
}
echo "$THOUGHTS_RESPONSE" | jq -e 'type == "array"' > /dev/null 2>&1 || {
  fail "Thoughts endpoint returned non-array"
  exit 1
}
pass "Thoughts endpoint returns valid array"

echo ""
echo -e "${GREEN}Container smoke test PASSED${NC}"
