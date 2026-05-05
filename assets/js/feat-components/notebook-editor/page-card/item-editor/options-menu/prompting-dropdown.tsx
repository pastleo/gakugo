import React from "react";
import type {
  NotebookItem,
  NotebookPage,
  PromptingMode,
} from "../../../../../contexts/notebook-editor-context";
import { useNotebookEditor } from "../../../../../contexts/notebook-editor-context";
import { defaultItemPrompting } from "../prompting-panel";

interface PromptingDropdownProps {
  page: NotebookPage;
  item: NotebookItem;
}

const ACTION_OPTIONS: Array<{ value: PromptingMode; label: string }> = [
  { value: "parse_as_items", label: "Parse as items" },
  { value: "parse_as_flashcards", label: "Parse as flashcards" },
];

export function PromptingDropdown({ page, item }: PromptingDropdownProps) {
  const { client } = useNotebookEditor();
  const promptingOpen = Boolean(item.prompting);
  const dropdownRef = React.useRef<HTMLDivElement | null>(null);

  const closeFocusMenu = () => {
    requestAnimationFrame(() => {
      if (document.activeElement instanceof HTMLElement) {
        document.activeElement.blur();
      }

      dropdownRef.current?.blur();
    });
  };

  const setPromptingMode = (mode: PromptingMode) => {
    void client.setPrompting(page, item.id, defaultItemPrompting(mode));
    closeFocusMenu();
  };

  return (
    <div ref={dropdownRef} className="dropdown dropdown-top w-full">
      <button
        type="button"
        tabIndex={0}
        className={[
          "btn min-h-0 w-full rounded-xl border-0 px-3 py-2.5 text-xs font-bold shadow-sm transition",
          promptingOpen
            ? "bg-primary text-primary-content hover:bg-primary/90"
            : "bg-gradient-to-r from-primary to-secondary text-primary-content hover:brightness-105",
        ].join(" ")}
      >
        Prompt / Parse / Import
      </button>

      <ul
        tabIndex={0}
        className="menu dropdown-content z-30 mb-2 w-full rounded-xl border border-primary/20 bg-base-100/98 p-2 text-xs shadow-2xl ring-1 ring-base-content/5 backdrop-blur-sm"
      >
        {ACTION_OPTIONS.map((option) => (
          <li key={option.value}>
            <button
              type="button"
              onClick={() => setPromptingMode(option.value)}
            >
              {option.label}
            </button>
          </li>
        ))}

        {promptingOpen ? (
          <li>
            <button
              type="button"
              className="text-error"
              onClick={() => {
                void client.setPrompting(page, item.id, null);
                closeFocusMenu();
              }}
            >
              Close prompting
            </button>
          </li>
        ) : null}
      </ul>
    </div>
  );
}
