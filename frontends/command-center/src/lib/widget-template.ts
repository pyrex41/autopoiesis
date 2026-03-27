import type { WidgetPayload } from "../stores/agents";
import { getDesignSystemCSS } from "./design-system";

/**
 * Build a complete HTML document for rendering an Arrow.js widget
 * inside a sandboxed iframe via srcdoc.
 */
export function buildWidgetHTML(widget: WidgetPayload): string {
  const designCSS = getDesignSystemCSS();
  const widgetCSS = widget.css ?? "";

  // Escape closing script tags in widget source to prevent premature closing
  const safeSource = widget.source.replace(/<\/script>/gi, "<\\/script>");

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://esm.sh https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://unpkg.com; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; connect-src *; img-src * data:;">
<style>${designCSS}</style>
${widgetCSS ? `<style>${widgetCSS}</style>` : ""}
</head>
<body>
<div id="app"></div>
<script type="module">
import { reactive, html, watch } from 'https://esm.sh/@arrow-js/core';

// Host communication bridge
function output(data) {
  window.parent.postMessage({
    type: 'widget_output',
    widgetId: ${JSON.stringify(widget.id)},
    data: data
  }, '*');
}

// Auto-report content height for dynamic iframe sizing
function reportHeight() {
  const h = document.body.scrollHeight;
  window.parent.postMessage({
    type: 'widget_resize',
    widgetId: ${JSON.stringify(widget.id)},
    height: h
  }, '*');
}

// Widget source
${safeSource}

// Report initial height after a frame
requestAnimationFrame(() => {
  reportHeight();
  // Observe future size changes
  new ResizeObserver(() => reportHeight()).observe(document.body);
});
</script>
</body>
</html>`;
}
