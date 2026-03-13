import { type Component, Show, For, createSignal, createEffect, createMemo, onMount, onCleanup } from "solid-js";
import { agentStore, type ChatMessage } from "../stores/agents";
import { wsStore } from "../stores/ws";
import { renderMarkdown } from "../lib/markdown";
import { commands, type Command } from "../lib/commands";

const JarvisBar: Component = () => {
  let inputRef!: HTMLInputElement;
  let historyRef!: HTMLDivElement;
  const [expanded, setExpanded] = createSignal(false);
  const [input, setInput] = createSignal("");
  const [cliSelectedIdx, setCliSelectedIdx] = createSignal(0);

  // CLI alias map
  const cliAliasMap: Record<string, string> = {
    "agent.create": "/create", "agent.start": "/start", "agent.stop": "/stop",
    "agent.step": "/step", "agent.fork": "/fork", "agent.upgrade": "/upgrade",
    "view.dashboard": "/dashboard", "view.dag": "/dag", "view.timeline": "/timeline",
    "view.tasks": "/tasks", "view.holodeck": "/holodeck",
    "system.connect": "/connect", "system.mock": "/mock", "system.refresh": "/refresh",
  };

  const cliMode = createMemo(() => {
    const v = input();
    return v.startsWith("/") || v.startsWith(":");
  });

  const cliMatches = createMemo(() => {
    if (!cliMode()) return [];
    const q = input().slice(1).toLowerCase();
    return commands.filter((cmd) => {
      const alias = cliAliasMap[cmd.id] ?? "";
      return alias.toLowerCase().includes(q) ||
        cmd.name.toLowerCase().includes(q) ||
        cmd.id.toLowerCase().includes(q);
    }).slice(0, 10);
  });

  // Reset selection when matches change
  createEffect(() => {
    cliMatches();
    setCliSelectedIdx(0);
  });

  function executeCliCommand(cmd: Command) {
    cmd.handler();
    setInput("");
  }

  function submit() {
    if (cliMode()) {
      const matches = cliMatches();
      if (matches.length > 0) {
        executeCliCommand(matches[cliSelectedIdx()]);
      }
      return;
    }
    const text = input().trim();
    if (!text) return;
    agentStore.sendChatMessage(text);
    setInput("");
    setExpanded(true);
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (cliMode()) {
      const matches = cliMatches();
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setCliSelectedIdx((i) => Math.min(i + 1, matches.length - 1));
        return;
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        setCliSelectedIdx((i) => Math.max(i - 1, 0));
        return;
      }
      if (e.key === "Escape") {
        e.preventDefault();
        setInput("");
        return;
      }
    }
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submit();
    }
    if (e.key === "Escape") {
      setExpanded(false);
      inputRef?.blur();
    }
  }

  // Global `/` shortcut to focus jarvis bar
  function handleGlobalKey(e: KeyboardEvent) {
    if (e.key === "/" && !isInputFocused()) {
      e.preventDefault();
      inputRef?.focus();
    }
  }

  function isInputFocused() {
    const el = document.activeElement;
    if (!el) return false;
    const tag = el.tagName;
    return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || (el as HTMLElement).isContentEditable;
  }

  onMount(() => {
    window.addEventListener("keydown", handleGlobalKey);
  });

  onCleanup(() => {
    window.removeEventListener("keydown", handleGlobalKey);
  });

  // Auto-scroll history
  createEffect(() => {
    const _ = agentStore.chatMessages().length;
    if (historyRef) {
      requestAnimationFrame(() => {
        historyRef.scrollTop = historyRef.scrollHeight;
      });
    }
  });

  // Determine chat target name
  const chatTarget = createMemo(() => {
    const agent = agentStore.selectedAgent();
    if (agent) return agent.name;
    return "Jarvis";
  });

  return (
    <div class="jarvis-bar" classList={{ "jarvis-expanded": expanded(), "jarvis-cli-mode": cliMode() }}>
      {/* CLI autocomplete dropdown */}
      <Show when={cliMode() && cliMatches().length > 0}>
        <div class="jarvis-autocomplete">
          <For each={cliMatches()}>
            {(cmd, idx) => (
              <div
                class="jarvis-autocomplete-item"
                classList={{ "jarvis-autocomplete-item-selected": idx() === cliSelectedIdx() }}
                onClick={() => executeCliCommand(cmd)}
              >
                <div>
                  <span class="jarvis-autocomplete-alias">{cliAliasMap[cmd.id] ?? `/${cmd.id}`}</span>
                  <span class="jarvis-autocomplete-name"> {cmd.name}</span>
                </div>
                <Show when={cmd.description}>
                  <span class="jarvis-autocomplete-desc">{cmd.description}</span>
                </Show>
              </div>
            )}
          </For>
        </div>
      </Show>
      {/* Connection hint when expanded with no messages */}
      <Show when={expanded() && agentStore.chatMessages().length === 0 && !wsStore.connected()}>
        <div class="jarvis-history">
          <div class="jarvis-msg jarvis-msg-jarvis">
            <span class="jarvis-msg-sender">Jarvis</span>
            <span class="jarvis-msg-content">Jarvis requires a running backend. Type <code>/</code> for local CLI commands.</span>
          </div>
        </div>
      </Show>
      {/* Chat history (expanded) */}
      <Show when={expanded() && agentStore.chatMessages().length > 0}>
        <div class="jarvis-history" ref={historyRef!}>
          <For each={agentStore.chatMessages()}>
            {(msg) => (
              <div class={`jarvis-msg jarvis-msg-${msg.sender}`}>
                <span class="jarvis-msg-sender">
                  {msg.sender === "user" ? "You" : chatTarget()}
                </span>
                {msg.sender === "jarvis" ? (
                  <span class="jarvis-msg-content jarvis-markdown" innerHTML={renderMarkdown(msg.content)} />
                ) : (
                  <span class="jarvis-msg-content">{msg.content}</span>
                )}
              </div>
            )}
          </For>
          <Show when={agentStore.chatLoading() && !agentStore.streamingText()}>
            <div class="jarvis-msg jarvis-msg-jarvis">
              <span class="jarvis-msg-sender">{chatTarget()}</span>
              <span class="jarvis-msg-content jarvis-typing-wave">
                <span /><span /><span /><span /><span />
              </span>
            </div>
          </Show>
        </div>
      </Show>

      {/* Input bar */}
      <div class="jarvis-input-row">
        <button
          class="jarvis-expand-btn"
          onClick={() => setExpanded(!expanded())}
          title={expanded() ? "Collapse chat" : "Expand chat"}
        >
          {expanded() ? "▾" : "▴"}
        </button>
        <div class="jarvis-input-wrap">
          <span class="jarvis-prompt-icon">{cliMode() ? ">" : chatTarget()[0]}</span>
          <input
            ref={inputRef!}
            type="text"
            class="jarvis-input"
            placeholder={`Ask ${chatTarget()} anything... (press / to focus)`}
            value={input()}
            onInput={(e) => setInput(e.currentTarget.value)}
            onKeyDown={handleKeyDown}
            onFocus={() => setExpanded(true)}
          />
          <Show when={input().trim()}>
            <button class="jarvis-send-btn" onClick={submit}>
              Send
            </button>
          </Show>
        </div>
      </div>
    </div>
  );
};

export default JarvisBar;
