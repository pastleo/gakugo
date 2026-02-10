defmodule GakugoWeb.UnitLive.Index do
  use GakugoWeb, :live_view

  alias Gakugo.Learning
  alias Gakugo.Learning.FromTargetLang

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Units
        <:actions>
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
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Units")
     |> stream(:units, list_units())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    unit = Learning.get_unit!(id)
    {:ok, _} = Learning.delete_unit(unit)

    {:noreply, stream_delete(socket, :units, unit)}
  end

  defp list_units() do
    Learning.list_units()
  end
end
