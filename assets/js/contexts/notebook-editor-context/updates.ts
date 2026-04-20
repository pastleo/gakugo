import type {
  ApplyIntentReplyError,
  CanonicalUpdate,
  NotebookEditorState,
  NotebookInitialPages,
  NotebookPage,
} from "./types";

export function buildInitialState(
  initialPages: NotebookInitialPages,
): NotebookEditorState {
  return {
    unitId: initialPages.unitId,
    pages: initialPages.pages,
    lastUpdateKind: null,
  };
}

export function upsertPage(
  pages: NotebookPage[],
  nextPage: NotebookPage,
): NotebookPage[] {
  const existingIndex = pages.findIndex((page) => page.id === nextPage.id);

  if (existingIndex === -1) {
    return [...pages, nextPage];
  }

  return pages.map((page) => (page.id === nextPage.id ? nextPage : page));
}

export function applyCanonicalUpdate(
  state: NotebookEditorState,
  update: CanonicalUpdate,
): NotebookEditorState {
  switch (update.kind) {
    case "pages_list_updated":
      return {
        ...state,
        pages: update.pages,
        lastUpdateKind: update.kind,
      };

    case "page_updated":
    case "page_item_updated":
      return {
        ...state,
        pages: upsertPage(state.pages, update.page),
        lastUpdateKind: update.kind,
      };
  }
}

export function isCanonicalUpdate(
  payload: unknown,
): payload is CanonicalUpdate {
  if (!payload || typeof payload !== "object" || !("kind" in payload)) {
    return false;
  }

  const kind = (payload as { kind?: unknown }).kind;

  return (
    kind === "page_updated" ||
    kind === "pages_list_updated" ||
    kind === "page_item_updated"
  );
}

export function invalidParamsReply(reason: string): ApplyIntentReplyError {
  return { status: "invalid_params", reason };
}
