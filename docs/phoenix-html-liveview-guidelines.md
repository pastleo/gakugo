# Phoenix HTML and LiveView Guidelines

This file holds the longer Phoenix HTML / HEEx / LiveView reference guidance that was previously embedded in `AGENTS.md`.

Use `AGENTS.md` for the concise project-local rules first. Reach for this file when you need the longer reference details and examples.

## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or `.html.heex` files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponents, and all modules that do `use MyAppWeb, :html`

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never** use `else if` or `elseif` in Elixir. **Always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx requires special tag annotation if you want to insert literal curly braces like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you **must** annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. Use class lists for conditional class composition.
- **Never** use `<% Enum.each %>` or non-`for` comprehensions for generating template content. **Always** use `<%= for item <- @collection do %>`.
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use HEEx comment syntax.
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but `<%= %>` only works within tag bodies. Use `{...}` within attributes.

## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions. **Always** use `<.link navigate={href}>`, `<.link patch={href}>`, `push_navigate`, and `push_patch`.
- **Avoid LiveComponents** unless you have a strong, specific need for them.
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix.

### LiveView streams

- **Always** use LiveView streams for collections when appropriate to avoid memory ballooning.
- When using `stream/3`, the template must:
  1. set `phx-update="stream"` on the parent container with a DOM id
  2. render `@streams.stream_name` and use the per-item DOM id
- Streams are not enumerable. To filter/prune/refresh a stream, refetch and restream with `reset: true`.
- Streams do not directly support counting or empty states. Track counts separately and structure empty states carefully.
- When assign changes must affect streamed items, re-stream the items.
- **Never** use deprecated `phx-update="append"` or `phx-update="prepend"`.

### LiveView JavaScript interop

- When using `phx-hook="MyHook"` and the hook manages its own DOM, **always** also use `phx-update="ignore"`.
- **Always** provide a unique DOM id alongside `phx-hook`.
- Do not embed raw `<script>` tags in HEEx. Use colocated hooks or external hook modules.
- External hooks belong in `assets/js/` and are passed to the `LiveSocket` constructor.
- Use `push_event/3` for server-to-client events and `this.handleEvent` on the client.
- Use `this.pushEvent` / `{:reply, ...}` for client-to-server event/reply flows.

### LiveView tests

- Prefer `Phoenix.LiveViewTest` and `LazyHTML` selectors/assertions.
- Use explicit DOM IDs in templates to support reliable tests.
- Favor outcome-oriented assertions over fragile full-HTML expectations.

### Form handling

- Always assign forms via `to_form/2` in the LiveView module.
- In templates, always use `<.form for={@form}>` and `<.input field={@form[:field]}>`.
- Never drive forms directly from changesets in templates.
