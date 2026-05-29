/* @refresh reload */
/*
 * Legacy entry: the original 9-tab AppShell dashboard, now served at
 * /app.html. The root (index.html) is the SB cockpit (see src/index.tsx).
 */
import { render } from "solid-js/web";
import App from "./App";
import "./styles/global.css";

const root = document.getElementById("root");
if (!root) throw new Error("Root element not found");

render(() => <App />, root);
