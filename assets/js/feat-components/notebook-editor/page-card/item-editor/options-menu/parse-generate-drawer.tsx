import React, { useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import type {
  NotebookItem,
  NotebookPage,
} from "../../../../../contexts/notebook-editor-context";
import {
  NotebookActionClientError,
  parseAsFlashcards,
  parseAsItems,
} from "../../../../../utils/notebook-action-client";

type ParseGenerateActionId = "parse_as_items" | "parse_as_flashcards";
type ParseAsItemsInsertionMode = "next_siblings" | "children";
type ParseAsFlashcardsAnswerMode =
  | "first_depth"
  | "non_first_depth"
  | "no_answer";

interface ParseGenerateDrawerProps {
  open: boolean;
  page: NotebookPage;
  item: NotebookItem;
  onClose: () => void;
}

const ACTION_OPTIONS: Array<{
  value: ParseGenerateActionId;
  label: string;
}> = [
  { value: "parse_as_items", label: "Parse as items" },
  { value: "parse_as_flashcards", label: "Parse as flashcards" },
];

const INSERTION_MODE_OPTIONS: Array<{
  value: ParseAsItemsInsertionMode;
  label: string;
}> = [
  { value: "next_siblings", label: "Next siblings" },
  { value: "children", label: "Children" },
];

const ANSWER_MODE_OPTIONS: Array<{
  value: ParseAsFlashcardsAnswerMode;
  label: string;
}> = [
  { value: "first_depth", label: "First depth also as answer" },
  { value: "non_first_depth", label: "Non-first depth as answer" },
  { value: "no_answer", label: "No answer" },
];

export function ParseGenerateDrawer({
  open,
  page,
  item,
  onClose,
}: ParseGenerateDrawerProps) {
  const [selectedAction, setSelectedAction] =
    useState<ParseGenerateActionId>("parse_as_items");
  const [insertionMode, setInsertionMode] =
    useState<ParseAsItemsInsertionMode>("next_siblings");
  const [answerMode, setAnswerMode] =
    useState<ParseAsFlashcardsAnswerMode>("first_depth");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      return;
    }

    setSelectedAction("parse_as_items");
    setInsertionMode("next_siblings");
    setAnswerMode("first_depth");
    setError(null);
    setIsSubmitting(false);
  }, [open]);

  const selectedActionLabel = useMemo(
    () =>
      ACTION_OPTIONS.find((option) => option.value === selectedAction)?.label ??
      "",
    [selectedAction],
  );

  if (!open || typeof document === "undefined") {
    return null;
  }

  const handleSubmit = async () => {
    setIsSubmitting(true);
    setError(null);

    try {
      if (selectedAction === "parse_as_flashcards") {
        await parseAsFlashcards({
          unit_id: page.unit_id,
          page_id: page.id,
          item_id: item.id,
          insertion_mode: insertionMode,
          answer_mode: answerMode,
        });
      } else {
        await parseAsItems({
          unit_id: page.unit_id,
          page_id: page.id,
          item_id: item.id,
          insertion_mode: insertionMode,
        });
      }

      onClose();
    } catch (error) {
      if (error instanceof NotebookActionClientError) {
        setError(error.message);
      } else {
        setError("Failed to parse the item.");
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return createPortal(
    <div className="fixed inset-0 z-50">
      <button
        type="button"
        aria-label="Close parse and generate drawer"
        className="absolute inset-0 cursor-default bg-base-content/25 backdrop-blur-[1px]"
        onClick={onClose}
      />

      <aside className="absolute right-0 top-0 flex h-full w-full max-w-md flex-col border-l border-base-300 bg-base-100 shadow-2xl">
        <div className="flex items-start justify-between gap-3 border-b border-base-300 px-5 py-4">
          <div>
            <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-base-content/55">
              Parse / Generate
            </p>
            <h2 className="mt-1 text-lg font-semibold text-base-content">
              Notebook action
            </h2>
          </div>

          <button
            type="button"
            className="rounded-md border border-base-300 px-2 py-1 text-sm text-base-content/70 transition hover:bg-base-200"
            onClick={onClose}
          >
            Close
          </button>
        </div>

        <div className="flex-1 space-y-5 overflow-y-auto px-5 py-4">
          <section className="space-y-2">
            <label className="block text-xs font-semibold uppercase tracking-[0.14em] text-base-content/55">
              Action
            </label>

            <select
              value={selectedAction}
              onChange={(event) =>
                setSelectedAction(event.target.value as ParseGenerateActionId)
              }
              className="w-full rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-sm text-base-content outline-none transition focus:border-primary"
            >
              {ACTION_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </section>

          <section className="space-y-2 rounded-2xl border border-base-300 bg-base-200/30 p-4">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.14em] text-base-content/55">
                Source item
              </p>
              <p className="text-sm text-base-content/70">
                Current content will be parsed as notebook items.
              </p>
            </div>

            <pre className="max-h-40 overflow-auto rounded-xl border border-base-300 bg-base-100 p-3 text-xs leading-5 text-base-content/80">
              {item.text || "(empty)"}
            </pre>
          </section>

          <section className="space-y-2">
            <label className="block text-xs font-semibold uppercase tracking-[0.14em] text-base-content/55">
              Insertion mode
            </label>

            <div className="grid gap-2 sm:grid-cols-2">
              {INSERTION_MODE_OPTIONS.map((option) => (
                <label
                  key={option.value}
                  className={[
                    "flex cursor-pointer items-center gap-2 rounded-xl border px-3 py-2 text-sm transition",
                    insertionMode === option.value
                      ? "border-primary bg-primary/10 text-base-content"
                      : "border-base-300 bg-base-100 hover:bg-base-200/70",
                  ].join(" ")}
                >
                  <input
                    type="radio"
                    name="parse-generate-insertion-mode"
                    value={option.value}
                    checked={insertionMode === option.value}
                    onChange={() => setInsertionMode(option.value)}
                    className="radio radio-xs"
                  />
                  <span>{option.label}</span>
                </label>
              ))}
            </div>
          </section>

          {selectedAction === "parse_as_flashcards" ? (
            <section className="space-y-2">
              <label className="block text-xs font-semibold uppercase tracking-[0.14em] text-base-content/55">
                Answer mode
              </label>

              <div className="space-y-2">
                {ANSWER_MODE_OPTIONS.map((option) => (
                  <label
                    key={option.value}
                    className={[
                      "flex cursor-pointer items-center gap-2 rounded-xl border px-3 py-2 text-sm transition",
                      answerMode === option.value
                        ? "border-primary bg-primary/10 text-base-content"
                        : "border-base-300 bg-base-100 hover:bg-base-200/70",
                    ].join(" ")}
                  >
                    <input
                      type="radio"
                      name="parse-generate-answer-mode"
                      value={option.value}
                      checked={answerMode === option.value}
                      onChange={() => setAnswerMode(option.value)}
                      className="radio radio-xs"
                    />
                    <span>{option.label}</span>
                  </label>
                ))}
              </div>
            </section>
          ) : null}

          {error ? (
            <div className="rounded-xl border border-error/30 bg-error/10 px-3 py-2 text-sm text-error">
              {error}
            </div>
          ) : null}
        </div>

        <div className="border-t border-base-300 px-5 py-4">
          <button
            type="button"
            onClick={() => void handleSubmit()}
            disabled={isSubmitting}
            className="inline-flex w-full items-center justify-center rounded-xl bg-primary px-4 py-3 text-sm font-semibold text-primary-content transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isSubmitting ? "Working…" : `Run ${selectedActionLabel}`}
          </button>
        </div>
      </aside>
    </div>,
    document.body,
  );
}
