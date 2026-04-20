import type { ReactNode } from "react";
import type { NotebookColorName as NotebookColorNameBase } from "../../utils/notebook-colors";

export type NotebookColorName = NotebookColorNameBase;

export type NotebookUnitId = number;
export type NotebookPageId = number;
export type NotebookItemId = string;

export interface NotebookItem {
  id: NotebookItemId;
  text: string;
  depth: number;
  flashcard: boolean;
  answer: boolean;
  yStateAsUpdate: string;
  textColor?: NotebookColorName | null;
  backgroundColor?: NotebookColorName | null;
}

export interface NotebookPage {
  id: NotebookPageId;
  title: string;
  version: number;
  items: NotebookItem[];
  inserted_at: string | null;
  unit_id: NotebookUnitId;
  position: number | null;
}

export interface NotebookInitialPages {
  unitId: NotebookUnitId | null;
  pages: NotebookPage[];
}

export type ReactUpdateListener = (
  callback: (payload: unknown) => void,
) => void | (() => void);

export interface ApplyIntentReplySuccess {
  status: "updated";
  update: CanonicalUpdate;
}

export interface ApplyIntentReplyNoop {
  status: "noop";
}

export interface ApplyIntentReplyError {
  status: "invalid_params" | "error";
  reason: string;
}

export type ApplyIntentReply =
  | ApplyIntentReplySuccess
  | ApplyIntentReplyNoop
  | ApplyIntentReplyError;

export type ApplyIntent = (
  intent: Record<string, unknown>,
) => Promise<ApplyIntentReply>;

export type PageContentAction =
  | "set_text"
  | "set_item_text_color"
  | "set_item_background_color"
  | "text_collab_update"
  | "toggle_flag"
  | "insert_above"
  | "insert_below"
  | "insert_child_below"
  | "indent_item"
  | "outdent_item"
  | "indent_subtree"
  | "outdent_subtree"
  | "add_root_item"
  | "remove_item"
  | "append_many"
  | "insert_many_after";

export type NotebookFlag = "flashcard" | "answer";
export type MoveDirection = "up" | "down";
export type RootInsertPosition = "first" | "last";
export type MoveItemPosition =
  | "before"
  | "after_as_peer"
  | "after_as_child"
  | "root_end";

export type CanonicalUpdate =
  | { kind: "page_updated"; page: NotebookPage }
  | { kind: "pages_list_updated"; pages: NotebookPage[] }
  | { kind: "page_item_updated"; page: NotebookPage };

export interface NotebookEditorProps {
  initialPages: NotebookInitialPages;
  addReactUpdateListener: ReactUpdateListener;
  applyIntent: ApplyIntent;
}

export interface PageContentIntentArgs {
  page: NotebookPage;
  action: PageContentAction;
  payload?: Record<string, unknown>;
  target?: {
    itemId?: NotebookItemId;
    path?: string;
  };
}

export interface MoveItemIntentArgs {
  sourcePage: NotebookPage;
  targetPage: NotebookPage;
  sourceItemId: NotebookItemId;
  targetItemId?: NotebookItemId;
  targetPosition?: MoveItemPosition;
}

export interface NotebookEditorProviderProps extends NotebookEditorProps {
  children?: ReactNode;
}

export interface NotebookEditorState {
  unitId: NotebookUnitId | null;
  pages: NotebookPage[];
  lastUpdateKind: CanonicalUpdate["kind"] | null;
}

export interface NotebookEditorClient {
  send: (intent: Record<string, unknown>) => Promise<ApplyIntentReply>;
  getState: () => NotebookEditorState;
  pageContent: (args: PageContentIntentArgs) => Promise<ApplyIntentReply>;
  setText: (
    page: NotebookPage,
    itemId: NotebookItemId,
    text: string,
  ) => Promise<ApplyIntentReply>;
  textCollabUpdate: (
    page: NotebookPage,
    itemId: NotebookItemId,
    text: string,
    yStateAsUpdate: string,
  ) => Promise<ApplyIntentReply>;
  setItemTextColor: (
    page: NotebookPage,
    itemId: NotebookItemId,
    color: NotebookColorName | null,
  ) => Promise<ApplyIntentReply>;
  setItemBackgroundColor: (
    page: NotebookPage,
    itemId: NotebookItemId,
    color: NotebookColorName | null,
  ) => Promise<ApplyIntentReply>;
  toggleFlag: (
    page: NotebookPage,
    itemId: NotebookItemId,
    flag: NotebookFlag,
  ) => Promise<ApplyIntentReply>;
  insertAbove: (
    page: NotebookPage,
    itemId: NotebookItemId,
    text: string,
  ) => Promise<ApplyIntentReply>;
  insertBelow: (
    page: NotebookPage,
    itemId: NotebookItemId,
    text: string,
  ) => Promise<ApplyIntentReply>;
  insertChildBelow: (
    page: NotebookPage,
    itemId: NotebookItemId,
    text: string,
  ) => Promise<ApplyIntentReply>;
  indentItem: (
    page: NotebookPage,
    itemId: NotebookItemId,
    text: string,
  ) => Promise<ApplyIntentReply>;
  indentSubtree: (
    page: NotebookPage,
    itemId: NotebookItemId,
    text: string,
  ) => Promise<ApplyIntentReply>;
  outdentItem: (
    page: NotebookPage,
    itemId: NotebookItemId,
    text: string,
  ) => Promise<ApplyIntentReply>;
  outdentSubtree: (
    page: NotebookPage,
    itemId: NotebookItemId,
    text: string,
  ) => Promise<ApplyIntentReply>;
  addRootItem: (
    page: NotebookPage,
    position?: RootInsertPosition,
  ) => Promise<ApplyIntentReply>;
  removeItem: (
    page: NotebookPage,
    itemId: NotebookItemId,
  ) => Promise<ApplyIntentReply>;
  appendMany: (
    page: NotebookPage,
    items: NotebookItem[],
  ) => Promise<ApplyIntentReply>;
  insertManyAfter: (
    page: NotebookPage,
    itemId: NotebookItemId,
    items: NotebookItem[],
  ) => Promise<ApplyIntentReply>;
  moveItem: (args: MoveItemIntentArgs) => Promise<ApplyIntentReply>;
  setPageTitle: (
    page: NotebookPage,
    title: string,
  ) => Promise<ApplyIntentReply>;
  addPage: () => Promise<ApplyIntentReply>;
  deletePage: (pageId: NotebookPageId) => Promise<ApplyIntentReply>;
  movePage: (
    pageId: NotebookPageId,
    direction: MoveDirection,
  ) => Promise<ApplyIntentReply>;
}

export interface NotebookEditorContextValue extends NotebookEditorState {
  client: NotebookEditorClient;
}
