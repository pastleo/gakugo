defmodule GakugoWeb.UnitLive.ShowEditFormHelpers do
  alias Gakugo.Learning.Notebook.Tree
  alias GakugoWeb.UnitLive.ShowEditHelpers

  def drawer_title("options"), do: "Unit options"
  def drawer_title("import"), do: "Import"
  def drawer_title("generate"), do: "Generate"
  def drawer_title(_), do: "Flashcards"

  def page_options(assigns) do
    Enum.map(assigns.unit.pages, fn page ->
      state = ShowEditHelpers.page_state(assigns, page.id)
      {state.title, to_string(page.id)}
    end)
  end

  def generate_output_mode_options(nil), do: [{"Append to page root", "page_root"}]

  def generate_output_mode_options(_source_item_label) do
    [
      {"Under source item", "source_item"},
      {"Append to page root", "page_root"}
    ]
  end

  def generate_source_item_label(assigns) do
    source_item = Map.get(assigns, :generate_source_item)

    with %{page_id: page_id, node_id: node_id} <- source_item,
         state when not is_nil(state) <- Map.get(assigns.page_states, page_id),
         path when is_list(path) <- Tree.path_for_id(state.nodes, node_id),
         node when not is_nil(node) <- Tree.get_node(state.nodes, path) do
      text = String.trim(node["text"] || "")
      if(text == "", do: "(empty item)", else: text)
    else
      _ -> nil
    end
  end

  def generate_output_hint(assigns) do
    output_mode = assigns.generate_values["output_mode"]

    case output_mode do
      "source_item" ->
        source_label = Map.get(assigns, :generate_source_item_label)

        if is_binary(source_label) do
          "Will insert under source item: #{source_label}"
        else
          "Will append to selected page root"
        end

      _ ->
        page_id = assigns.generate_values["output_page_id"]

        case page_title_by_id(assigns, page_id) do
          nil -> "Will append to selected page root"
          title -> "Will append to page root: #{title}"
        end
    end
  end

  def assign_import_values(socket, params) when is_map(params) do
    current = socket.assigns.import_values

    next_values = %{
      "type" => Map.get(params, "type", current["type"]),
      "source" => Map.get(params, "source", current["source"]),
      "ai_model" => Map.get(params, "ai_model", current["ai_model"]),
      "ocr_model" => Map.get(params, "ocr_model", current["ocr_model"]),
      "page_id" =>
        normalize_import_page_id(socket, Map.get(params, "page_id", current["page_id"]))
    }

    socket
    |> Phoenix.Component.assign(:import_values, next_values)
    |> Phoenix.Component.assign(:import_form, Phoenix.Component.to_form(next_values, as: :import))
  end

  def assign_import_values(socket, _params), do: socket

  def sync_import_page_selection(socket, unit) do
    page_id = normalize_import_page_id(socket, socket.assigns.import_values["page_id"], unit)
    assign_import_values(socket, %{"page_id" => page_id})
  end

  def selected_import_page_id(socket) do
    socket
    |> normalize_import_page_id(socket.assigns.import_values["page_id"])
    |> String.to_integer()
  end

  def assign_generate_values(socket, params) when is_map(params) do
    current = socket.assigns.generate_values
    source_item = socket.assigns.generate_source_item

    next_values = %{
      "type" => Map.get(params, "type", current["type"]),
      "vocabulary" => Map.get(params, "vocabulary", current["vocabulary"]),
      "ai_model" => Map.get(params, "ai_model", current["ai_model"]),
      "grammar_page_id" =>
        normalize_generate_grammar_page_id(
          socket,
          Map.get(params, "grammar_page_id", current["grammar_page_id"])
        ),
      "output_mode" =>
        normalize_generate_output_mode(
          Map.get(params, "output_mode", current["output_mode"]),
          source_item
        ),
      "output_page_id" =>
        normalize_generate_output_page_id(
          socket,
          Map.get(params, "output_page_id", current["output_page_id"])
        )
    }

    socket
    |> Phoenix.Component.assign(:generate_values, next_values)
    |> Phoenix.Component.assign(
      :generate_form,
      Phoenix.Component.to_form(next_values, as: :generate)
    )
  end

  def assign_generate_values(socket, _params), do: socket

  def sync_generate_page_selection(socket, unit) do
    grammar_page_id =
      normalize_generate_grammar_page_id(
        socket,
        socket.assigns.generate_values["grammar_page_id"],
        unit
      )

    output_page_id =
      normalize_generate_output_page_id(
        socket,
        socket.assigns.generate_values["output_page_id"],
        unit
      )

    assign_generate_values(socket, %{
      "grammar_page_id" => grammar_page_id,
      "output_page_id" => output_page_id
    })
  end

  def selected_generate_grammar_page_id(socket) do
    socket
    |> normalize_generate_grammar_page_id(socket.assigns.generate_values["grammar_page_id"])
    |> String.to_integer()
    |> then(&{:ok, &1})
  end

  def selected_generate_output_page_id(socket) do
    socket
    |> normalize_generate_output_page_id(socket.assigns.generate_values["output_page_id"])
    |> String.to_integer()
    |> then(&{:ok, &1})
  end

  def normalize_generate_output_mode(mode, source_item) when is_binary(mode) do
    normalized_mode = if mode == "source_item", do: "source_item", else: "page_root"

    if normalized_mode == "source_item" and is_nil(source_item) do
      "page_root"
    else
      normalized_mode
    end
  end

  def normalize_generate_output_mode(_mode, source_item) do
    if is_map(source_item), do: "source_item", else: "page_root"
  end

  def normalize_import_page_id(socket, page_id, unit \\ nil) do
    target_unit = if(is_nil(unit), do: socket.assigns.unit, else: unit)
    normalize_page_id_for_unit(target_unit, page_id)
  end

  def normalize_generate_grammar_page_id(socket, page_id, unit \\ nil) do
    target_unit = if(is_nil(unit), do: socket.assigns.unit, else: unit)
    normalize_page_id_for_unit(target_unit, page_id)
  end

  def normalize_generate_output_page_id(socket, page_id, unit \\ nil) do
    target_unit = if(is_nil(unit), do: socket.assigns.unit, else: unit)
    normalize_page_id_for_unit(target_unit, page_id)
  end

  defp page_title_by_id(assigns, page_id) do
    with {:ok, parsed_page_id} <- parse_page_id(page_id),
         page when not is_nil(page) <- ShowEditHelpers.page_by_id(assigns.unit, parsed_page_id) do
      ShowEditHelpers.page_state(assigns, page.id).title
    else
      _ -> nil
    end
  end

  defp normalize_page_id_for_unit(unit, page_id) do
    case parse_page_id(page_id) do
      {:ok, parsed_page_id} ->
        if Enum.any?(unit.pages, fn page -> page.id == parsed_page_id end) do
          to_string(parsed_page_id)
        else
          to_string(ShowEditHelpers.default_page_id_from_unit(unit))
        end

      :error ->
        to_string(ShowEditHelpers.default_page_id_from_unit(unit))
    end
  end

  defp parse_page_id(page_id) when is_integer(page_id), do: {:ok, page_id}

  defp parse_page_id(page_id) when is_binary(page_id) do
    case Integer.parse(page_id) do
      {parsed_page_id, ""} -> {:ok, parsed_page_id}
      _ -> :error
    end
  end

  defp parse_page_id(_page_id), do: :error
end
