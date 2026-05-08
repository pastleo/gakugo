# Notebook Typing Performance

This note records the current performance-sensitive shape of the notebook editor.
The goal is to keep local typing smooth even for units with many pages/items and a very large DOM.

## Key Principles

- Local Milkdown/Yjs editing must stay immediate and should not wait for LiveView/server round trips.
- `textCollabUpdate` is intentionally throttled and coalesced before crossing the LiveView boundary.
- Server-owned `editedAt` timestamps are render invalidation metadata for pages/items; they are not persistence timestamps.
- React editor components should subscribe to the smallest practical slice of editor state.
- Phoenix LiveView should act as a transport/shell bridge and should not touch the large React editor subtree during typing.

## Implemented Shape

### Text Collaboration Throttle

`assets/js/feat-components/notebook-editor/page-card/item-editor/milkdown.tsx` throttles `textCollabUpdate` to reduce LiveView traffic, UnitSession work, peer broadcasts, and autosave pressure.

Important behavior:

- send a leading update so peers see edits quickly
- keep a trailing latest-state flush inside the throttle window
- flush pending updates on blur/unmount
- preserve the existing protocol shape: send both `text` and `y_state_as_update`

### Runtime `editedAt`

Runtime pages/items include `editedAt` millisecond timestamps.

Use them for UI invalidation only:

- `page.editedAt` tells page shells when page-visible content/order/meta changed
- `item.editedAt` tells item shells when item-visible content/meta/order context changed
- do not use `editedAt` as a DB `updated_at` replacement
- clients should not author `editedAt` in intents

### React Store And Selectors

The editor still stores page-shaped canonical data, but rendering avoids broad subscriptions where possible.

Current direction:

- `NotebookEditorSurface` renders pages from stable page summary keys containing `pageId` and `editedAt`
- `PageCard` takes `pageId`, `editedAt`, `pageIndex`, and `pageCount`, then selects its page internally
- `ItemEditor` takes `pageId`, `itemId`, `editedAt`, and `itemIndex`, then selects its item internally
- client-only helpers and menus use `useNotebookEditorActions()` instead of subscribing to full editor state
- drag/drop reads latest pages from `client.getState()` at drop time instead of subscribing to the full `pages` array
- update reconciliation preserves unchanged page/item object identity so selectors do not rerender unnecessarily

Avoid selectors that allocate fresh objects/arrays every snapshot unless they use a stable equality strategy. React external-store snapshots must be cached/stable; otherwise React can enter an infinite update loop.

### LiveView Boundary

The LiveView hook transport element is intentionally separate from the React mount root.

Current shape in `GakugoWeb.UnitLive.ShowEdit`:

- `#notebook-editor-bridge` owns `phx-hook="NotebookEditorPhxHook"` and stays empty
- `#notebook-editor-root` is a sibling `phx-update="ignore"` element where React mounts

This prevents Phoenix loading/ref attributes from landing on the large React subtree. In traces, putting the hook directly on the React root caused expensive style recalculation across tens of thousands of DOM elements during typing.

LiveView also avoids assigning notebook page data on normal page/item text updates. React receives canonical replies/updates and owns the interactive editor state. LiveView refreshes page data only when server-rendered UI needs it, such as opening the flashcard drawer.

## Trace Symptoms To Watch

If typing regresses, record a Chrome performance trace and check for:

- long `EventDispatch` entries for keyboard/text input
- large `UpdateLayoutTree` / `Recalculate style` under input events
- `morphdom-esm.js` hotspots such as `indexTree`, `getNodeKey`, or `isPhxDestroyed`
- Phoenix `putRef`, `pushWithReply`, or loading/ref operations touching the React editor root
- React selectors returning uncached fresh snapshots

Common root causes:

- broad `pages` subscriptions in deeply nested components
- passing full page/item objects through many render levels
- LiveView assigning page data on every text update
- placing `phx-hook` directly on the large React root
- selectors that allocate new arrays/objects without shallow equality
