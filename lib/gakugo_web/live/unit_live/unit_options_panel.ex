defmodule GakugoWeb.UnitLive.UnitOptionsPanel do
  use GakugoWeb, :live_component

  attr(:meta_form, :any, required: true)
  attr(:from_target_lang_options, :list, required: true)
  attr(:unit, :map, required: true)

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <p class="text-xs text-base-content/65">
        Configure language pair and notebook behavior.
      </p>

      <.form
        for={@meta_form}
        id="unit-options-form"
        phx-change="validate_meta"
        class="mt-4 space-y-4"
      >
        <.input
          field={@meta_form[:from_target_lang]}
          type="select"
          label="Language pair"
          options={@from_target_lang_options}
          phx-debounce="250"
        />
        <input type="hidden" name="unit_session[title]" value={@unit.title} />
      </.form>

      <section id="unit-quick-help" class="mt-6 rounded-xl border border-base-300 bg-base-200/25 p-4">
        <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
          Quick help
        </h3>
        <ul class="mt-2 space-y-1 text-xs text-base-content/70">
          <li>Enter: child item</li>
          <li>Shift+Enter: newline</li>
          <li>Backspace/Delete on empty: remove item</li>
        </ul>
      </section>
    </div>
    """
  end
end
