import { type Component, Show, For, onMount } from "solid-js";
import { widgetStore } from "../stores/widgets";
import WidgetSandbox from "./WidgetSandbox";
import { wsStore } from "../stores/ws";

const WidgetsView: Component = () => {
  onMount(() => {
    widgetStore.init();
  });

  function handleWidgetOutput(data: unknown) {
    if (!data || typeof data !== "object") return;
    const d = data as Record<string, unknown>;
    if (d.widgetId) {
      wsStore.send({ type: "widget_output", widgetId: d.widgetId as string, data } as any);
    }
  }

  function removeWidget(id: string) {
    widgetStore.removeWidget(id);
  }

  return (
    <div class="widgets-view">
      <div class="widgets-view-header">
        <h2>Widgets</h2>
        <span style={{ color: "var(--text-dim)", "font-size": "12px" }}>
          {widgetStore.widgets().length} pinned
        </span>
      </div>

      <Show
        when={widgetStore.widgets().length > 0}
        fallback={
          <div class="widgets-empty">
            <div class="widgets-empty-icon">⧉</div>
            <div>No widgets pinned yet.</div>
            <div style={{ color: "var(--text-dim)", "font-size": "12px" }}>
              Ask an agent to show a widget, then pin it here from chat.
            </div>
          </div>
        }
      >
        <div class="widgets-grid">
          <For each={widgetStore.widgets()}>
            {(widget) => (
              <div class="widget-card">
                <div class="widget-card-header">
                  <span class="widget-card-title">
                    {widget.title ?? widget.id}
                  </span>
                  <div class="widget-card-actions">
                    <button
                      class="widget-card-btn"
                      onClick={() => removeWidget(widget.id)}
                      title="Remove widget"
                    >
                      ×
                    </button>
                  </div>
                </div>
                <WidgetSandbox
                  widget={widget}
                  onOutput={handleWidgetOutput}
                />
              </div>
            )}
          </For>
        </div>
      </Show>
    </div>
  );
};

export default WidgetsView;
