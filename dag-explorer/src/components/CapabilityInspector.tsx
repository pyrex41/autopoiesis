import { type Component, For, Show, createSignal } from "solid-js";
import { agentStore } from "../stores/agents";
import type { CapabilityDetail } from "../api/types";
import * as api from "../api/client";

const CAP_GROUPS: Record<string, { label: string; caps: string[] }> = {
  cognitive: { label: "Cognitive", caps: ["observe", "reason", "decide", "reflect"] },
  action: { label: "Action", caps: ["act", "learn", "tooluse", "selfmodify", "tool-use", "self-modify"] },
  social: { label: "Social", caps: ["communicate", "collaborate"] },
};

function formatCap(cap: string): string {
  const map: Record<string, string> = {
    selfmodify: "Self-Modify", tooluse: "Tool Use",
    "self-modify": "Self-Modify", "tool-use": "Tool Use",
  };
  return map[cap.toLowerCase()] ?? cap.charAt(0).toUpperCase() + cap.slice(1);
}

function groupCapabilities(caps: string[]): { group: string; items: string[] }[] {
  const result: { group: string; items: string[] }[] = [];
  for (const [, def] of Object.entries(CAP_GROUPS)) {
    const matched = caps.filter(c => def.caps.includes(c.toLowerCase()));
    if (matched.length > 0) result.push({ group: def.label, items: matched });
  }
  const allGrouped = Object.values(CAP_GROUPS).flatMap(g => g.caps);
  const remaining = caps.filter(c => !allGrouped.includes(c.toLowerCase()));
  if (remaining.length > 0) result.push({ group: "Other", items: remaining });
  return result;
}

function findCapDetail(name: string, details: CapabilityDetail[]): CapabilityDetail | undefined {
  return details.find(d => d.name.toLowerCase() === name.toLowerCase());
}

const CapabilityInspector: Component<{ capabilities: string[] }> = (props) => {
  const [expandedCap, setExpandedCap] = createSignal<string | null>(null);
  const [paramValues, setParamValues] = createSignal<Record<string, string>>({});
  const [invokeResult, setInvokeResult] = createSignal<unknown>(null);
  const [invokeError, setInvokeError] = createSignal<string | null>(null);
  const [invoking, setInvoking] = createSignal(false);

  const details = () => agentStore.agentCapabilities();

  function toggleCap(cap: string) {
    if (expandedCap() === cap) {
      setExpandedCap(null);
    } else {
      setExpandedCap(cap);
      setParamValues({});
      setInvokeResult(null);
      setInvokeError(null);
    }
  }

  function setParam(name: string, value: string) {
    setParamValues(prev => ({ ...prev, [name]: value }));
  }

  async function invoke(cap: string) {
    const agentId = agentStore.selectedId();
    if (!agentId) return;
    setInvoking(true);
    setInvokeError(null);
    setInvokeResult(null);
    try {
      const args: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(paramValues())) {
        if (v.trim()) args[k] = v;
      }
      const result = await api.invokeCapability(agentId, cap, Object.keys(args).length > 0 ? args : undefined);
      setInvokeResult(result);
    } catch (e) {
      setInvokeError(e instanceof Error ? e.message : String(e));
    } finally {
      setInvoking(false);
    }
  }

  return (
    <Show when={props.capabilities.length > 0} fallback={
      <span class="text-dim" style={{ "font-size": "12px" }}>None assigned</span>
    }>
      <div class="agent-caps-grouped">
        {groupCapabilities(props.capabilities).map(({ group, items }) => (
          <div class="agent-cap-group">
            <span class="agent-cap-group-label">{group}</span>
            <div class="agent-cap-group-items">
              {items.map((cap) => {
                const detail = () => findCapDetail(cap, details());
                const isExpanded = () => expandedCap() === cap;
                return (
                  <div class="cap-inspector-wrapper">
                    <button
                      class="agent-cap-badge cap-badge-clickable"
                      classList={{ "cap-badge-expanded": isExpanded() }}
                      onClick={() => toggleCap(cap)}
                    >
                      {formatCap(cap)}
                    </button>
                    <Show when={isExpanded()}>
                      <div class="cap-detail-panel">
                        <Show when={detail()} fallback={
                          <p class="cap-detail-desc">No details available from backend</p>
                        }>
                          {(d) => (
                            <>
                              <p class="cap-detail-desc">{d().description}</p>
                              <Show when={d().parameters.length > 0}>
                                <div class="cap-params">
                                  <For each={d().parameters}>
                                    {(param) => (
                                      <div class="cap-param-row">
                                        <label class="cap-param-label">
                                          {param.name}
                                          <span class="cap-param-type">{param.type}</span>
                                        </label>
                                        <input
                                          type="text"
                                          class="cap-param-input"
                                          placeholder={param.type}
                                          value={paramValues()[param.name] ?? ""}
                                          onInput={(e) => setParam(param.name, e.currentTarget.value)}
                                        />
                                      </div>
                                    )}
                                  </For>
                                </div>
                              </Show>
                              <button
                                class="cap-invoke-btn"
                                disabled={invoking()}
                                onClick={() => invoke(cap)}
                              >
                                {invoking() ? "Invoking..." : "Invoke"}
                              </button>
                            </>
                          )}
                        </Show>
                        <Show when={invokeResult()}>
                          <pre class="cap-result">{JSON.stringify(invokeResult(), null, 2)}</pre>
                        </Show>
                        <Show when={invokeError()}>
                          <div class="cap-error">{invokeError()}</div>
                        </Show>
                      </div>
                    </Show>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </Show>
  );
};

export default CapabilityInspector;
