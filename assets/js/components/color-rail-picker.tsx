import React from "react";
import {
  NOTEBOOK_COLOR_PALETTE,
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
  clearLabel?: string;
  previewTextColor?: NotebookColorName | null | undefined;
  previewBackgroundColor?: NotebookColorName | null | undefined;
}

function notebookColorCssVar(name: NotebookColorName, role: NotebookColorRole) {
  return `var(--gakugo-notebook-color-${name}-${role})`;
}

function isElementVisible(element: HTMLElement) {
  if (!element.isConnected) return false;
  if (element.getClientRects().length === 0) return false;

  const { visibility } = window.getComputedStyle(element);
  return visibility !== "hidden" && visibility !== "collapse";
}

function ColorPreviewTile({
  role,
  color,
  previewTextColor,
  previewBackgroundColor,
}: {
  role: NotebookColorRole;
  color?: NotebookColorName | null;
  previewTextColor?: NotebookColorName | null;
  previewBackgroundColor?: NotebookColorName | null;
}) {
  const textColor = role === "foreground" ? color : previewTextColor;
  const backgroundColor =
    role === "background" ? color : previewBackgroundColor;
  const style: React.CSSProperties = {
    color: textColor ? notebookColorCssVar(textColor, "foreground") : undefined,
    backgroundColor: backgroundColor
      ? notebookColorCssVar(backgroundColor, "background")
      : undefined,
  };

  return (
    <span
      className="inline-flex size-6 items-center justify-center rounded-lg border border-base-content/10 bg-base-100 text-[13px] font-black leading-none text-base-content shadow-sm"
      style={style}
    >
      A
    </span>
  );
}

export function ColorRailPicker({
  label,
  role,
  currentColor,
  onClear,
  onSelect,
  className,
  clearLabel = "default",
  previewTextColor,
  previewBackgroundColor,
}: ColorRailPickerProps) {
  const railRef = React.useRef<HTMLDivElement>(null);

  React.useEffect(() => {
    const rail = railRef.current;
    const selectedButton = rail?.querySelector<HTMLElement>(
      '[data-selected="true"]',
    );

    if (!rail || !selectedButton) return;
    if (!isElementVisible(rail) || !isElementVisible(selectedButton)) return;

    const railRect = rail.getBoundingClientRect();
    const selectedRect = selectedButton.getBoundingClientRect();
    const selectedCenter =
      selectedRect.left - railRect.left + selectedRect.width / 2;

    rail.scrollTo({
      behavior: "smooth",
      left: rail.scrollLeft + selectedCenter - rail.clientWidth / 2,
    });
  }, [currentColor]);

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
      <div className="relative min-w-0 flex-1">
        <div
          ref={railRef}
          className="flex min-w-0 items-center gap-1 overflow-x-auto overflow-y-hidden px-1 py-1.5 pr-4 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        >
          <button
            type="button"
            aria-pressed={!currentColor}
            aria-label={`${label}: ${clearLabel}`}
            title={`${label}: ${clearLabel}`}
            data-selected={!currentColor ? "true" : undefined}
            onClick={onClear}
            className={[
              "relative inline-flex size-7 shrink-0 items-center justify-center rounded-xl border bg-base-100 transition",
              !currentColor
                ? "border-primary ring-2 ring-primary/45 ring-offset-1 ring-offset-base-100"
                : "border-base-300 hover:border-base-content/25 hover:bg-base-200/80",
            ].join(" ")}
          >
            <ColorPreviewTile
              role={role}
              previewTextColor={previewTextColor}
              previewBackgroundColor={previewBackgroundColor}
            />
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
                title={`${label}: ${color.label}`}
                data-selected={selected ? "true" : undefined}
                onClick={() => onSelect(colorName)}
                className={[
                  "inline-flex size-7 shrink-0 items-center justify-center rounded-xl border transition",
                  selected
                    ? "border-primary bg-base-100 ring-2 ring-primary/45 ring-offset-1 ring-offset-base-100"
                    : "border-base-300 hover:border-base-content/25 hover:bg-base-200/80",
                ].join(" ")}
              >
                <ColorPreviewTile
                  color={colorName}
                  role={role}
                  previewTextColor={previewTextColor}
                  previewBackgroundColor={previewBackgroundColor}
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
