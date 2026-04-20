import React from "react";
import { useNotebookEditor } from "../../../contexts/notebook-editor-context";
import type { NotebookPage } from "../../../contexts/notebook-editor-context";

interface AddItemMenuProps {
  page: NotebookPage;
}

export function AddItemMenu({ page }: AddItemMenuProps) {
  const { client } = useNotebookEditor();

  return (
    <div className="focus-menu relative">
      <button
        type="button"
        className="inline-flex list-none items-center gap-1 rounded-md border border-base-300 px-2 py-1 text-xs font-medium text-base-content/80 transition hover:bg-base-200"
      >
        <span className="text-sm">+</span>
        <span className="hidden sm:inline">Add item</span>
      </button>

      <div
        tabIndex={0}
        className="focus-menu-panel absolute right-0 top-full z-20 mt-2 w-40 origin-top-right rounded-lg border border-base-300 bg-base-100 p-1.5 shadow-lg transition duration-150 ease-out"
      >
        <button
          type="button"
          onClick={() => void client.addRootItem(page, "first")}
          className="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200"
        >
          ↑ Add to first
        </button>

        <button
          type="button"
          onClick={() => void client.addRootItem(page, "last")}
          className="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200"
        >
          ↓ Add to last
        </button>
      </div>
    </div>
  );
}
