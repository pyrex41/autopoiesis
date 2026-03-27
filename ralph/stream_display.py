#!/usr/bin/env python3
"""
Ralph Stream Display - TUI for following claude/cursor-agent iteration progress.

Reads streaming JSON from stdin (--output-format stream-json) and renders
a clean, readable terminal display.

Press [v] during streaming to toggle text output visibility.
Tool calls are always shown.

Usage:
    cursor-agent ... | python3 stream_display.py --iteration 3 --mode build --model "opus 4.5"
    claude ...       | python3 stream_display.py --iteration 1 --mode plan --model sonnet
    # Debug: dump raw JSON to file
    claude ... | python3 stream_display.py --dump /tmp/stream.jsonl
"""

import argparse
import json
import os
import subprocess
import sys
import threading
import time

try:
    import termios
    import tty
    HAS_TTY = True
except ImportError:
    HAS_TTY = False


# ── ANSI helpers ──────────────────────────────────────────────────────────────

BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
MAGENTA = "\033[35m"
WHITE = "\033[37m"

SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

TOOL_COLORS = {
    "Read": BLUE,
    "Glob": BLUE,
    "Grep": BLUE,
    "LS": BLUE,
    "Edit": YELLOW,
    "Write": YELLOW,
    "NotebookEdit": YELLOW,
    "Bash": GREEN,
    "Task": MAGENTA,
    "WebFetch": CYAN,
    "WebSearch": CYAN,
}


def cols():
    """Terminal width, default 80."""
    try:
        return os.get_terminal_size().columns
    except OSError:
        return 80


def hrule(left="", right="", ch="─", cap_l="─", cap_r="─"):
    """Draw a horizontal rule with optional left/right labels."""
    left_str = f" {left} " if left else ""
    right_str = f" {right} " if right else ""
    fill = cols() - len(cap_l) - len(left_str) - len(right_str) - len(cap_r)
    if fill < 0:
        fill = 0
    return f"{cap_l}{left_str}{ch * fill}{right_str}{cap_r}"


def fmt_duration(seconds):
    """Format seconds as human-readable duration."""
    if seconds < 60:
        return f"{int(seconds)}s"
    m, s = divmod(int(seconds), 60)
    return f"{m}m{s:02d}s"


# ── Git helpers ───────────────────────────────────────────────────────────────

def git_status_snapshot():
    """Capture current git status --porcelain output as a set of lines."""
    try:
        r = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True, text=True, timeout=5,
        )
        return set(r.stdout.strip().splitlines()) if r.stdout.strip() else set()
    except Exception:
        return set()


def git_diff_files(before, after):
    """Return list of changed file lines (new or modified since snapshot)."""
    return sorted(after - before)


# ── Tool arg extraction ──────────────────────────────────────────────────────

def extract_tool_arg(name, inp):
    """Pull the most informative single arg from a tool input dict."""
    if not isinstance(inp, dict):
        return ""
    if name in ("Read", "Write", "Edit", "NotebookEdit"):
        return inp.get("file_path") or inp.get("notebook_path") or ""
    if name == "Bash":
        cmd = inp.get("command", "")
        if len(cmd) > 60:
            cmd = cmd[:57] + "..."
        return cmd
    if name == "Glob":
        return inp.get("pattern", "")
    if name == "Grep":
        return inp.get("pattern", "")
    if name == "Task":
        return inp.get("description") or inp.get("subagent_type") or ""
    if name == "WebFetch":
        return inp.get("url", "")
    if name == "WebSearch":
        return inp.get("query", "")
    # Generic fallback
    for key in ("file_path", "path", "pattern", "command", "query", "url", "description"):
        if key in inp:
            v = str(inp[key])
            return v[:60] + "..." if len(v) > 60 else v
    return ""


# ── Stream processor ─────────────────────────────────────────────────────────

class StreamDisplay:
    def __init__(self, iteration, mode, model, dump_file=None):
        self.iteration = iteration
        self.mode = mode
        self.model = model
        self.start_time = time.time()
        self.tool_calls = 0
        self.tool_names = []
        self.text_len = 0
        self.git_before = set()
        self.git_after = set()
        self.printed_header = False
        self.in_tool = False

        # Per-block dedup: track text printed and tools emitted per content index
        # These reset when a new assistant message ID is seen
        self._current_msg_id = None
        self._block_text_lens = {}   # content_index -> chars already printed
        self._seen_tool_blocks = set()  # content indices where tool was printed

        # Pending tool from content_block_start (input arrives via deltas)
        self._pending_tool = None  # {"name", "input", "index"}

        # Verbose toggle
        self.verbose = True
        self._lock = threading.Lock()
        self._status_shown = False
        self._spinner_tick = 0

        # Keyboard
        self._tty_file = None
        self._old_tty = None

        # Debug dump
        self._dump = open(dump_file, "w") if dump_file else None

    def elapsed(self):
        return time.time() - self.start_time

    # ── Keyboard toggle ──────────────────────────────────────────────────

    def _setup_keyboard(self):
        if not HAS_TTY:
            return
        try:
            self._tty_file = open("/dev/tty", "rb", buffering=0)
            fd = self._tty_file.fileno()
            self._old_tty = termios.tcgetattr(fd)
            tty.setcbreak(fd)
            t = threading.Thread(target=self._kb_loop, daemon=True)
            t.start()
        except Exception:
            self._tty_file = None

    def _cleanup_keyboard(self):
        if self._tty_file and self._old_tty:
            try:
                termios.tcsetattr(
                    self._tty_file.fileno(), termios.TCSADRAIN, self._old_tty
                )
            except Exception:
                pass
            try:
                self._tty_file.close()
            except Exception:
                pass

    def _kb_loop(self):
        while True:
            try:
                ch = self._tty_file.read(1)
                if not ch:
                    break
                if ch in (b"v", b"V"):
                    with self._lock:
                        self.verbose = not self.verbose
                        if self.verbose:
                            self._clear_status()
                        else:
                            self._draw_status()
            except Exception:
                break

    # ── Output primitives (must hold _lock) ──────────────────────────────

    def _out(self, text):
        sys.stdout.write(text)
        sys.stdout.flush()

    def _clear_status(self):
        """Erase the in-place status line."""
        if self._status_shown:
            self._out("\r\033[K")
            self._status_shown = False

    def _draw_status(self):
        """Draw/refresh the in-place status bar (collapsed mode)."""
        self._spinner_tick += 1
        sp = SPINNER[self._spinner_tick % len(SPINNER)]
        elapsed = fmt_duration(self.elapsed())
        left = f"  {sp} streaming | {self.tool_calls} tools | {elapsed}"
        right = "[v] show"
        pad = cols() - len(left) - len(right)
        if pad < 1:
            pad = 1
        self._out(f"\r\033[K{DIM}{left}{' ' * pad}{right}{RESET}")
        self._status_shown = True

    # ── Display methods ──────────────────────────────────────────────────

    def print_header(self):
        if self.printed_header:
            return
        self.printed_header = True
        with self._lock:
            left = f"Iteration {self.iteration}"
            right = f"{self.mode} | {self.model}"
            line = hrule(left, right, cap_l="┌─", cap_r="─┐")
            self._out(f"\n{BOLD}{line}{RESET}\n\n")

    def print_footer(self):
        with self._lock:
            if self._status_shown:
                self._clear_status()
            changed = git_diff_files(self.git_before, self.git_after)
            if changed:
                self._out("\n")
                self._out(f"  {DIM}Files changed:{RESET}\n")
                for f in changed:
                    self._out(f"    {f}\n")
            elapsed_str = fmt_duration(self.elapsed())
            parts = [elapsed_str, f"{self.tool_calls} tool calls"]
            if changed:
                parts.append(f"{len(changed)} files changed")
            right = " | ".join(parts)
            line = hrule("", right, cap_l="└─", cap_r="─┘")
            self._out(f"\n{BOLD}{line}{RESET}\n\n")

    def print_tool(self, name, arg=""):
        """Print a tool call line. Always visible regardless of verbose."""
        with self._lock:
            if self._status_shown:
                self._clear_status()
            if not self.in_tool:
                self._out("\n")
            self.in_tool = True
            self.tool_calls += 1
            self.tool_names.append(name)
            color = TOOL_COLORS.get(name, WHITE)
            arg_str = f"  {DIM}{arg}{RESET}" if arg else ""
            self._out(f"  {color}>{RESET} {BOLD}{name}{RESET}{arg_str}\n")
            if not self.verbose:
                self._draw_status()

    def print_text(self, text):
        """Print assistant text. Hidden when verbose=False."""
        if not text:
            return
        with self._lock:
            self.text_len += len(text)
            if not self.verbose:
                self._draw_status()
                return
            if self._status_shown:
                self._clear_status()
            if self.in_tool:
                self._out("\n")
                self.in_tool = False
            self._out(text)

    # ── Content processing ───────────────────────────────────────────────

    def _process_content(self, msg_id, content):
        """Process content blocks from an assistant message, deduplicating."""
        if msg_id and msg_id != self._current_msg_id:
            self._current_msg_id = msg_id
            self._block_text_lens = {}
            self._seen_tool_blocks = set()
        for i, block in enumerate(content):
            if not isinstance(block, dict):
                continue
            btype = block.get("type")

            if btype == "text":
                text = block.get("text", "")
                prev_len = self._block_text_lens.get(i, 0)
                if len(text) > prev_len:
                    self.print_text(text[prev_len:])
                    self._block_text_lens[i] = len(text)

            elif btype == "tool_use":
                if i not in self._seen_tool_blocks:
                    name = block.get("name", "?")
                    inp = block.get("input", {})
                    # Only emit once input is populated (partials send {} first)
                    if inp:
                        arg = extract_tool_arg(name, inp)
                        self.print_tool(name, arg)
                        self._seen_tool_blocks.add(i)

    # ── Event dispatch ───────────────────────────────────────────────────

    def process_line(self, line):
        """Process a single JSON line from the stream."""
        line = line.strip()
        if not line:
            return
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            return

        if self._dump:
            self._dump.write(line + "\n")
            self._dump.flush()

        self.print_header()

        t = msg.get("type", "")

        if t in ("system", "init"):
            pass

        elif t == "assistant":
            message = msg.get("message", {})
            msg_id = message.get("id", "")
            content = message.get("content", [])
            self._process_content(msg_id, content)

        # ── Streaming content block events (claude API / some CLI modes) ──

        elif t == "message_start":
            # New message in streaming mode - reset per-block tracking
            new_id = msg.get("message", {}).get("id", "")
            if new_id and new_id != self._current_msg_id:
                self._current_msg_id = new_id
                self._block_text_lens = {}
                self._seen_tool_blocks = set()

        elif t == "content_block_start":
            block = msg.get("content_block", {})
            idx = msg.get("index", 0)
            if block.get("type") == "tool_use":
                self._pending_tool = {
                    "name": block.get("name", "?"),
                    "input": "",
                    "index": idx,
                }

        elif t == "content_block_delta":
            delta = msg.get("delta", {})
            idx = msg.get("index", 0)
            if delta.get("type") == "text_delta":
                text = delta.get("text", "")
                if text:
                    self.print_text(text)
                    self._block_text_lens[idx] = (
                        self._block_text_lens.get(idx, 0) + len(text)
                    )
            elif delta.get("type") == "input_json_delta":
                if self._pending_tool:
                    self._pending_tool["input"] += delta.get("partial_json", "")

        elif t == "content_block_stop":
            if self._pending_tool:
                inp = {}
                if self._pending_tool["input"]:
                    try:
                        inp = json.loads(self._pending_tool["input"])
                    except json.JSONDecodeError:
                        pass
                name = self._pending_tool["name"]
                idx = self._pending_tool["index"]
                arg = extract_tool_arg(name, inp)
                self.print_tool(name, arg)
                self._seen_tool_blocks.add(idx)
                self._pending_tool = None

        # ── Cursor-agent tool_call events (if sent separately) ───────────

        elif t == "tool_call":
            sub = msg.get("subtype", "")
            if sub == "started":
                name = msg.get("tool_name", msg.get("name", "?"))
                inp = msg.get("input", {})
                arg = extract_tool_arg(name, inp)
                self.print_tool(name, arg)

        elif t == "result":
            pass  # handled by footer

    # ── Main loop ────────────────────────────────────────────────────────

    def run(self):
        """Read stdin, display stream, print footer."""
        self.git_before = git_status_snapshot()
        self._setup_keyboard()
        try:
            for line in sys.stdin:
                self.process_line(line)
        except KeyboardInterrupt:
            pass
        except BrokenPipeError:
            pass
        finally:
            self._cleanup_keyboard()
            if self._dump:
                self._dump.close()

        # Ensure trailing newline after text
        with self._lock:
            if self._status_shown:
                self._clear_status()
            if self.text_len > 0:
                self._out("\n")

        self.git_after = git_status_snapshot()
        self.print_header()  # in case no messages arrived
        self.print_footer()


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Ralph stream display TUI")
    parser.add_argument(
        "--iteration", "-i", type=int, default=1, help="Current iteration number"
    )
    parser.add_argument("--mode", "-m", default="build", help="Mode (plan/build)")
    parser.add_argument("--model", default="opus 4.5", help="Model name for display")
    parser.add_argument(
        "--dump", default=None, metavar="FILE",
        help="Dump raw JSON lines to file for debugging",
    )
    args = parser.parse_args()

    display = StreamDisplay(args.iteration, args.mode, args.model, dump_file=args.dump)
    display.run()


if __name__ == "__main__":
    main()
