import { type Component, Show, For, createSignal, createEffect, createMemo, onMount, onCleanup } from "solid-js";
import { agentStore, type ChatMessage } from "../stores/agents";
import { wsStore } from "../stores/ws";
import { renderMarkdown } from "../lib/markdown";
import { commands, type Command, navigateTo, type ViewId } from "../lib/commands";
import WidgetSandbox from "./WidgetSandbox";

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
    "system.connect": "/connect", "system.refresh": "/refresh",
  };

  // Widget output handler — receives data from sandboxed widget iframes
  function handleWidgetOutput(data: unknown) {
    if (!data || typeof data !== "object") return;
    const d = data as Record<string, unknown>;
    // Forward to backend
    if (d.widgetId) {
      wsStore.send({ type: "widget_output", widgetId: d.widgetId as string, data } as any);
    }
    // Handle local navigation actions
    if (d.action === "navigate" && typeof d.view === "string") {
      navigateTo(d.view as ViewId, (d.label as string) ?? d.view);
    }
  }

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

  function handleExpandJarvis() {
    setExpanded(true);
  }

  onMount(() => {
    window.addEventListener("keydown", handleGlobalKey);
    window.addEventListener("ap:expand-jarvis", handleExpandJarvis);
  });

  onCleanup(() => {
    window.removeEventListener("keydown", handleGlobalKey);
    window.removeEventListener("ap:expand-jarvis", handleExpandJarvis);
  });

  createEffect(() => {
    const _ = agentStore.chatMessages().length;
    if (historyRef) {
      requestAnimationFrame(() => {
        historyRef.scrollTop = historyRef.scrollHeight;
      });
    }
  });

  const chatTarget = createMemo(() => {
    const agent = agentStore.selectedAgent();
    if (agent) return agent.name;
    return "Jarvis";
  });

  const targetState = createMemo(() => {
    const agent = agentStore.selectedAgent();
    return agent?.state ?? null;
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
                <div class="jarvis-autocomplete-left">
                  <span class="jarvis-autocomplete-alias">{cliAliasMap[cmd.id] ?? `/${cmd.id}`}</span>
                  <span class="jarvis-autocomplete-name">{cmd.name}</span>
                </div>
                <Show when={cmd.description}>
                  <span class="jarvis-autocomplete-desc">{cmd.description}</span>
                </Show>
              </div>
            )}
          </For>
        </div>
      </Show>

      {/* Chat history (expanded) */}
      <Show when={expanded()}>
        <div class="jarvis-history" ref={historyRef!}>
          <Show when={agentStore.chatMessages().length === 0}>
            <div class="jarvis-welcome">
              <Show when={wsStore.connected()} fallback={
                <span class="jarvis-welcome-text">Backend offline. Type <code>/</code> for local commands.</span>
              }>
                <span class="jarvis-welcome-text">
                  Ready. Ask <strong>{chatTarget()}</strong> anything, or type <code>/</code> for commands.
                </span>
              </Show>
            </div>
          </Show>
          <For each={agentStore.chatMessages()}>
            {(msg) => (
              <div class={`jarvis-msg jarvis-msg-${msg.sender}`}>
                <span class="jarvis-msg-sender">
                  {msg.sender === "user" ? "you" : chatTarget()}
                </span>
                <Show when={msg.widget} fallback={
                  msg.sender === "jarvis" ? (
                    <span class="jarvis-msg-content jarvis-markdown" innerHTML={renderMarkdown(msg.content)} />
                  ) : (
                    <span class="jarvis-msg-content">{msg.content}</span>
                  )
                }>
                  {(widget) => (
                    <div class="jarvis-msg-widget">
                      <Show when={widget().title}>
                        <div class="widget-header">{widget().title}</div>
                      </Show>
                      <WidgetSandbox
                        widget={widget()}
                        onOutput={handleWidgetOutput}
                      />
                      <Show when={msg.content}>
                        <span class="jarvis-msg-content jarvis-markdown" innerHTML={renderMarkdown(msg.content)} />
                      </Show>
                    </div>
                  )}
                </Show>
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
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <path
              d={expanded() ? "M2 4l4 4 4-4" : "M2 8l4-4 4 4"}
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </button>
        <div class="jarvis-input-wrap">
          <div class="jarvis-target-indicator">
            <span class="jarvis-target-pip" classList={{
              "pip-running": targetState() === "running",
              "pip-paused": targetState() === "paused",
              "pip-jarvis": !agentStore.selectedAgent(),
            }} />
            <span class="jarvis-target-name">{chatTarget()}</span>
          </div>
          <input
            ref={inputRef!}
            type="text"
            class="jarvis-input"
            placeholder={cliMode() ? "Search commands..." : "Message or / for commands"}
            value={input()}
            onInput={(e) => setInput(e.currentTarget.value)}
            onKeyDown={handleKeyDown}
            onFocus={() => setExpanded(true)}
          />
          <Show when={input().trim()}>
            <button class="jarvis-send-btn" onClick={submit}>
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <path d="M2 7h10M8 3l4 4-4 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
            </button>
          </Show>
          <Show when={!input().trim()}>
            <kbd class="jarvis-shortcut-hint">/</kbd>
          </Show>
        </div>
      </div>
    </div>
  );
};

export default JarvisBar;
