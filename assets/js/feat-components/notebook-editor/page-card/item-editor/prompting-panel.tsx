import React, { useEffect, useRef, useState } from "react";
import type {
  NotebookItem,
  NotebookItemPrompting,
  NotebookPage,
  PromptingAnswerMode,
  PromptingInsertionMode,
  PromptingMode,
} from "../../../../contexts/notebook-editor-context";
import { useNotebookEditorActions } from "../../../../contexts/notebook-editor-context";
import { useToast } from "../../../../contexts/toast-context";
import {
  NotebookActionClientError,
  parseAsFlashcards,
  parseAsItems,
} from "../../../../utils/notebook-action-client";

interface PromptingPanelProps {
  page: NotebookPage;
  item: NotebookItem;
}

const ACTION_OPTIONS: Array<{ value: PromptingMode; label: string }> = [
  { value: "parse_as_items", label: "Parse as items" },
  { value: "parse_as_flashcards", label: "Parse as flashcards" },
];

const INSERTION_MODE_OPTIONS: Array<{
  value: PromptingInsertionMode;
  label: string;
}> = [
  { value: "next_siblings", label: "Next siblings" },
  { value: "children", label: "Children" },
];

const ANSWER_MODE_OPTIONS: Array<{
  value: PromptingAnswerMode;
  label: string;
}> = [
  { value: "first_depth", label: "First depth also as answer" },
  {
    value: "first_second_depth_front",
    label: "First item of 2nd depth as front",
  },
  { value: "non_first_depth", label: "Non-first depth as answer" },
  { value: "no_answer", label: "No answer" },
];

export function defaultItemPrompting(mode: PromptingMode = "parse_as_items") {
  if (mode === "parse_as_flashcards") {
    return {
      mode,
      insertionMode: "next_siblings",
      answerMode: "first_depth",
    } satisfies NotebookItemPrompting;
  }

  return {
    mode,
    insertionMode: "next_siblings",
  } satisfies NotebookItemPrompting;
}

function promptingWithMode(
  current: NotebookItemPrompting,
  mode: PromptingMode,
): NotebookItemPrompting {
  const insertionMode = current.insertionMode;

  if (mode === "parse_as_flashcards") {
    return {
      mode,
      insertionMode,
      answerMode:
        current.mode === "parse_as_flashcards"
          ? current.answerMode
          : "first_depth",
    };
  }

  return { mode, insertionMode };
}

function promptingWithInsertionMode(
  current: NotebookItemPrompting,
  insertionMode: PromptingInsertionMode,
): NotebookItemPrompting {
  if (current.mode === "parse_as_flashcards") {
    return { ...current, insertionMode };
  }

  return { ...current, insertionMode };
}

function promptingWithAnswerMode(
  current: NotebookItemPrompting,
  answerMode: PromptingAnswerMode,
): NotebookItemPrompting {
  if (current.mode === "parse_as_flashcards") {
    return { ...current, answerMode };
  }

  return current;
}

export function ItemEditorPromptingPanel({ page, item }: PromptingPanelProps) {
  const client = useNotebookEditorActions();
  const { pushToast } = useToast();
  const prompting = item.prompting;
  const [renderedPrompting, setRenderedPrompting] =
    useState<NotebookItemPrompting | null>(prompting ?? null);
  const [isExpanded, setIsExpanded] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [promptingSaveCount, setPromptingSaveCount] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const hasRenderedPromptingRef = useRef(Boolean(prompting));

  useEffect(() => {
    if (!prompting) {
      setIsExpanded(false);
      const timeout = window.setTimeout(() => {
        hasRenderedPromptingRef.current = false;
        setRenderedPrompting(null);
      }, 200);
      return () => window.clearTimeout(timeout);
    }

    setRenderedPrompting(prompting);
    const shouldAnimateOpen = !hasRenderedPromptingRef.current;
    hasRenderedPromptingRef.current = true;

    if (!shouldAnimateOpen) {
      setIsExpanded(true);
      return;
    }

    setIsExpanded(false);
    let secondFrame: number | null = null;
    const firstFrame = requestAnimationFrame(() => {
      secondFrame = requestAnimationFrame(() => setIsExpanded(true));
    });

    return () => {
      cancelAnimationFrame(firstFrame);

      if (secondFrame !== null) {
        cancelAnimationFrame(secondFrame);
      }
    };
  }, [prompting]);

  if (!renderedPrompting) {
    return null;
  }

  const setPrompting = (nextPrompting: NotebookItemPrompting | null) => {
    setError(null);

    if (nextPrompting) {
      setRenderedPrompting(nextPrompting);
    } else {
      setIsExpanded(false);
    }

    setPromptingSaveCount((count) => count + 1);

    void client.setPrompting(page, item.id, nextPrompting).finally(() => {
      setPromptingSaveCount((count) => Math.max(0, count - 1));
    });
  };

  const handleSubmit = async () => {
    if (promptingSaveCount > 0) {
      return;
    }

    setIsSubmitting(true);
    setError(null);

    try {
      if (renderedPrompting.mode === "parse_as_flashcards") {
        await parseAsFlashcards({
          unit_id: page.unit_id,
          page_id: page.id,
          item_id: item.id,
          insertion_mode: renderedPrompting.insertionMode,
          answer_mode: renderedPrompting.answerMode,
        });
      } else {
        await parseAsItems({
          unit_id: page.unit_id,
          page_id: page.id,
          item_id: item.id,
          insertion_mode: renderedPrompting.insertionMode,
        });
      }

      await client.setPrompting(page, item.id, null);
      pushToast({ tone: "success", title: "Notebook action applied" });
    } catch (error) {
      const message =
        error instanceof NotebookActionClientError
          ? error.message
          : "Failed to parse the item.";

      setError(message);
      pushToast({
        tone: "error",
        title: "Notebook action failed",
        description: message,
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div
      className={[
        "mt-2 grid overflow-hidden rounded-2xl border border-primary/25 bg-base-100/90 shadow-sm transition-[grid-template-rows,opacity,transform] duration-200 ease-out",
        isExpanded
          ? "grid-rows-[1fr] translate-y-0 opacity-100"
          : "grid-rows-[0fr] translate-y-1 opacity-0",
      ].join(" ")}
    >
      <div className="min-h-0 overflow-hidden">
        <div className="flex flex-wrap items-center gap-2 bg-base-200/35 px-3 py-2">
          <select
            value={renderedPrompting.mode}
            onChange={(event) =>
              setPrompting(
                promptingWithMode(
                  renderedPrompting,
                  event.target.value as PromptingMode,
                ),
              )
            }
            className="min-w-44 rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-xs font-semibold text-base-content outline-none transition focus:border-primary"
            aria-label="Prompting action"
          >
            {ACTION_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>

          <select
            value={renderedPrompting.insertionMode}
            onChange={(event) =>
              setPrompting(
                promptingWithInsertionMode(
                  renderedPrompting,
                  event.target.value as PromptingInsertionMode,
                ),
              )
            }
            className="min-w-36 rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-xs font-semibold text-base-content outline-none transition focus:border-primary"
            aria-label="Insertion mode"
          >
            {INSERTION_MODE_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>

          {renderedPrompting.mode === "parse_as_flashcards" ? (
            <select
              value={renderedPrompting.answerMode}
              onChange={(event) =>
                setPrompting(
                  promptingWithAnswerMode(
                    renderedPrompting,
                    event.target.value as PromptingAnswerMode,
                  ),
                )
              }
              className="min-w-48 rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-xs font-semibold text-base-content outline-none transition focus:border-secondary"
              aria-label="Answer mode"
            >
              {ANSWER_MODE_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          ) : null}

          {error ? (
            <div className="min-w-48 flex-1 rounded-xl border border-error/30 bg-error/10 px-3 py-2 text-xs text-error">
              {error}
            </div>
          ) : null}

          <button
            type="button"
            onClick={() => setPrompting(null)}
            disabled={isSubmitting}
            className="ml-auto rounded-xl border border-base-300 px-3 py-2 text-xs font-semibold text-base-content/70 transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-60"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => void handleSubmit()}
            disabled={isSubmitting || promptingSaveCount > 0}
            className="rounded-xl bg-primary px-4 py-2 text-xs font-semibold text-primary-content shadow-sm transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isSubmitting
              ? "Working..."
              : promptingSaveCount > 0
                ? "Saving..."
                : "Submit"}
          </button>
        </div>
      </div>
    </div>
  );
}
