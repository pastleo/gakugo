# Notebook Collaborative Editing Architecture

This document is the concise architecture guide for AI agents working on notebook collaboration.
It summarizes the current runtime-first model and the protocol shapes agents should preserve.

## High-level model

Notebook editing and sync logic is intentionally separated into 3 layers:

1. view layer
   - `GakugoWeb.UnitLive.ShowEdit`
   - React editor and LiveView hook code
   - owns transport, UI shell behavior, local browser interaction
   - should not interact with `Gakugo.Db` directly during editing

2. notebook runtime layer
   - `Gakugo.Notebook.*` / `Gakugo.Learning.Notebook.*`
   - `Gakugo.Learning.Notebook.UnitSession` is the canonical runtime controller for a unit
   - owns canonical in-memory notebook state, intent handling, runtime mutation, versioning, broadcasts, and persistence scheduling

3. persistence layer
   - `Gakugo.Db.*`
   - owns Ecto/database reads and writes
   - initializes runtime state and persists downstream changes

Core direction:
- collaboration is unit-scoped via PubSub topic `unit:notebook:{unit_id}`
- focus is not part of the server mutation contract
- canonical `apply_intent` is the main mutation entrypoint
- `move_item` is first-class, including cross-page movement
- `initial_pages_json` is mount-time hydration only
- runtime state is read from `UnitSession.snapshot/1` and persisted downstream instead of treating DB state as the live editing owner

## Ownership boundaries

### View layer

- React constructs canonical `apply_intent` payloads directly for notebook/editor actions
- LiveView acts primarily as a transport and shell bridge
- sender replies and peer updates are applied through shared browser update handling
- page ordering affordances such as move-up/move-down are derived client-side from page order, not sent by the server

### Runtime layer

- `UnitSession` is the canonical runtime mutation owner
- it handles intent grammar, editor delegation, page/meta/page-list mutations, page-local version tracking on runtime page maps, snapshot generation, broadcasts, and canonical result construction
- most page-content tree editing is delegated to `Gakugo.Learning.Notebook.Editor.apply/2`
- cross-page `move_item` is orchestrated directly in `UnitSession`

### Persistence layer

- DB/Ecto reads are for initialization and persistence workflows
- DB writes are downstream persistence, not interactive editing ownership
- new editing logic should align with runtime-first state ownership

## Protocol layers

Keep these structures conceptually separate:

1. intent
   - browser/React requests an operation via `apply_intent`

2. reply envelope
   - LiveView returns sender-local status/update payloads

3. update packet
   - canonical inner state-update payload reused by sender replies and peer broadcasts

Prefer this principle:

> one canonical update packet, many transport envelopes

## Runtime item shape

Current protocol direction for editable notebook items:

```json
{
  "id": "uuid",
  "text": "plain text / markdown projection",
  "depth": 0,
  "flashcard": false,
  "answer": false,
  "yStateAsUpdate": "<opaque serialized editor state>"
}
```

Key rules:
- `text` is the canonical projected plain-text/markdown used for persistence and non-editor surfaces
- `yStateAsUpdate` is an opaque editor snapshot blob produced by the server/runtime hydration path or by the Milkdown/Yjs client on edits
- the server stores and rebroadcasts `yStateAsUpdate` but should not interpret editor internals from it
- `yStateAsUpdate` is expected to be non-null everywhere in the app

## Text editing actions

Two distinct editing action families share the `page_content` scope:

### `set_text`

Plain-text replacement for non-editor surfaces (AI generation, bulk import, etc.).

```json
{
  "scope": "page_content",
  "action": "set_text",
  "target": { "page_id": 456, "item_id": "..." },
  "payload": { "text": "replacement text" }
}
```

Server-side direction:
- update `item.text`
- rebuild `item.yStateAsUpdate` from `text` using the runtime hydration helper
- the rebuilt state should come from the server-side `y_ex` XML path, not from the client

### `text_collab_update`

Collaborative editor update from Milkdown/editor clients.
Carries the latest opaque editor-state blob plus the required text projection.

```json
{
  "scope": "page_content",
  "action": "text_collab_update",
  "target": { "page_id": 456, "item_id": "..." },
  "payload": {
    "y_state_as_update": "<opaque serialized editor state>",
    "text": "current markdown/plain projection"
  }
}
```

Server-side direction:
- require both `payload.y_state_as_update` and `payload.text`
- store `item.text = payload.text`
- store `item.yStateAsUpdate = payload.y_state_as_update`
- do not interpret, merge, or reconstruct editor internals on the server

## Data structures

### Intent

Intent is what the client wants to do.

```json
{
  "scope": "page_content | page_meta | unit_meta | page_list",
  "action": "string action name",
  "target": {
    "unit_id": 123,
    "page_id": 456,
    "item_id": "optional-item-id"
  },
  "version": {
    "local": 12,
    "source": 11
  },
  "nodes": [],
  "payload": {
    "text": "...",
    "title": "...",
    "direction": "up",
    "source_item_id": "...",
    "y_state_as_update": "..."
  },
  "meta": {
    "client": "react"
  }
}
```

Notes:
- React constructs these payloads in `assets/js/notebook-editor.tsx` and the rebuilt notebook editor tree under `assets/js/feat-components/notebook-editor*`
- `nodes` still appears in some `page_content` intents because current page-content application still uses it
- `version.source` is used in some move flows
- runtime page identity is just `page_id`
- runtime page version is stored directly on each runtime page as `page.version`

Current main intent families:
- `page_content`
- `page_meta`
- `unit_meta`
- `page_list`

Current `handle_intent` scope/action pairs:

- `page_content`
  - `set_text` — plain text replacement; rebuilds opaque editor state from text on the server
  - `text_collab_update` — stores opaque editor state plus required text projection
  - `toggle_flag`
  - `insert_above`
  - `insert_below`
  - `insert_child_below`
  - `indent_item` - move the item only
  - `outdent_item` - move the item only
  - `indent_subtree` - subtree-aware indent
  - `outdent_subtree` - subtree-aware outdent
  - `add_root_item`
  - `remove_item`
  - `append_many`
  - `insert_many_after`
  - `move_item`
- `page_meta`
  - `set_page_title`
- `unit_meta`
  - `update_unit_meta`
- `page_list`
  - `add_page`
  - `delete_page`
  - `move_page`

### Reply envelope

Reply envelope is what the browser receives back from LiveView after `apply_intent`.

```json
{
  "status": "updated | noop | invalid_params | error",
  "update": {
    "kind": "..."
  },
  "reason": "optional string reason"
}
```

Success example:

```json
{
  "status": "updated",
  "update": {
    "kind": "page_updated",
    "page": {}
  }
}
```

Invalid params example:

```json
{
  "status": "invalid_params",
  "reason": "invalid_params"
}
```

### Update packet

Update packet is the canonical inner state-update payload reused by:
- sender reply envelopes
- peer browser update events via `react:update`

Common update kinds:
- `page_updated`
- `pages_list_updated`
- `unit_meta_updated`
- `page_item_updated`

Page payloads inside update packets and snapshots are plain runtime page maps. They include `id`, `title`, `version`, `items`, and persisted page metadata needed by the editor/runtime. They do not include server-derived UI booleans such as `can_move_up` or `can_move_down`.

Examples:

```json
{
  "kind": "page_updated",
  "page": {}
}
```

```json
{
  "kind": "pages_list_updated",
  "pages": []
}
```

```json
{
  "kind": "unit_meta_updated",
  "unit": {
    "id": 123,
    "title": "...",
    "from_target_lang": "ja"
  }
}
```

## Request/update flow

### Browser to server

- React builds intents in the rebuilt notebook editor tree under `assets/js/feat-components/notebook-editor*`
- the thin LiveView hook lives in `assets/js/notebook-editor.tsx`
- transport call is `pushEvent("apply_intent", intent, reply => ...)`

### Server handling

- `GakugoWeb.UnitLive.ShowEdit` handles `apply_intent`
- it delegates to `UnitSession.apply_intent(unit_id, actor_id, params)`

### Sender-local updates

- LiveView replies with a reply envelope
- the hook applies it through `applyIntentReply(reply)`
- reply updates and peer updates both converge on `applyUpdate(update)`

### Peer updates

- LiveView pushes peer updates with `push_event(socket, "react:update", %{update: update})`
- the hook listens for `react:update`
- the hook applies the inner packet through the same `applyUpdate(update)` path

## Milkdown collab integration (experimental)

The experimental Milkdown editor path uses `@milkdown/plugin-collab` to bind each item's `Y.Doc` ProseMirror fragment to Milkdown via `collabService.bindXmlFragment(doc.getXmlFragment("prosemirror"))`:

- one `Y.Doc` per item, created in `item-editor.tsx` via `createDocFromSnapshot`
- local edits flow: Milkdown → `ySyncPlugin` → `prosemirror` fragment update → `doc.on("update")` → `text_collab_update` intent
- remote updates flow: `UnitSession` broadcast → `applyUpdate` to local `Y.Doc` → `ySyncPlugin` updates Milkdown view automatically
- initial content is expected to arrive from the server already hydrated in `item.yStateAsUpdate`
- the client no longer seeds content with `collabService.applyTemplate`

## Important collaboration rules for agents

- keep LiveView thin; do not move notebook ownership back into `ShowEdit`
- keep React and `UnitSession` speaking the same canonical intent/update protocol
- do not introduce direct `Gakugo.Db` editing access from LiveView/React flows
- prefer reading notebook state from runtime snapshots/state, not from ad hoc DB reads during editing
- treat `move_item` as a special first-class action, especially for cross-page movement
- preserve shared update handling for sender replies and peer broadcasts

## Practical reading order

1. `AGENTS.md`
2. `docs/notebook-collaborative-editing.md`
3. inspect code entry points:
   - `lib/gakugo/notebook/unit_session.ex`
   - `lib/gakugo/notebook/editor.ex`
   - `lib/gakugo/notebook/outline.ex`
   - `lib/gakugo_web/live/unit_live/show_edit.ex`
   - `assets/js/notebook-editor.tsx`
   - `assets/js/feat-components/notebook-editor.tsx`
   - `assets/js/feat-components/notebook-editor/page-card/item-editor.tsx`
   - `assets/js/utils/y-doc.ts`
