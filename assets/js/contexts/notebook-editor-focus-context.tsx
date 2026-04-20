import React, {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
} from "react";
import type {
  NotebookItemId,
  NotebookPageId,
} from "./notebook-editor-context/types";

export interface NotebookEditorItemSelectionRange {
  from: number;
  to: number;
}

export type NotebookEditorItemSelectionTarget =
  | NotebookEditorItemSelectionRange
  | "start"
  | "end";

export interface NotebookEditorItemFocusTarget {
  pageId: NotebookPageId;
  itemId: NotebookItemId;
  selection?: NotebookEditorItemSelectionTarget;
}

interface NotebookEditorFocusContextValue {
  pendingFocusTarget: NotebookEditorItemFocusTarget | null;
  requestItemFocus: (target: NotebookEditorItemFocusTarget) => void;
  clearPendingFocusTarget: () => void;
}

const NotebookEditorFocusContext =
  createContext<NotebookEditorFocusContextValue | null>(null);

export function NotebookEditorFocusProvider({
  children,
}: {
  children?: React.ReactNode;
}) {
  const [pendingFocusTarget, setPendingFocusTarget] =
    useState<NotebookEditorItemFocusTarget | null>(null);

  const requestItemFocus = useCallback(
    (target: NotebookEditorItemFocusTarget) => {
      setPendingFocusTarget(target);
    },
    [],
  );

  const clearPendingFocusTarget = useCallback(() => {
    setPendingFocusTarget(null);
  }, []);

  const value = useMemo<NotebookEditorFocusContextValue>(
    () => ({
      pendingFocusTarget,
      requestItemFocus,
      clearPendingFocusTarget,
    }),
    [clearPendingFocusTarget, pendingFocusTarget, requestItemFocus],
  );

  return (
    <NotebookEditorFocusContext.Provider value={value}>
      {children}
    </NotebookEditorFocusContext.Provider>
  );
}

export function useNotebookEditorFocus() {
  const context = useContext(NotebookEditorFocusContext);

  if (!context) {
    throw new Error(
      "useNotebookEditorFocus must be used within NotebookEditorFocusProvider",
    );
  }

  return context;
}
