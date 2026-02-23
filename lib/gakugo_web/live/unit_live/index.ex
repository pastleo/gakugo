defmodule GakugoWeb.UnitLive.Index do
  use GakugoWeb, :live_view

  alias Gakugo.AI.Config, as: AIConfig
  alias Gakugo.Learning
  alias Gakugo.Learning.FromTargetLang

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Units
        <:actions>
          <.button
            id="refresh-ai-models-btn"
            phx-click="refresh_ai_models"
            class="btn btn-ghost"
            disabled={@refreshing_ai_models}
          >
            <%= if @refreshing_ai_models do %>
              <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Refreshing models...
            <% else %>
              <.icon name="hero-arrow-path" class="size-4" /> Refresh available AI models
            <% end %>
          </.button>

          <.button phx-click="toggle_recycle_bin" class="btn btn-ghost">
            <.icon name="hero-archive-box" />
            {if @show_recycle_bin, do: "Hide Recycle Bin", else: "Recycle Bin"} ({length(
              @deleted_units
            )})
          </.button>
          <.button variant="primary" navigate={~p"/units/new"}>
            <.icon name="hero-plus" /> New Unit
          </.button>
        </:actions>
      </.header>

      <.table
        id="units"
        rows={@streams.units}
        row_click={fn {_id, unit} -> JS.navigate(~p"/units/#{unit}") end}
      >
        <:col :let={{_id, unit}} label="Title">{unit.title}</:col>
        <:col :let={{_id, unit}} label="Language Pair">
          {FromTargetLang.label(unit.from_target_lang)}
        </:col>
        <:action :let={{id, unit}}>
          <.link
            phx-click={JS.push("delete", value: %{id: unit.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
        </:action>
      </.table>

      <%= if @show_recycle_bin do %>
        <div class="mt-8 rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
          <div class="mb-4 flex items-center justify-between gap-3">
            <div>
              <h3 class="text-base font-semibold text-base-content">Recycle Bin</h3>
              <p class="text-sm text-base-content/70">
                Restore units that were deleted.
              </p>
            </div>
            <span class="badge badge-ghost">{length(@deleted_units)} item(s)</span>
          </div>

          <div
            :if={@deleted_units == []}
            class="rounded-xl border border-dashed border-base-300 p-6 text-center"
          >
            <p class="text-sm text-base-content/70">No deleted units.</p>
          </div>

          <div :if={@deleted_units != []} class="overflow-x-auto">
            <table id="deleted-units" class="table table-zebra">
              <thead>
                <tr>
                  <th>Title</th>
                  <th>Language Pair</th>
                  <th>Deleted At</th>
                  <th><span class="sr-only">Actions</span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={unit <- @deleted_units} id={"deleted-unit-#{unit.id}"}>
                  <td>{unit.title}</td>
                  <td>{FromTargetLang.label(unit.from_target_lang)}</td>
                  <td>{unit.deleted_at}</td>
                  <td>
                    <div class="flex gap-4">
                      <.link phx-click="restore" phx-value-id={unit.id}>Restore</.link>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    ai_runtime = AIConfig.runtime_snapshot()

    if ai_loading?(ai_runtime) do
      Process.send_after(self(), :reload_ai_runtime, 500)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Units")
     |> assign(:show_recycle_bin, false)
     |> assign(:refreshing_ai_models, ai_loading?(ai_runtime))
     |> assign(:ai_runtime, ai_runtime)
     |> assign(:deleted_units, Learning.list_deleted_units())
     |> stream(:units, list_units())}
  end

  @impl true
  def handle_event("toggle_recycle_bin", _params, socket) do
    {:noreply, assign(socket, :show_recycle_bin, !socket.assigns.show_recycle_bin)}
  end

  @impl true
  def handle_event("refresh_ai_models", _params, socket) do
    AIConfig.refresh()
    Process.send_after(self(), :reload_ai_runtime, 150)

    {:noreply,
     socket
     |> assign(:refreshing_ai_models, true)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    unit = Learning.get_unit!(id)
    {:ok, _unit} = Learning.delete_unit(unit)

    {:noreply,
     socket
     |> stream_delete(:units, unit)
     |> assign(:deleted_units, Learning.list_deleted_units())
     |> put_flash(:info, "Unit moved to recycle bin")}
  end

  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    unit = Learning.get_unit_with_deleted!(id)
    {:ok, restored_unit} = Learning.restore_unit(unit)

    {:noreply,
     socket
     |> stream_insert(:units, restored_unit)
     |> assign(:deleted_units, Learning.list_deleted_units())
     |> put_flash(:info, "Unit restored")}
  end

  @impl true
  def handle_info(:reload_ai_runtime, socket) do
    was_refreshing = socket.assigns.refreshing_ai_models
    ai_runtime = AIConfig.runtime_snapshot()
    still_loading = ai_loading?(ai_runtime)

    if still_loading do
      Process.send_after(self(), :reload_ai_runtime, 500)
    end

    socket =
      socket
      |> assign(:ai_runtime, ai_runtime)
      |> assign(:refreshing_ai_models, still_loading)

    socket =
      if was_refreshing and not still_loading do
        put_flash(socket, :info, "Refreshed, #{ai_refresh_summary(ai_runtime)}")
      else
        socket
      end

    {:noreply, socket}
  end

  defp list_units() do
    Learning.list_units()
  end

  defp ai_loading?(ai_runtime) do
    Enum.any?(ai_runtime.providers, fn {_provider, check} -> check.status == :loading end)
  end

  defp ai_refresh_summary(ai_runtime) do
    [:ollama, :openai, :gemini]
    |> Enum.map(fn provider ->
      check =
        Map.get(ai_runtime.providers, provider, %{status: :error, models: [], error: :unknown})

      "#{provider_label(provider)}: #{provider_refresh_status(check)}"
    end)
    |> Enum.join(", ")
  end

  defp provider_refresh_status(%{status: :ok, models: models}) when is_list(models) do
    "#{length(models)} models"
  end

  defp provider_refresh_status(%{error: reason})
       when reason in [:missing_api_key, :missing_base_url, :disabled],
       do: "not configured"

  defp provider_refresh_status(_check), do: "error"

  defp provider_label(:openai), do: "openai"
  defp provider_label(:gemini), do: "gemini"
  defp provider_label(:ollama), do: "ollama"
  defp provider_label(provider), do: to_string(provider)
end
