import React, { memo } from "react";
import {
  useNotebookEditor,
  type NotebookPage,
} from "../../contexts/notebook-editor-context";
import {
  targetMatchesPage,
  useNotebookEditorDrag,
} from "../../contexts/notebook-editor-drag-context";
import { useSyncedValue } from "../../utils/use-synced-value";
import { AddItemMenu } from "./page-card/add-item-menu";
import { ItemEditor } from "./page-card/item-editor";
import { PageActionsMenu } from "./page-card/page-actions-menu";

interface PageCardProps {
  page: NotebookPage;
  pageIndex: number;
  pageCount: number;
}

export const PageCard = memo(function PageCard({
  page,
  pageIndex,
  pageCount,
}: PageCardProps) {
  const { client } = useNotebookEditor();
  const {
    dragState,
    handlePageRootEndDragLeave,
    handlePageRootEndDragOver,
    handlePageRootEndDrop,
  } = useNotebookEditorDrag();
  const [titleDraft, setTitleDraft] = useSyncedValue(page.title);
  const canMoveUp = pageIndex > 0;
  const canMoveDown = pageIndex < pageCount - 1;
  const isPageDropTarget = targetMatchesPage(
    dragState?.target ?? null,
    page.id,
    "root_end",
  );
  return (
    <article
      id={`react-page-card-${page.id}`}
      data-page-version={page.version}
      data-page-id={page.id}
      data-drop-zone="root_end"
      onDragOver={handlePageRootEndDragOver}
      onDrop={handlePageRootEndDrop}
      onDragLeave={handlePageRootEndDragLeave}
      className={[
        "relative rounded-3xl border bg-base-100 p-5 shadow-sm transition",
        isPageDropTarget
          ? "border-primary bg-primary/5 shadow-[0_0_0_1px_rgba(var(--p),0.2)]"
          : "border-base-300",
      ].join(" ")}
    >
      {isPageDropTarget ? (
        <div className="pointer-events-none absolute inset-x-5 bottom-0 h-1 rounded-full bg-primary/70" />
      ) : null}

      <div className="mb-3 flex items-start justify-between gap-3">
        <div className="min-w-0 grow">
          <input
            value={titleDraft}
            onChange={(event) => {
              const title = event.target.value;
              setTitleDraft(title);
              void client.setPageTitle(page, title);
            }}
            placeholder="Untitled page"
            className="w-full border-0 border-b border-base-content/30 bg-transparent px-1 py-1 text-lg font-semibold text-base-content outline-hidden transition focus:border-primary"
          />
        </div>

        <div className="flex items-center gap-1">
          <AddItemMenu page={page} />
          <PageActionsMenu
            page={page}
            canMoveUp={canMoveUp}
            canMoveDown={canMoveDown}
          />
        </div>
      </div>

      <div className="space-y-2 text-sm text-base-content">
        {page.items.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-base-300/80 px-4 py-5 text-center text-xs text-base-content/45 transition">
            Drag an item into this page.
          </div>
        ) : null}

        <ul className="space-y-2">
          {page.items.map((item, index) => (
            <ItemEditor
              key={item.id}
              page={page}
              item={item}
              itemIndex={index}
            />
          ))}
        </ul>
      </div>
    </article>
  );
});
