import { type Component, createSignal, createEffect, onMount, onCleanup, For, Show } from "solid-js";
import type { Agent } from "../api/types";

interface ChatMessage {
  id: string;
  sender: "user" | "agent";
  content: string;
  timestamp: Date;
}

interface ChatSession {
  agentId: string;
  messages: ChatMessage[];
  isActive: boolean;
}

const ChatPane: Component = () => {
  const [isOpen, setIsOpen] = createSignal(false);
  const [selectedAgent, setSelectedAgent] = createSignal<string | null>(null);
  const [chatInput, setChatInput] = createSignal("");
  const [chatSessions, setChatSessions] = createSignal<Map<string, ChatSession>>(new Map());
  const [agents, setAgents] = createSignal<Agent[]>([]);
  const [isLoading, setIsLoading] = createSignal(false);

  // WebSocket connection for chat
  let ws: WebSocket | null = null;

  const connectWebSocket = (agentId: string) => {
    if (ws) ws.close();

    // Connect to WebSocket endpoint for chat
    ws = new WebSocket(`ws://${window.location.host}/api/chat/${agentId}`);

    ws.onopen = () => {
      console.log(`Chat WebSocket connected for agent ${agentId}`);
      updateSession(agentId, { isActive: true });
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === "chat_response") {
          addMessage(agentId, "agent", data.content);
        }
      } catch (error) {
        console.error("Failed to parse chat message:", error);
      }
    };

    ws.onclose = () => {
      console.log(`Chat WebSocket disconnected for agent ${agentId}`);
      updateSession(agentId, { isActive: false });
    };

    ws.onerror = (error) => {
      console.error("Chat WebSocket error:", error);
      updateSession(agentId, { isActive: false });
    };
  };

  const disconnectWebSocket = () => {
    if (ws) {
      ws.close();
      ws = null;
    }
  };

  const updateSession = (agentId: string, updates: Partial<ChatSession>) => {
    setChatSessions(prev => {
      const newMap = new Map(prev);
      const session = newMap.get(agentId);
      if (session) {
        newMap.set(agentId, { ...session, ...updates });
      }
      return newMap;
    });
  };

  const addMessage = (agentId: string, sender: "user" | "agent", content: string) => {
    const message: ChatMessage = {
      id: `${Date.now()}-${Math.random()}`,
      sender,
      content,
      timestamp: new Date(),
    };

    setChatSessions(prev => {
      const newMap = new Map(prev);
      const session = newMap.get(agentId);
      if (session) {
        newMap.set(agentId, {
          ...session,
          messages: [...session.messages, message],
        });
      } else {
        newMap.set(agentId, {
          agentId,
          messages: [message],
          isActive: false,
        });
      }
      return newMap;
    });
  };

  const sendMessage = async () => {
    const agentId = selectedAgent();
    const message = chatInput().trim();
    if (!agentId || !message) return;

    addMessage(agentId, "user", message);
    setChatInput("");

    if (ws && ws.readyState === WebSocket.OPEN) {
      setIsLoading(true);
      ws.send(JSON.stringify({
        type: "chat_prompt",
        content: message,
      }));
      setIsLoading(false);
    } else {
      // Fallback: try to connect and send
      connectWebSocket(agentId);
      setTimeout(() => {
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({
            type: "chat_prompt",
            content: message,
          }));
        }
      }, 100);
    }
  };

  const handleKeyPress = (e: KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  const startChat = (agentId: string) => {
    setSelectedAgent(agentId);
    connectWebSocket(agentId);
    setIsOpen(true);
  };

  const closeChat = () => {
    disconnectWebSocket();
    setSelectedAgent(null);
    setIsOpen(false);
  };

  // Load agents on mount
  onMount(async () => {
    try {
      const response = await fetch("/api/agents");
      const agentList = await response.json();
      setAgents(agentList);
    } catch (error) {
      console.error("Failed to load agents:", error);
    }
  });

  onCleanup(() => {
    disconnectWebSocket();
  });

  const currentSession = () => {
    const agentId = selectedAgent();
    return agentId ? chatSessions().get(agentId) : null;
  };

  return (
    <div class="chat-pane" classList={{ open: isOpen() }}>
      {/* Chat toggle button */}
      <button
        class="chat-toggle-btn"
        onClick={() => setIsOpen(!isOpen())}
        title="Toggle chat pane"
      >
        💬
      </button>

      {/* Chat panel */}
      <div class="chat-panel">
        <div class="chat-header">
          <h3>Agent Chat</h3>
          <button class="btn-close" onClick={closeChat}>×</button>
        </div>

        <Show
          when={selectedAgent()}
          fallback={
            <div class="chat-agent-list">
              <h4>Select an Agent</h4>
              <For each={agents()}>
                {(agent) => (
                  <button
                    class="agent-chat-btn"
                    onClick={() => startChat(agent.id)}
                  >
                    <div class="agent-name">{agent.name}</div>
                    <div class="agent-status">
                      {agent.state === "running" ? "🟢" : "⚪"} {agent.state}
                    </div>
                  </button>
                )}
              </For>
            </div>
          }
        >
          <div class="chat-session">
            <div class="chat-messages">
              <For each={currentSession()?.messages || []}>
                {(message) => (
                  <div class={`chat-message ${message.sender}`}>
                    <div class="message-content">{message.content}</div>
                    <div class="message-time">
                      {message.timestamp.toLocaleTimeString()}
                    </div>
                  </div>
                )}
              </For>
              <Show when={isLoading()}>
                <div class="chat-message agent loading">
                  <div class="message-content">Thinking...</div>
                </div>
              </Show>
            </div>

            <div class="chat-input-area">
              <textarea
                class="chat-input"
                placeholder="Type your message..."
                value={chatInput()}
                onInput={(e) => setChatInput(e.currentTarget.value)}
                onKeyPress={handleKeyPress}
                rows="2"
              />
              <button
                class="btn-send"
                onClick={sendMessage}
                disabled={!chatInput().trim() || isLoading()}
              >
                Send
              </button>
            </div>
          </div>
        </Show>
      </div>
    </div>
  );
};

export default ChatPane;