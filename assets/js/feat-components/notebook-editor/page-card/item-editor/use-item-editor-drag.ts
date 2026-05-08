import { useCallback, useMemo } from "react";
import {
  useNotebookEditorActions,
  type NotebookItemId,
  type NotebookPageId,
} from "../../../../contexts/notebook-editor-context";
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
interface UseItemEditorDragArgs {
  pageId: NotebookPageId;
  itemId: NotebookItemId;
}

export function useItemEditorDrag({ pageId, itemId }: UseItemEditorDragArgs) {
  const client = useNotebookEditorActions();
  const { dragState, setDragState } = useNotebookEditorDrag();

  const isDraggingSource =
    dragState?.source.pageId === pageId && dragState.source.itemId === itemId;

  const isDropBefore = targetMatchesRow(
    dragState?.target ?? null,
    pageId,
    itemId,
    "before",
  );

  const isDropAfter = targetMatchesRow(
    dragState?.target ?? null,
    pageId,
    itemId,
    "after_as_peer",
  );

  const isDropAsChild = targetMatchesRow(
    dragState?.target ?? null,
    pageId,
    itemId,
    "after_as_child",
  );

  const handleDragStart = useCallback(
    (event: React.DragEvent<HTMLElement>) => {
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData(
        NOTEBOOK_ITEM_DRAG_MIME,
        encodeDragPayload({ pageId, itemId }),
      );

      setDragState({
        source: { pageId, itemId },
        target: null,
      });
    },
    [itemId, pageId, setDragState],
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
          pageId,
          itemId,
          placement,
        },
      }));
    },
    [dragState?.source, isDraggingSource, itemId, pageId, setDragState],
  );

  const handleRowDragLeave = useCallback(
    (event: React.DragEvent<HTMLElement>) => {
      if (event.currentTarget.contains(event.relatedTarget as Node | null)) {
        return;
      }

      setDragState((current) => {
        if (
          current?.target?.kind === "item" &&
          current.target.pageId === pageId &&
          current.target.itemId === itemId
        ) {
          return { ...current, target: null };
        }

        return current;
      });
    },
    [itemId, pageId, setDragState],
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

        if (!source || (source.pageId === pageId && source.itemId === itemId)) {
          return;
        }

        const { pages } = client.getState();
        const sourcePage = pages.find(
          (current) => current.id === source.pageId,
        );
        const targetPage = pages.find((current) => current.id === pageId);
        if (!sourcePage || !targetPage) {
          return;
        }

        const target: NotebookDragTarget = {
          kind: "item" as const,
          pageId,
          itemId,
          placement,
        };

        await client.moveItem(
          makeMoveItemArgs({
            sourcePage,
            targetPage,
            sourceItemId: source.itemId,
            target,
          }),
        );
      } finally {
        setDragState(null);
      }
    },
    [client, dragState?.source, itemId, pageId, setDragState],
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
