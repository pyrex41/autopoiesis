import { type Component, Show, For, createSignal, createEffect, onMount, onCleanup } from "solid-js";
import { agentStore, type ChatMessage } from "../stores/agents";

const JarvisBar: Component = () => {
  let inputRef!: HTMLInputElement;
  let historyRef!: HTMLDivElement;
  const [expanded, setExpanded] = createSignal(false);
  const [input, setInput] = createSignal("");

  function submit() {
    const text = input().trim();
    if (!text) return;
    agentStore.sendChatMessage(text);
    setInput("");
    setExpanded(true);
  }

  function handleKeyDown(e: KeyboardEvent) {
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

  return (
    <div class="jarvis-bar" classList={{ "jarvis-expanded": expanded() }}>
      {/* Chat history (expanded) */}
      <Show when={expanded() && agentStore.chatMessages().length > 0}>
        <div class="jarvis-history" ref={historyRef!}>
          <For each={agentStore.chatMessages()}>
            {(msg) => (
              <div class={`jarvis-msg jarvis-msg-${msg.sender}`}>
                <span class="jarvis-msg-sender">
                  {msg.sender === "user" ? "You" : "Jarvis"}
                </span>
                <span class="jarvis-msg-content">{msg.content}</span>
              </div>
            )}
          </For>
          <Show when={agentStore.chatLoading()}>
            <div class="jarvis-msg jarvis-msg-jarvis">
              <span class="jarvis-msg-sender">Jarvis</span>
              <span class="jarvis-msg-content jarvis-typing">
                <span class="typing-dot" />
                <span class="typing-dot" />
                <span class="typing-dot" />
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
          <span class="jarvis-prompt-icon">J</span>
          <input
            ref={inputRef!}
            type="text"
            class="jarvis-input"
            placeholder='Ask Jarvis anything... (press / to focus)'
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
