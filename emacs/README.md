# sly-autopoiesis

SLY contrib for the Autopoiesis agent platform. Provides in-image RPC to a running SBCL instance via the Slynk wire protocol — zero HTTP overhead.

## Setup

1. Load autopoiesis in your SBCL image:

```lisp
(ql:quickload :autopoiesis)
```

2. Add this directory to your Emacs `load-path` and require the package:

```elisp
(add-to-list 'load-path "/path/to/ap/emacs")
(require 'sly-autopoiesis)
```

3. Connect to your SBCL via `M-x sly`.

The Slynk-side module (`slynk-autopoiesis.lisp`) is loaded automatically on connect.

## Usage

| Key       | Command                        | Description                       |
|-----------|--------------------------------|-----------------------------------|
| `C-c a l` | `sly-autopoiesis-list-agents`  | Agent list (tabulated-list-mode)  |
| `C-c a s` | `sly-autopoiesis-system-status`| System status in minibuffer       |
| `C-c a c` | `sly-autopoiesis-chat`         | Chat with agent (prompts for ID)  |

### Agent List

- `RET` — open agent detail
- `c` — open chat shell for agent at point
- `g` — refresh
- Auto-refreshes every 5 seconds (configurable via `sly-autopoiesis-refresh-interval`)

### Agent Detail

- `c` — chat
- `t` — show thoughts
- `g` — refresh
- `q` — quit

### Chat Shell

Built on `comint-mode` — standard history (`M-p`/`M-n`) works out of the box.

- Jarvis session starts automatically on first message
- Session is cleaned up when the buffer is killed
- `C-u C-c a c` prompts for a provider model name

## Architecture

```
Emacs (sly-autopoiesis.el)
  │
  │  sly-eval-async / Slynk wire protocol
  │
  ▼
SBCL (slynk-autopoiesis.lisp)
  │
  │  direct CL function calls
  │
  ▼
autopoiesis.agent / autopoiesis.jarvis / autopoiesis.snapshot
```

No HTTP server required. The Slynk connection is the transport.
