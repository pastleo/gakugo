import React from "react";
import type { NotebookColorName } from "../../../../../contexts/notebook-editor-context";
import {
  NOTEBOOK_COLOR_PALETTE,
  notebookColorSwatchClass,
  type NotebookColorRole,
} from "../../../../../utils/notebook-colors";

interface ColorGridProps {
  title: string;
  role: NotebookColorRole;
  currentColor: NotebookColorName | null | undefined;
  onClear: () => void;
  onSelect: (color: NotebookColorName) => void;
}

export function ColorGrid({
  title,
  role,
  currentColor,
  onClear,
  onSelect,
}: ColorGridProps) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between gap-2">
        <span className="text-[11px] font-semibold uppercase tracking-[0.18em] text-base-content/55">
          {title}
        </span>
        <button
          type="button"
          onClick={onClear}
          className="rounded-full border border-base-300 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[0.18em] text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
        >
          Default
        </button>
      </div>

      <div className="grid grid-cols-12 gap-1">
        {NOTEBOOK_COLOR_PALETTE.map((color) => {
          const selected = currentColor === color.name;

          return (
            <button
              key={color.name}
              type="button"
              aria-pressed={selected}
              aria-label={`${title}: ${color.label}`}
              title={color.label}
              onClick={() => onSelect(color.name as NotebookColorName)}
              className={[
                "inline-flex size-6 items-center justify-center rounded-full border transition",
                selected
                  ? "border-primary bg-base-100 ring-2 ring-primary/45 ring-offset-2 ring-offset-base-100"
                  : "border-base-300 hover:border-base-content/25 hover:bg-base-200/80",
              ].join(" ")}
            >
              <span
                className={[
                  "size-3.5 rounded-full border border-base-content/10 shadow-sm",
                  notebookColorSwatchClass(
                    color.name as NotebookColorName,
                    role,
                  ),
                ].join(" ")}
              />
            </button>
          );
        })}
      </div>
    </div>
  );
}
