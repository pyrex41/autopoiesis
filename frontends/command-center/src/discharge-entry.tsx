/**
 * Entry point for the standalone /discharge.html page.
 * Renders a Shen-Backpressure discharge report.
 */
import { render } from "solid-js/web";
import DischargeView from "./pages/DischargeView";

const root = document.getElementById("discharge-root");
if (!root) throw new Error("Root element #discharge-root not found");

render(() => <DischargeView />, root);
