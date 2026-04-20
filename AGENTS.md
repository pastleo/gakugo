This is a web application written using the Phoenix web framework.

* this project is called Gakugo, a language learning system

## Anki Integration

Gakugo syncs flashcards to Anki via [anki-sync-server](https://github.com/ankicommunity/anki-sync-server) for mobile study.

### Architecture

```
Gakugo App (priv/anki/collection.anki2)
    ↓ (anki Python package via Pythonx)
anki-sync-server (Docker, holds its own collection)
    ↓ (Anki sync protocol)
Mobile Anki App
```

**Key insight**: Gakugo maintains its **own** `collection.anki2` file and uses the `anki` Python library's sync functions to push changes to the sync server. The server and mobile app each have their own collections that sync via the standard Anki protocol.

### Key Files

- `lib/gakugo/anki/anki.py` - Python functions for Anki operations (CRUD, sync)
- `lib/gakugo/anki.ex` - GenServer wrapping Python calls via Pythonx
- `lib/gakugo/anki/sync_service.ex` - High-level sync logic:
  - Custom "Gakugo" note type with fields: `["Front", "Back", "GakugoId"]`
  - Builds cards from unit pages `items` (each `front: true` node becomes one card)
  - Uses the front node's descendants as card back content (occlusion-style)
  - Uses tags (`gakugo-id-unit-{unit_id}-path-{path}`) to track identity and prevent duplicates
  - Handles deletions by removing orphaned notes when notebook fronts are removed

### Sync Flow

1. `SyncService.sync_unit_to_anki/1` - Syncs a unit's notebook-derived flashcards to local Anki collection
   - Creates/updates notes based on stable notebook-path tags (`gakugo-id-unit-...-path-...`)
   - Front is rendered as nested HTML list with descendant back lines occluded and front highlighted
   - Back is generated from the front node's descendant text
2. `SyncService.sync_to_server/0` - Pushes local collection to anki-sync-server
3. Mobile Anki app syncs from the server

### Configuration

**Development** (config/dev.exs) - uses env vars with defaults:
```elixir
config :gakugo, Gakugo.Anki,
  collection_path: System.get_env("ANKI_COLLECTION_PATH", "priv/anki/collection.anki2"),
  sync_endpoint: System.get_env("ANKI_SYNC_ENDPOINT", "http://localhost:8080/"),
  sync_username: System.get_env("ANKI_SYNC_USERNAME", "dev"),
  sync_password: System.get_env("ANKI_SYNC_PASSWORD", "asdfasdf")
```

**Production** (config/runtime.exs) - env vars required:
- `ANKI_COLLECTION_PATH` (required): Path to the Anki collection file
- `ANKI_SYNC_ENDPOINT` (optional): URL of anki-sync-server
- `ANKI_SYNC_USERNAME` (optional): Sync server username
- `ANKI_SYNC_PASSWORD` (optional): Sync server password

Sync features are disabled if sync env vars are not set.

## Real-Time Collaboration (Notebook)

The collaborative-editing architecture has changed significantly and the old lock-based / narrow-event description is no longer accurate.

Read this file for the implemented architecture:
- `docs/notebook-collaborative-editing.md`

Durable truths to keep in mind:
- notebook editing/sync logic is intentionally separated into 3 layers:
  - view layer: LiveView + React are transport/UI shells and should not talk to `Gakugo.Db` directly during editing
  - notebook runtime layer: `Gakugo.Notebook.*` owns notebook runtime logic, with `Gakugo.Notebook.UnitSession` as the canonical runtime controller for a unit
  - persistence layer: `Gakugo.Db.*` owns Ecto/database reads and writes
- notebook collaboration is unit-scoped via PubSub topic `unit:notebook:{unit_id}`
- `Gakugo.Notebook.UnitSession` / `Gakugo.Learning.Notebook.UnitSession` is the canonical runtime mutation owner and holder of the canonical in-memory unit state
- React now constructs canonical `apply_intent` payloads directly for main notebook actions
- `GakugoWeb.UnitLive.ShowEdit` should be treated as a transport/shell bridge, not the source of collaboration truth
- `move_item` is a first-class canonical intent action, including cross-page movement
- sender replies and peer updates converge on shared canonical update handling through `react:update` / shared `applyUpdate(update)` logic
- runtime state is read from `UnitSession.snapshot/1`, then persisted downstream rather than treating DB state as the live editing owner
- structural editing keybindings/spec for the notebook editor live in `docs/notebook-structural-editing-keybindings.md`; keep focus choreography on the React side rather than the server

### Collaboration layers and protocol

- Keep these protocol layers conceptually separate:
  1. intent - browser/React requests an operation via `apply_intent`
  2. reply envelope - LiveView returns sender-local status/update payloads
  3. update packet - canonical inner update payload reused for sender replies and peer broadcasts
- Main current intent families:
  - `page_content`
  - `page_meta`
  - `unit_meta`
  - `page_list`
- `move_item` is special-cased as a first-class action because cross-page movement needs orchestration across source/target pages, versions, and persistence
- runtime page identity is just `page_id`
- runtime page version lives on the runtime page map itself as `page.version`
- page ordering UI affordances such as move-up/move-down should be derived client-side from page order, not emitted by the server
- Prefer the principle: one canonical update packet, many transport envelopes

### Collaboration ownership

- `GakugoWeb.UnitLive.ShowEdit` still owns shell-level assigns/forms and transport bridging, but should stay thin
- `UnitSession` owns intent handling, runtime mutation, version tracking, persistence scheduling, broadcast emission, snapshot generation, and canonical result construction
- After initialization, read/edit notebook state from canonical runtime state wherever possible; DB access is for init and downstream persistence, not interactive editing ownership

### Practical reading order

- `lib/gakugo/learning/notebook/unit_session.ex`
- `lib/gakugo_web/live/unit_live/show_edit.ex`
- `assets/js/notebook-editor.tsx`
- `assets/js/feat-components/notebook-editor.tsx`

### Flashcard/Answer rules

- `front: true` marks a notebook item as a flashcard source.
- Never allow nested flashcards: an item under a flashcard branch cannot be marked `front: true`.
- `answer: true` is allowed for descendants inside a flashcard branch.
- `answer: true` is also allowed on the flashcard item itself (`front: true`) when explicitly selected.

## Notebook-first AI / Action Direction

- Legacy model-centric entities (`Grammar`, `Vocabulary`, `Flashcard`) and their old CRUD/AI flow have been removed; keep all parse/generate/AI features notebook-native.
- Item-local parse/generate functionality now grows through the `Gakugo.NotebookAction.*` action layer instead of the old global import/generate drawer architecture.
- New notebook-native functionality should preserve this layered shape:
  - item-local UI shell (for example the `Parse / Generate` drawer)
  - frontend transport helper (`assets/js/utils/notebook-action-client.ts`)
  - notebook action web API
  - `Gakugo.NotebookAction.*`
  - canonical runtime mutation through `UnitSession.apply_intent(...)`
- The extra notebook action web API is intentional. Even though it is a second browser-facing command path, it should still converge into canonical runtime mutation through `UnitSession.apply_intent(...)`.
- Current notebook action entrypoint:
  - item-local `Parse / Generate` button in the item editor options menu
- Current implemented actions:
  - `parse as items`
  - `parse as flashcards`
- Planned future actions include things like:
  - sentence generation with AI
  - analysis with AI
  - "ask AI how to say this"
- Parse/generate/AI outputs should stay in notebook page/item structures so users can edit and collaborate in one place.
- Keep UI shell state thin. Do not re-bloat `UnitLive.ShowEdit` with the old form-heavy global drawer architecture.
- Use old git history only as behavioral reference when useful, not as the target structure.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- Put temporary local artifacts under `tmp/` so git status stays clean. This includes Playwright/debug outputs such as `.playwright-mcp/` snapshots/logs and ad-hoc files like `playwright-*.txt`.
- Prefer colocated parent/child file structure across the project when a module/component has a clear local subtree. Use the parent file as the primary module file, and place supporting children in a same-name directory instead of relying on `index`-style files. Example:

      some-dir/
        page-card.tsx
        page-card/
          item-row.tsx

  The same idea applies on the Elixir side when a parent module has closely related supporting files. Prefer this structure for clarity and local discoverability.

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### Tailwind CSS guidelines

- Use Tailwind CSS classes and small custom CSS rules to build polished, responsive interfaces.
- Dark mode / theming: this project uses daisyUI themes with the `data-theme` attribute (see `assets/css/app.css`). The Tailwind `dark:` variant is remapped to `[data-theme=dark]`, which means `dark:` classes do **not** behave correctly for the `auto` theme. Prefer daisyUI semantic color tokens instead of `dark:` variants:

  | Instead of | Use |
  |------------|-----|
  | `text-gray-900 dark:text-gray-100` | `text-base-content` |
  | `text-gray-500 dark:text-gray-400` | `text-base-content/60` |
  | `bg-white dark:bg-gray-800` | `bg-base-100` |
  | `bg-gray-100 dark:bg-gray-700` | `bg-base-200` |
  | `border-gray-200 dark:border-gray-700` | `border-base-300` |
  | `text-red-500 dark:text-red-400` | `text-error` |
  | `text-green-600 dark:text-green-400` | `text-success` |
  | `hover:bg-red-50 dark:hover:bg-red-900/30` | `hover:bg-error/10` |

- Tailwindcss v4 does not need `tailwind.config.js` in this setup. Maintain the import/source structure in `assets/css/app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/gakugo_web";

- Never use `@apply` in raw CSS.
- Prefer hand-written Tailwind-based UI over leaning on daisyUI components for page structure. Use daisyUI mainly for theme tokens and selective primitives.
- Only the `app.js` and `app.css` bundles are supported by default:
  - do not add external `<script src>` or stylesheet `<link href>` tags in layouts for frontend code
  - import JS dependencies into `app.js`
  - import CSS/plugin dependencies into `app.css`
  - never write inline `<script>` tags in HEEx templates

### TypeScript / React frontend guidelines

- Frontend checks live under `assets/` and should be used before finishing frontend work:
  - `npm run check` for read-only validation (`ts:check`, `eslint:check`, `prettier:check`)
  - `npm run format` to apply frontend formatting fixes (`eslint:format`, `prettier:format`)
- Prefer function components and Hooks. Do not introduce class components.
- Component modularization is encouraged: prefer one component per file.
- Use PascalCase for component names, and dash-case for filenames.
- Define explicit TypeScript types/interfaces for component props and shared domain shapes.
- Keep Phoenix/LiveView integration entrypoints thin. Hook/bootstrap files should mount React, bridge events, and pass initial data; feature logic belongs deeper in the React tree.
- Follow the current frontend structure direction:
  - `assets/js/feat-components/` for feature or application-specific UI
  - `assets/js/components/` for reusable, utility-like shared components
  - `assets/js/contexts/` for shared React contexts when state truly needs app-wide ownership
  - `assets/js/utils/` for generic frontend helpers
  - `assets/js/types/` for shared frontend/domain types when they are reused across features
- Shared components should stay generic. If a component knows too much about notebook/page/item workflow, it belongs in `feat-components/`, not `components/`.
- Keep React vs LiveView boundaries explicit:
  - LiveView owns shell/layout, server-rendered forms, initial hydration payloads, and transport bridge concerns
  - React owns rich editor interaction, local interaction state, and client-side view composition inside the mounted root
- Do not scatter LiveView transport details (`pushEvent`, reply envelopes, payload shaping) across presentational components. Keep protocol/integration logic close to the feature boundary.
- Prefer explicit domain types for notebook entities and protocol payloads instead of repeating anonymous inline object shapes across files.
- Keep state local by default; lift or introduce context only when multiple branches genuinely need shared ownership.
- Use relative imports unless path aliases are intentionally added later.
- Do not fight Prettier or duplicate formatting concerns in ESLint. Prettier owns formatting; ESLint owns correctness and code-quality rules.
- Shared frontend debug-only affordances should use `assets/js/utils/debug.ts` and the shared `?debug` URL param instead of feature-specific query params.

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

For the longer Phoenix HTML / HEEx / LiveView reference, read:
- `docs/phoenix-html-liveview-guidelines.md`

Project-local HTML / HEEx reminders:
- Use HEEx (`~H` / `.html.heex`), never `~E`.
- Use `to_form/2`, `<.form for={@form}>`, and `<.input field={@form[:field]}>` instead of driving templates directly from changesets.
- Give important interactive elements stable DOM IDs for tests and hooks.
- Use HEEx-native syntax correctly:
  - `{...}` for attribute interpolation
  - `<%= ... %>` for block constructs in tag bodies
  - `<%!-- ... --%>` for comments
- For multiple conditional classes, use HEEx class lists (`class={[...]}`).
- Prefer `for` comprehensions in templates over `Enum.each`.
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

For the longer Phoenix HTML / HEEx / LiveView reference, read:
- `docs/phoenix-html-liveview-guidelines.md`

Project-local LiveView reminders:
- Prefer `<.link navigate={...}>`, `<.link patch={...}>`, `push_navigate`, and `push_patch`; do not use deprecated redirect/patch helpers.
- Avoid LiveComponents unless there is a clear state or reuse need.
- When using `phx-hook`, always provide a stable DOM id; if the hook owns its DOM subtree, also use `phx-update="ignore"`.
- Keep LiveView as the shell/transport boundary and avoid pushing rich client logic into HEEx or LiveView when React already owns that UI surface.
- Use streams intentionally for large/interactive collections, and follow the proper `phx-update="stream"` + `@streams.*` structure.
- Test LiveViews with `Phoenix.LiveViewTest`, stable element IDs, and outcome-oriented assertions.
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->
