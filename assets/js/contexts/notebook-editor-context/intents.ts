import type {
  MoveItemIntentArgs,
  NotebookItemId,
  NotebookPage,
  NotebookUnitId,
  PageContentIntentArgs,
} from "./types";

function withReactMeta(intent: Record<string, unknown>) {
  return {
    ...intent,
    meta: { client: "react" },
  };
}

export function pageContentIntent(args: PageContentIntentArgs) {
  const target: Record<string, unknown> = { page_id: args.page.id };

  if (args.target?.itemId) {
    target.item_id = args.target.itemId;
  }

  if (args.target?.path) {
    target.path = args.target.path;
  }

  return withReactMeta({
    scope: "page_content",
    action: args.action,
    target,
    version: { local: args.page.version },
    nodes: args.page.items,
    payload: args.payload ?? {},
  });
}

export function setItemColorIntent(
  page: NotebookPage,
  itemId: NotebookItemId,
  action: "set_item_text_color" | "set_item_background_color",
  color: string | null,
) {
  return withReactMeta({
    scope: "page_content",
    action,
    target: { page_id: page.id, item_id: itemId },
    version: { local: page.version },
    nodes: page.items,
    payload: { color },
  });
}

export function pageMetaIntent(page: NotebookPage, title: string) {
  return withReactMeta({
    scope: "page_meta",
    action: "set_page_title",
    target: { page_id: page.id },
    version: { local: page.version },
    payload: { title },
  });
}

export function pageListIntent(
  unitId: NotebookUnitId,
  action: "add_page" | "delete_page" | "move_page",
  payload: Record<string, unknown> = {},
  target: Record<string, unknown> = {},
) {
  return withReactMeta({
    scope: "page_list",
    action,
    target: { unit_id: unitId, ...target },
    payload,
  });
}

export function moveItemIntent(args: MoveItemIntentArgs) {
  const payload: Record<string, unknown> = {
    source_page_id: args.sourcePage.id,
    source_item_id: args.sourceItemId,
    target_page_id: args.targetPage.id,
  };

  if (args.targetItemId) {
    payload.target_item_id = args.targetItemId;
  }

  if (args.targetPosition) {
    payload.position = args.targetPosition;
  }

  return withReactMeta({
    scope: "page_content",
    action: "move_item",
    target: {
      page_id: args.targetPage.id,
      ...(args.targetItemId ? { item_id: args.targetItemId } : {}),
    },
    version: {
      local: args.targetPage.version,
      source: args.sourcePage.version,
    },
    payload,
  });
}
