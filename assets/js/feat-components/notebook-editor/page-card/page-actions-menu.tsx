import React from "react";
import { useNotebookEditor } from "../../../contexts/notebook-editor-context";

interface PageActionsMenuProps {
  pageId: number;
  canMoveUp: boolean;
  canMoveDown: boolean;
}

export function PageActionsMenu({
  pageId,
  canMoveUp,
  canMoveDown,
}: PageActionsMenuProps) {
  const { client } = useNotebookEditor();

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
        className="focus-menu-panel absolute right-0 top-full z-20 mt-2 w-40 origin-top-right rounded-lg border border-base-300 bg-base-100 p-1.5 shadow-lg transition duration-150 ease-out"
      >
        <button
          type="button"
          onClick={() => void client.movePage(pageId, "up")}
          disabled={!canMoveUp}
          className="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-35"
        >
          ↑ Move up
        </button>

        <button
          type="button"
          onClick={() => void client.movePage(pageId, "down")}
          disabled={!canMoveDown}
          className="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-35"
        >
          ↓ Move down
        </button>

        <button
          type="button"
          onClick={() => {
            if (window.confirm("Delete this page and all its items?")) {
              void client.deletePage(pageId);
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
