import React from "react";
import {
  NOTEBOOK_COLOR_PALETTE,
  notebookColorSwatchClass,
  type NotebookColorName,
  type NotebookColorRole,
} from "../utils/notebook-colors";

interface ColorRailPickerProps {
  label: string;
  role: NotebookColorRole;
  currentColor: NotebookColorName | null | undefined;
  onClear: () => void;
  onSelect: (color: NotebookColorName) => void;
  className?: string;
}

export function ColorRailPicker({
  label,
  role,
  currentColor,
  onClear,
  onSelect,
  className,
}: ColorRailPickerProps) {
  const railRef = React.useRef<HTMLDivElement>(null);

  React.useEffect(() => {
    const rail = railRef.current;
    if (!rail) return;

    const handleWheel = (event: WheelEvent) => {
      if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return;

      event.preventDefault();
      event.stopPropagation();
      rail.scrollLeft += event.deltaY;
    };

    rail.addEventListener("wheel", handleWheel, { passive: false });

    return () => {
      rail.removeEventListener("wheel", handleWheel);
    };
  }, []);

  return (
    <div
      className={[
        "flex min-w-0 flex-1 items-center gap-1.5 rounded-lg border border-base-300 bg-base-100/75 px-1.5 py-1",
        className ?? "",
      ].join(" ")}
    >
      <span className="shrink-0 text-[10px] font-semibold uppercase tracking-[0.14em] text-base-content/55">
        {label}
      </span>

      <div className="relative min-w-0 flex-1">
        <div
          ref={railRef}
          className="flex min-w-0 items-center gap-1 overflow-x-auto overflow-y-hidden px-1 py-1.5 pr-4 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        >
          <button
            type="button"
            aria-pressed={!currentColor}
            aria-label={`${label}: default`}
            title="Default"
            onClick={onClear}
            className={[
              "relative inline-flex size-6 shrink-0 items-center justify-center rounded-full border bg-base-100 transition",
              !currentColor
                ? "border-primary ring-2 ring-primary/45 ring-offset-1 ring-offset-base-100"
                : "border-base-300 hover:border-base-content/25 hover:bg-base-200/80",
            ].join(" ")}
          >
            <span className="size-3.5 rounded-full border border-base-content/15 shadow-sm" />
            <span className="absolute h-4 w-0.5 rotate-45 rounded-full bg-error" />
          </button>

          {NOTEBOOK_COLOR_PALETTE.map((color) => {
            const colorName = color.name as NotebookColorName;
            const selected = currentColor === colorName;

            return (
              <button
                key={color.name}
                type="button"
                aria-pressed={selected}
                aria-label={`${label}: ${color.label}`}
                title={color.label}
                onClick={() => onSelect(colorName)}
                className={[
                  "inline-flex size-6 shrink-0 items-center justify-center rounded-full border transition",
                  selected
                    ? "border-primary bg-base-100 ring-2 ring-primary/45 ring-offset-1 ring-offset-base-100"
                    : "border-base-300 hover:border-base-content/25 hover:bg-base-200/80",
                ].join(" ")}
              >
                <span
                  className={[
                    "size-3.5 rounded-full border border-base-content/10 shadow-sm",
                    notebookColorSwatchClass(colorName, role),
                  ].join(" ")}
                />
              </button>
            );
          })}
        </div>

        <div className="pointer-events-none absolute inset-y-1 right-0 w-5 bg-gradient-to-l from-base-100 to-transparent" />
      </div>
    </div>
  );
}
