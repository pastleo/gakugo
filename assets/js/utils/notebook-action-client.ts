import type { NotebookPage } from "../contexts/notebook-editor-context";
import { readCsrfToken } from "./csrf";

type NotebookActionPath =
  | "/api/notebook_action/parse_as_items"
  | "/api/notebook_action/parse_as_flashcards";

export type NotebookActionResponse =
  | { kind: "page_updated"; page: NotebookPage }
  | { status: "noop" };

export type ParseAsItemsRequest = {
  unit_id: number;
  page_id: number;
  item_id: string;
  insertion_mode: "next_siblings" | "children";
};

export type ParseAsFlashcardsRequest = ParseAsItemsRequest & {
  answer_mode: "first_depth" | "non_first_depth" | "no_answer";
};

export class NotebookActionClientError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NotebookActionClientError";
  }
}

export function parseAsItems(body: ParseAsItemsRequest) {
  return postNotebookAction("/api/notebook_action/parse_as_items", body);
}

export function parseAsFlashcards(body: ParseAsFlashcardsRequest) {
  return postNotebookAction("/api/notebook_action/parse_as_flashcards", body);
}

async function postNotebookAction<T extends NotebookActionResponse>(
  path: NotebookActionPath,
  body: Record<string, unknown>,
): Promise<T> {
  const response = await fetch(path, {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": readCsrfToken(),
    },
    body: JSON.stringify(body),
  });

  const payload = await safeJson(response);

  if (!response.ok) {
    throw new NotebookActionClientError(
      normalizeErrorMessage(payload, response.status),
    );
  }

  return payload as T;
}

async function safeJson(response: Response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

function normalizeErrorMessage(payload: unknown, status: number) {
  if (payload && typeof payload === "object") {
    const reason = (payload as { reason?: unknown }).reason;

    if (typeof reason === "string" && reason.length > 0) {
      return reason;
    }
  }

  return `Notebook action failed (${status})`;
}
