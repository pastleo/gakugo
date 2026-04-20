import React, { memo } from "react";
import type {
  NotebookItem,
  NotebookPage,
} from "../../../../contexts/notebook-editor-context";
import { useNotebookEditor } from "../../../../contexts/notebook-editor-context";

interface DebugSetTextButtonProps {
  page: NotebookPage;
  item: NotebookItem;
}

export const DebugSetTextButton = memo(function DebugSetTextButton({
  page,
  item,
}: DebugSetTextButtonProps) {
  const { client } = useNotebookEditor();

  return (
    <button
      type="button"
      className="mt-1 shrink-0 rounded-full border border-warning/40 bg-warning/10 px-2 py-1 text-[10px] font-semibold uppercase tracking-[0.2em] text-warning transition hover:border-warning/70 hover:bg-warning/20"
      title="Debug: send set_text intent"
      onClick={() => {
        const nextText = window.prompt("Debug set_text markdown", item.text);

        if (nextText == null) {
          return;
        }

        void client.setText(page, item.id, nextText);
      }}
    >
      Debug Set Text
    </button>
  );
});
