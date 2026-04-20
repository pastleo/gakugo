import { useLayoutEffect, type MutableRefObject } from "react";
import { editorViewCtx, type Editor } from "@milkdown/kit/core";
import { Selection, TextSelection } from "prosemirror-state";
import {
  useNotebookEditorFocus,
  type NotebookEditorItemSelectionTarget,
} from "../../../../../contexts/notebook-editor-focus-context";

interface UseFocusControlArgs {
  loading: boolean;
  get: () => Editor | undefined;
  pageId: number;
  itemId: string;
  pendingArrowUpToFrontRef: MutableRefObject<boolean>;
}

function resolveSelection(
  selection: Exclude<NotebookEditorItemSelectionTarget, "end"> | undefined,
  docSize: number,
) {
  if (selection === "start" || !selection) {
    return { from: 1, to: 1 };
  }

  return {
    from: Math.max(1, Math.min(selection.from, docSize)),
    to: Math.max(1, Math.min(selection.to, docSize)),
  };
}

export function useFocusControl({
  loading,
  get,
  pageId,
  itemId,
  pendingArrowUpToFrontRef,
}: UseFocusControlArgs) {
  const { pendingFocusTarget, clearPendingFocusTarget } =
    useNotebookEditorFocus();

  useLayoutEffect(() => {
    if (loading || !pendingFocusTarget) {
      return;
    }

    if (
      pendingFocusTarget.pageId !== pageId ||
      pendingFocusTarget.itemId !== itemId
    ) {
      return;
    }

    const editor = get();

    if (!editor) {
      return;
    }
    const frame = window.requestAnimationFrame(() => {
      editor.action((ctx) => {
        const view = ctx.get(editorViewCtx);
        const selection =
          pendingFocusTarget.selection === "end"
            ? Selection.atEnd(view.state.doc)
            : (() => {
                const { from, to } = resolveSelection(
                  pendingFocusTarget.selection,
                  view.state.doc.content.size,
                );

                return TextSelection.create(
                  view.state.doc,
                  from,
                  Math.max(from, to),
                );
              })();
        const transaction = view.state.tr.setSelection(selection);

        view.dispatch(transaction);
        pendingArrowUpToFrontRef.current =
          pendingFocusTarget.selection === "end";
        view.dom.focus();
        view.focus();
      });

      clearPendingFocusTarget();
    });

    return () => window.cancelAnimationFrame(frame);
  }, [
    clearPendingFocusTarget,
    get,
    itemId,
    loading,
    pageId,
    pendingArrowUpToFrontRef,
    pendingFocusTarget,
  ]);
}
