defmodule GakugoWeb.LearningComponents do
  use Phoenix.Component
  use Gettext, backend: GakugoWeb.Gettext

  import GakugoWeb.CoreComponents

  @doc """
  Renders a WYSIWYG nested list editor for structured content.

  The editor manages a hierarchical list structure where each item has a `detail` text
  and optional `children` array. It syncs state to a hidden input for form integration.

  ## Examples

      <.nested_list_editor
        id="grammar-details-123"
        field={@form[:details_json]}
        placeholder="Add a grammar point..."
      />

  ## Data Structure

  The editor works with JSON in this format:
  ```json
  [
    {"detail": "Point 1", "children": [{"detail": "Sub-point 1.1"}]},
    {"detail": "Point 2", "children": []}
  ]
  ```

  ## Keyboard Shortcuts

  - `Enter`: Create new sibling item below current
  - `Tab`: Indent item (make child of previous sibling)
  - `Shift+Tab`: Outdent item (move up one level)
  - `Backspace` on empty: Delete the item
  """
  attr :id, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :placeholder, :string, default: "Add a point..."
  attr :max_depth, :integer, default: 3

  def nested_list_editor(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".NestedListEditor"
      phx-update="ignore"
      data-max-depth={@max_depth}
      data-placeholder={@placeholder}
      class="nested-list-editor"
    >
      <input type="hidden" id={"#{@id}-input"} name={@field.name} value={@field.value || "[]"} />
      <div id={"#{@id}-container"} class="space-y-1"></div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".NestedListEditor">
      export default {
        mounted() {
          this.maxDepth = parseInt(this.el.dataset.maxDepth) || 3;
          this.placeholder = this.el.dataset.placeholder || "Add a point...";
          this.hiddenInput = this.el.querySelector("input[type='hidden']");
          this.container = this.el.querySelector("[id$='-container']");

          // Parse initial data
          try {
            this.data = JSON.parse(this.hiddenInput.value) || [];
          } catch (e) {
            this.data = [];
          }

          // Ensure we have at least one empty item
          if (this.data.length === 0) {
            this.data = [{ detail: "", children: [] }];
          }

          this.render();
          this.focusFirst();
        },

        // Generate unique ID for each item
        genId() {
          return 'item-' + Math.random().toString(36).substr(2, 9);
        },

        // Flatten nested structure for easier traversal
        flatten(items, depth = 0, parentPath = []) {
          let result = [];
          items.forEach((item, idx) => {
            const path = [...parentPath, idx];
            result.push({ item, depth, path });
            if (item.children && item.children.length > 0) {
              result = result.concat(this.flatten(item.children, depth + 1, [...path, 'children']));
            }
          });
          return result;
        },

        // Get item at path
        getAtPath(path) {
          let current = this.data;
          for (let i = 0; i < path.length; i++) {
            if (path[i] === 'children') {
              current = current.children;
            } else {
              current = current[path[i]];
            }
          }
          return current;
        },

        // Set item at path
        setAtPath(path, value) {
          if (path.length === 1) {
            this.data[path[0]] = value;
            return;
          }
          let current = this.data;
          for (let i = 0; i < path.length - 1; i++) {
            if (path[i] === 'children') {
              current = current.children;
            } else {
              current = current[path[i]];
            }
          }
          const lastKey = path[path.length - 1];
          if (lastKey === 'children') {
            current.children = value;
          } else {
            current[lastKey] = value;
          }
        },

        // Get parent array and index for a path
        getParentInfo(path) {
          if (path.length === 1) {
            return { parent: this.data, index: path[0], isRoot: true };
          }
          // path like [0, 'children', 1] means data[0].children[1]
          let parent = this.data;
          for (let i = 0; i < path.length - 1; i++) {
            if (path[i] === 'children') {
              parent = parent.children;
            } else if (i < path.length - 2) {
              parent = parent[path[i]];
            }
          }
          // Handle the case where we need to get to .children
          const secondLast = path[path.length - 2];
          if (secondLast === 'children') {
            // parent is already the children array
          } else {
            parent = parent[secondLast].children;
          }
          return { parent, index: path[path.length - 1], isRoot: false };
        },

        // Remove item at path
        removeAtPath(path) {
          if (path.length === 1) {
            this.data.splice(path[0], 1);
            return;
          }
          const { parent, index } = this.getParentInfo(path);
          parent.splice(index, 1);
        },

        // Insert item at path
        insertAtPath(path, item) {
          if (path.length === 1) {
            this.data.splice(path[0], 0, item);
            return;
          }
          const { parent, index } = this.getParentInfo(path);
          parent.splice(index, 0, item);
        },

        // Sync state to hidden input
        sync() {
          // Clean up empty children arrays for cleaner JSON
          const clean = (items) => items.map(item => ({
            detail: item.detail,
            children: item.children && item.children.length > 0 ? clean(item.children) : []
          }));
          this.hiddenInput.value = JSON.stringify(clean(this.data));
          this.hiddenInput.dispatchEvent(new Event('input', { bubbles: true }));
        },

        render() {
          const flat = this.flatten(this.data);
          this.container.innerHTML = '';

          if (flat.length === 0) {
            this.data = [{ detail: "", children: [] }];
            flat.push({ item: this.data[0], depth: 0, path: [0] });
          }

          flat.forEach(({ item, depth, path }, idx) => {
            const row = this.createRow(item, depth, path, idx);
            this.container.appendChild(row);
          });
        },

        createRow(item, depth, path, flatIndex) {
          const row = document.createElement('div');
          row.className = 'flex items-center gap-1 group';
          row.dataset.path = JSON.stringify(path);
          row.dataset.depth = depth;
          row.dataset.flatIndex = flatIndex;

          // Indent indicator
          const indent = document.createElement('div');
          indent.className = 'flex items-center shrink-0';
          indent.style.width = `${depth * 20}px`;

          // Depth markers
          for (let i = 0; i < depth; i++) {
            const marker = document.createElement('span');
            marker.className = 'w-5 h-full border-l border-base-300';
            indent.appendChild(marker);
          }
          row.appendChild(indent);

          // Bullet point
          const bullet = document.createElement('span');
          bullet.className = 'w-1.5 h-1.5 rounded-full bg-base-content/40 shrink-0';
          row.appendChild(bullet);

          // Mobile indent/outdent buttons
          const mobileButtons = document.createElement('div');
          mobileButtons.className = 'flex gap-0.5 sm:hidden shrink-0';

          const outdentBtn = document.createElement('button');
          outdentBtn.type = 'button';
          outdentBtn.className = 'w-6 h-6 flex items-center justify-center text-xs text-base-content/60 hover:text-base-content hover:bg-base-200 rounded transition-colors disabled:opacity-30 disabled:cursor-not-allowed';
          outdentBtn.innerHTML = '&lt;';
          outdentBtn.disabled = depth === 0;
          outdentBtn.addEventListener('click', () => this.outdent(path));
          mobileButtons.appendChild(outdentBtn);

          const indentBtn = document.createElement('button');
          indentBtn.type = 'button';
          indentBtn.className = 'w-6 h-6 flex items-center justify-center text-xs text-base-content/60 hover:text-base-content hover:bg-base-200 rounded transition-colors disabled:opacity-30 disabled:cursor-not-allowed';
          indentBtn.innerHTML = '&gt;';
          const canIndent = this.canIndent(path, depth);
          indentBtn.disabled = !canIndent;
          indentBtn.addEventListener('click', () => this.indent(path));
          mobileButtons.appendChild(indentBtn);

          row.appendChild(mobileButtons);

          // Text input
          const input = document.createElement('input');
          input.type = 'text';
          input.value = item.detail || '';
          input.placeholder = this.placeholder;
          input.className = 'flex-1 min-w-0 px-2 py-1.5 text-sm bg-transparent text-base-content border-0 border-b border-transparent focus:border-base-300 focus:outline-none transition-colors placeholder:text-base-content/40';
          input.dataset.path = JSON.stringify(path);

          input.addEventListener('input', (e) => {
            item.detail = e.target.value;
            this.sync();
          });

          input.addEventListener('keydown', (e) => this.handleKeydown(e, path, depth, item));

          row.appendChild(input);

          // Action buttons (visible on hover for desktop, always for mobile)
          const actions = document.createElement('div');
          actions.className = 'flex gap-0.5 shrink-0 opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity';

          const addBtn = document.createElement('button');
          addBtn.type = 'button';
          addBtn.className = 'w-6 h-6 flex items-center justify-center text-xs text-success hover:bg-success/10 rounded transition-colors';
          addBtn.textContent = '+';
          addBtn.title = 'Add item below (Enter)';
          addBtn.addEventListener('click', () => this.addSibling(path));
          actions.appendChild(addBtn);

          const deleteBtn = document.createElement('button');
          deleteBtn.type = 'button';
          deleteBtn.className = 'w-6 h-6 flex items-center justify-center text-xs text-error hover:bg-error/10 rounded transition-colors';
          deleteBtn.textContent = '×';
          deleteBtn.title = 'Delete item';
          deleteBtn.addEventListener('click', () => this.deleteItem(path));
          actions.appendChild(deleteBtn);

          row.appendChild(actions);

          return row;
        },

        handleKeydown(e, path, depth, item) {
          if (e.key === 'Enter') {
            e.preventDefault();
            this.addSibling(path);
          } else if (e.key === 'Tab' && !e.shiftKey) {
            e.preventDefault();
            this.indent(path);
          } else if (e.key === 'Tab' && e.shiftKey) {
            e.preventDefault();
            this.outdent(path);
          } else if (e.key === 'Backspace' && item.detail === '') {
            e.preventDefault();
            this.deleteItem(path);
          } else if (e.key === 'ArrowUp' && e.altKey) {
            e.preventDefault();
            this.focusPrev(path);
          } else if (e.key === 'ArrowDown' && e.altKey) {
            e.preventDefault();
            this.focusNext(path);
          }
        },

        canIndent(path, depth) {
          // Cannot indent if at max depth
          if (depth >= this.maxDepth - 1) return false;
          // Cannot indent first item at any level (no previous sibling)
          const index = path[path.length - 1];
          if (typeof index !== 'number') return false;
          return index > 0;
        },

        indent(path) {
          const depth = this.getDepth(path);
          if (!this.canIndent(path, depth)) return;

          const index = path[path.length - 1];
          const item = this.getAtPath(path);

          // Get previous sibling
          let prevPath;
          if (path.length === 1) {
            prevPath = [index - 1];
          } else {
            prevPath = [...path.slice(0, -1), index - 1];
          }
          const prevItem = this.getAtPath(prevPath);

          // Initialize children array if needed
          if (!prevItem.children) prevItem.children = [];

          // Move item (and its children) to be last child of previous sibling
          this.removeAtPath(path);
          prevItem.children.push(item);

          this.sync();
          this.render();

          // Focus the moved item
          const newPath = [...prevPath, 'children', prevItem.children.length - 1];
          this.focusPath(newPath);
        },

        outdent(path) {
          const depth = this.getDepth(path);
          if (depth === 0) return; // Can't outdent root items

          const item = this.getAtPath(path);
          const index = path[path.length - 1];

          // Find parent's path (remove last 'children' and index)
          // path like [0, 'children', 1] -> parent is [0]
          const parentPath = path.slice(0, -2);
          const parentItem = this.getAtPath(parentPath);
          const parentIndex = parentPath[parentPath.length - 1] || 0;

          // Get siblings after this item - they become children of the moved item
          const siblings = parentItem.children.slice(index + 1);
          if (siblings.length > 0) {
            if (!item.children) item.children = [];
            item.children = item.children.concat(siblings);
          }

          // Remove item and following siblings from parent
          parentItem.children = parentItem.children.slice(0, index);

          // Insert item after parent in grandparent's children
          let newPath;
          if (parentPath.length === 1) {
            // Parent is at root level
            this.data.splice(parentIndex + 1, 0, item);
            newPath = [parentIndex + 1];
          } else {
            // Parent is nested
            const grandparentPath = parentPath.slice(0, -2);
            const grandparent = this.getAtPath(grandparentPath);
            const grandparentChildrenPath = [...grandparentPath, 'children'];
            let gpChildren = grandparent.children;
            const parentIdxInGP = parentPath[parentPath.length - 1];
            gpChildren.splice(parentIdxInGP + 1, 0, item);
            newPath = [...grandparentPath, 'children', parentIdxInGP + 1];
          }

          this.sync();
          this.render();
          this.focusPath(newPath);
        },

        getDepth(path) {
          // Count 'children' in path
          return path.filter(p => p === 'children').length;
        },

        addSibling(path) {
          const newItem = { detail: "", children: [] };
          const index = path[path.length - 1];

          if (path.length === 1) {
            this.data.splice(index + 1, 0, newItem);
            this.sync();
            this.render();
            this.focusPath([index + 1]);
          } else {
            const parentPath = path.slice(0, -1);
            const parent = this.getAtPath(parentPath);
            parent.splice(index + 1, 0, newItem);
            this.sync();
            this.render();
            this.focusPath([...parentPath, index + 1]);
          }
        },

        deleteItem(path) {
          const flat = this.flatten(this.data);

          // Don't delete if it's the only item
          if (flat.length === 1) {
            // Just clear the text
            this.data[0].detail = "";
            this.data[0].children = [];
            this.sync();
            this.render();
            this.focusFirst();
            return;
          }

          // Find previous item to focus
          const currentFlatIdx = flat.findIndex(f => JSON.stringify(f.path) === JSON.stringify(path));
          const prevFlatIdx = Math.max(0, currentFlatIdx - 1);
          const prevPath = flat[prevFlatIdx]?.path || [0];

          this.removeAtPath(path);

          // Ensure we still have at least one item
          if (this.data.length === 0) {
            this.data = [{ detail: "", children: [] }];
          }

          this.sync();
          this.render();

          // Focus previous item, or first if we deleted the first
          if (currentFlatIdx === 0) {
            this.focusFirst();
          } else {
            this.focusPath(prevPath);
          }
        },

        focusPath(path) {
          setTimeout(() => {
            const pathStr = JSON.stringify(path);
            const input = this.container.querySelector(`input[data-path='${pathStr}']`);
            if (input) {
              input.focus();
              input.setSelectionRange(input.value.length, input.value.length);
            }
          }, 0);
        },

        focusFirst() {
          setTimeout(() => {
            const input = this.container.querySelector('input[type="text"]');
            if (input) input.focus();
          }, 0);
        },

        focusPrev(path) {
          const flat = this.flatten(this.data);
          const idx = flat.findIndex(f => JSON.stringify(f.path) === JSON.stringify(path));
          if (idx > 0) {
            this.focusPath(flat[idx - 1].path);
          }
        },

        focusNext(path) {
          const flat = this.flatten(this.data);
          const idx = flat.findIndex(f => JSON.stringify(f.path) === JSON.stringify(path));
          if (idx < flat.length - 1) {
            this.focusPath(flat[idx + 1].path);
          }
        }
      }
    </script>
    """
  end

  @doc """
  Renders a grammar card with inline editing support.

  ## Examples

      <.grammar_card
        id="grammar-1"
        title_field={@form[:title]}
        details_field={@form[:details]}
        on_remove="delete_grammar"
        phx-value-grammar_id={grammar.id}
      />

  """
  attr :id, :string, required: true
  attr :title_field, Phoenix.HTML.FormField, required: true
  attr :details_field, Phoenix.HTML.FormField, required: true
  attr :on_remove, :string, default: nil
  attr :show_delete, :boolean, default: true
  attr :rest, :global

  def grammar_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="border border-base-300 rounded-lg p-4 space-y-3 hover:shadow-md transition-shadow bg-base-100"
    >
      <div class="flex items-start gap-3">
        <div class="flex-1 relative">
          <label class="block text-xs font-medium text-base-content/60 mb-1">
            Title
          </label>
          <.input field={@title_field} type="text" class="text-sm w-full focus:outline-hidden" />
        </div>

        <button
          :if={@show_delete && @on_remove}
          type="button"
          phx-click={@on_remove}
          {@rest}
          class="w-7 h-7 flex items-center justify-center text-error hover:bg-error/10 rounded transition-colors"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>

      <div class="relative">
        <label class="block text-xs font-medium text-base-content/60 mb-2">
          Details
        </label>
        <.nested_list_editor
          id={"#{@id}-details"}
          field={@details_field}
          placeholder="Add a grammar point..."
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a flashcard card with inline editing support.

  ## Examples

      <.flashcard_card
        id="flashcard-1"
        front_field={@form[:front]}
        back_field={@form[:back]}
        on_remove="delete_flashcard"
        phx-value-flashcard_id={flashcard.id}
      />

  """
  attr :id, :string, required: true
  attr :front_field, Phoenix.HTML.FormField, required: true
  attr :back_field, Phoenix.HTML.FormField, required: true
  attr :on_remove, :string, default: nil
  attr :show_delete, :boolean, default: true
  attr :rest, :global

  def flashcard_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="border border-base-300 rounded-lg p-4 space-y-3 hover:shadow-md transition-shadow bg-base-100"
    >
      <div class="flex items-start gap-3">
        <div class="flex-1 relative">
          <label class="block text-xs font-medium text-base-content/60 mb-1">
            Front
          </label>
          <.input
            field={@front_field}
            type="textarea"
            rows="2"
            class="text-sm w-full focus:outline-hidden"
          />
        </div>

        <div class="flex-1 relative">
          <label class="block text-xs font-medium text-base-content/60 mb-1">
            Back
          </label>
          <.input
            field={@back_field}
            type="textarea"
            rows="2"
            class="text-sm w-full focus:outline-hidden"
          />
        </div>

        <button
          :if={@show_delete && @on_remove}
          type="button"
          phx-click={@on_remove}
          {@rest}
          class="w-7 h-7 flex items-center justify-center text-error hover:bg-error/10 rounded transition-colors"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a vocabulary card with inline editing support.

  ## Examples

      <.vocabulary_card
        id="vocab-1"
        index={0}
        target_field={@form[:target]}
        from_field={@form[:from]}
        note_field={@form[:note]}
        on_remove="remove_vocabulary"
        phx-target={@myself}
      />

  """
  attr :id, :string, required: true
  attr :index, :integer, default: nil
  attr :target_field, Phoenix.HTML.FormField, required: true
  attr :from_field, Phoenix.HTML.FormField, required: true
  attr :note_field, Phoenix.HTML.FormField, required: true
  attr :on_remove, :string, default: nil
  attr :show_delete, :boolean, default: true
  attr :rest, :global

  def vocabulary_card(assigns) do
    ~H"""
    <div
      id={@id}
      class="border border-base-300 rounded-lg p-4 space-y-3 hover:shadow-md transition-shadow bg-base-100"
    >
      <div class="flex items-start gap-3">
        <span :if={@index != nil} class="text-xs font-medium text-base-content/60">
          #{@index + 1}
        </span>
        <div class="flex-1 relative">
          <label class="block text-xs font-medium text-base-content/60 mb-1">
            Target
          </label>
          <.input field={@target_field} type="text" class="text-sm w-full focus:outline-hidden" />
        </div>

        <div class="flex-1 relative">
          <label class="block text-xs font-medium text-base-content/60 mb-1">
            From
          </label>
          <.input field={@from_field} type="text" class="text-sm w-full focus:outline-hidden" />
        </div>

        <button
          :if={@show_delete && @on_remove}
          type="button"
          phx-click={@on_remove}
          {@rest}
          class="w-7 h-7 flex items-center justify-center text-error hover:bg-error/10 rounded transition-colors"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>

      <div class="relative">
        <label class="block text-xs font-medium text-base-content/60 mb-1">
          Note
        </label>
        <.input
          field={@note_field}
          type="textarea"
          rows="2"
          class="text-sm w-full focus:outline-hidden"
        />
      </div>
    </div>
    """
  end
end
