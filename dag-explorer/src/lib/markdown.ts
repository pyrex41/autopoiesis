/**
 * Lightweight markdown renderer — no external dependencies.
 * Supports: **bold**, *italic*, `inline code`, ```code blocks```, [links](url), bullet lists.
 */

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function renderMarkdown(text: string): string {
  // Escape HTML entities first
  let html = escapeHtml(text);

  // Fenced code blocks: ```...```
  html = html.replace(/```([\s\S]*?)```/g, (_match, code) => {
    return `<pre><code>${code.trim()}</code></pre>`;
  });

  // Inline code: `...`
  html = html.replace(/`([^`]+)`/g, "<code>$1</code>");

  // Bold: **...**
  html = html.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");

  // Italic: *...*
  html = html.replace(/\*(.+?)\*/g, "<em>$1</em>");

  // Links: [text](url)
  html = html.replace(
    /\[([^\]]+)\]\(([^)]+)\)/g,
    '<a href="$2" target="_blank" rel="noopener">$1</a>'
  );

  // Bullet lists: lines starting with - or *
  html = html.replace(/(^|\n)([-*] .+(?:\n[-*] .+)*)/g, (_match, prefix, list) => {
    const items = (list as string)
      .split("\n")
      .map((line: string) => `<li>${line.replace(/^[-*] /, "")}</li>`)
      .join("");
    return `${prefix}<ul>${items}</ul>`;
  });

  // Line breaks
  html = html.replace(/\n/g, "<br>");

  return html;
}
