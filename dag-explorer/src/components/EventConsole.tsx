import { type Component, createSignal, onMount, onCleanup, For } from "solid-js";
import { subscribeEvents } from "../api/client";

interface SSEEvent {
  type: string;
  data: any;
  timestamp: number;
}

const EventConsole: Component = () => {
  const [events, setEvents] = createSignal<SSEEvent[]>([]);
  const [isConnected, setIsConnected] = createSignal(false);
  const [filter, setFilter] = createSignal("");

  let unsubscribe: (() => void) | undefined;

  onMount(() => {
    unsubscribe = subscribeEvents((type, data) => {
      setIsConnected(true);
      const event: SSEEvent = {
        type,
        data,
        timestamp: Date.now()
      };
      setEvents(prev => [event, ...prev.slice(0, 99)]); // Keep last 100 events
    });
  });

  onCleanup(() => {
    if (unsubscribe) {
      unsubscribe();
    }
  });

  const filteredEvents = () => {
    const f = filter().toLowerCase();
    if (!f) return events();
    return events().filter(event =>
      event.type.toLowerCase().includes(f) ||
      JSON.stringify(event.data).toLowerCase().includes(f)
    );
  };

  const formatTimestamp = (timestamp: number) => {
    return new Date(timestamp).toLocaleTimeString();
  };

  const getEventIcon = (type: string) => {
    if (type.includes('agent')) return '🤖';
    if (type.includes('snapshot')) return '📸';
    if (type.includes('branch')) return '🌿';
    if (type.includes('request')) return '📨';
    if (type.includes('capability')) return '🛠️';
    return '📢';
  };

  return (
    <div class="event-console">
      <div class="console-header">
        <h3>
          {getEventIcon('')} Event Console
          <span class={`connection-status ${isConnected() ? 'connected' : 'disconnected'}`}>
            {isConnected() ? '🟢' : '🔴'} {isConnected() ? 'Live' : 'Disconnected'}
          </span>
        </h3>
        <div class="console-controls">
          <input
            type="text"
            placeholder="Filter events..."
            value={filter()}
            onInput={(e) => setFilter(e.currentTarget.value)}
            class="filter-input"
          />
          <button
            class="btn-clear"
            onClick={() => setEvents([])}
          >
            Clear
          </button>
        </div>
      </div>

      <div class="events-list">
        <For each={filteredEvents()}>
          {(event) => (
            <div class="event-item">
              <div class="event-header">
                <span class="event-icon">{getEventIcon(event.type)}</span>
                <span class="event-type">{event.type}</span>
                <span class="event-time">{formatTimestamp(event.timestamp)}</span>
              </div>
              <div class="event-data">
                <pre>{JSON.stringify(event.data, null, 2)}</pre>
              </div>
            </div>
          )}
        </For>

        {filteredEvents().length === 0 && (
          <div class="empty-console">
            <p>No events to display</p>
            <p class="hint">
              {filter() ? 'Try adjusting your filter' : 'Events will appear here when they occur'}
            </p>
          </div>
        )}
      </div>
    </div>
  );
};

export default EventConsole;