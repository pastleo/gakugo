defmodule GakugoWeb.UnitLive.ShowEdit do
  use GakugoWeb, :live_view

  alias Gakugo.Db
  alias Gakugo.Notebook.UnitSession
  alias Gakugo.Db.FromTargetLang
  alias Gakugo.Notebook.Outline

  @unit_session_heartbeat_ms 10_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    unit = ensure_unit_has_page(Db.get_unit!(id))
    snapshot = UnitSession.snapshot(unit.id)

    socket =
      socket
      |> assign(:page_title, "Unit Notebook")
      |> assign(:unit, snapshot.unit)
      |> assign(:from_target_lang_options, FromTargetLang.options())
      |> assign(:meta_form, to_form(UnitSession.change_unit_session(snapshot.unit)))
      |> assign(:initial_pages_json, build_initial_pages_json(snapshot.unit))
      |> assign(:active_drawer, nil)
      |> assign(:actor_id, Ecto.UUID.generate())

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Gakugo.PubSub, notebook_topic(unit.id))

        socket
        |> touch_unit_session()
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} main_container_class="mx-auto w-full max-w-[1320px] space-y-4">
      <:header>
        <header class="sticky top-0 z-40 border-b border-base-300/70 bg-base-100/95 backdrop-blur-xl">
          <nav class="mx-auto flex w-full max-w-[1320px] flex-col items-stretch gap-3 px-4 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-6 lg:px-8">
            <div class="flex min-w-0 items-center gap-3 sm:flex-1">
              <.link
                navigate={~p"/"}
                class="group shrink-0 rounded-xl border border-base-300 bg-base-100 p-1.5 transition hover:bg-base-200"
                title="Back to units"
              >
                <img src={~p"/images/logo.svg"} width="28" alt="Home" class="size-7" />
              </.link>

              <.form
                for={@meta_form}
                id="unit-title-form"
                phx-change="validate_meta"
                class="min-w-0 flex-1"
              >
                <.input
                  field={@meta_form[:title]}
                  id="unit-title-input"
                  type="text"
                  placeholder="Notebook title"
                  phx-debounce="250"
                  class="w-full border-0 border-b border-base-content/30 bg-transparent px-1 py-1 text-lg font-semibold text-base-content outline-hidden transition focus:border-primary"
                />
                <input
                  type="hidden"
                  name="unit_session[from_target_lang]"
                  value={@unit.from_target_lang}
                />
              </.form>
            </div>

            <div class="grid grid-cols-4 gap-1 sm:flex sm:items-center sm:gap-2">
              <button
                id="unit-flashcards-panel-toggle"
                type="button"
                phx-click="toggle_drawer"
                phx-value-panel="flashcards"
                class={[
                  "w-full rounded-xl border px-2 py-1.5 text-[11px] font-medium transition sm:w-auto sm:px-3 sm:text-sm",
                  @active_drawer == "flashcards" && "border-primary/40 bg-primary/12 text-primary",
                  @active_drawer != "flashcards" &&
                    "border-base-300 text-base-content/80 hover:bg-base-200"
                ]}
              >
                Flashcards
              </button>

              <button
                id="unit-options-panel-toggle"
                type="button"
                phx-click="toggle_drawer"
                phx-value-panel="options"
                class={[
                  "w-full rounded-xl border px-2 py-1.5 text-[11px] font-medium transition sm:w-auto sm:px-3 sm:text-sm",
                  @active_drawer == "options" && "border-primary/40 bg-primary/12 text-primary",
                  @active_drawer != "options" &&
                    "border-base-300 text-base-content/80 hover:bg-base-200"
                ]}
              >
                Options
              </button>
            </div>
          </nav>
        </header>
      </:header>

      <div class="drawer drawer-end">
        <input
          id="unit-drawer-toggle"
          type="checkbox"
          class="drawer-toggle"
          checked={not is_nil(@active_drawer)}
        />

        <div class="drawer-content">
          <section class="space-y-6">
            <section class="space-y-3">
              <div
                id="notebook-editor-root"
                phx-hook="NotebookEditorPhxHook"
                phx-update="ignore"
                data-initial-pages-json={@initial_pages_json}
              >
              </div>
            </section>
          </section>
        </div>

        <div class="drawer-side z-50">
          <label
            for="unit-drawer-toggle"
            class="drawer-overlay"
            aria-label="close sidebar"
            phx-click="close_drawer"
          >
          </label>

          <section class="h-full w-[22rem] overflow-y-auto border-l border-base-300 bg-base-100 p-5 shadow-2xl">
            <div class="mb-4 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-base-content">
                {drawer_title(@active_drawer)}
              </h2>

              <button
                id="close-drawer-btn"
                type="button"
                phx-click="close_drawer"
                class="rounded-md p-1 text-base-content/70 transition hover:bg-base-200"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <%= if @active_drawer == "options" do %>
              <.live_component
                module={GakugoWeb.UnitLive.UnitOptionsPanel}
                id="unit-options-panel"
                meta_form={@meta_form}
                from_target_lang_options={@from_target_lang_options}
                unit={@unit}
              />
            <% end %>

            <%= if @active_drawer == "flashcards" do %>
              <.live_component
                module={GakugoWeb.UnitLive.FlashcardPanel}
                id="flashcard-panel"
                unit={@unit}
              />
            <% end %>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate_meta", %{"unit_session" => unit_params}, socket) do
    changeset = UnitSession.change_unit_session(socket.assigns.unit, unit_params)

    socket =
      socket
      |> assign(:meta_form, to_form(changeset, action: :validate))

    if changeset.valid? do
      {:noreply, apply_unit_meta_intent(socket, unit_params)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_drawer", %{"panel" => "options"}, socket) do
    active_drawer = if socket.assigns.active_drawer == "options", do: nil, else: "options"
    {:noreply, assign(socket, :active_drawer, active_drawer)}
  end

  def handle_event("toggle_drawer", %{"panel" => "flashcards"}, socket) do
    if socket.assigns.active_drawer == "flashcards" do
      {:noreply, assign(socket, :active_drawer, nil)}
    else
      {:noreply, assign(socket, :active_drawer, "flashcards")}
    end
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :active_drawer, nil)}
  end

  def handle_event("apply_intent", params, socket) do
    case UnitSession.apply_intent(socket.assigns.unit.id, socket.assigns.actor_id, params) do
      {:ok, result} ->
        next_socket = apply_canonical_update(socket, result)

        {:reply, %{status: "updated", update: result}, next_socket}

      {:error, :noop} ->
        {:reply, %{status: "noop"}, socket}

      {:error, :invalid_params} ->
        {:reply, %{status: "invalid_params", reason: "invalid_params"}, socket}

      {:error, reason} ->
        {:reply, %{status: "error", reason: inspect(reason)}, socket}

      _other ->
        {:reply, %{status: "invalid_params", reason: "invalid_params"}, socket}
    end
  end

  @impl true
  def handle_info({:notebook_operation, operation}, socket) do
    {:noreply, maybe_apply_remote_operation(socket, operation)}
  end

  @impl true
  def handle_info(:unit_session_heartbeat, socket) do
    {:noreply, touch_unit_session(socket)}
  end

  @impl true
  def terminate(_reason, _socket) do
    :ok
  end

  defp touch_unit_session(socket) do
    :ok = UnitSession.heartbeat(socket.assigns.unit.id, socket.assigns.actor_id)
    Process.send_after(self(), :unit_session_heartbeat, @unit_session_heartbeat_ms)
    socket
  end

  defp ensure_unit_has_page(unit) do
    if unit.pages == [] do
      {:ok, _page} =
        Db.create_page(%{
          "unit_id" => unit.id,
          "title" => "Page 1",
          "items" => [Outline.new_item()]
        })

      Db.get_unit!(unit.id)
    else
      unit
    end
  end

  defp notebook_topic(unit_id), do: "unit:notebook:#{unit_id}"

  defp maybe_apply_remote_operation(socket, %{unit_id: unit_id})
       when unit_id != socket.assigns.unit.id,
       do: socket

  defp maybe_apply_remote_operation(socket, %{actor_id: actor_id})
       when actor_id == socket.assigns.actor_id,
       do: socket

  defp maybe_apply_remote_operation(socket, %{op_id: op_id, result: result})
       when is_map(result) do
    _ = op_id

    socket
    |> apply_canonical_update(result)
    |> push_react_update(result)
  end

  defp apply_canonical_update(socket, %{kind: "unit_meta_updated", unit: unit}) do
    unit = Map.merge(socket.assigns.unit, unit)

    socket
    |> assign(:unit, unit)
    |> assign(:meta_form, to_form(UnitSession.change_unit_session(unit)))
  end

  defp apply_canonical_update(socket, %{kind: "page_updated", page: page}) do
    assign(socket, :unit, put_unit_page(socket.assigns.unit, page))
  end

  defp apply_canonical_update(socket, %{kind: "pages_list_updated", pages: pages}) do
    assign(socket, :unit, %{socket.assigns.unit | pages: pages})
  end

  defp apply_canonical_update(socket, _), do: socket

  defp apply_unit_meta_intent(socket, unit_params) do
    case UnitSession.apply_intent(socket.assigns.unit.id, socket.assigns.actor_id, %{
           scope: "unit_meta",
           action: "update_unit_meta",
           target: %{unit_id: socket.assigns.unit.id},
           payload: unit_params,
           meta: %{client: "liveview"}
         }) do
      {:ok, result} -> apply_canonical_update(socket, result)
      {:error, _reason} -> socket
      _ -> socket
    end
  end

  defp build_initial_pages_json(unit) do
    %{unit_id: unit.id, pages: unit.pages} |> Jason.encode!()
  end

  defp drawer_title("flashcards"), do: "Flashcards"
  defp drawer_title(_), do: "Unit options"

  defp put_unit_page(unit, page) do
    pages =
      Enum.map(unit.pages, fn existing_page ->
        if existing_page.id == page.id, do: page, else: existing_page
      end)

    %{unit | pages: pages}
  end

  defp push_react_update(socket, update) when is_map(update) do
    push_event(socket, "react:update", %{update: update})
  end

  defp push_react_update(socket, _update), do: socket
end
