import React, { useEffect } from "react";
import {
  NotebookEditorProvider,
  useNotebookEditorActions,
  useNotebookEditorPageSummaries,
  useNotebookEditorUnitId,
  type ApplyIntent,
  type ApplyIntentReply,
  type NotebookEditorProps,
  type NotebookInitialPages,
  type NotebookPage,
  type ReactUpdateListener,
} from "../contexts/notebook-editor-context";
import { NotebookEditorDragProvider } from "../contexts/notebook-editor-drag-context";
import {
  NotebookEditorFocusProvider,
  useNotebookEditorFocus,
} from "../contexts/notebook-editor-focus-context";
import { ToastProvider } from "../contexts/toast-context";
import { PageCard } from "./notebook-editor/page-card";

function InitialFocusTarget({
  target,
}: {
  target: NotebookEditorProps["initialFocusTarget"];
}) {
  const { requestItemFocus } = useNotebookEditorFocus();

  useEffect(() => {
    if (!target) {
      return;
    }

    requestItemFocus({
      pageId: target.pageId,
      itemId: target.itemId,
      selection: "start",
    });

    window.requestAnimationFrame(() => {
      document
        .getElementById(`react-notebook-item-${target.pageId}-${target.itemId}`)
        ?.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  }, [requestItemFocus, target]);

  return null;
}

function NotebookEditorSurface() {
  const client = useNotebookEditorActions();
  const pageSummaries = useNotebookEditorPageSummaries();
  const unitId = useNotebookEditorUnitId();

  return (
    <section
      id="notebook-editor-shell"
      className="space-y-4 text-sm text-base-content"
      data-unit-id={unitId ?? ""}
      data-page-count={String(pageSummaries.length)}
    >
      <div className="space-y-4">
        {pageSummaries.map((pageSummary, index) => {
          const [pageId, editedAt] = pageSummary.split(":").map(Number);

          return (
            <PageCard
              key={pageId}
              pageId={pageId}
              editedAt={editedAt}
              pageIndex={index}
              pageCount={pageSummaries.length}
            />
          );
        })}

        <button
          type="button"
          onClick={() => void client.addPage()}
          className="rounded-xl border border-dashed border-base-300 px-4 py-2 text-sm font-medium text-base-content/80 transition hover:bg-base-200"
        >
          + New Page
        </button>
      </div>
    </section>
  );
}

export function NotebookEditor({
  initialPages,
  initialFocusTarget,
  addReactUpdateListener,
  applyIntent,
}: NotebookEditorProps) {
  return (
    <ToastProvider>
      <NotebookEditorProvider
        initialPages={initialPages}
        addReactUpdateListener={addReactUpdateListener}
        applyIntent={applyIntent}
      >
        <NotebookEditorFocusProvider>
          <InitialFocusTarget target={initialFocusTarget} />
          <NotebookEditorDragProvider>
            <NotebookEditorSurface />
          </NotebookEditorDragProvider>
        </NotebookEditorFocusProvider>
      </NotebookEditorProvider>
    </ToastProvider>
  );
}

export type {
  ApplyIntent,
  ApplyIntentReply,
  NotebookEditorProps,
  NotebookInitialPages,
  NotebookPage,
  ReactUpdateListener,
};
