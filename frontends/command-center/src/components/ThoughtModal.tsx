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

/**
 * Handle nested Lisp→JSON double-escaping.
 * Repeats until no more escape sequences are found.
 */
export function deepUnescape(s: string): string {
  let prev = s;
  for (let i = 0; i < 3; i++) {
    const next = prev
      .replace(/\\\\n/g, "\\n")   // \\n → \n (literal)
      .replace(/\\\\t/g, "\\t")
      .replace(/\\\\"/g, '\\"')
      .replace(/\\\\\\\\/g, "\\\\")
      .replace(/\\n/g, "\n")
      .replace(/\\t/g, "\t")
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, "\\");
    if (next === prev) break;
    prev = next;
  }
  return prev;
}

/** Normalize CL timestamps (seconds) to JS timestamps (milliseconds) */
export function normalizeTimestamp(ts: number): number {
  if (ts < 1e12) return ts * 1000;
  return ts;
}

interface FormattedContent {
  toolName?: string;
  filePath?: string;
  codeContent?: string;
  codeLang?: string;
  formatted: string;
  lang: string;
}

/** Try to pretty-print content that looks like JSON, tool invocations, or S-expressions */
function formatContent(raw: string): FormattedContent {
  const trimmed = raw.trim();

  // JSON object or array
  if ((trimmed.startsWith("{") && trimmed.endsWith("}")) ||
      (trimmed.startsWith("[") && trimmed.endsWith("]"))) {
    try {
      const obj = JSON.parse(trimmed);
      return { formatted: JSON.stringify(obj, null, 2), lang: "json" };
    } catch { /* not valid JSON */ }
  }

  // Tool invocation: (:INVOKE :TOOL_NAME "..." ) or (:INVOKE :TOOL_NAME "...") or truncated with ...
  if (trimmed.startsWith("(:INVOKE :") || trimmed.startsWith("(:INVOKE:")) {
    return parseToolInvocation(trimmed);
  }

  // S-expression (starts with paren)
  if (trimmed.startsWith("(") || trimmed.startsWith("(:")) {
    return { formatted: formatSexpr(trimmed), lang: "lisp" };
  }

  // Plain text — deep unescape
  return { formatted: deepUnescape(raw), lang: "text" };
}

function parseToolInvocation(trimmed: string): FormattedContent {
  // Extract tool name: (:INVOKE :TOOL_NAME ...)
  const toolMatch = trimmed.match(/^\(:INVOKE\s+:(\S+)/);
  const toolName = toolMatch ? toolMatch[1] : "UNKNOWN";

  // Extract the JSON arg string between first " and last " (or ...")
  const firstQuote = trimmed.indexOf('"');
  let args = "";
  if (firstQuote !== -1) {
    // Find the last quote (may be followed by ) or ...)
    let lastQuote = trimmed.lastIndexOf('"');
    // If the last char sequence is ...") or ") — find the actual end
    if (lastQuote > firstQuote) {
      args = trimmed.slice(firstQuote + 1, lastQuote);
    } else {
      args = trimmed.slice(firstQuote + 1);
    }
  }

  // Deep unescape the nested escaping
  const unescaped = deepUnescape(args);

  // Try to parse as JSON
  let filePath: string | undefined;
  let codeContent: string | undefined;
  let codeLang: string | undefined;
  let prettyArgs = unescaped;

  try {
    const obj = JSON.parse(unescaped);
    prettyArgs = JSON.stringify(obj, null, 2);

    // Extract file path and content for WRITE/READ tools
    if (obj.file_path || obj.path || obj.file) {
      filePath = obj.file_path || obj.path || obj.file;
    }
    if (obj.content || obj.code) {
      codeContent = obj.content || obj.code;
      codeLang = detectLanguage(filePath || "");
    }
  } catch {
    // Not valid JSON — just use the unescaped text
    // Try to detect file path patterns in the text
    const pathMatch = unescaped.match(/(?:file_path|path|file)\s*[":]\s*"?([^\s",}]+)/);
    if (pathMatch) filePath = pathMatch[1];
  }

  const formatted = codeContent
    ? `Tool: ${toolName}${filePath ? `\nFile: ${filePath}` : ""}\n\n${codeContent}`
    : `Tool: ${toolName}${filePath ? `\nFile: ${filePath}` : ""}\n\n${prettyArgs}`;

  return {
    toolName,
    filePath,
    codeContent,
    codeLang,
    formatted,
    lang: "tool",
  };
}

function detectLanguage(path: string): string {
  const ext = path.split(".").pop()?.toLowerCase() || "";
  const langMap: Record<string, string> = {
    go: "go", rs: "rust", py: "python", js: "javascript", ts: "typescript",
    tsx: "typescript", jsx: "javascript", lisp: "lisp", lsp: "lisp",
    cl: "lisp", el: "lisp", rb: "ruby", java: "java", c: "c", cpp: "cpp",
    h: "c", hpp: "cpp", css: "css", html: "html", json: "json", yaml: "yaml",
    yml: "yaml", toml: "toml", md: "markdown", sh: "bash", bash: "bash",
    sql: "sql", xml: "xml",
  };
  return langMap[ext] || "text";
}

function formatSexpr(s: string): string {
  let indent = 0;
  let result = "";
  let inString = false;
  const knownForms = new Set([":INVOKE", ":REFLECT-ON", ":DECIDED", ":OBSERVED", ":CAPABILITY"]);

  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '"' && (i === 0 || s[i - 1] !== "\\")) {
      inString = !inString;
      result += c;
    } else if (inString) {
      result += c;
    } else if (c === "(") {
      if (indent > 0 && result.length > 0 && !result.endsWith("\n") && !result.endsWith("(")) {
        result += "\n" + " ".repeat(indent);
      }
      result += c;
      indent += 2;
    } else if (c === ")") {
      indent = Math.max(0, indent - 2);
      if (indent > 0 && result.length > 0 && !result.endsWith("\n") && !result.endsWith("(")) {
        result += "\n" + " ".repeat(indent);
      }
      result += c;
    } else if (c === ":" && !inString) {
      // Check if this starts a known form keyword — add newline before it
      let keyword = ":";
      let j = i + 1;
      while (j < s.length && /[A-Z_-]/.test(s[j])) {
        keyword += s[j];
        j++;
      }
      if (knownForms.has(keyword) && indent > 0 && result.length > 0 && !result.endsWith("\n") && !result.endsWith("(")) {
        result += "\n" + " ".repeat(indent);
      }
      result += c;
    } else {
      result += c;
    }
  }
  return result;
}

/**
 * Produce a clean 1-line summary for ThoughtCards and Timeline entries.
 */
export function summarizeThought(t: Thought): string {
  const content = t.content.trim();

  // Tool invocations: (:INVOKE :WRITE "{...}") → "WRITE main.go"
  if (content.startsWith("(:INVOKE")) {
    const toolMatch = content.match(/^\(:INVOKE\s+:(\S+)/);
    const toolName = toolMatch ? toolMatch[1] : "TOOL";

    // Try to extract a file path from the JSON args
    const pathMatch = content.match(/(?:file_path|path|file)[\\]*"[:\\s]*[\\]*"([^"\\]+)/);
    if (pathMatch) {
      // Shorten long paths
      const path = pathMatch[1];
      const short = path.split("/").slice(-2).join("/");
      return `${toolName} ${short}`;
    }
    return toolName;
  }

  // Decisions: (:DECIDED :DELEGATE ...) → "Decided: DELEGATE"
  if (content.startsWith("(:DECIDED")) {
    const decMatch = content.match(/^\(:DECIDED\s+:(\S+)/);
    if (decMatch) return `Decided: ${decMatch[1]}`;
  }

  // Reflections: (:REFLECT-ON ...) → extract key info
  if (content.startsWith("(:REFLECT-ON")) {
    const reflMatch = content.match(/^\(:REFLECT-ON\s+:(\S+)/);
    if (reflMatch) {
      // Look for :RESULT :SUCCESS or :TURNS N
      const resultMatch = content.match(/:RESULT\s+:(\S+)/);
      const turnsMatch = content.match(/:TURNS\s+(\d+)/);
      let summary = `Reflect: ${reflMatch[1]}`;
      if (resultMatch) summary += ` (${resultMatch[1].toLowerCase()})`;
      if (turnsMatch) summary += `, ${turnsMatch[1]} turns`;
      return summary;
    }
  }

  // Observations: strip wrapping quotes and parens
  let cleaned = content;
  if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
    cleaned = cleaned.slice(1, -1);
  }
  if (cleaned.startsWith("(:OBSERVED ")) {
    const obsMatch = cleaned.match(/^\(:OBSERVED\s+:(\S+)\s+"?([^"]*)"?\)?$/);
    if (obsMatch) return `Observed: ${obsMatch[1]} — ${obsMatch[2].slice(0, 80)}`;
  }

  // Deep unescape and truncate
  cleaned = deepUnescape(cleaned);
  if (cleaned.length > 120) return cleaned.slice(0, 117) + "...";
  return cleaned;
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
        const time = () => new Date(normalizeTimestamp(t().timestamp)).toLocaleString();
        const content = () => formatContent(t().content);

        return (
          <div class="thought-modal-overlay" onClick={() => setModalThought(null)}>
            <div class="thought-modal" onClick={(e) => e.stopPropagation()}>
              {/* Header */}
              <div class="thought-modal-header">
                <span class="thought-modal-badge" style={{ color: color(), "border-color": color() }}>
                  {label()}
                </span>
                <Show when={content().toolName}>
                  <span class="thought-modal-tool-badge">{content().toolName}</span>
                </Show>
                <span class="thought-modal-time">{time()}</span>
                <span class="thought-modal-agent">{t().agentId?.substring(0, 8)}...</span>
                <button class="thought-modal-close" onClick={() => setModalThought(null)}>
                  &times;
                </button>
              </div>

              {/* Tool header with file path */}
              <Show when={content().filePath}>
                <div class="thought-modal-tool-header">
                  <span class="thought-modal-tool-filepath">{content().filePath}</span>
                </div>
              </Show>

              {/* Scrollable body: content + metadata + raw JSON */}
              <div class="thought-modal-body">
                <Show when={content().codeContent} fallback={
                  <pre class={`thought-modal-content thought-modal-lang-${content().lang}`}>
                    {content().formatted}
                  </pre>
                }>
                  <pre class="thought-modal-content thought-modal-code">
                    {content().codeContent}
                  </pre>
                </Show>

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
                        <pre class="thought-modal-result">{typeof t().result === "string" ? t().result as string : JSON.stringify(t().result, null, 2)}</pre>
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
          </div>
        );
      }}
    </Show>
  );
};

export default ThoughtModal;
