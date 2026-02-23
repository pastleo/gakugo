defmodule GakugoWeb.UnitLive.ShowEditHelpers do
  alias Gakugo.Learning
  alias Gakugo.Learning.Notebook.Tree

  def external_link?(link) when is_binary(link) do
    link = String.trim(link)

    case URI.parse(link) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  def external_link?(_), do: false

  def unit_for_flashcard_preview(assigns) do
    pages =
      Enum.map(assigns.unit.pages, fn page ->
        state = page_state(assigns, page.id)
        %{page | items: state.nodes, title: state.title}
      end)

    %{assigns.unit | pages: pages}
  end

  def build_flashcard_fronts_by_page(unit) do
    unit.pages
    |> Enum.map(fn page ->
      fronts =
        page.items
        |> flatten_nodes_for_fronts()
        |> Enum.filter(& &1["front"])
        |> Enum.map(fn node -> String.trim(node["text"] || "") end)

      %{title: page.title, fronts: fronts}
    end)
    |> Enum.filter(&(&1.fronts != []))
  end

  def build_page_states(unit, existing_states \\ %{}) do
    Map.new(unit.pages, fn page ->
      existing_state = Map.get(existing_states, page.id)

      {page.id,
       %{
         title: if(is_nil(existing_state), do: page.title, else: existing_state.title),
         nodes:
           if(is_nil(existing_state),
             do: Tree.normalize_nodes(page.items),
             else: existing_state.nodes
           ),
         form:
           if(is_nil(existing_state),
             do: Phoenix.Component.to_form(Learning.change_page(page)),
             else: existing_state.form
           ),
         version: if(is_nil(existing_state), do: 0, else: existing_state.version)
       }}
    end)
  end

  def build_page_states_from_db(unit, existing_states) do
    Map.new(unit.pages, fn page ->
      existing_state = Map.get(existing_states, page.id)

      {page.id,
       %{
         title: page.title,
         nodes: Tree.normalize_nodes(page.items),
         form: Phoenix.Component.to_form(Learning.change_page(page)),
         version: if(is_nil(existing_state), do: 0, else: existing_state.version)
       }}
    end)
  end

  def page_state(%{assigns: assigns}, page_id), do: page_state(assigns, page_id)

  def page_state(assigns, page_id) when is_map(assigns) do
    states = Map.get(assigns, :page_states, %{})

    case Map.get(states, page_id) do
      nil ->
        page = page_by_id(assigns.unit, page_id)

        %{
          title: page.title,
          nodes: Tree.normalize_nodes(page.items),
          form: Phoenix.Component.to_form(Learning.change_page(page)),
          version: 0
        }

      state ->
        state
    end
  end

  def page_by_id(unit, page_id), do: Enum.find(unit.pages, fn page -> page.id == page_id end)

  def page_version_key(page), do: {page.id, page.inserted_at}

  def default_page_id(socket), do: default_page_id_from_unit(socket.assigns.unit)

  def default_page_id_from_unit(unit) do
    unit.pages
    |> List.first()
    |> Map.fetch!(:id)
  end

  def with_page_state(socket, page_id_param, fun) do
    case Integer.parse(to_string(page_id_param)) do
      {page_id, ""} ->
        page = page_by_id(socket.assigns.unit, page_id)
        state = Map.get(socket.assigns.page_states, page_id)

        if is_nil(page) or is_nil(state) do
          {:noreply, socket}
        else
          {:noreply, fun.(socket, page, state)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def update_page_state(socket, page_id, fun) do
    current_state = page_state(socket, page_id)
    next_state = fun.(current_state)

    Phoenix.Component.assign(
      socket,
      :page_states,
      Map.put(socket.assigns.page_states, page_id, next_state)
    )
  end

  def drop_page_state(page_states, page_id), do: Map.delete(page_states, page_id)

  defp flatten_nodes_for_fronts(nodes) do
    nodes
    |> List.wrap()
    |> Enum.flat_map(fn node -> [node | flatten_nodes_for_fronts(node["children"] || [])] end)
  end
end
