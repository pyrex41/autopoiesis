import { createSignal, createEffect, onCleanup, type Component } from "solid-js";
import type { WidgetPayload } from "../stores/agents";
import { buildWidgetHTML } from "../lib/widget-template";

interface WidgetSandboxProps {
  widget: WidgetPayload;
  onOutput?: (data: unknown) => void;
}

const WidgetSandbox: Component<WidgetSandboxProps> = (props) => {
  let iframeRef: HTMLIFrameElement | undefined;
  const [height, setHeight] = createSignal(props.widget.height ?? 200);

  const srcdoc = () => buildWidgetHTML(props.widget);

  // Listen for postMessage from the sandboxed iframe
  createEffect(() => {
    function handleMessage(event: MessageEvent) {
      // Validate source is our iframe
      if (!iframeRef || event.source !== iframeRef.contentWindow) return;

      const msg = event.data;
      if (!msg || typeof msg !== "object" || !msg.type) return;

      // Only process messages from this widget
      if (msg.widgetId !== props.widget.id) return;

      switch (msg.type) {
        case "widget_output":
          props.onOutput?.(msg.data);
          break;
        case "widget_resize":
          if (typeof msg.height === "number" && msg.height > 0) {
            setHeight(Math.min(msg.height + 2, 800)); // cap at 800px
          }
          break;
      }
    }

    window.addEventListener("message", handleMessage);
    onCleanup(() => window.removeEventListener("message", handleMessage));
  });

  return (
    <iframe
      ref={iframeRef}
      class="widget-sandbox-frame"
      sandbox="allow-scripts"
      srcdoc={srcdoc()}
      style={{ height: `${height()}px` }}
      title={props.widget.title ?? "Widget"}
    />
  );
};

export default WidgetSandbox;
