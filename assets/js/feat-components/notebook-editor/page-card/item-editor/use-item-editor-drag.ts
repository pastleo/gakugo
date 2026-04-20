import { useCallback, useMemo } from "react";
import { useNotebookEditor } from "../../../../contexts/notebook-editor-context";
import {
  decodeDragPayload,
  encodeDragPayload,
  getRowDropPlacement,
  makeMoveItemArgs,
  NOTEBOOK_ITEM_DRAG_MIME,
  setDragEffect,
  targetMatchesRow,
  useNotebookEditorDrag,
  type NotebookDragTarget,
} from "../../../../contexts/notebook-editor-drag-context";
import type {
  NotebookItem,
  NotebookPage,
} from "../../../../contexts/notebook-editor-context";

interface UseItemEditorDragArgs {
  page: NotebookPage;
  item: NotebookItem;
}

export function useItemEditorDrag({ page, item }: UseItemEditorDragArgs) {
  const { client, pages } = useNotebookEditor();
  const { dragState, setDragState } = useNotebookEditorDrag();

  const isDraggingSource =
    dragState?.source.pageId === page.id && dragState.source.itemId === item.id;

  const isDropBefore = targetMatchesRow(
    dragState?.target ?? null,
    page.id,
    item.id,
    "before",
  );

  const isDropAfter = targetMatchesRow(
    dragState?.target ?? null,
    page.id,
    item.id,
    "after_as_peer",
  );

  const isDropAsChild = targetMatchesRow(
    dragState?.target ?? null,
    page.id,
    item.id,
    "after_as_child",
  );

  const handleDragStart = useCallback(
    (event: React.DragEvent<HTMLElement>) => {
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData(
        NOTEBOOK_ITEM_DRAG_MIME,
        encodeDragPayload({ pageId: page.id, itemId: item.id }),
      );

      setDragState({
        source: { pageId: page.id, itemId: item.id },
        target: null,
      });
    },
    [item.id, page.id, setDragState],
  );

  const handleDragEnd = useCallback(() => {
    setDragState(null);
  }, [setDragState]);

  const handleRowDragOver = useCallback(
    (event: React.DragEvent<HTMLElement>) => {
      setDragEffect(event);
      const source =
        dragState?.source ??
        decodeDragPayload(event.dataTransfer.getData(NOTEBOOK_ITEM_DRAG_MIME));
      if (!source || isDraggingSource) return;

      const placement = getRowDropPlacement(event);

      setDragState((current) => ({
        ...(current ?? { source, target: null }),
        target: {
          kind: "item",
          pageId: page.id,
          itemId: item.id,
          placement,
        },
      }));
    },
    [dragState?.source, isDraggingSource, item.id, page.id, setDragState],
  );

  const handleRowDragLeave = useCallback(
    (event: React.DragEvent<HTMLElement>) => {
      if (event.currentTarget.contains(event.relatedTarget as Node | null)) {
        return;
      }

      setDragState((current) => {
        if (
          current?.target?.kind === "item" &&
          current.target.pageId === page.id &&
          current.target.itemId === item.id
        ) {
          return { ...current, target: null };
        }

        return current;
      });
    },
    [item.id, page.id, setDragState],
  );

  const handleRowDrop = useCallback(
    async (event: React.DragEvent<HTMLElement>) => {
      setDragEffect(event);

      try {
        const placement = getRowDropPlacement(event);
        const source =
          dragState?.source ??
          decodeDragPayload(
            event.dataTransfer.getData(NOTEBOOK_ITEM_DRAG_MIME),
          );

        if (
          !source ||
          (source.pageId === page.id && source.itemId === item.id)
        ) {
          return;
        }

        const sourcePage = pages.find(
          (current) => current.id === source.pageId,
        );
        if (!sourcePage) {
          return;
        }

        const target: NotebookDragTarget = {
          kind: "item" as const,
          pageId: page.id,
          itemId: item.id,
          placement,
        };

        await client.moveItem(
          makeMoveItemArgs({
            sourcePage,
            targetPage: page,
            sourceItemId: source.itemId,
            target,
          }),
        );
      } finally {
        setDragState(null);
      }
    },
    [client, dragState?.source, item.id, page, pages, setDragState],
  );

  const rowClassName = useMemo(
    () =>
      [
        "relative rounded-2xl transition",
        isDraggingSource ? "opacity-50" : "opacity-100",
        isDropBefore || isDropAfter || isDropAsChild ? "bg-primary/5" : "",
      ].join(" "),
    [isDraggingSource, isDropAfter, isDropAsChild, isDropBefore],
  );

  return {
    isDropBefore,
    isDropAfter,
    isDropAsChild,
    rowClassName,
    handleDragStart,
    handleDragEnd,
    handleRowDragOver,
    handleRowDragLeave,
    handleRowDrop,
  };
}
