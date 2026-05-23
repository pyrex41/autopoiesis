/**
 * Entry point for the standalone /aether.html page.
 * Mirrors src/index.tsx and src/detached.tsx — minimal mount.
 */
import { render } from "solid-js/web";
import AetherMap from "./pages/AetherMap";

const root = document.getElementById("aether-root");
if (!root) throw new Error("Root element #aether-root not found");

render(() => <AetherMap />, root);
