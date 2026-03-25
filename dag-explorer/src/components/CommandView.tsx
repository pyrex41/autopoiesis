import { type Component, Show, For, createSignal, createEffect, onMount, onCleanup } from "solid-js";
import { agentStore } from "../stores/agents";
import { wsStore } from "../stores/ws";
import { renderMarkdown } from "../lib/markdown";
import { commands, type Command } from "../lib/commands";
import BlockRenderer, { type Block } from "./blocks/BlockRenderer";

/**
 * CommandView — the primary interaction surface.
 *
 * Full-screen conversational agent (Jarvis) with generative UI.
 * User types natural language → Jarvis queries DAG/substrate →
 * responses render as rich blocks (diffs, file trees, timelines, etc.)
 * alongside markdown text.
 */
const CommandView: Component = () => {
  let inputRef!: HTMLTextAreaElement;
  let historyRef!: HTMLDivElement;
  const [input, setInput] = createSignal("");
  const [cliSelectedIdx, setCliSelectedIdx] = createSignal(0);

  // CLI command mode (starts with / or :)
  const cliMode = () => {
    const v = input();
    return v.startsWith("/") || v.startsWith(":");
  };

  const cliAliasMap: Record<string, string> = {
    "agent.create": "/create", "agent.start": "/start", "agent.stop": "/stop",
    "agent.step": "/step", "agent.fork": "/fork",
    "view.command": "/command", "view.dag": "/graph", "view.timeline": "/stream",
    "view.dashboard": "/dashboard",
    "system.connect": "/connect", "system.refresh": "/refresh",
  };

  const cliMatches = () => {
    if (!cliMode()) return [];
    const q = input().slice(1).toLowerCase();
    return commands.filter((cmd) => {
      const alias = cliAliasMap[cmd.id] ?? "";
      return alias.toLowerCase().includes(q) ||
        cmd.name.toLowerCase().includes(q) ||
        cmd.id.toLowerCase().includes(q);
    }).slice(0, 8);
  };

  createEffect(() => { cliMatches(); setCliSelectedIdx(0); });

  function executeCliCommand(cmd: Command) {
    cmd.handler();
    setInput("");
  }

  function submit() {
    if (cliMode()) {
      const matches = cliMatches();
      if (matches.length > 0) executeCliCommand(matches[cliSelectedIdx()]);
      return;
    }
    const text = input().trim();
    if (!text) return;
    agentStore.sendChatMessage(text);
    setInput("");
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (cliMode()) {
      const matches = cliMatches();
      if (e.key === "ArrowDown") { e.preventDefault(); setCliSelectedIdx(i => Math.min(i + 1, matches.length - 1)); return; }
      if (e.key === "ArrowUp") { e.preventDefault(); setCliSelectedIdx(i => Math.max(i - 1, 0)); return; }
      if (e.key === "Escape") { e.preventDefault(); setInput(""); return; }
    }
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); submit(); }
    if (e.key === "Escape" && !cliMode()) { inputRef?.blur(); }
  }

  // Auto-scroll to bottom on new messages
  createEffect(() => {
    const _ = agentStore.chatMessages().length;
    const __ = agentStore.streamingText();
    if (historyRef) {
      requestAnimationFrame(() => { historyRef.scrollTop = historyRef.scrollHeight; });
    }
  });

  // Focus input on mount
  onMount(() => {
    requestAnimationFrame(() => inputRef?.focus());
  });

  const chatTarget = () => {
    const agent = agentStore.selectedAgent();
    return agent ? agent.name : "Jarvis";
  };

  // Extract blocks from chat messages (embedded in message metadata)
  const getBlocks = (msg: any): Block[] => {
    return msg.blocks ?? [];
  };

  return (
    <div class="command-view">
      {/* Chat history with generative blocks */}
      <div class="command-history" ref={historyRef!}>
        <Show when={agentStore.chatMessages().length === 0}>
          <div class="command-welcome">
            <div class="command-welcome-icon">
              <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
                <path d="M4 10l8 8-8 8" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
                <path d="M16 26h12" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
              </svg>
            </div>
            <Show when={wsStore.connected()} fallback={
              <div class="command-welcome-text">
                <strong>Backend offline.</strong> Type <code>/</code> for local commands.
              </div>
            }>
              <div class="command-welcome-text">
                Ask <strong>{chatTarget()}</strong> anything about your sandboxes, snapshots, or agent state.
              </div>
              <div class="command-welcome-hints">
                <button class="command-hint" onClick={() => { setInput("Show me all snapshots"); submit(); }}>
                  Show me all snapshots
                </button>
                <button class="command-hint" onClick={() => { setInput("What changed today?"); submit(); }}>
                  What changed today?
                </button>
                <button class="command-hint" onClick={() => { setInput("List active sandboxes"); submit(); }}>
                  List active sandboxes
                </button>
              </div>
            </Show>
          </div>
        </Show>

        <For each={agentStore.chatMessages()}>
          {(msg) => (
            <div class={`command-msg command-msg-${msg.sender}`}>
              <div class="command-msg-header">
                <span class="command-msg-sender">
                  {msg.sender === "user" ? "you" : chatTarget()}
                </span>
              </div>
              <div class="command-msg-body">
                {msg.sender === "jarvis" ? (
                  <div class="command-msg-content command-markdown" innerHTML={renderMarkdown(msg.content)} />
                ) : (
                  <div class="command-msg-content">{msg.content}</div>
                )}
                {/* Render generative UI blocks */}
                <Show when={getBlocks(msg).length > 0}>
                  <BlockRenderer blocks={getBlocks(msg)} />
                </Show>
              </div>
            </div>
          )}
        </For>

        {/* Streaming indicator */}
        <Show when={agentStore.chatLoading()}>
          <div class="command-msg command-msg-jarvis">
            <div class="command-msg-header">
              <span class="command-msg-sender">{chatTarget()}</span>
            </div>
            <div class="command-msg-body">
              <Show when={agentStore.streamingText()} fallback={
                <div class="command-typing">
                  <span /><span /><span />
                </div>
              }>
                <div class="command-msg-content command-markdown"
                     innerHTML={renderMarkdown(agentStore.streamingText()!)} />
              </Show>
            </div>
          </div>
        </Show>
      </div>

      {/* CLI autocomplete */}
      <Show when={cliMode() && cliMatches().length > 0}>
        <div class="command-autocomplete">
          <For each={cliMatches()}>
            {(cmd, idx) => (
              <div
                class="command-autocomplete-item"
                classList={{ "command-autocomplete-selected": idx() === cliSelectedIdx() }}
                onClick={() => executeCliCommand(cmd)}
              >
                <span class="command-autocomplete-alias">{cliAliasMap[cmd.id] ?? `/${cmd.id}`}</span>
                <span class="command-autocomplete-name">{cmd.name}</span>
                <Show when={cmd.description}>
                  <span class="command-autocomplete-desc">{cmd.description}</span>
                </Show>
              </div>
            )}
          </For>
        </div>
      </Show>

      {/* Input area */}
      <div class="command-input-area">
        <div class="command-input-wrap">
          <textarea
            ref={inputRef!}
            class="command-input"
            placeholder={cliMode() ? "Search commands..." : `Message ${chatTarget()} or / for commands`}
            value={input()}
            onInput={(e) => setInput(e.currentTarget.value)}
            onKeyDown={handleKeyDown}
            rows={1}
          />
          <Show when={input().trim()}>
            <button class="command-send" onClick={submit}>
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <path d="M2 8h12M10 4l4 4-4 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
            </button>
          </Show>
        </div>
      </div>
    </div>
  );
};

export default CommandView;
