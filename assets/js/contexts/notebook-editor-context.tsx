import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
} from "react";
import { useStore } from "zustand";
import { createStore, type StoreApi } from "zustand/vanilla";
import {
  moveItemIntent,
  pageContentIntent,
  pageListIntent,
  pageMetaIntent,
  setItemColorIntent,
} from "./notebook-editor-context/intents";
import {
  applyCanonicalUpdate,
  buildInitialState,
  invalidParamsReply,
  isCanonicalUpdate,
} from "./notebook-editor-context/updates";
import type {
  ApplyIntentReply,
  CanonicalUpdate,
  NotebookEditorClient,
  NotebookEditorContextValue,
  NotebookEditorProviderProps,
  NotebookEditorState,
  NotebookInitialPages,
  NotebookItemId,
  NotebookPage,
  NotebookPageId,
  PageContentAction,
  PageContentIntentArgs,
} from "./notebook-editor-context/types";

interface NotebookEditorStoreState extends NotebookEditorState {
  initialize: (initialPages: NotebookInitialPages) => void;
  applyCanonicalUpdate: (update: CanonicalUpdate) => void;
}

const NotebookEditorStoreContext =
  createContext<StoreApi<NotebookEditorStoreState> | null>(null);

const NotebookEditorClientContext = createContext<NotebookEditorClient | null>(
  null,
);

function createNotebookEditorStore(initialPages: NotebookInitialPages) {
  return createStore<NotebookEditorStoreState>()((set) => ({
    ...buildInitialState(initialPages),
    initialize: (nextInitialPages) =>
      set(() => buildInitialState(nextInitialPages)),
    applyCanonicalUpdate: (update) =>
      set((state) => applyCanonicalUpdate(state, update)),
  }));
}

function useNotebookEditorStore() {
  const store = useContext(NotebookEditorStoreContext);

  if (!store) {
    throw new Error(
      "useNotebookEditor must be used within NotebookEditorProvider",
    );
  }

  return store;
}

function useNotebookEditorClient() {
  const client = useContext(NotebookEditorClientContext);

  if (!client) {
    throw new Error(
      "useNotebookEditor must be used within NotebookEditorProvider",
    );
  }

  return client;
}

export function NotebookEditorProvider({
  initialPages,
  addReactUpdateListener,
  applyIntent,
  children,
}: NotebookEditorProviderProps) {
  const storeRef = useRef<StoreApi<NotebookEditorStoreState> | null>(null);

  if (storeRef.current === null) {
    storeRef.current = createNotebookEditorStore(initialPages);
  }

  const store = storeRef.current;

  useEffect(() => {
    store.getState().initialize(initialPages);
  }, [initialPages, store]);

  useEffect(() => {
    const cleanup = addReactUpdateListener((payload) => {
      if (isCanonicalUpdate(payload)) {
        store.getState().applyCanonicalUpdate(payload);
      }
    });

    return typeof cleanup === "function" ? cleanup : undefined;
  }, [addReactUpdateListener, store]);

  const send = useCallback(
    async (intent: Record<string, unknown>): Promise<ApplyIntentReply> => {
      const reply = await applyIntent(intent);

      if (reply.status === "updated" && isCanonicalUpdate(reply.update)) {
        store.getState().applyCanonicalUpdate(reply.update);
      }

      return reply;
    },
    [applyIntent, store],
  );

  const client = useMemo<NotebookEditorClient>(() => {
    const getState = (): NotebookEditorState => {
      const {
        unitId: currentUnitId,
        pages: currentPages,
        lastUpdateKind: currentLastUpdateKind,
      } = store.getState();

      return {
        unitId: currentUnitId,
        pages: currentPages,
        lastUpdateKind: currentLastUpdateKind,
      };
    };

    const pageContent = (args: PageContentIntentArgs) =>
      send(pageContentIntent(args));

    const sendPageAction = (
      page: NotebookPage,
      action: PageContentAction,
      itemId?: NotebookItemId,
      payload: Record<string, unknown> = {},
    ) =>
      pageContent({
        page,
        action,
        target: itemId ? { itemId } : undefined,
        payload,
      });

    return {
      send,
      getState,
      pageContent,
      setText: (page, itemId, text) =>
        sendPageAction(page, "set_text", itemId, { text }),
      textCollabUpdate: (page, itemId, text, yStateAsUpdate) =>
        sendPageAction(page, "text_collab_update", itemId, {
          text,
          y_state_as_update: yStateAsUpdate,
        }),
      setItemTextColor: (page, itemId, color) =>
        send(setItemColorIntent(page, itemId, "set_item_text_color", color)),
      setItemBackgroundColor: (page, itemId, color) =>
        send(
          setItemColorIntent(page, itemId, "set_item_background_color", color),
        ),
      toggleFlag: (page, itemId, flag) =>
        sendPageAction(page, "toggle_flag", itemId, { flag }),
      insertAbove: (page, itemId, text) =>
        sendPageAction(page, "insert_above", itemId, { text }),
      insertBelow: (page, itemId, text) =>
        sendPageAction(page, "insert_below", itemId, { text }),
      insertChildBelow: (page, itemId, text) =>
        sendPageAction(page, "insert_child_below", itemId, { text }),
      indentItem: (page, itemId, text) =>
        sendPageAction(page, "indent_item", itemId, { text }),
      indentSubtree: (page, itemId, text) =>
        sendPageAction(page, "indent_subtree", itemId, { text }),
      outdentItem: (page, itemId, text) =>
        sendPageAction(page, "outdent_item", itemId, { text }),
      outdentSubtree: (page, itemId, text) =>
        sendPageAction(page, "outdent_subtree", itemId, { text }),
      addRootItem: (page, position = "last") =>
        pageContent({
          page,
          action: "add_root_item",
          payload: position === "first" ? { position: "first" } : {},
        }),
      removeItem: (page, itemId) => sendPageAction(page, "remove_item", itemId),
      appendMany: (page, items) =>
        pageContent({ page, action: "append_many", payload: { items } }),
      insertManyAfter: (page, itemId, items) =>
        pageContent({
          page,
          action: "insert_many_after",
          target: { itemId },
          payload: { items },
        }),
      moveItem: (args) => send(moveItemIntent(args)),
      setPageTitle: (page, title) => send(pageMetaIntent(page, title)),
      addPage: () => {
        const { unitId: currentUnitId } = getState();

        if (currentUnitId === null) {
          return Promise.resolve(invalidParamsReply("missing_unit_id"));
        }

        return send(pageListIntent(currentUnitId, "add_page"));
      },
      deletePage: (pageId: NotebookPageId) => {
        const { unitId: currentUnitId } = getState();

        if (currentUnitId === null) {
          return Promise.resolve(invalidParamsReply("missing_unit_id"));
        }

        return send(
          pageListIntent(currentUnitId, "delete_page", {}, { page_id: pageId }),
        );
      },
      movePage: (pageId: NotebookPageId, direction) => {
        const { unitId: currentUnitId } = getState();

        if (currentUnitId === null) {
          return Promise.resolve(invalidParamsReply("missing_unit_id"));
        }

        return send(
          pageListIntent(
            currentUnitId,
            "move_page",
            { direction },
            { page_id: pageId },
          ),
        );
      },
    };
  }, [send, store]);

  return (
    <NotebookEditorStoreContext.Provider value={store}>
      <NotebookEditorClientContext.Provider value={client}>
        {children}
      </NotebookEditorClientContext.Provider>
    </NotebookEditorStoreContext.Provider>
  );
}

export function useNotebookEditor() {
  const store = useNotebookEditorStore();
  const client = useNotebookEditorClient();

  const unitId = useStore(store, (state) => state.unitId);
  const pages = useStore(store, (state) => state.pages);
  const lastUpdateKind = useStore(store, (state) => state.lastUpdateKind);

  return useMemo<NotebookEditorContextValue>(
    () => ({
      unitId,
      pages,
      lastUpdateKind,
      client,
    }),
    [client, lastUpdateKind, pages, unitId],
  );
}

export type {
  ApplyIntent,
  ApplyIntentReply,
  CanonicalUpdate,
  MoveDirection,
  MoveItemIntentArgs,
  NotebookEditorClient,
  NotebookEditorProps,
  NotebookFlag,
  NotebookInitialPages,
  NotebookColorName,
  NotebookItem,
  NotebookItemId,
  NotebookPage,
  NotebookPageId,
  NotebookUnitId,
  PageContentAction,
  PageContentIntentArgs,
  ReactUpdateListener,
  RootInsertPosition,
} from "./notebook-editor-context/types";
