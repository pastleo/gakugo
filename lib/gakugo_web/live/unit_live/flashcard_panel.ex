defmodule GakugoWeb.UnitLive.FlashcardPanel do
  use GakugoWeb, :live_component

  alias Gakugo.Anki
  alias Gakugo.Notebook.UnitSession

  @impl true
  def update(%{unit: unit} = assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:initialized] do
      {:ok, maybe_reload_preview(socket, unit)}
    else
      socket =
        socket
        |> assign(:initialized, true)
        |> assign(:note_type_options, Anki.note_type_options())
        |> assign(:note_type, Anki.default_note_type())
        |> assign(:delete_orphans, true)
        |> assign(:sync_result, nil)
        |> assign(:preview_entries, [])
        |> assign(:preview_entry_count, 0)
        |> assign(:preview_error, nil)
        |> assign(:panel_form, panel_form())
        |> load_preview()

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("change_flashcard_panel", %{"flashcard_panel" => panel_params}, socket) do
    note_type = Map.get(panel_params, "note_type", Anki.default_note_type())
    delete_orphans = truthy_param?(Map.get(panel_params, "delete_orphans"))

    {:noreply,
     socket
     |> assign(:note_type, note_type)
     |> assign(:delete_orphans, delete_orphans)
     |> assign(:panel_form, panel_form(note_type, delete_orphans))
     |> assign(:sync_result, nil)
     |> load_preview()}
  end

  def handle_event("sync_flashcards", _params, socket) do
    unit = UnitSession.snapshot(socket.assigns.unit.id).unit

    socket =
      case Anki.sync_unit_via_server(unit,
             note_type: socket.assigns.note_type,
             delete_orphans?: socket.assigns.delete_orphans
           ) do
        {:ok, result} ->
          socket
          |> assign(:sync_result, result)
          |> assign(:preview_error, nil)
          |> assign(:unit, unit)
          |> load_preview()

        {:error, reason} ->
          socket
          |> assign(:sync_result, nil)
          |> assign(:preview_error, inspect(reason))
      end

    {:noreply, socket}
  end

  attr(:unit, :map, required: true)

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-5">
      <div>
        <p class="text-xs text-base-content/65">
          Preview notebook-derived flashcards and sync them to Anki on demand.
        </p>
      </div>

      <.form
        for={@panel_form}
        id="flashcard-panel-form"
        phx-target={@myself}
        phx-change="change_flashcard_panel"
        class="space-y-4"
      >
        <.input
          field={@panel_form[:note_type]}
          type="select"
          label="Note type"
          options={@note_type_options}
        />

        <.input
          field={@panel_form[:delete_orphans]}
          type="checkbox"
          label="Delete orphaned Anki notes during sync"
        />
      </.form>

      <div class="flex flex-col gap-2">
        <button
          id="flashcard-sync-btn"
          type="button"
          phx-target={@myself}
          phx-click="sync_flashcards"
          class="rounded-xl border border-primary/30 bg-primary/12 px-3 py-2 text-sm font-medium text-primary transition hover:bg-primary/18"
        >
          Sync
        </button>

        <p class="text-xs leading-5 text-base-content/60">
          Syncs local and server collections first, updates only notebook-owned Anki notes by
          stable Gakugo ids, then syncs the result back to the server.
        </p>
      </div>

      <%= if @sync_result do %>
        <section class="rounded-xl border border-success/30 bg-success/10 px-3 py-2.5 text-sm leading-5 text-base-content">
          Synced <strong>{@sync_result.sync.synced_count}</strong>
          cards to <strong>{@sync_result.sync.deck_name}</strong>
          <span class="text-base-content/70 whitespace-nowrap">
            (deleted {@sync_result.sync.deleted_count} orphaned notes)
          </span>
        </section>
      <% end %>

      <section class="space-y-3">
        <div class="flex items-center justify-between">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
            Preview
          </h3>
          <span class="text-xs text-base-content/55">{@preview_entry_count} cards</span>
        </div>

        <%= if @preview_error do %>
          <div class="rounded-xl border border-error/30 bg-error/10 p-3 text-xs text-error">
            {@preview_error}
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for entry <- @preview_entries do %>
              <div class="rounded-xl border border-base-300 bg-base-200/30 px-3 py-2 transition hover:border-base-content/20 hover:bg-base-200/60">
                <div class="truncate text-sm font-medium text-base-content">
                  {entry.summary |> blank_summary_fallback()}
                </div>
              </div>
            <% end %>

            <%= if @preview_entries == [] do %>
              <div class="rounded-xl border border-dashed border-base-300 px-3 py-6 text-center text-xs text-base-content/55">
                No flashcards found in this notebook yet.
              </div>
            <% end %>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  defp panel_form(note_type \\ Anki.default_note_type(), delete_orphans \\ true) do
    to_form(%{"note_type" => note_type, "delete_orphans" => delete_orphans}, as: :flashcard_panel)
  end

  defp load_preview(socket) do
    unit = current_unit(socket.assigns.unit.id)

    case Anki.preview_unit(unit, note_type: socket.assigns.note_type) do
      {:ok, preview} ->
        socket
        |> assign(:unit, unit)
        |> assign(:preview_entries, preview.entries)
        |> assign(:preview_entry_count, preview.entry_count)
        |> assign(:preview_error, nil)

      {:error, reason} ->
        socket
        |> assign(:unit, unit)
        |> assign(:preview_entries, [])
        |> assign(:preview_entry_count, 0)
        |> assign(:preview_error, inspect(reason))
    end
  end

  defp maybe_reload_preview(socket, unit) do
    previous_unit = socket.assigns.unit
    current_unit = current_unit(unit.id)
    socket = assign(socket, :unit, current_unit)

    if previous_unit == current_unit do
      socket
    else
      load_preview(socket)
    end
  end

  defp current_unit(unit_id), do: UnitSession.snapshot(unit_id).unit

  defp truthy_param?(value), do: value in [true, "true", "on"]

  defp blank_summary_fallback(""), do: "Untitled flashcard"
  defp blank_summary_fallback(nil), do: "Untitled flashcard"
  defp blank_summary_fallback(summary), do: summary
end
