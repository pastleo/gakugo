import type { NotebookPage } from "../contexts/notebook-editor-context";

export function notebookPageToMarkdownList(page: NotebookPage) {
  return page.items
    .map((item) => itemToMarkdownListItem(item.depth, item.text))
    .join("\n");
}

function itemToMarkdownListItem(depth: number, text: string) {
  const indent = "  ".repeat(Math.max(0, depth));
  const lines = text.split(/\r?\n/);
  const [firstLine, ...restLines] = lines;
  const continuationIndent = `${indent}  `;

  return [
    `${indent}- ${firstLine ?? ""}`,
    ...restLines.map((line) => `${continuationIndent}${line}`),
  ].join("\n");
}
