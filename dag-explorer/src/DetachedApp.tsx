import { type Component, lazy, Suspense } from "solid-js";
import { getDetachedPanel } from "./lib/detach";

const DAGView = lazy(() => import("./components/DAGView"));
const HolodeckView = lazy(() => import("./components/HolodeckView"));

const panels: Record<string, Component> = {
  dag: () => (
    <Suspense fallback={<div style={{ color: "#d0daf0", padding: "24px" }}>Loading DAG...</div>}>
      <DAGView />
    </Suspense>
  ),
  holodeck: () => (
    <Suspense fallback={<div style={{ color: "#d0daf0", padding: "24px" }}>Loading Holodeck...</div>}>
      <HolodeckView />
    </Suspense>
  ),
};

const DetachedApp: Component = () => {
  const panelId = getDetachedPanel();
  const Panel = panelId ? panels[panelId] : null;

  return (
    <div style={{ width: "100vw", height: "100vh", background: "#04060e", overflow: "hidden" }}>
      {Panel ? <Panel /> : <div style={{ color: "#d0daf0", padding: "24px" }}>Unknown panel: {panelId}</div>}
    </div>
  );
};

export default DetachedApp;
