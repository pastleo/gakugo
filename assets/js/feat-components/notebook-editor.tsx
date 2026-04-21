import React from "react";
import {
  NotebookEditorProvider,
  useNotebookEditor,
  type ApplyIntent,
  type ApplyIntentReply,
  type NotebookEditorProps,
  type NotebookInitialPages,
  type NotebookPage,
  type ReactUpdateListener,
} from "../contexts/notebook-editor-context";
import { NotebookEditorDragProvider } from "../contexts/notebook-editor-drag-context";
import { NotebookEditorFocusProvider } from "../contexts/notebook-editor-focus-context";
import { ToastProvider } from "../contexts/toast-context";
import { PageCard } from "./notebook-editor/page-card";

function NotebookEditorSurface() {
  const { client, pages, unitId } = useNotebookEditor();

  return (
    <section
      id="notebook-editor-shell"
      className="space-y-4 text-sm text-base-content"
      data-unit-id={unitId ?? ""}
      data-page-count={String(pages.length)}
    >
      <div className="space-y-4">
        {pages.map((page, index) => (
          <PageCard
            key={page.id}
            page={page}
            pageIndex={index}
            pageCount={pages.length}
          />
        ))}

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
