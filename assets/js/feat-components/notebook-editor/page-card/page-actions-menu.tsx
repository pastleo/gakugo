import React from "react";
import type { NotebookPage } from "../../../contexts/notebook-editor-context";
import { useNotebookEditor } from "../../../contexts/notebook-editor-context";
import { useToast } from "../../../contexts/toast-context";
import { copyTextToClipboard } from "../../../utils/clipboard";
import { notebookPageToMarkdownList } from "../../../utils/notebook-page-markdown";

interface PageActionsMenuProps {
  page: NotebookPage;
  canMoveUp: boolean;
  canMoveDown: boolean;
}

export function PageActionsMenu({
  page,
  canMoveUp,
  canMoveDown,
}: PageActionsMenuProps) {
  const { client } = useNotebookEditor();
  const { pushToast } = useToast();

  const handleCopyPageAsMarkdown = async () => {
    const markdown = notebookPageToMarkdownList(page);

    try {
      await copyTextToClipboard(markdown);
      pushToast({
        tone: "success",
        title: "Copied page as markdown",
      });
    } catch {
      pushToast({
        tone: "error",
        title: "Copy failed",
        description: "Your browser blocked clipboard access.",
      });
    }
  };

  return (
    <div className="focus-menu relative">
      <button
        type="button"
        className="inline-flex list-none items-center rounded-md border border-base-300 p-1 text-base-content/80 transition hover:bg-base-200"
      >
        <span className="text-sm">...</span>
      </button>

      <div
        tabIndex={0}
        className="focus-menu-panel absolute right-0 top-full z-20 mt-2 w-52 origin-top-right rounded-lg border border-base-300 bg-base-100 p-1.5 shadow-lg transition duration-150 ease-out"
      >
        <button
          type="button"
          onClick={() => void client.movePage(page.id, "up")}
          disabled={!canMoveUp}
          className="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-35"
        >
          ↑ Move up
        </button>

        <button
          type="button"
          onClick={() => void client.movePage(page.id, "down")}
          disabled={!canMoveDown}
          className="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-35"
        >
          ↓ Move down
        </button>

        <button
          type="button"
          onClick={() => void handleCopyPageAsMarkdown()}
          className="inline-flex w-full items-center gap-1.5 whitespace-nowrap rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200"
        >
          ⧉ Copy page as markdown
        </button>

        <button
          type="button"
          onClick={() => {
            if (window.confirm("Delete this page and all its items?")) {
              void client.deletePage(page.id);
            }
          }}
          className="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-error transition hover:bg-error/12"
        >
          ✕ Delete
        </button>
      </div>
    </div>
  );
}
