import React from "react";
import { useNotebookEditor } from "../../../../contexts/notebook-editor-context";
import type {
  NotebookItem,
  NotebookPage,
} from "../../../../contexts/notebook-editor-context";
import { ColorGrid } from "./options-menu/color-grid";
import { ParseGenerateDrawer } from "./options-menu/parse-generate-drawer";

function renderItemBadge(item: NotebookItem) {
  const baseClass =
    "inline-flex size-6 shrink-0 items-center justify-center border text-[11px] font-bold transition";

  if (item.flashcard && item.answer) {
    return (
      <span
        className={`${baseClass} rounded-md border-accent/45 bg-accent/15 text-accent`}
      >
        F
      </span>
    );
  }

  if (item.flashcard) {
    return (
      <span
        className={`${baseClass} rounded-md border-primary/45 bg-primary/15 text-primary`}
      >
        Q
      </span>
    );
  }

  if (item.answer) {
    return (
      <span
        className={`${baseClass} rounded-md border-secondary/45 bg-secondary/15 text-secondary`}
      >
        A
      </span>
    );
  }

  return (
    <span
      className={`${baseClass} rounded-full border-base-300 text-base-content/60 hover:bg-base-200`}
    >
      <span className="size-2 rounded-full border border-base-content/45" />
    </span>
  );
}

interface OptionsMenuProps {
  page: NotebookPage;
  item: NotebookItem;
  buttonProps?: React.ButtonHTMLAttributes<HTMLButtonElement>;
}

export function ItemEditorOptionsMenu({
  page,
  item,
  buttonProps,
}: OptionsMenuProps) {
  const { client } = useNotebookEditor();
  const [parseGenerateOpen, setParseGenerateOpen] = React.useState(false);

  return (
    <div className="focus-menu relative">
      <button
        type="button"
        {...buttonProps}
        className={[
          "inline-flex size-6 items-center justify-center rounded-md transition",
          buttonProps?.draggable
            ? "cursor-grab hover:bg-base-200/60 active:cursor-grabbing"
            : "hover:bg-base-200/60",
          buttonProps?.className ?? "",
        ].join(" ")}
        title={buttonProps?.title ?? "Item options"}
      >
        {renderItemBadge(item)}
      </button>

      <div
        tabIndex={0}
        className="focus-menu-panel absolute left-8 top-0 z-20 ml-2 w-[25rem] origin-top-left rounded-xl border border-base-300 bg-base-100 p-3 shadow-xl transition duration-150 ease-out"
      >
        <div className="mb-3 grid grid-cols-2 gap-2">
          <button
            type="button"
            onClick={() => void client.indentSubtree(page, item.id, item.text)}
            className="inline-flex items-center justify-center gap-1 rounded-md border border-base-300 bg-base-200/35 px-2 py-1 text-xs font-semibold text-base-content transition hover:bg-base-200"
            title="Indent subtree"
          >
            ⇥ Indent
          </button>

          <button
            type="button"
            onClick={() => void client.outdentSubtree(page, item.id, item.text)}
            className="inline-flex items-center justify-center gap-1 rounded-md border border-base-300 bg-base-200/35 px-2 py-1 text-xs font-semibold text-base-content transition hover:bg-base-200"
            title="Unindent subtree"
          >
            ⇤ Unindent
          </button>
        </div>

        <button
          type="button"
          onClick={() => setParseGenerateOpen(true)}
          className="mb-3 inline-flex w-full items-center justify-center gap-1 rounded-md border border-base-300 bg-base-200/35 px-2 py-1 text-xs font-semibold text-base-content transition hover:bg-base-200"
          title="Open parse and generate actions"
        >
          Parse / Generate
        </button>

        <label className="mb-2 flex cursor-pointer items-center gap-2 text-xs font-medium text-base-content">
          <input
            type="checkbox"
            checked={item.flashcard}
            onChange={() => void client.toggleFlag(page, item.id, "flashcard")}
            className="checkbox checkbox-xs"
          />
          Flashcard
        </label>

        <label className="mb-3 flex cursor-pointer items-center gap-2 text-xs font-medium text-base-content">
          <input
            type="checkbox"
            checked={item.answer}
            onChange={() => void client.toggleFlag(page, item.id, "answer")}
            className="checkbox checkbox-xs"
          />
          Answer
        </label>

        <div className="mb-3 space-y-3 rounded-xl border border-base-300 bg-base-100/75 p-2">
          <ColorGrid
            title="Text color"
            currentColor={item.textColor}
            role="foreground"
            onClear={() => void client.setItemTextColor(page, item.id, null)}
            onSelect={(color) =>
              void client.setItemTextColor(page, item.id, color)
            }
          />

          <div className="h-px bg-base-300/70" />

          <ColorGrid
            title="Background"
            currentColor={item.backgroundColor}
            role="background"
            onClear={() =>
              void client.setItemBackgroundColor(page, item.id, null)
            }
            onSelect={(color) =>
              void client.setItemBackgroundColor(page, item.id, color)
            }
          />
        </div>

        <button
          type="button"
          onClick={() => void client.removeItem(page, item.id)}
          className="inline-flex w-full items-center justify-center gap-1 rounded-md border border-error/35 bg-error/10 px-2 py-1 text-xs font-semibold text-error transition hover:bg-error/15"
        >
          ✕ Delete
        </button>
      </div>

      <ParseGenerateDrawer
        open={parseGenerateOpen}
        page={page}
        item={item}
        onClose={() => setParseGenerateOpen(false)}
      />
    </div>
  );
}
