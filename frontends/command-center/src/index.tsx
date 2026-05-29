/* @refresh reload */
/*
 * Primary app surface: the Shen-Backpressure cockpit. The original 9-tab
 * dashboard now lives at /app.html (see src/app-entry.tsx).
 */
import { render } from "solid-js/web";
import Cockpit from "./components/cockpit/Cockpit";
import "./styles/reset.css";
import "./styles/discharge.css";
import "./styles/cockpit.css";

const root = document.getElementById("root");
if (!root) throw new Error("Root element not found");

render(() => <Cockpit />, root);
