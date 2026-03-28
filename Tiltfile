# Tiltfile — Dev environment orchestration for E2E testing
#
# Usage:
#   tilt up --port 14400          # Start backend + frontend (non-default tilt port)
#   tilt trigger e2e-tests       # Run browser E2E tests
#   tilt trigger ws-smoke        # Run WS-only smoke test
#
# Ports: 14400 tilt UI, 14401 WS, 14402 REST, 14403 frontend

# Build backend via Earthly
local_resource(
  'earthly-build',
  cmd='earthly +server',
  deps=['packages/', 'autopoiesis.asd', 'vendor/'],
  labels=['backend']
)

# Run backend container
docker_compose('e2e/docker-compose.e2e.yml')
dc_resource('autopoiesis-server', resource_deps=['earthly-build'], labels=['backend'])

# Frontend dev server
local_resource(
  'frontend',
  serve_cmd='cd frontends/command-center && AP_WS_PORT=14401 AP_REST_PORT=14402 bun run dev -- --port 14403',
  deps=['frontends/command-center/src'],
  readiness_probe=probe(http_get=http_get_action(port=14403, path='/'), period_secs=2),
  labels=['frontend']
)

# WS smoke test — manual trigger, only needs backend
local_resource(
  'ws-smoke',
  cmd='./e2e/ws-smoke.sh',
  resource_deps=['autopoiesis-server'],
  auto_init=False,
  trigger_mode=TRIGGER_MODE_MANUAL,
  labels=['test']
)

# Container smoke test — standalone, builds + tests Docker image
local_resource(
  'container-smoke',
  cmd='./e2e/container-smoke.sh',
  auto_init=False,
  trigger_mode=TRIGGER_MODE_MANUAL,
  labels=['test']
)

# Full browser E2E test — manual trigger, needs both backend and frontend
local_resource(
  'e2e-tests',
  cmd='./e2e/run.sh',
  resource_deps=['autopoiesis-server', 'frontend'],
  auto_init=False,
  trigger_mode=TRIGGER_MODE_MANUAL,
  labels=['test']
)
