import { type Component, Show, createSignal, createEffect } from "solid-js";
import type { Thought } from "../stores/agents";

// Global signal for the modal — any component can open it
export const [modalThought, setModalThought] = createSignal<Thought | null>(null);

const typeLabels: Record<string, string> = {
  observation: "Observation",
  decision: "Decision",
  action: "Action",
  reflection: "Reflection",
};

const typeColors: Record<string, string> = {
  observation: "var(--signal)",
  decision: "var(--warm)",
  action: "var(--emerge)",
  reflection: "var(--purple)",
};

/** Try to pretty-print content that looks like JSON or S-expressions */
function formatContent(raw: string): { formatted: string; lang: string } {
  const trimmed = raw.trim();

  // JSON object or array
  if ((trimmed.startsWith("{") && trimmed.endsWith("}")) ||
      (trimmed.startsWith("[") && trimmed.endsWith("]"))) {
    try {
      const obj = JSON.parse(trimmed);
      return { formatted: JSON.stringify(obj, null, 2), lang: "json" };
    } catch { /* not valid JSON */ }
  }

  // Tool invocation: (:INVOKE :TOOL_NAME "{json...}")
  const invokeMatch = trimmed.match(/^\(:INVOKE\s+:(\S+)\s+"(.*)"\)$/s);
  if (invokeMatch) {
    const toolName = invokeMatch[1];
    let args = invokeMatch[2];
    // Unescape the JSON string
    try {
      args = JSON.stringify(JSON.parse(args.replace(/\\"/g, '"').replace(/\\\\/g, "\\")), null, 2);
    } catch {
      args = args.replace(/\\n/g, "\n").replace(/\\t/g, "\t").replace(/\\"/g, '"');
    }
    return { formatted: `Tool: ${toolName}\n\n${args}`, lang: "tool" };
  }

  // S-expression (starts with paren)
  if (trimmed.startsWith("(") || trimmed.startsWith("(:")) {
    // Simple indent formatting for S-expressions
    return { formatted: formatSexpr(trimmed), lang: "lisp" };
  }

  // Plain text — unescape common escape sequences
  const unescaped = raw
    .replace(/\\n/g, "\n")
    .replace(/\\t/g, "\t")
    .replace(/\\"/g, '"');
  return { formatted: unescaped, lang: "text" };
}

function formatSexpr(s: string): string {
  let indent = 0;
  let result = "";
  let inString = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '"' && (i === 0 || s[i - 1] !== "\\")) {
      inString = !inString;
      result += c;
    } else if (inString) {
      result += c;
    } else if (c === "(") {
      result += c;
      indent += 2;
    } else if (c === ")") {
      indent = Math.max(0, indent - 2);
      result += c;
    } else {
      result += c;
    }
  }
  return result;
}

const ThoughtModal: Component = () => {
  const thought = () => modalThought();

  // Close on Escape
  createEffect(() => {
    if (!thought()) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") setModalThought(null);
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  });

  return (
    <Show when={thought()}>
      {(t) => {
        const color = () => typeColors[t().type] || "var(--text)";
        const label = () => typeLabels[t().type] || t().type;
        const time = () => new Date(t().timestamp).toLocaleString();
        const { formatted, lang } = formatContent(t().content);

        return (
          <div class="thought-modal-overlay" onClick={() => setModalThought(null)}>
            <div class="thought-modal" onClick={(e) => e.stopPropagation()}>
              {/* Header */}
              <div class="thought-modal-header">
                <span class="thought-modal-badge" style={{ color: color(), "border-color": color() }}>
                  {label()}
                </span>
                <span class="thought-modal-time">{time()}</span>
                <span class="thought-modal-agent">{t().agentId?.substring(0, 8)}...</span>
                <button class="thought-modal-close" onClick={() => setModalThought(null)}>
                  &times;
                </button>
              </div>

              {/* Content */}
              <div class="thought-modal-body">
                <pre class={`thought-modal-content thought-modal-lang-${lang}`}>{formatted}</pre>
              </div>

              {/* Metadata */}
              <Show when={t().source || t().rationale || t().confidence != null || t().capability || t().result != null}>
                <div class="thought-modal-meta">
                  <Show when={t().source}>
                    <div class="thought-modal-meta-row">
                      <span class="thought-modal-meta-label">Source</span>
                      <span>{t().source}</span>
                    </div>
                  </Show>
                  <Show when={t().rationale}>
                    <div class="thought-modal-meta-row">
                      <span class="thought-modal-meta-label">Rationale</span>
                      <span>{t().rationale}</span>
                    </div>
                  </Show>
                  <Show when={t().confidence != null}>
                    <div class="thought-modal-meta-row">
                      <span class="thought-modal-meta-label">Confidence</span>
                      <span>{Math.round((t().confidence ?? 0) * 100)}%</span>
                    </div>
                  </Show>
                  <Show when={t().capability}>
                    <div class="thought-modal-meta-row">
                      <span class="thought-modal-meta-label">Capability</span>
                      <code>{t().capability}</code>
                    </div>
                  </Show>
                  <Show when={t().result != null}>
                    <div class="thought-modal-meta-row">
                      <span class="thought-modal-meta-label">Result</span>
                      <pre class="thought-modal-result">{typeof t().result === "string" ? t().result : JSON.stringify(t().result, null, 2)}</pre>
                    </div>
                  </Show>
                  <Show when={t().alternatives}>
                    <div class="thought-modal-meta-row">
                      <span class="thought-modal-meta-label">Alternatives</span>
                      <ul>
                        {t().alternatives?.map((alt: string) => (
                          <li classList={{ "thought-modal-chosen": alt === t().chosen }}>
                            {alt} {alt === t().chosen ? "\u2713" : ""}
                          </li>
                        ))}
                      </ul>
                    </div>
                  </Show>
                </div>
              </Show>

              {/* Raw JSON toggle */}
              <details class="thought-modal-raw">
                <summary>Raw JSON</summary>
                <pre>{JSON.stringify(t(), null, 2)}</pre>
              </details>
            </div>
          </div>
        );
      }}
    </Show>
  );
};

export default ThoughtModal;
