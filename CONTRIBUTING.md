# Contributing to Autopoiesis

## Prerequisites

- SBCL (2.4+) with Quicklisp
- Bun (for frontend)
- System libraries: libssl, libev, liblmdb, libncurses

Or use the containerized path:
- Earthly (for container builds)
- Docker

## Running Tests

### Common Lisp platform
```bash
./packages/core/scripts/test.sh
```

### Frontend
```bash
cd frontends/command-center
bun install
bun run build
```

### Containerized
```bash
earthly +test
```

## Project Structure

The project uses a monorepo layout with packages in `packages/`:

- `packages/substrate/` - Datom store (standalone, no internal deps)
- `packages/core/` - Main platform (depends on substrate)
- `packages/api-server/` - REST/WebSocket API
- `packages/eval/` - Agent evaluation framework
- `packages/swarm/`, `packages/team/`, etc. - Optional extensions

Frontend: `frontends/command-center/` (SolidJS)

## License

MIT
