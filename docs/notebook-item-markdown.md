# Notebook Item Markdown

This document describes notebook item markdown syntax that is intentionally
customized by Gakugo beyond normal CommonMark / GFM behavior.

## Current custom syntax

### Inline highlight

Basic inline highlight uses `==...==`:

```md
==highlight==
```

This is parsed as a highlight mark in the frontend Milkdown editor and as a
Gakugo highlight node in the Elixir markdown pipeline.

### Highlight attrs

Highlight attrs are encoded as an HTML comment immediately after the opening
`==` marker:

```md
==<!-- {"textColor":"amber","backgroundColor":"blue"} -->highlight==
```

Current supported attrs:

- `textColor`: notebook color name
- `backgroundColor`: notebook color name or `"none"`

Examples:

```md
==<!-- {"textColor":"amber"} -->highlight==
==<!-- {"backgroundColor":"blue"} -->highlight==
==<!-- {"textColor":"amber","backgroundColor":"none"} -->highlight==
```

## Semantics

### Plain highlight

```md
==highlight==
```

- no explicit attrs are stored
- renders as a normal `<mark>...</mark>` in the editor / HTML renderers
- browser/default styling provides the visible highlight background

### Explicit transparent background

```md
==<!-- {"backgroundColor":"none"} -->highlight==
```

- `backgroundColor: "none"` is a highlight-local value
- it is not part of the shared notebook color palette
- it means the highlight keeps mark semantics while rendering with a
  transparent background

This is mainly used for text-only highlight styling, for example:

```md
==<!-- {"textColor":"amber","backgroundColor":"none"} -->highlight==
```

## Toolbar behavior

The Milkdown floating toolbar treats highlight formatting like this:

- setting only text color produces `backgroundColor: "none"`
- setting a real background color preserves any existing text color
- clearing background when a text color exists returns to
  `backgroundColor: "none"`
- clearing both text and background removes the highlight mark entirely,
  returning to normal text

That means a full reset should become:

```md
text
```

instead of an internal highlight form such as:

```md
==<!-- {"backgroundColor":"none"} -->text==
```

## Validation

- real color values are validated against `priv/notebook_colors.json`
- `"none"` is accepted only for inline highlight `backgroundColor`
- invalid color names are ignored during parsing / normalization

## Frontend implementation

Frontend support lives in the notebook item Milkdown editor pipeline.

Current implementation includes:

- micromark parsing for `==...==`
- mdast parse / serialize support for highlight nodes
- Milkdown mark schema and toolbar editing behavior
- DOM rendering as `<mark data-gakugo-highlight ...>` with notebook color
  classes

## Elixir implementation

Notebook markdown on the Elixir side must go through
`Gakugo.Notebook.Markdown`, not direct `MDEx` calls.

Use:

- `Gakugo.Notebook.Markdown.parse_document/1` instead of
  `MDEx.parse_document!/2` for notebook content
- `Gakugo.Notebook.Markdown.to_html/1` instead of `MDEx.to_html!/2` for
  notebook/user markdown rendering

Reason: `Gakugo.Notebook.Markdown` installs Gakugo-specific markdown behavior,
including inline highlight parsing/rendering and safety handling. Direct `MDEx`
usage will not understand `==...==` highlights and may either render raw syntax
or bypass project-specific sanitization expectations.

Current Elixir support includes:

- `Gakugo.Notebook.Markdown.HighlightPlugin`, which collapses parsed MDEx text /
  HTML-comment nodes into `Gakugo.Notebook.Markdown.HighlightNode`
- Yjs hydration in `Gakugo.Notebook.Item.YStateAsUpdate`, which converts
  highlight nodes into ProseMirror/Yjs `highlight` marks
- HTML rendering through `Gakugo.Notebook.Markdown.to_html/1`, which preserves
  generated `<mark>` tags while filtering raw user HTML and sanitizing unsafe
  markdown URLs
- Anki rendering through `Gakugo.Anki.Markdown.render_html/1`, which delegates
  to `Gakugo.Notebook.Markdown.to_html/1`
- Anki preview summaries through `Gakugo.Anki.Preview`, which parses notebook
  markdown and extracts text from the parsed document instead of regex-stripping
  raw markdown

### `unsafe: true` note

`Gakugo.Notebook.Markdown.to_html/1` renders with `render: [unsafe: true]` only
after the custom pipeline has removed raw user HTML. This is needed because the
highlight renderer intentionally creates generated `<mark>` HTML nodes, and MDEx
only emits HTML nodes when unsafe rendering is enabled.

Do not call `MDEx.to_html!(..., render: [unsafe: true])` directly on notebook or
user content. Use `Gakugo.Notebook.Markdown.to_html/1` so generated highlight
HTML survives while raw user HTML and unsafe URLs are handled consistently.
