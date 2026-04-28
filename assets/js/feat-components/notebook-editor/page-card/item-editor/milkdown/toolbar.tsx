import React, { useCallback, useMemo, useState } from "react";
import { TooltipProvider } from "@milkdown/kit/plugin/tooltip";
import {
  TextSelection,
  type EditorState,
  Plugin,
  PluginKey,
  type PluginView,
} from "@milkdown/kit/prose/state";
import type { EditorView } from "@milkdown/kit/prose/view";
import {
  emphasisSchema,
  inlineCodeSchema,
  strongSchema,
  toggleEmphasisCommand,
  toggleInlineCodeCommand,
  toggleStrongCommand,
} from "@milkdown/kit/preset/commonmark";
import {
  strikethroughSchema,
  toggleStrikethroughCommand,
} from "@milkdown/kit/preset/gfm";
import type { Ctx } from "@milkdown/kit/ctx";
import { $prose, callCommand } from "@milkdown/kit/utils";
import { createPortal } from "react-dom";
import { useInstance } from "@milkdown/react";
import { HighlightToolbarControls } from "./toolbar/highlight";

export interface MilkdownToolbarTool {
  id: string;
  label: string;
  icon: React.ReactNode;
  active?: boolean;
  disabled?: boolean;
  onMouseDown: (event: React.MouseEvent<HTMLButtonElement>) => void;
}

export interface MilkdownToolbarSelectionSnapshot {
  activeToolIds: string[];
  markAttrsByType: Record<string, Record<string, unknown>>;
}

export interface MilkdownToolbarState {
  container: HTMLDivElement | null;
  selection: MilkdownToolbarSelectionSnapshot;
}

export interface UseMilkdownToolbarResult {
  plugin: ReturnType<typeof createMilkdownToolbarPlugin>;
  element: React.ReactNode;
}

interface MilkdownToolbarProps {
  container: HTMLDivElement | null;
  tools: MilkdownToolbarTool[];
  selection: MilkdownToolbarSelectionSnapshot;
}

interface CreateMilkdownToolbarPluginOptions {
  onStateChange: (state: MilkdownToolbarState) => void;
}

const EMPTY_SELECTION_SNAPSHOT: MilkdownToolbarSelectionSnapshot = {
  activeToolIds: [],
  markAttrsByType: {},
};

const EMPTY_TOOLBAR_STATE: MilkdownToolbarState = {
  container: null,
  selection: EMPTY_SELECTION_SNAPSHOT,
};

function GlyphIcon({
  className,
  children,
}: {
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <span
      aria-hidden="true"
      className={["select-none text-[11px] leading-none", className ?? ""].join(
        " ",
      )}
    >
      {children}
    </span>
  );
}

function BoldIcon() {
  return <GlyphIcon className="font-black">B</GlyphIcon>;
}

function ItalicIcon() {
  return <GlyphIcon className="text-xs italic font-semibold">I</GlyphIcon>;
}

function StrikethroughIcon() {
  return <GlyphIcon className="font-bold line-through">S</GlyphIcon>;
}

function CodeIcon() {
  return <span aria-hidden="true" className="hero-code-bracket size-3.5" />;
}

function shouldShowToolbar(view: EditorView, _content: HTMLDivElement) {
  const { doc, selection } = view.state;
  const isTextSelection = selection instanceof TextSelection;
  const hasSelectedText =
    doc.textBetween(selection.from, selection.to).length > 0;

  if (
    !view.hasFocus() ||
    !view.editable ||
    selection.empty ||
    !isTextSelection ||
    !hasSelectedText
  ) {
    return false;
  }

  return true;
}

function getActiveToolIds(ctx: Ctx, view: EditorView) {
  const strongMark = strongSchema.type(ctx);
  const emphasisMark = emphasisSchema.type(ctx);
  const strikethroughMark = strikethroughSchema.type(ctx);
  const inlineCodeMark = inlineCodeSchema.type(ctx);
  const { selection, doc } = view.state;

  if (selection.empty) {
    return [];
  }

  return [
    doc.rangeHasMark(selection.from, selection.to, strongMark) ? "bold" : null,
    doc.rangeHasMark(selection.from, selection.to, emphasisMark)
      ? "italic"
      : null,
    doc.rangeHasMark(selection.from, selection.to, strikethroughMark)
      ? "strikethrough"
      : null,
    doc.rangeHasMark(selection.from, selection.to, inlineCodeMark)
      ? "code"
      : null,
  ].filter((toolId): toolId is string => toolId !== null);
}

function getMarkAttrsByType(view: EditorView) {
  const { selection, doc } = view.state;
  const markAttrsByType: Record<string, Record<string, unknown>> = {};

  if (selection.empty) {
    return markAttrsByType;
  }

  doc.nodesBetween(selection.from, selection.to, (node) => {
    for (const mark of node.marks) {
      if (!markAttrsByType[mark.type.name]) {
        markAttrsByType[mark.type.name] = mark.attrs as Record<string, unknown>;
      }
    }

    return undefined;
  });

  return markAttrsByType;
}

function getSelectionSnapshot(
  ctx: Ctx,
  view: EditorView,
): MilkdownToolbarSelectionSnapshot {
  return {
    activeToolIds: getActiveToolIds(ctx, view),
    markAttrsByType: getMarkAttrsByType(view),
  };
}

function sameSelectionSnapshot(
  previous: MilkdownToolbarSelectionSnapshot,
  next: MilkdownToolbarSelectionSnapshot,
) {
  const sameActiveTools =
    previous.activeToolIds.length === next.activeToolIds.length &&
    previous.activeToolIds.every(
      (toolId, index) => toolId === next.activeToolIds[index],
    );

  return (
    sameActiveTools &&
    JSON.stringify(previous.markAttrsByType) ===
      JSON.stringify(next.markAttrsByType)
  );
}

export function MilkdownToolbar({
  container,
  tools,
  selection,
}: MilkdownToolbarProps) {
  if (!container || tools.length === 0) {
    return null;
  }

  return createPortal(
    <div
      className="pointer-events-auto flex w-[80vw] max-w-[400px] min-w-0 items-center gap-1 rounded-2xl border border-base-300 bg-base-100/95 p-1.5 shadow-lg shadow-base-300/30 backdrop-blur"
      onMouseDownCapture={(event) => {
        event.preventDefault();
      }}
    >
      <div className="flex shrink-0 items-center gap-1 rounded-full border border-base-300/70 bg-base-100/80 p-1">
        {tools.map((tool) => (
          <button
            key={tool.id}
            type="button"
            disabled={tool.disabled}
            title={tool.label}
            aria-label={tool.label}
            aria-pressed={tool.active ? "true" : "false"}
            className={[
              "inline-flex size-7 items-center justify-center rounded-full transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30 disabled:cursor-not-allowed disabled:opacity-50",
              tool.active
                ? "bg-primary text-primary-content"
                : "text-base-content hover:bg-base-200",
            ].join(" ")}
            onMouseDown={tool.onMouseDown}
          >
            {tool.icon}
          </button>
        ))}
      </div>

      <HighlightToolbarControls selection={selection} />
    </div>,
    container,
  );
}

export function useMilkdownToolbar(): UseMilkdownToolbarResult {
  const [loading, get] = useInstance();
  const [toolbarState, setToolbarState] =
    useState<MilkdownToolbarState>(EMPTY_TOOLBAR_STATE);

  const handleToolbarStateChange = useCallback(
    (nextState: MilkdownToolbarState) => {
      setToolbarState((previousState) => {
        const sameContainer = previousState.container === nextState.container;
        return sameContainer &&
          sameSelectionSnapshot(previousState.selection, nextState.selection)
          ? previousState
          : nextState;
      });
    },
    [],
  );

  const plugin = useMemo(
    () =>
      createMilkdownToolbarPlugin({ onStateChange: handleToolbarStateChange }),
    [handleToolbarStateChange],
  );

  const tools = useMemo(
    () => [
      {
        id: "bold",
        label: "Bold",
        icon: <BoldIcon />,
        active: toolbarState.selection.activeToolIds.includes("bold"),
        onMouseDown: (event: React.MouseEvent<HTMLButtonElement>) => {
          event.preventDefault();

          if (loading) {
            return;
          }

          get()?.action(callCommand(toggleStrongCommand.key));
        },
      },
      {
        id: "italic",
        label: "Italic",
        icon: <ItalicIcon />,
        active: toolbarState.selection.activeToolIds.includes("italic"),
        onMouseDown: (event: React.MouseEvent<HTMLButtonElement>) => {
          event.preventDefault();

          if (loading) {
            return;
          }

          get()?.action(callCommand(toggleEmphasisCommand.key));
        },
      },
      {
        id: "strikethrough",
        label: "Strikethrough",
        icon: <StrikethroughIcon />,
        active: toolbarState.selection.activeToolIds.includes("strikethrough"),
        onMouseDown: (event: React.MouseEvent<HTMLButtonElement>) => {
          event.preventDefault();

          if (loading) {
            return;
          }

          get()?.action(callCommand(toggleStrikethroughCommand.key));
        },
      },
      {
        id: "code",
        label: "Code",
        icon: <CodeIcon />,
        active: toolbarState.selection.activeToolIds.includes("code"),
        onMouseDown: (event: React.MouseEvent<HTMLButtonElement>) => {
          event.preventDefault();

          if (loading) {
            return;
          }

          get()?.action(callCommand(toggleInlineCodeCommand.key));
        },
      },
    ],
    [get, loading, toolbarState.selection.activeToolIds],
  );

  return {
    plugin,
    element: (
      <MilkdownToolbar
        container={toolbarState.container}
        tools={tools}
        selection={toolbarState.selection}
      />
    ),
  };
}

class MilkdownToolbarView implements PluginView {
  #content: HTMLDivElement;

  #tooltipProvider: TooltipProvider;

  #view: EditorView;

  #ctx: Ctx;

  #onStateChange: CreateMilkdownToolbarPluginOptions["onStateChange"];

  #handleBlur: () => void;

  constructor(
    ctx: Ctx,
    view: EditorView,
    options: CreateMilkdownToolbarPluginOptions,
  ) {
    const content = document.createElement("div");
    content.className =
      "milkdown-toolbar pointer-events-none absolute z-50 data-[show=false]:hidden";

    this.#content = content;
    this.#view = view;
    this.#ctx = ctx;
    this.#onStateChange = options.onStateChange;

    this.#tooltipProvider = new TooltipProvider({
      content,
      debounce: 20,
      offset: 18,
      shift: { padding: 8 },
      floatingUIOptions: { placement: "bottom" },
      shouldShow(currentView: EditorView) {
        return shouldShowToolbar(currentView, content);
      },
    });

    this.#handleBlur = () => {
      this.#tooltipProvider.hide();
    };

    view.dom.addEventListener("blur", this.#handleBlur, true);

    this.#publishState(view);
    this.update(view);
  }

  #publishState(view: EditorView) {
    this.#onStateChange({
      container: this.#content,
      selection: getSelectionSnapshot(this.#ctx, view),
    });
  }

  update = (view: EditorView, prevState?: EditorState) => {
    this.#view = view;
    this.#tooltipProvider.update(view, prevState);
    this.#publishState(view);
  };

  destroy = () => {
    this.#view.dom.removeEventListener("blur", this.#handleBlur, true);
    this.#onStateChange(EMPTY_TOOLBAR_STATE);
    this.#tooltipProvider.destroy();
    this.#content.remove();
  };
}

export function createMilkdownToolbarPlugin(
  options: CreateMilkdownToolbarPluginOptions,
) {
  return $prose((ctx) => {
    return new Plugin({
      key: new PluginKey("GAKUGO_MILKDOWN_TOOLBAR"),
      view: (view) => new MilkdownToolbarView(ctx, view, options),
    });
  });
}
