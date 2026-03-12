import { type Component, Show } from "solid-js";
import { holodeckStore } from "../stores/holodeck";

const HolodeckHUD: Component = () => {
  return (
    <Show when={holodeckStore.hudVisible()}>
      <div class="holodeck-hud" style={hudContainerStyle}>
        {/* Top-left: FPS + stats */}
        <div style={topLeftStyle}>
          <div style={panelStyle}>
            <span style={labelStyle}>FPS</span>
            <span style={valueStyle}>{holodeckStore.fps()}</span>
          </div>
          <div style={panelStyle}>
            <span style={labelStyle}>Entities</span>
            <span style={valueStyle}>{holodeckStore.entityCount()}</span>
          </div>
          <div style={panelStyle}>
            <span style={labelStyle}>Connections</span>
            <span style={valueStyle}>{holodeckStore.connectionCount()}</span>
          </div>
        </div>

        {/* Top-right: View mode */}
        <div style={topRightStyle}>
          <div style={panelStyle}>
            <span style={labelStyle}>Mode</span>
            <span style={valueStyle}>{holodeckStore.viewMode()}</span>
          </div>
        </div>

        {/* Bottom-left: Selected entity info */}
        <Show when={holodeckStore.selectedEntity()}>
          {(entity) => (
            <div style={bottomLeftStyle}>
              <div style={{ ...panelStyle, "min-width": "200px" }}>
                <div style={entityHeaderStyle}>
                  <span style={entityKindStyle}>{entity().kind}</span>
                  <span style={entityNameStyle}>{entity().label || `#${entity().id}`}</span>
                </div>
                <Show when={entity().agentId}>
                  <div style={entityRowStyle}>
                    <span style={labelStyle}>Agent</span>
                    <span style={smallValueStyle}>{entity().agentId}</span>
                  </div>
                </Show>
                <Show when={entity().cognitivePhase}>
                  <div style={entityRowStyle}>
                    <span style={labelStyle}>Phase</span>
                    <span style={phaseStyle(entity().cognitivePhase!)}>{entity().cognitivePhase}</span>
                  </div>
                </Show>
                <div style={entityRowStyle}>
                  <span style={labelStyle}>Position</span>
                  <span style={smallValueStyle}>
                    {entity().position.map((v) => v.toFixed(1)).join(", ")}
                  </span>
                </div>
              </div>
            </div>
          )}
        </Show>
      </div>
    </Show>
  );
};

// ── Styles ───────────────────────────────────────────────────────

const hudContainerStyle: Record<string, string> = {
  position: "absolute",
  inset: "0",
  "pointer-events": "none",
  "font-family": "'JetBrains Mono', monospace",
  "font-size": "12px",
  "z-index": "10",
};

const topLeftStyle: Record<string, string> = {
  position: "absolute",
  top: "12px",
  left: "12px",
  display: "flex",
  gap: "8px",
};

const topRightStyle: Record<string, string> = {
  position: "absolute",
  top: "12px",
  right: "12px",
  display: "flex",
  gap: "8px",
};

const bottomLeftStyle: Record<string, string> = {
  position: "absolute",
  bottom: "12px",
  left: "12px",
};

const panelStyle: Record<string, string> = {
  background: "rgba(10, 10, 30, 0.85)",
  border: "1px solid rgba(100, 100, 255, 0.25)",
  "border-radius": "4px",
  padding: "6px 10px",
  display: "flex",
  "flex-direction": "column",
  gap: "2px",
};

const labelStyle: Record<string, string> = {
  color: "rgba(160, 160, 200, 0.7)",
  "font-size": "9px",
  "text-transform": "uppercase",
  "letter-spacing": "0.5px",
};

const valueStyle: Record<string, string> = {
  color: "#e0e0ff",
  "font-size": "16px",
  "font-weight": "bold",
};

const smallValueStyle: Record<string, string> = {
  color: "#c0c0e0",
  "font-size": "11px",
};

const entityHeaderStyle: Record<string, string> = {
  display: "flex",
  "align-items": "center",
  gap: "8px",
  "margin-bottom": "4px",
};

const entityKindStyle: Record<string, string> = {
  color: "#8080ff",
  "font-size": "9px",
  "text-transform": "uppercase",
  background: "rgba(80, 80, 255, 0.15)",
  padding: "1px 5px",
  "border-radius": "2px",
};

const entityNameStyle: Record<string, string> = {
  color: "#e0e0ff",
  "font-size": "13px",
  "font-weight": "bold",
};

const entityRowStyle: Record<string, string> = {
  display: "flex",
  "justify-content": "space-between",
  gap: "12px",
  "align-items": "center",
};

function phaseStyle(phase: string): Record<string, string> {
  const colors: Record<string, string> = {
    observe: "#44cc88",
    reason: "#4488ff",
    decide: "#ff8844",
    act: "#ff4488",
    reflect: "#aa44ff",
  };
  return {
    color: colors[phase] || "#c0c0e0",
    "font-size": "11px",
    "font-weight": "bold",
  };
}

export default HolodeckHUD;
