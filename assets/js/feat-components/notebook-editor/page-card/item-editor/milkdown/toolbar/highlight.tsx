import React from "react";
import { editorViewCtx } from "@milkdown/kit/core";
import type { Ctx } from "@milkdown/kit/ctx";
import type { EditorView } from "@milkdown/kit/prose/view";
import { useInstance } from "@milkdown/react";
import { ColorRailPicker } from "../../../../../../components/color-rail-picker";
import type { MilkdownToolbarSelectionSnapshot } from "../toolbar";
import { isNotebookColorName } from "../../../../../../utils/notebook-colors";
import {
  normalizeNotebookHighlightAttrs,
  notebookHighlightSchema,
  type NotebookHighlightAttrs,
} from "../highlight";

function visibleNotebookColor(
  value:
    | NotebookHighlightAttrs["backgroundColor"]
    | NotebookHighlightAttrs["textColor"],
) {
  return isNotebookColorName(value) ? value : null;
}

export function getHighlightAttrs(
  ctx: Ctx,
  view: EditorView,
): NotebookHighlightAttrs {
  const highlightMark = notebookHighlightSchema.type(ctx);
  const { selection, doc } = view.state;

  if (
    selection.empty ||
    !doc.rangeHasMark(selection.from, selection.to, highlightMark)
  ) {
    return {};
  }

  let attrs: NotebookHighlightAttrs = {};

  doc.nodesBetween(selection.from, selection.to, (node) => {
    const mark = node.marks.find(
      (currentMark) => currentMark.type === highlightMark,
    );

    if (mark) {
      attrs = normalizeNotebookHighlightAttrs(
        mark.attrs as Record<string, unknown>,
      );
      return false;
    }

    return undefined;
  });

  return attrs;
}

function getHighlightAttrsFromSelection(
  selection: MilkdownToolbarSelectionSnapshot,
): NotebookHighlightAttrs {
  return normalizeNotebookHighlightAttrs(selection.markAttrsByType.highlight);
}

export function applyHighlightAttrsUpdate(
  ctx: Ctx,
  view: EditorView,
  nextPartialAttrs: Partial<NotebookHighlightAttrs>,
) {
  const markType = notebookHighlightSchema.type(ctx);
  const { selection, doc, tr } = view.state;

  if (selection.empty) {
    return;
  }

  const hasHighlight = doc.rangeHasMark(selection.from, selection.to, markType);
  const currentAttrs = hasHighlight ? getHighlightAttrs(ctx, view) : {};
  const nextAttrs: NotebookHighlightAttrs = { ...currentAttrs };

  if (Object.hasOwn(nextPartialAttrs, "textColor")) {
    const nextTextColor = nextPartialAttrs.textColor;
    nextAttrs.textColor =
      nextTextColor === null || nextTextColor === undefined
        ? null
        : normalizeNotebookHighlightAttrs({ textColor: nextTextColor })
            .textColor;
  }

  if (Object.hasOwn(nextPartialAttrs, "backgroundColor")) {
    const nextBackgroundColor = nextPartialAttrs.backgroundColor;
    nextAttrs.backgroundColor =
      nextBackgroundColor === null || nextBackgroundColor === undefined
        ? null
        : nextBackgroundColor === "none"
          ? "none"
          : normalizeNotebookHighlightAttrs({
              backgroundColor: nextBackgroundColor,
            }).backgroundColor;
  }

  if (nextAttrs.textColor && !nextAttrs.backgroundColor) {
    nextAttrs.backgroundColor = "none";
  }

  tr.removeMark(selection.from, selection.to, markType);

  const hasVisibleTextColor = visibleNotebookColor(nextAttrs.textColor);
  const hasVisibleBackgroundColor = visibleNotebookColor(
    nextAttrs.backgroundColor,
  );

  if (hasVisibleTextColor || hasVisibleBackgroundColor) {
    tr.addMark(selection.from, selection.to, markType.create(nextAttrs));
  }

  view.dispatch(tr);
  view.focus();
}

export function HighlightToolbarControls({
  selection,
}: {
  selection: MilkdownToolbarSelectionSnapshot;
}) {
  const [loading, get] = useInstance();
  const attrs = getHighlightAttrsFromSelection(selection);

  const updateAttrs = React.useCallback(
    (nextPartialAttrs: Partial<NotebookHighlightAttrs>) => {
      if (loading) return;

      get()?.action((ctx) => {
        const view = ctx.get(editorViewCtx);
        applyHighlightAttrsUpdate(ctx, view, nextPartialAttrs);
      });
    },
    [get, loading],
  );

  return (
    <div className="flex min-w-0 items-center gap-1.5 rounded-xl border border-base-300/70 bg-base-100/80 p-1">
      <ColorRailPicker
        label="Text"
        role="foreground"
        currentColor={attrs.textColor}
        onClear={() => updateAttrs({ textColor: null })}
        onSelect={(color) => updateAttrs({ textColor: color })}
        className="min-w-0 flex-1 border-transparent bg-transparent"
      />

      <ColorRailPicker
        label="Bg"
        role="background"
        currentColor={visibleNotebookColor(attrs.backgroundColor)}
        onClear={() => updateAttrs({ backgroundColor: "none" })}
        onSelect={(color) => updateAttrs({ backgroundColor: color })}
        className="min-w-0 flex-1 border-transparent bg-transparent"
      />
    </div>
  );
}
