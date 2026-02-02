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
      export { default } from "@/js/hooks/nested_list_editor.js";
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
