import { type Component, Show, createSignal } from "solid-js";

interface CodeBlockData {
  content: string;
  path?: string;
  language?: string;
  start_line?: number;
}

const CodeBlock: Component<{ data: CodeBlockData }> = (props) => {
  const [copied, setCopied] = createSignal(false);
  const lines = () => props.data.content.split("\n");
  const startLine = () => props.data.start_line ?? 1;

  const copyToClipboard = () => {
    navigator.clipboard.writeText(props.data.content).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  return (
    <div class="block-code">
      <Show when={props.data.path}>
        <div class="block-code-header">
          <span class="block-code-path">{props.data.path}</span>
          <Show when={props.data.language}>
            <span class="block-code-lang">{props.data.language}</span>
          </Show>
          <button class="block-code-copy" onClick={copyToClipboard}>
            {copied() ? "Copied" : "Copy"}
          </button>
        </div>
      </Show>
      <pre class="block-code-content">
        <code>{props.data.content}</code>
      </pre>
    </div>
  );
};

export default CodeBlock;
