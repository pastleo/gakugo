defmodule GakugoWeb.UnitLive.FlashcardPanel do
  use GakugoWeb, :live_component

  alias Gakugo.Anki
  alias Gakugo.Notebook.UnitSession

  @impl true
  def update(%{async_preview_progress: progress}, socket) do
    if socket.assigns[:preview_ref] == progress.ref do
      {:ok, assign(socket, :preview_progress, Map.delete(progress, :ref))}
    else
      {:ok, socket}
    end
  end

  def update(%{async_sync_progress: progress}, socket) do
    if socket.assigns[:sync_ref] == progress.ref do
      {:ok, assign(socket, :sync_progress, Map.delete(progress, :ref))}
    else
      {:ok, socket}
    end
  end

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
        |> assign(:syncing, false)
        |> assign(:sync_progress, initial_sync_progress())
        |> assign(:sync_ref, nil)
        |> assign(:preview_entries, [])
        |> assign(:preview_entry_count, 0)
        |> assign(:preview_loading, false)
        |> assign(:preview_progress, initial_preview_progress())
        |> assign(:preview_ref, nil)
        |> assign(:preview_error, nil)
        |> assign(:panel_form, panel_form())
        |> start_preview()

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
     |> start_preview()}
  end

  def handle_event("refresh_preview", _params, socket) do
    {:noreply, start_preview(socket)}
  end

  def handle_event("sync_flashcards", _params, socket) do
    if socket.assigns.syncing do
      {:noreply, socket}
    else
      {:noreply, start_sync(socket)}
    end
  end

  @impl true
  def handle_async({:preview, ref}, {:ok, {:ok, unit, preview}}, socket) do
    if socket.assigns.preview_ref == ref do
      {:noreply,
       socket
       |> assign(:unit, unit)
       |> assign(:preview_entries, preview.entries)
       |> assign(:preview_entry_count, preview.entry_count)
       |> assign(:preview_loading, false)
       |> assign(:preview_progress, %{total: preview.entry_count, processed: preview.entry_count})
       |> assign(:preview_error, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:preview, ref}, {:ok, {:error, reason}}, socket) do
    if socket.assigns.preview_ref == ref do
      {:noreply,
       socket
       |> assign(:preview_entries, [])
       |> assign(:preview_entry_count, 0)
       |> assign(:preview_loading, false)
       |> assign(:preview_progress, initial_preview_progress())
       |> assign(:preview_error, inspect(reason))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:preview, ref}, {:exit, reason}, socket) do
    if socket.assigns.preview_ref == ref do
      {:noreply,
       socket
       |> assign(:preview_loading, false)
       |> assign(:preview_error, inspect(reason))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:sync, ref}, {:ok, {:ok, unit, result}}, socket) do
    if socket.assigns.sync_ref == ref do
      {:noreply,
       socket
       |> assign(:sync_result, result)
       |> assign(:syncing, false)
       |> assign(:sync_progress, %{
         stage: :done,
         total: result.sync.synced_count,
         processed: result.sync.synced_count,
         synced: result.sync.synced_count,
         deleted: result.sync.deleted_count
       })
       |> assign(:preview_error, nil)
       |> assign(:unit, unit)
       |> start_preview()}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:sync, ref}, {:ok, {:error, reason}}, socket) do
    if socket.assigns.sync_ref == ref do
      {:noreply,
       socket
       |> assign(:sync_result, nil)
       |> assign(:syncing, false)
       |> assign(:preview_error, inspect(reason))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:sync, ref}, {:exit, reason}, socket) do
    if socket.assigns.sync_ref == ref do
      {:noreply,
       socket
       |> assign(:syncing, false)
       |> assign(:preview_error, inspect(reason))}
    else
      {:noreply, socket}
    end
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
          disabled={@syncing}
          class="rounded-xl border border-primary/30 bg-primary/12 px-3 py-2 text-sm font-medium text-primary transition hover:bg-primary/18"
        >
          <%= if @syncing do %>
            Syncing...
          <% else %>
            Sync
          <% end %>
        </button>

        <%= if @syncing do %>
          <p class="text-xs text-base-content/60">
            {sync_progress_label(@sync_progress)}
          </p>
        <% end %>

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
          <div class="flex items-center gap-2">
            <span class="text-xs text-base-content/55">
              {preview_progress_label(@preview_loading, @preview_progress, @preview_entry_count)}
            </span>
            <button
              id="flashcard-refresh-preview-btn"
              type="button"
              phx-target={@myself}
              phx-click="refresh_preview"
              disabled={@preview_loading}
              class="rounded-lg border border-base-300 px-2 py-1 text-xs font-medium text-base-content/70 transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <%= if @preview_loading do %>
                Rendering...
              <% else %>
                Refresh preview
              <% end %>
            </button>
          </div>
        </div>

        <%= if @preview_error do %>
          <div class="rounded-xl border border-error/30 bg-error/10 p-3 text-xs text-error">
            {@preview_error}
          </div>
        <% else %>
          <%= if @preview_loading do %>
            <div class="rounded-xl border border-base-300 bg-base-200/40 px-3 py-4 text-xs text-base-content/60">
              Rendering preview in the background. You can keep editing while this runs.
            </div>
          <% end %>

          <%= if @preview_entries != [] do %>
            <div class="space-y-2">
              <%= for entry <- @preview_entries do %>
                <div class="rounded-xl border border-base-300 bg-base-200/30 px-3 py-2 transition hover:border-base-content/20 hover:bg-base-200/60">
                  <div class="truncate text-sm font-medium text-base-content">
                    {entry.summary |> blank_summary_fallback()}
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>

          <%= if not @preview_loading and @preview_entries == [] do %>
            <div class="rounded-xl border border-dashed border-base-300 px-3 py-6 text-center text-xs text-base-content/55">
              No flashcards found in this notebook yet.
            </div>
          <% end %>
        <% end %>
      </section>
    </div>
    """
  end

  defp panel_form(note_type \\ Anki.default_note_type(), delete_orphans \\ true) do
    to_form(%{"note_type" => note_type, "delete_orphans" => delete_orphans}, as: :flashcard_panel)
  end

  defp start_preview(socket) do
    ref = make_ref()
    panel_id = socket.assigns.id
    live_view_pid = self()
    unit_id = socket.assigns.unit.id
    note_type = socket.assigns.note_type

    progress_callback = fn progress ->
      Phoenix.LiveView.send_update(live_view_pid, __MODULE__,
        id: panel_id,
        async_preview_progress: preview_progress(ref, progress)
      )
    end

    socket
    |> assign(:preview_loading, true)
    |> assign(:preview_ref, ref)
    |> assign(:preview_progress, initial_preview_progress())
    |> assign(:preview_error, nil)
    |> start_async({:preview, ref}, fn ->
      unit = current_unit(unit_id)
      result = Anki.preview_unit(unit, note_type: note_type, progress_callback: progress_callback)
      with({:ok, preview} <- result, do: {:ok, unit, preview})
    end)
  end

  defp start_sync(socket) do
    ref = make_ref()
    panel_id = socket.assigns.id
    live_view_pid = self()
    unit_id = socket.assigns.unit.id
    note_type = socket.assigns.note_type
    delete_orphans = socket.assigns.delete_orphans

    progress_callback = fn progress ->
      Phoenix.LiveView.send_update(live_view_pid, __MODULE__,
        id: panel_id,
        async_sync_progress: sync_progress(ref, progress)
      )
    end

    socket
    |> assign(:syncing, true)
    |> assign(:sync_ref, ref)
    |> assign(:sync_progress, initial_sync_progress())
    |> assign(:sync_result, nil)
    |> assign(:preview_error, nil)
    |> start_async({:sync, ref}, fn ->
      unit = current_unit(unit_id)

      result =
        Anki.sync_unit_via_server(unit,
          note_type: note_type,
          delete_orphans?: delete_orphans,
          progress_callback: progress_callback
        )

      with({:ok, sync_result} <- result, do: {:ok, unit, sync_result})
    end)
  end

  defp maybe_reload_preview(socket, unit) do
    previous_unit = socket.assigns.unit
    current_unit = current_unit(unit.id)
    socket = assign(socket, :unit, current_unit)

    if previous_unit == current_unit do
      socket
    else
      start_preview(socket)
    end
  end

  defp current_unit(unit_id), do: UnitSession.snapshot(unit_id).unit

  defp truthy_param?(value), do: value in [true, "true", "on"]

  defp blank_summary_fallback(""), do: "Untitled flashcard"
  defp blank_summary_fallback(nil), do: "Untitled flashcard"
  defp blank_summary_fallback(summary), do: summary

  defp initial_preview_progress, do: %{total: nil, processed: 0}

  defp initial_sync_progress do
    %{stage: :queued, total: nil, processed: 0, synced: 0, deleted: 0}
  end

  defp preview_progress(ref, progress) do
    %{
      ref: ref,
      total: Map.get(progress, :total),
      processed: Map.get(progress, :processed, 0)
    }
  end

  defp sync_progress(ref, progress) do
    %{
      ref: ref,
      stage: Map.get(progress, :stage, :syncing),
      total: Map.get(progress, :total),
      processed: Map.get(progress, :processed, 0),
      synced: Map.get(progress, :synced, 0),
      deleted: Map.get(progress, :deleted, 0)
    }
  end

  defp preview_progress_label(true, %{total: total, processed: processed}, _entry_count)
       when is_integer(total) do
    "Rendered #{processed}/#{total} cards"
  end

  defp preview_progress_label(true, _progress, _entry_count), do: "Collecting cards..."
  defp preview_progress_label(false, _progress, entry_count), do: "#{entry_count} cards"

  defp sync_progress_label(%{stage: :download}), do: "Syncing from Anki server..."
  defp sync_progress_label(%{stage: :upload}), do: "Uploading Anki changes..."
  defp sync_progress_label(%{stage: :ensure_model}), do: "Preparing Anki note type..."
  defp sync_progress_label(%{stage: :ensure_deck}), do: "Preparing Anki deck..."

  defp sync_progress_label(%{stage: stage, total: total, processed: processed})
       when stage in [:collected, :rendered, :render] and is_integer(total) do
    "Rendered #{processed}/#{total} cards for Anki"
  end

  defp sync_progress_label(%{stage: :synced, total: total, synced: synced})
       when is_integer(total) do
    "Synced #{synced}/#{total} cards"
  end

  defp sync_progress_label(%{stage: :done, synced: synced, deleted: deleted}) do
    "Synced #{synced} cards; deleted #{deleted} orphaned notes"
  end

  defp sync_progress_label(_progress), do: "Starting Anki sync..."
end
