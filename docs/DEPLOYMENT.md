# Autopoiesis Deployment Guide

This guide covers deploying Autopoiesis in production environments using Docker.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Docker Deployment](#docker-deployment)
- [Configuration](#configuration)
- [Monitoring](#monitoring)
- [Production Checklist](#production-checklist)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Docker 20.10+ and Docker Compose 2.0+
- At least 2GB RAM available for containers
- (Optional) Anthropic API key for Claude integration

## Quick Start

```bash
# Clone the repository
git clone <repo-url> autopoiesis
cd autopoiesis

# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Access the REPL
docker attach autopoiesis
```

## Docker Deployment

### Building the Image

```bash
# Build the Docker image
docker build -t autopoiesis:latest .

# Run a single container
docker run -it \
  -v autopoiesis-data:/data \
  -p 8080:8080 \
  autopoiesis:latest
```

### Using Docker Compose

The `docker-compose.yml` provides two services:

| Service | Description | Ports |
|---------|-------------|-------|
| `autopoiesis` | Interactive REPL for development | - |
| `autopoiesis-server` | HTTP server with monitoring | 8080, 8081 |

```bash
# Start all services
docker-compose up -d

# Start only the server
docker-compose up -d autopoiesis-server

# Stop all services
docker-compose down

# Stop and remove volumes (WARNING: deletes data)
docker-compose down -v
```

### Environment Variables

Configure the deployment via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTOPOIESIS_HOST` | `0.0.0.0` | Server bind address |
| `AUTOPOIESIS_PORT` | `8080` | Main application port |
| `AUTOPOIESIS_DATA_DIR` | `/data` | Data directory path |
| `AUTOPOIESIS_LOG_DIR` | `/data/logs` | Log directory path |
| `AUTOPOIESIS_LOG_LEVEL` | `info` | Log level: debug, info, warn, error |
| `ANTHROPIC_API_KEY` | - | Claude API key (optional) |
| `AUTOPOIESIS_MODEL` | `claude-sonnet-4-20250514` | Claude model name |

Create a `.env` file for local configuration:

```bash
# .env
LOG_LEVEL=debug
ANTHROPIC_API_KEY=sk-ant-...
APP_PORT=8080
MONITORING_PORT=8081
```

### Volumes

The deployment uses a single named volume for persistent data:

```yaml
volumes:
  autopoiesis-data:
    driver: local
```

Volume contents:
- `/data/snapshots/` - Agent state snapshots
- `/data/logs/` - Application logs
- `/data/autopoiesis.db` - SQLite database (if configured)

To backup data:

```bash
# Create backup
docker run --rm \
  -v autopoiesis-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar czf /backup/autopoiesis-backup.tar.gz /data

# Restore backup
docker run --rm \
  -v autopoiesis-data:/data \
  -v $(pwd)/backup:/backup \
  alpine tar xzf /backup/autopoiesis-backup.tar.gz -C /
```

## Configuration

### Configuration File

Create a configuration file at `config/config.lisp`:

```lisp
;; config/config.lisp
(:server (:host "0.0.0.0"
          :port 8080
          :max-connections 100)
 :storage (:type :sqlite
           :path "/data/autopoiesis.db"
           :cache-size 1000)
 :logging (:level :info
           :file "/data/logs/autopoiesis.log"
           :rotate-size 10485760)
 :security (:sandbox-level :strict
            :audit-enabled t
            :max-extension-size 10000)
 :performance (:parallel-systems t
               :gc-threshold 100000000)
 :claude (:model "claude-sonnet-4-20250514"
          :max-tokens 4096
          :timeout 30))
```

Mount the config directory in docker-compose:

```yaml
volumes:
  - ./config:/app/config:ro
```

### Configuration Precedence

Configuration is loaded in this order (later overrides earlier):

1. Default values (built-in)
2. Configuration file (`/app/config/config.lisp`)
3. Environment variables

### Security Settings

| Setting | Values | Description |
|---------|--------|-------------|
| `sandbox-level` | `:strict`, `:moderate`, `:permissive` | Code sandbox strictness |
| `audit-enabled` | `t`, `nil` | Enable audit logging |
| `max-extension-size` | Integer | Max bytes for agent-written code |

For production, always use `:strict` sandbox level.

## Monitoring

### Health Endpoints

The monitoring server (port 8081) provides these endpoints:

| Endpoint | Description | Response |
|----------|-------------|----------|
| `/health` | Full health check | JSON with status and checks |
| `/healthz` | Kubernetes liveness probe | `OK` or error |
| `/readyz` | Kubernetes readiness probe | `OK` or error |
| `/metrics` | Prometheus metrics | Prometheus text format |

### Health Check Response

```json
{
  "status": "healthy",
  "checks": [
    {"name": "core_packages", "status": "ok"},
    {"name": "memory", "status": "ok", "value": 524288000}
  ],
  "timestamp": 1706976000.123
}
```

### Prometheus Metrics

Available metrics:

```
# System metrics
autopoiesis_up 1
autopoiesis_memory_bytes 524288000

# Request metrics
autopoiesis_http_requests_total{endpoint="/health",status="200"} 42

# Agent metrics
autopoiesis_agent_status{agent_id="agent-001"} 1

# Snapshot metrics
autopoiesis_snapshot_operations_total{operation="create"} 100
```

### Prometheus Configuration

Add to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'autopoiesis'
    static_configs:
      - targets: ['autopoiesis-server:8081']
    scrape_interval: 30s
```

### Kubernetes Deployment

Example Kubernetes deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: autopoiesis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: autopoiesis
  template:
    metadata:
      labels:
        app: autopoiesis
    spec:
      containers:
      - name: autopoiesis
        image: autopoiesis:latest
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 8081
          name: metrics
        env:
        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: autopoiesis-secrets
              key: anthropic-api-key
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8081
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /readyz
            port: 8081
          initialDelaySeconds: 10
          periodSeconds: 10
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: autopoiesis-data
---
apiVersion: v1
kind: Service
metadata:
  name: autopoiesis
spec:
  selector:
    app: autopoiesis
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  - name: metrics
    port: 8081
    targetPort: 8081
```

## Production Checklist

Before deploying to production:

### Security

- [ ] Set `ANTHROPIC_API_KEY` via secrets management (not in config files)
- [ ] Use `:strict` sandbox level
- [ ] Enable audit logging (`audit-enabled t`)
- [ ] Review and restrict network access
- [ ] Use TLS termination at load balancer

### Reliability

- [ ] Configure health checks in orchestrator
- [ ] Set up log aggregation
- [ ] Configure backup schedule for `/data` volume
- [ ] Test restore procedure

### Monitoring

- [ ] Connect Prometheus to `/metrics` endpoint
- [ ] Set up alerts for:
  - Health check failures
  - High memory usage (>80%)
  - Error rate spikes
- [ ] Configure log rotation

### Performance

- [ ] Allocate sufficient memory (minimum 1GB, recommended 2GB)
- [ ] Configure `cache-size` based on expected snapshot count
- [ ] Enable `parallel-systems` for multi-core systems

## Troubleshooting

### Container Won't Start

Check logs:
```bash
docker-compose logs autopoiesis
```

Common issues:
- **Port already in use**: Change `APP_PORT` or `MONITORING_PORT`
- **Out of memory**: Increase container memory limit
- **Permission denied on volume**: Check volume permissions

### Health Check Failing

```bash
# Check health endpoint directly
curl http://localhost:8081/health

# Check container health
docker inspect --format='{{.State.Health.Status}}' autopoiesis-server
```

### Memory Issues

Monitor memory usage:
```bash
docker stats autopoiesis-server
```

If memory is high:
- Reduce `cache-size` in configuration
- Increase `gc-threshold` to trigger GC more often
- Compact old snapshots

### Connection Issues

```bash
# Test network connectivity
docker-compose exec autopoiesis-server curl http://localhost:8081/healthz

# Check exposed ports
docker-compose port autopoiesis-server 8080
```

### Accessing the REPL

For debugging:
```bash
# Attach to running container
docker attach autopoiesis

# Or start a new REPL session
docker-compose exec autopoiesis sbcl --noinform \
  --eval "(push #P\"/app/\" asdf:*central-registry*)" \
  --eval "(ql:quickload :autopoiesis :silent t)" \
  --eval "(in-package :autopoiesis)"
```

### Log Analysis

```bash
# View recent logs
docker-compose logs --tail=100 autopoiesis-server

# Follow logs in real-time
docker-compose logs -f autopoiesis-server

# Access log files in volume
docker run --rm -v autopoiesis-data:/data alpine cat /data/logs/autopoiesis.log
```

## Upgrading

To upgrade to a new version:

```bash
# Pull latest code
git pull

# Rebuild image
docker-compose build

# Restart with new image
docker-compose up -d

# Verify health
curl http://localhost:8081/health
```

For zero-downtime upgrades with Kubernetes, use rolling updates:

```bash
kubectl rollout restart deployment/autopoiesis
kubectl rollout status deployment/autopoiesis
```

## Support

- [GitHub Issues](https://github.com/your-org/autopoiesis/issues)
- [Documentation](docs/)
- [Specification Documents](docs/specs/)
