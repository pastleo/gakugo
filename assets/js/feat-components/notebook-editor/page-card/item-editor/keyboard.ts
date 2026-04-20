import { useCallback, useRef, type MutableRefObject } from "react";
import { TextSelection, type Transaction } from "prosemirror-state";
import type { Node as ProseMirrorNode } from "prosemirror-model";
import type { EditorView } from "prosemirror-view";
import { useNotebookEditor } from "../../../../contexts/notebook-editor-context";
import {
  useNotebookEditorFocus,
  type NotebookEditorItemSelectionTarget,
} from "../../../../contexts/notebook-editor-focus-context";
import type {
  NotebookItem,
  NotebookPage,
} from "../../../../contexts/notebook-editor-context";

interface ItemEditorSelectionBoundary {
  collapsed: boolean;
  empty: boolean;
  atStart: boolean;
  atEnd: boolean;
}

interface ItemEditorDocLike {
  textContent: string;
  childCount: number;
  content: { size: number };
}

interface ItemEditorSelectionLike {
  from: number;
  to: number;
}

interface ItemEditorStateLike {
  doc: ProseMirrorNode & ItemEditorDocLike;
  selection: ItemEditorSelectionLike;
  tr: Transaction;
}

type ItemEditorViewLike = EditorView & { state: ItemEditorStateLike };

interface UseItemEditorKeyboardArgs {
  page: NotebookPage;
  item: NotebookItem;
  itemIndex: number;
  getCurrentMarkdown: () => string;
  pendingArrowUpToFrontRef: MutableRefObject<boolean>;
}

function classifySelection(
  state: ItemEditorStateLike,
): ItemEditorSelectionBoundary {
  const start = state.selection.from;
  const end = state.selection.to;
  const collapsed = start === end;

  return {
    collapsed,
    empty: state.doc.textContent.length === 0,
    atStart: start <= 1 && end <= 1,
    atEnd:
      start + 1 >= state.doc.content.size && end + 1 >= state.doc.content.size,
  };
}

function hasChildren(page: NotebookPage, itemIndex: number) {
  const current = page.items[itemIndex];
  const next = page.items[itemIndex + 1];

  return !!current && !!next && next.depth > current.depth;
}

function isLastChild(page: NotebookPage, itemIndex: number) {
  const current = page.items[itemIndex];
  const next = page.items[itemIndex + 1];

  return !!current && (!next || next.depth < current.depth);
}

function shouldEmptyEnterOutdent(page: NotebookPage, itemIndex: number) {
  const current = page.items[itemIndex];

  return !!current && current.depth > 0 && isLastChild(page, itemIndex);
}

function getPreviousItemIndex(page: NotebookPage, itemIndex: number) {
  return Math.max(itemIndex - 1, 0);
}

function getNextItemIndex(page: NotebookPage, itemIndex: number) {
  return Math.min(itemIndex + 1, Math.max(page.items.length - 1, 0));
}

function getFocusSelection() {
  return "start" as const;
}

function getEndFocusSelection() {
  return "end" as const;
}

export function useItemEditorKeyboard({
  page,
  item,
  itemIndex,
  getCurrentMarkdown,
  pendingArrowUpToFrontRef,
}: UseItemEditorKeyboardArgs) {
  const { client } = useNotebookEditor();
  const { requestItemFocus } = useNotebookEditorFocus();
  const latestArgsRef = useRef({ page, item, itemIndex, getCurrentMarkdown });

  latestArgsRef.current = { page, item, itemIndex, getCurrentMarkdown };

  const requestFreshItemFocus = useCallback(
    (
      pageId: number,
      focusItemIndex: number,
      selection: NotebookEditorItemSelectionTarget = getFocusSelection(),
    ) => {
      const nextState = client.getState();
      const nextPage = nextState.pages.find((current) => current.id === pageId);
      const nextItem = nextPage?.items[focusItemIndex];

      if (!nextPage || !nextItem) {
        return;
      }

      requestItemFocus({
        pageId: nextPage.id,
        itemId: nextItem.id,
        selection,
      });
    },
    [client, requestItemFocus],
  );

  const requestFreshItemFocusById = useCallback(
    (
      pageId: number,
      focusItemId: string,
      selection: NotebookEditorItemSelectionTarget = getFocusSelection(),
    ) => {
      const nextState = client.getState();
      const nextPage = nextState.pages.find((current) => current.id === pageId);
      const nextItem = nextPage?.items.find(
        (current) => current.id === focusItemId,
      );

      if (!nextPage || !nextItem) {
        return;
      }

      requestItemFocus({
        pageId: nextPage.id,
        itemId: nextItem.id,
        selection,
      });
    },
    [client, requestItemFocus],
  );

  const handleKeyDown = useCallback(
    (view: ItemEditorViewLike, event: KeyboardEvent) => {
      const {
        page: currentPage,
        item: currentItem,
        itemIndex: currentItemIndex,
      } = latestArgsRef.current;
      const boundary = classifySelection(view.state);

      if (
        event.key === "ArrowUp" &&
        pendingArrowUpToFrontRef.current &&
        boundary.collapsed &&
        boundary.atEnd
      ) {
        event.preventDefault();
        pendingArrowUpToFrontRef.current = false;
        view.dispatch(
          view.state.tr.setSelection(
            TextSelection.create(view.state.doc, 1, 1),
          ),
        );
        return true;
      }

      if (event.key !== "ArrowUp") {
        pendingArrowUpToFrontRef.current = false;
      }

      if (event.key === "Tab") {
        event.preventDefault();

        void (async () => {
          const text = getCurrentMarkdown();

          await (event.shiftKey
            ? client.outdentItem(currentPage, currentItem.id, text)
            : client.indentItem(currentPage, currentItem.id, text));

          requestFreshItemFocusById(currentPage.id, currentItem.id);
        })();

        return true;
      }

      if (
        event.key === "ArrowUp" &&
        boundary.collapsed &&
        (boundary.empty || boundary.atStart)
      ) {
        event.preventDefault();
        requestFreshItemFocus(
          currentPage.id,
          getPreviousItemIndex(currentPage, currentItemIndex),
          getEndFocusSelection(),
        );
        return true;
      }

      if (
        event.key === "ArrowDown" &&
        boundary.collapsed &&
        (boundary.empty || boundary.atEnd)
      ) {
        event.preventDefault();
        requestFreshItemFocus(
          currentPage.id,
          getNextItemIndex(currentPage, currentItemIndex),
        );
        return true;
      }

      if (
        event.key === "Backspace" &&
        boundary.empty &&
        !hasChildren(currentPage, currentItemIndex)
      ) {
        event.preventDefault();

        void (async () => {
          await client.removeItem(currentPage, currentItem.id);
          requestFreshItemFocus(
            currentPage.id,
            getPreviousItemIndex(currentPage, currentItemIndex),
            getEndFocusSelection(),
          );
        })();

        return true;
      }

      if (
        event.key === "Delete" &&
        boundary.empty &&
        !hasChildren(currentPage, currentItemIndex)
      ) {
        event.preventDefault();

        void (async () => {
          await client.removeItem(currentPage, currentItem.id);
          requestFreshItemFocus(
            currentPage.id,
            Math.min(
              currentItemIndex,
              Math.max(currentPage.items.length - 2, 0),
            ),
          );
        })();

        return true;
      }

      if (event.key !== "Enter" || !boundary.collapsed) {
        return false;
      }

      if (boundary.empty) {
        if (event.shiftKey) {
          return false;
        }

        event.preventDefault();

        void (async () => {
          const text = getCurrentMarkdown();

          if (shouldEmptyEnterOutdent(currentPage, currentItemIndex)) {
            await client.outdentItem(currentPage, currentItem.id, text);

            requestFreshItemFocusById(currentPage.id, currentItem.id);
            return;
          }

          await client.insertBelow(currentPage, currentItem.id, text);
          requestFreshItemFocus(currentPage.id, currentItemIndex + 1);
        })();

        return true;
      }

      const shouldInsertAbove = boundary.atStart && !event.shiftKey;
      const shouldInsertChildBelow =
        (boundary.atEnd && !event.shiftKey) ||
        (event.shiftKey && !boundary.atStart && !boundary.atEnd);

      if (!shouldInsertAbove && !shouldInsertChildBelow) {
        return false;
      }

      event.preventDefault();

      void (async () => {
        const text = getCurrentMarkdown();

        if (shouldInsertAbove) {
          await client.insertAbove(currentPage, currentItem.id, text);
          requestFreshItemFocus(currentPage.id, currentItemIndex);
          return;
        }

        if (shouldInsertChildBelow) {
          await client.insertChildBelow(currentPage, currentItem.id, text);
          requestFreshItemFocus(currentPage.id, currentItemIndex + 1);
        }
      })();

      return true;
    },
    [
      client,
      getCurrentMarkdown,
      pendingArrowUpToFrontRef,
      requestFreshItemFocus,
      requestFreshItemFocusById,
    ],
  );

  return handleKeyDown;
}
