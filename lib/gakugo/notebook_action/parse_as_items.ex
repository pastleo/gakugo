defmodule Gakugo.NotebookAction.ParseAsItems do
  @moduledoc false

  alias Gakugo.Notebook.Outline
  alias Gakugo.Notebook.UnitSession

  defstruct [:unit_id, :page_id, :item_id, :insertion_mode]

  def perform(unit_id, page_id, item_id, insertion_mode)
      when is_integer(unit_id) and is_integer(page_id) and is_binary(item_id) do
    with snapshot <- UnitSession.snapshot(unit_id),
         page when not is_nil(page) <- find_page(snapshot, page_id),
         source when not is_nil(source) <- Enum.find(page.items, &(&1["id"] == item_id)),
         {:ok, parsed_items} <- parse_source_item(source, insertion_mode),
         {:ok, insert_after_item_id} <- insert_after_item_id(page.items, item_id) do
      if parsed_items == [] do
        {:ok, %{status: "noop"}}
      else
        intent = %{
          "scope" => "page_content",
          "action" => "insert_many_after",
          "target" => %{"page_id" => page.id, "item_id" => insert_after_item_id},
          "version" => %{"local" => page.version},
          "nodes" => page.items,
          "payload" => %{"items" => parsed_items}
        }

        UnitSession.apply_intent(unit_id, "api", intent)
      end
    else
      _ -> {:error, :invalid_params}
    end
  end

  def parse(text, base_depth \\ 0)

  def parse(text, base_depth)
      when is_binary(text) and is_integer(base_depth) and base_depth >= 0 do
    with {:ok, document} <- parse_document(text) do
      items = document.nodes |> nodes_to_items() |> rebase_items(base_depth)

      case items do
        [] -> {:ok, []}
        _ -> {:ok, Outline.normalize_items(items)}
      end
    end
  rescue
    _ -> :error
  end

  def parse(_text, _base_depth), do: :error

  defp find_page(snapshot, page_id) do
    Enum.find(snapshot.unit.pages, &(&1.id == page_id))
  end

  defp parse_document(text) do
    {:ok, MDEx.parse_document!(text, plugins: [MDExGFM])}
  rescue
    _ -> :error
  end

  defp nodes_to_items(nodes) do
    Enum.flat_map(List.wrap(nodes), &node_to_items(&1, 0))
  end

  defp node_to_items(%MDEx.Paragraph{nodes: nodes}, depth) do
    case inline_markdown(nodes) do
      "" -> []
      text -> [%{"text" => text, "depth" => depth}]
    end
  end

  defp node_to_items(%MDEx.Heading{nodes: nodes, level: level}, depth) do
    text =
      [String.duplicate("#", level), inline_markdown(nodes)] |> Enum.join(" ") |> String.trim()

    case text do
      "" -> []
      _ -> [%{"text" => text, "depth" => depth}]
    end
  end

  defp node_to_items(%MDEx.BlockQuote{nodes: nodes}, depth) do
    nodes_to_items(nodes) |> rebase_items(depth)
  end

  defp node_to_items(%MDEx.CodeBlock{literal: literal, info: info}, depth) do
    [%{"text" => fenced_code_text(literal || "", info || ""), "depth" => depth}]
  end

  defp node_to_items(%MDEx.List{nodes: nodes}, depth) do
    Enum.flat_map(List.wrap(nodes), &list_item_to_items(&1, depth))
  end

  defp node_to_items(%MDEx.ThematicBreak{}, depth), do: [%{"text" => "---", "depth" => depth}]
  defp node_to_items(%MDEx.LineBreak{}, _depth), do: []
  defp node_to_items(_node, _depth), do: []

  defp list_item_to_items(%MDEx.ListItem{nodes: nodes}, depth),
    do: list_item_nodes_to_items(nodes, depth)

  defp list_item_to_items(%MDEx.TaskItem{nodes: nodes}, depth),
    do: list_item_nodes_to_items(nodes, depth)

  defp list_item_to_items(_node, _depth), do: []

  defp list_item_nodes_to_items(nodes, depth) do
    nodes = List.wrap(nodes)

    case Enum.find_index(nodes, &textual_block?/1) do
      nil ->
        [%{"text" => "", "depth" => depth} | Enum.flat_map(nodes, &node_to_items(&1, depth + 1))]

      index ->
        current_item = node_to_items(Enum.at(nodes, index), depth)
        child_nodes = Enum.drop(nodes, index + 1)
        current_item ++ Enum.flat_map(child_nodes, &node_to_items(&1, depth + 1))
    end
  end

  defp textual_block?(%MDEx.Paragraph{}), do: true
  defp textual_block?(%MDEx.Heading{}), do: true
  defp textual_block?(%MDEx.CodeBlock{}), do: true
  defp textual_block?(%MDEx.ThematicBreak{}), do: true
  defp textual_block?(_), do: false

  defp rebase_items(items, depth_offset) when is_list(items) do
    Enum.map(items, fn item -> Map.update!(item, "depth", &(&1 + depth_offset)) end)
  end

  defp inline_markdown(nodes) do
    nodes
    |> List.wrap()
    |> Enum.map_join("", &inline_node_markdown/1)
    |> String.trim()
  end

  defp inline_node_markdown(%MDEx.Text{literal: literal}), do: literal || ""
  defp inline_node_markdown(%MDEx.Code{literal: literal}), do: "`#{literal || ""}`"
  defp inline_node_markdown(%MDEx.Strong{nodes: nodes}), do: "**#{inline_markdown(nodes)}**"
  defp inline_node_markdown(%MDEx.Emph{nodes: nodes}), do: "*#{inline_markdown(nodes)}*"

  defp inline_node_markdown(%MDEx.Strikethrough{nodes: nodes}),
    do: "~~#{inline_markdown(nodes)}~~"

  defp inline_node_markdown(%MDEx.Link{} = link) do
    nodes = Map.get(link, :nodes, [])
    destination = Map.get(link, :destination, Map.get(link, :url, ""))
    title = Map.get(link, :title, "")

    label = inline_markdown(nodes)
    title_part = if is_binary(title) and title != "", do: ~s( "#{title}"), else: ""
    "[#{label}](#{destination || ""}#{title_part})"
  end

  defp inline_node_markdown(%MDEx.SoftBreak{}), do: " "
  defp inline_node_markdown(%MDEx.LineBreak{}), do: "  \n"
  defp inline_node_markdown(_), do: ""

  defp fenced_code_text(literal, info) do
    opening = if info == "", do: "```", else: "```#{info}"
    [opening, literal, "```"] |> Enum.join("\n") |> String.trim_trailing()
  end

  defp parse_source_item(source, insertion_mode) when is_map(source) do
    text = Map.get(source, "text", "")
    depth = Outline.item_depth(source)

    case insertion_mode do
      "next_siblings" -> parse(text, depth)
      "children" -> parse(text, depth + 1)
      _ -> :error
    end
  end

  defp parse_source_item(_source, _insertion_mode), do: :error

  defp insert_after_item_id(items, item_id) do
    case Outline.path_for_id(items, item_id) do
      [index] ->
        case subtree_end_index(items, index) do
          ^index -> {:ok, item_id}
          end_index -> {:ok, Enum.at(items, end_index)["id"]}
        end

      _ ->
        :error
    end
  end

  defp subtree_end_index(items, index) do
    case Enum.at(items, index) do
      nil ->
        index

      item ->
        depth = Outline.item_depth(item)

        items
        |> Enum.drop(index + 1)
        |> Enum.take_while(&(Outline.item_depth(&1) > depth))
        |> length()
        |> Kernel.+(index)
    end
  end
end
