import type {
  ApplyIntentReplyError,
  CanonicalUpdate,
  NotebookEditorState,
  NotebookInitialPages,
  NotebookItem,
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

  const reconciledPage = reconcilePage(pages[existingIndex], nextPage);

  if (reconciledPage === pages[existingIndex]) {
    return pages;
  }

  return pages.map((page, index) =>
    index === existingIndex ? reconciledPage : page,
  );
}

function promptingEqual(
  current: NotebookItem["prompting"],
  next: NotebookItem["prompting"],
) {
  if (current === next) return true;
  if (!current || !next) return false;
  if (
    current.mode !== next.mode ||
    current.insertionMode !== next.insertionMode
  ) {
    return false;
  }

  if (current.mode === "parse_as_flashcards") {
    return (
      next.mode === "parse_as_flashcards" &&
      current.answerMode === next.answerMode
    );
  }

  return next.mode === "parse_as_items";
}

function itemEqual(current: NotebookItem, next: NotebookItem) {
  return (
    current.id === next.id &&
    current.text === next.text &&
    current.depth === next.depth &&
    current.flashcard === next.flashcard &&
    current.answer === next.answer &&
    current.editedAt === next.editedAt &&
    current.yStateAsUpdate === next.yStateAsUpdate &&
    current.textColor === next.textColor &&
    current.backgroundColor === next.backgroundColor &&
    promptingEqual(current.prompting, next.prompting)
  );
}

function reconcileItems(
  currentItems: NotebookItem[],
  nextItems: NotebookItem[],
) {
  const currentById = new Map(currentItems.map((item) => [item.id, item]));
  let changed = currentItems.length !== nextItems.length;

  const reconciledItems = nextItems.map((nextItem, index) => {
    const currentItem = currentById.get(nextItem.id);

    if (currentItem && itemEqual(currentItem, nextItem)) {
      if (currentItems[index] !== currentItem) {
        changed = true;
      }

      return currentItem;
    }

    changed = true;
    return nextItem;
  });

  return changed ? reconciledItems : currentItems;
}

function pageMetaEqual(current: NotebookPage, next: NotebookPage) {
  return (
    current.id === next.id &&
    current.title === next.title &&
    current.version === next.version &&
    current.editedAt === next.editedAt &&
    current.inserted_at === next.inserted_at &&
    current.unit_id === next.unit_id &&
    current.position === next.position
  );
}

export function reconcilePage(
  currentPage: NotebookPage,
  nextPage: NotebookPage,
) {
  const items = reconcileItems(currentPage.items, nextPage.items);

  if (items === currentPage.items && pageMetaEqual(currentPage, nextPage)) {
    return currentPage;
  }

  return { ...nextPage, items };
}

function reconcilePages(
  currentPages: NotebookPage[],
  nextPages: NotebookPage[],
) {
  const currentById = new Map(currentPages.map((page) => [page.id, page]));
  let changed = currentPages.length !== nextPages.length;

  const reconciledPages = nextPages.map((nextPage, index) => {
    const currentPage = currentById.get(nextPage.id);
    const reconciledPage = currentPage
      ? reconcilePage(currentPage, nextPage)
      : nextPage;

    if (currentPages[index] !== reconciledPage) {
      changed = true;
    }

    return reconciledPage;
  });

  return changed ? reconciledPages : currentPages;
}

export function applyCanonicalUpdate(
  state: NotebookEditorState,
  update: CanonicalUpdate,
): NotebookEditorState {
  switch (update.kind) {
    case "pages_list_updated":
      return {
        ...state,
        pages: reconcilePages(state.pages, update.pages),
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
