import type { Ctx } from "@milkdown/ctx";
import { markRule } from "@milkdown/prose";
import type { Mark } from "@milkdown/prose/model";
import { $inputRule, $markSchema, $remark } from "@milkdown/utils";
import { resolveAll } from "micromark-util-resolve-all";
import type {
  Construct,
  Effects,
  Extension as MicromarkExtension,
  Resolver,
  State,
  TokenizeContext,
} from "micromark-util-types";
import type {
  CompileContext,
  Extension as FromMarkdownExtension,
  Handle as FromMarkdownHandle,
} from "mdast-util-from-markdown";
import type {
  ConstructName,
  Handle as ToMarkdownHandle,
  Options as ToMarkdownExtension,
} from "mdast-util-to-markdown";
import type { Processor } from "unified";
import {
  isNotebookColorName,
  notebookItemBackgroundColorClass,
  notebookItemTextColorClass,
  type NotebookColorName,
} from "../../../../../utils/notebook-colors";

declare module "micromark-util-types" {
  interface TokenTypeMap {
    highlight: "highlight";
    highlightSequence: "highlightSequence";
    highlightText: "highlightText";
  }
}

declare module "mdast-util-to-markdown" {
  interface ConstructNameMap {
    highlight: "highlight";
  }
}

export interface NotebookHighlightAttrs {
  textColor?: NotebookColorName | null;
  backgroundColor?: NotebookColorName | "none" | null;
}

interface MarkdownNode {
  [key: string]: unknown;
  type: string;
  value?: string;
  children?: MarkdownNode[];
  textColor?: unknown;
  backgroundColor?: unknown;
}

const equalsCode = 61;
const highlightType = "highlight";

const constructsWithoutHighlight: ConstructName[] = [
  "autolink",
  "destinationLiteral",
  "destinationRaw",
  "reference",
  "titleQuote",
  "titleApostrophe",
];

export function normalizeNotebookHighlightAttrs(
  attrs: Record<string, unknown> | null | undefined,
): NotebookHighlightAttrs {
  if (!attrs) return {};

  return {
    textColor: isNotebookColorName(attrs.textColor) ? attrs.textColor : null,
    backgroundColor:
      attrs.backgroundColor === "none"
        ? "none"
        : isNotebookColorName(attrs.backgroundColor)
          ? attrs.backgroundColor
          : null,
  };
}

export function serializeNotebookHighlightComment(
  attrs: NotebookHighlightAttrs,
) {
  const payload: Partial<
    Record<keyof NotebookHighlightAttrs, NotebookColorName | "none">
  > = {};

  const textColor = attrs.textColor;
  const backgroundColor = attrs.backgroundColor;

  if (textColor && isNotebookColorName(textColor)) {
    payload.textColor = textColor;
  }

  if (backgroundColor === "none" || isNotebookColorName(backgroundColor)) {
    payload.backgroundColor = backgroundColor;
  }

  return Object.keys(payload).length > 0
    ? `<!-- ${JSON.stringify(payload)} -->`
    : "";
}

export function parseNotebookHighlightComment(value: string) {
  const match = value.match(/^<!--\s*(\{[\s\S]*\})\s*-->$/);
  if (!match) return null;

  try {
    return normalizeNotebookHighlightAttrs(
      JSON.parse(match[1]) as Record<string, unknown>,
    );
  } catch {
    return null;
  }
}

export function notebookHighlightMicromark(): MicromarkExtension {
  const tokenizer: Construct = {
    name: "notebookHighlight",
    tokenize: tokenizeHighlight,
    resolveAll: resolveAllHighlight,
  };

  return {
    text: {
      [equalsCode]: tokenizer,
    },
    insideSpan: {
      null: [tokenizer],
    },
  };
}

const closeSequence: Construct = {
  tokenize(effects, ok, nok) {
    return start;

    function start(code: number | null) {
      if (code !== equalsCode) return nok(code);
      effects.consume(code);
      return second;
    }

    function second(code: number | null) {
      if (code !== equalsCode) return nok(code);
      effects.consume(code);
      return ok;
    }
  },
};

function tokenizeHighlight(
  this: TokenizeContext,
  effects: Effects,
  ok: State,
  nok: State,
): State {
  const previous = this.previous;
  let size = 0;
  let hasContent = false;

  return start;

  function start(code: number | null) {
    if (previous === equalsCode) return nok(code);

    effects.enter("highlight");
    effects.enter("highlightSequence");
    return opening(code);
  }

  function opening(code: number | null) {
    if (code !== equalsCode) return nok(code);

    effects.consume(code);
    size += 1;

    if (size === 2) {
      effects.exit("highlightSequence");
      const token = effects.enter("highlightText");
      token.contentType = "text";
      return content;
    }

    return opening;
  }

  function content(code: number | null): State | undefined {
    if (code === null) return nok(code);

    if (code === equalsCode) {
      return effects.check(closeSequence, close, data)(code);
    }

    return data(code);
  }

  function data(code: number | null): State | undefined {
    if (code === null) return nok(code);

    hasContent = true;
    effects.consume(code);
    return content;
  }

  function close(code: number | null): State | undefined {
    if (!hasContent) return nok(code);

    effects.exit("highlightText");
    effects.enter("highlightSequence");
    effects.consume(code);
    return closeSecond;
  }

  function closeSecond(code: number | null): State | undefined {
    effects.consume(code);
    effects.exit("highlightSequence");
    effects.exit("highlight");
    return ok;
  }
}

const resolveAllHighlight: Resolver = (events, context) => {
  const insideSpan = context.parser.constructs.insideSpan.null;
  if (!insideSpan) return events;

  let index = -1;
  while (++index < events.length) {
    if (
      events[index][0] !== "enter" ||
      events[index][1].type !== "highlightText"
    ) {
      continue;
    }

    let exitIndex = index;
    while (++exitIndex < events.length) {
      if (
        events[exitIndex][0] === "exit" &&
        events[exitIndex][1].type === "highlightText"
      ) {
        const resolved = resolveAll(
          insideSpan,
          events.slice(index + 1, exitIndex),
          context,
        );
        events.splice(index + 1, exitIndex - index - 1, ...resolved);
        index += resolved.length + 1;
        break;
      }
    }
  }

  return events;
};

export function notebookHighlightFromMarkdown(): FromMarkdownExtension {
  return {
    canContainEols: ["highlight"],
    enter: { highlight: enterHighlight },
    exit: { highlight: exitHighlight },
  };
}

const enterHighlight: FromMarkdownHandle = function (
  this: CompileContext,
  token,
) {
  this.enter({ type: highlightType, children: [] } as never, token);
};

const exitHighlight: FromMarkdownHandle = function (
  this: CompileContext,
  token,
) {
  const node = this.stack[this.stack.length - 1] as MarkdownNode;
  const firstChild = node.children?.[0];

  if (firstChild?.type === "html" && typeof firstChild.value === "string") {
    const attrs = parseNotebookHighlightComment(firstChild.value);
    if (attrs) {
      node.children = node.children?.slice(1) ?? [];
      node.textColor = attrs.textColor;
      node.backgroundColor = attrs.backgroundColor;
    }
  }

  this.exit(token);
};

export function notebookHighlightToMarkdown(): ToMarkdownExtension {
  return {
    unsafe: [
      {
        character: "=",
        inConstruct: "phrasing",
        notInConstruct: constructsWithoutHighlight,
      },
    ],
    handlers: { highlight: handleHighlight } as Record<
      string,
      ToMarkdownHandle
    >,
  };
}

const handleHighlight = ((node, _, state, info) => {
  const attrs = normalizeNotebookHighlightAttrs(
    node as Record<string, unknown>,
  );
  const marker = "==";
  const comment = serializeNotebookHighlightComment(attrs);
  const tracker = state.createTracker(info);
  const exit = state.enter("highlight" as ConstructName);
  let value = tracker.move(marker + comment);
  value += state.containerPhrasing(node, {
    ...tracker.current(),
    before: value,
    after: "=",
  });
  value += tracker.move(marker);
  exit();
  return value;
}) as ToMarkdownHandle & { peek: ToMarkdownHandle };

handleHighlight.peek = () => "=";

export function remarkNotebookHighlight(this: Processor) {
  const data = this.data();
  const micromarkExtensions =
    data.micromarkExtensions || (data.micromarkExtensions = []);
  const fromMarkdownExtensions =
    data.fromMarkdownExtensions || (data.fromMarkdownExtensions = []);
  const toMarkdownExtensions =
    data.toMarkdownExtensions || (data.toMarkdownExtensions = []);

  micromarkExtensions.push(notebookHighlightMicromark());
  fromMarkdownExtensions.push(notebookHighlightFromMarkdown());
  toMarkdownExtensions.push(notebookHighlightToMarkdown());
}

export const notebookHighlightRemarkPlugin = $remark(
  "notebookHighlight",
  () => remarkNotebookHighlight,
);

function normalizeMarkAttrs(mark: Mark) {
  return normalizeNotebookHighlightAttrs(mark.attrs as Record<string, unknown>);
}

function hasVisibleHighlightAttrs(attrs: NotebookHighlightAttrs) {
  return Boolean(
    (attrs.textColor && isNotebookColorName(attrs.textColor)) ||
      (attrs.backgroundColor && isNotebookColorName(attrs.backgroundColor)),
  );
}

export const notebookHighlightSchema = $markSchema(
  "highlight",
  (_ctx: Ctx) => ({
    attrs: {
      textColor: {
        default: null,
        validate: (value: unknown) =>
          value === null || isNotebookColorName(value),
      },
      backgroundColor: {
        default: null,
        validate: (value: unknown) =>
          value === null || value === "none" || isNotebookColorName(value),
      },
    },
    parseDOM: [
      {
        tag: "mark[data-gakugo-highlight]",
        getAttrs: (dom) =>
          normalizeNotebookHighlightAttrs({
            textColor: (dom as HTMLElement).dataset.textColor,
            backgroundColor: (dom as HTMLElement).dataset.backgroundColor,
          }),
      },
    ],
    toDOM: (mark) => {
      const attrs = normalizeMarkAttrs(mark);
      const plainHighlight = !attrs.textColor && !attrs.backgroundColor;
      const appliedTextColor = isNotebookColorName(attrs.textColor)
        ? attrs.textColor
        : null;
      const appliedBackgroundColor = isNotebookColorName(attrs.backgroundColor)
        ? attrs.backgroundColor
        : null;
      const domAttrs: Record<string, string> = {
        "data-gakugo-highlight": "true",
      };
      const resetStyles = [
        !plainHighlight && !appliedTextColor ? "color: inherit;" : null,
        attrs.backgroundColor === "none"
          ? "background-color: transparent;"
          : null,
      ].filter(Boolean);
      const classes = [
        notebookItemTextColorClass(appliedTextColor),
        notebookItemBackgroundColorClass(appliedBackgroundColor),
      ].filter(Boolean);

      if (attrs.textColor) {
        domAttrs["data-text-color"] = attrs.textColor;
      }
      if (attrs.backgroundColor) {
        domAttrs["data-background-color"] = attrs.backgroundColor;
      }
      if (resetStyles.length > 0) domAttrs.style = resetStyles.join(" ");
      if (classes.length > 0) domAttrs.class = classes.join(" ");

      return ["mark", domAttrs];
    },
    parseMarkdown: {
      match: (node) => node.type === highlightType,
      runner: (state, node, markType) => {
        state.openMark(
          markType,
          normalizeNotebookHighlightAttrs(node as Record<string, unknown>),
        );
        state.next(((node as MarkdownNode).children ?? []) as never);
        state.closeMark(markType);
      },
    },
    toMarkdown: {
      match: (mark) => mark.type.name === "highlight",
      runner: (state, mark) => {
        const attrs = normalizeMarkAttrs(mark);
        const plainHighlight = !attrs.textColor && !attrs.backgroundColor;

        if (!plainHighlight && !hasVisibleHighlightAttrs(attrs)) {
          return;
        }

        state.withMark(mark, highlightType, undefined, attrs as never);
      },
    },
  }),
);

export const notebookHighlightInputRule = $inputRule((ctx) => {
  return markRule(
    /(?:^|[^=])(==(<!--\s*\{[\s\S]*?\}\s*-->)?([\s\S]+?)==)$/,
    notebookHighlightSchema.type(ctx),
    {
      getAttr: (match) => {
        const comment = match[2];
        return typeof comment === "string"
          ? (parseNotebookHighlightComment(comment) ?? {})
          : {};
      },
      updateCaptured: ({ fullMatch, start }) => {
        if (fullMatch.startsWith("==")) {
          return { fullMatch, start };
        }

        return {
          fullMatch: fullMatch.slice(1),
          start: start + 1,
        };
      },
    },
  );
});

export const notebookHighlight = [
  notebookHighlightRemarkPlugin,
  notebookHighlightSchema,
  notebookHighlightInputRule,
].flat();
