# Notebook structural editing keybindings

This file documents the structural editing keyboard behavior expected on the `UnitLive.ShowEdit` notebook editor surface.

Durable implementation note:
- focus targeting, focus restoration, and keyboard choreography should live on the React side
- server/runtime should continue to own canonical notebook mutation/state

## Keybinding spec

Semantic boundary detection for the Milkdown/ProseMirror item editor:
- `atStart`
  - `selection.from <= 1 && selection.to <= 1`
- `atEnd`
  - `selection.from + 1 >= doc.content.size && selection.to + 1 >= doc.content.size`

Notes:
- keybinding behavior should stay stable by cursor position and empty-item state
- do not swap `Enter` and `Shift+Enter` behavior based on multiline content
- soft-wrapped long content, explicit hard breaks, and multiple document blocks should all preserve the same structural keybinding mapping
- these values should be derived on demand inside the key handler rather than stored as long-lived editor state

Keybinding policy mapping:

- when cursor is at the end
  - `Enter` should call `insertChildBelow` and focus the new item
  - `Shift+Enter` inserts a newline character in the item
- when cursor is at the front
  - `Enter` should call `insertAbove` and focus the new item
  - `Shift+Enter` inserts a newline character in the item
- when cursor is in the middle
  - `Enter` inserts a newline character in the item
  - `Shift+Enter` should call `insertChildBelow` and focus the new item
- when the item is empty
  - if the item has a parent and is the last child
    - `Enter` should call `outdentItem`
  - else
    - `Enter` should call `insertBelow` and focus the new item
  - `Shift+Enter` inserts a newline character in the item
- when the item is empty or cursor is at the front
  - `ArrowUp` focuses the visually previous item and put cursor at the end
- when the item is empty or cursor is at the end
  - `ArrowDown` focuses the visually next item
- if it has no child
  - `Backspace` should call `removeItem` and focus the previous item at the end
  - `Delete` should call `removeItem` and focus the next item
- `Tab` should call `indentItem` when possible
- `Shift+Tab` should call `outdentItem` when possible
