/** Standalone entry point for the embeddable holodeck.
 *  Built separately via `bun run build:holodeck` and outputs holodeck.js + holodeck.html.
 */
import { render } from "solid-js/web";
import HolodeckEmbed from "./components/HolodeckEmbed";

// Read wsUrl from URL params or default to current host
const params = new URLSearchParams(window.location.search);
const wsUrl = params.get("ws") ??
  `ws://${window.location.hostname}:${params.get("port") ?? "8080"}/ws`;
const theme = (params.get("theme") as "dark" | "light") ?? "dark";

const root = document.getElementById("holodeck-root");
if (root) {
  render(() => <HolodeckEmbed wsUrl={wsUrl} theme={theme} />, root);
}
