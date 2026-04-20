import React, { createContext, useContext, useMemo, useState } from "react";

import {
  useNotebookEditor,
  type NotebookItemId,
  type NotebookPage,
} from "./notebook-editor-context";

export const NOTEBOOK_ITEM_DRAG_MIME = "application/x-gakugo-notebook-item";

export type NotebookDragPlacement =
  | "before"
  | "after_as_peer"
  | "after_as_child"
  | "root_end";

export interface NotebookDragSource {
  pageId: number;
  itemId: NotebookItemId;
}

export type NotebookDragTarget =
  | {
      kind: "item";
      pageId: number;
      itemId: NotebookItemId;
      placement: "before" | "after_as_peer" | "after_as_child";
    }
  | {
      kind: "page";
      pageId: number;
      placement: "root_end";
    };

export interface NotebookDragState {
  source: NotebookDragSource;
  target: NotebookDragTarget | null;
}

interface NotebookEditorDragContextValue {
  dragState: NotebookDragState | null;
  setDragState: React.Dispatch<React.SetStateAction<NotebookDragState | null>>;
  handlePageRootEndDragOver: React.DragEventHandler<HTMLElement>;
  handlePageRootEndDrop: React.DragEventHandler<HTMLElement>;
  handlePageRootEndDragLeave: React.DragEventHandler<HTMLElement>;
}

const NotebookEditorDragContext =
  createContext<NotebookEditorDragContextValue | null>(null);

export function encodeDragPayload(source: NotebookDragSource) {
  return JSON.stringify(source);
}

export function decodeDragPayload(value: string): NotebookDragSource | null {
  try {
    const parsed = JSON.parse(value) as Partial<NotebookDragSource>;

    if (
      typeof parsed.pageId !== "number" ||
      typeof parsed.itemId !== "string" ||
      parsed.itemId === ""
    ) {
      return null;
    }

    return { pageId: parsed.pageId, itemId: parsed.itemId };
  } catch {
    return null;
  }
}

export function setDragEffect(event: React.DragEvent<HTMLElement>) {
  event.preventDefault();
  event.stopPropagation();

  if (event.dataTransfer) {
    event.dataTransfer.dropEffect = "move";
  }
}

export function getRowDropPlacement(event: React.DragEvent<HTMLElement>) {
  const rect = event.currentTarget.getBoundingClientRect();
  const midpoint = rect.top + rect.height / 2;

  if (event.clientY < midpoint) {
    return "before";
  }

  return event.clientX < rect.left + 40 ? "after_as_peer" : "after_as_child";
}

export function targetMatchesPage(
  target: NotebookDragTarget | null,
  pageId: number,
  placement: "root_end",
) {
  return (
    target?.kind === "page" &&
    target.pageId === pageId &&
    target.placement === placement
  );
}

export function targetMatchesRow(
  target: NotebookDragTarget | null,
  pageId: number,
  itemId: NotebookItemId,
  placement: "before" | "after_as_peer" | "after_as_child",
) {
  return (
    target?.kind === "item" &&
    target.pageId === pageId &&
    target.itemId === itemId &&
    target.placement === placement
  );
}

export function makeMoveItemArgs({
  sourcePage,
  targetPage,
  sourceItemId,
  target,
}: {
  sourcePage: NotebookPage;
  targetPage: NotebookPage;
  sourceItemId: NotebookItemId;
  target: NotebookDragTarget;
}) {
  if (target.kind === "page") {
    return {
      sourcePage,
      targetPage,
      sourceItemId,
      targetPosition: target.placement,
    };
  }

  return {
    sourcePage,
    targetPage,
    sourceItemId,
    targetItemId: target.itemId,
    targetPosition: target.placement,
  };
}

export function NotebookEditorDragProvider({
  children,
}: {
  children: React.ReactNode;
}) {
  const { client, pages } = useNotebookEditor();
  const [dragState, setDragState] = useState<NotebookDragState | null>(null);

  const value = useMemo<NotebookEditorDragContextValue>(
    () => ({
      dragState,
      setDragState,
      handlePageRootEndDragOver: (event) => {
        setDragEffect(event);
        const source =
          dragState?.source ??
          decodeDragPayload(
            event.dataTransfer.getData(NOTEBOOK_ITEM_DRAG_MIME),
          );
        if (!source) return;

        const pageId = Number(
          event.currentTarget.getAttribute("data-page-id") ?? "",
        );
        if (!Number.isFinite(pageId)) return;

        setDragState((current) => ({
          ...(current ?? { source, target: null }),
          target: { kind: "page", pageId, placement: "root_end" },
        }));
      },
      handlePageRootEndDrop: async (event) => {
        setDragEffect(event);

        try {
          const source =
            dragState?.source ??
            decodeDragPayload(
              event.dataTransfer.getData(NOTEBOOK_ITEM_DRAG_MIME),
            );
          if (!source) return;

          const pageId = Number(
            event.currentTarget.getAttribute("data-page-id") ?? "",
          );
          if (!Number.isFinite(pageId)) return;

          const sourcePage = pages.find((page) => page.id === source.pageId);
          const targetPage = pages.find((page) => page.id === pageId);
          if (!sourcePage || !targetPage) return;

          await client.moveItem(
            makeMoveItemArgs({
              sourcePage,
              targetPage,
              sourceItemId: source.itemId,
              target: { kind: "page", pageId, placement: "root_end" },
            }),
          );
        } finally {
          setDragState(null);
        }
      },
      handlePageRootEndDragLeave: (event) => {
        if (event.currentTarget.contains(event.relatedTarget as Node | null)) {
          return;
        }

        const pageId = Number(
          event.currentTarget.getAttribute("data-page-id") ?? "",
        );
        if (!Number.isFinite(pageId)) return;

        setDragState((current) => {
          if (
            current?.target?.kind === "page" &&
            current.target.pageId === pageId &&
            current.target.placement === "root_end"
          ) {
            return { ...current, target: null };
          }

          return current;
        });
      },
    }),
    [client, dragState, pages],
  );

  return (
    <NotebookEditorDragContext.Provider value={value}>
      {children}
    </NotebookEditorDragContext.Provider>
  );
}

export function useNotebookEditorDrag() {
  const context = useContext(NotebookEditorDragContext);

  if (!context) {
    throw new Error(
      "useNotebookEditorDrag must be used within NotebookEditorDragProvider",
    );
  }

  return context;
}
