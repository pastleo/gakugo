defmodule Gakugo.Learning.Notebook.Editor do
  alias Gakugo.Learning.Notebook.Tree

  def apply(nodes, {:edit_text, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      {:ok,
       %{
         nodes:
           nodes |> Tree.update_node(path, &Map.put(&1, "text", text)) |> Tree.normalize_nodes(),
         focus_path: nil
       }}
    end
  end

  def apply(nodes, {:item_enter, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      nodes_with_latest_text = Tree.apply_inline_text(nodes, path, text)
      current = Tree.get_node(nodes_with_latest_text, path)

      {next_nodes, focus_path} =
        cond do
          is_nil(current) ->
            {nodes_with_latest_text, path}

          String.trim(current["text"] || "") == "" and length(path) > 1 ->
            Tree.outdent_node(nodes_with_latest_text, path)

          String.trim(current["text"] || "") == "" ->
            nodes = Tree.insert_sibling(nodes_with_latest_text, path, Tree.new_node())
            {Tree.normalize_nodes(nodes), Tree.sibling_path(path)}

          true ->
            insert_child_first(nodes_with_latest_text, path)
        end

      {:ok, %{nodes: next_nodes, focus_path: focus_path}}
    end
  end

  def apply(nodes, {:insert_child_first, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      nodes_with_latest_text = Tree.apply_inline_text(nodes, path, text)
      {next_nodes, focus_path} = insert_child_first(nodes_with_latest_text, path)
      {:ok, %{nodes: next_nodes, focus_path: focus_path}}
    end
  end

  def apply(nodes, {:insert_above, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      nodes_with_latest_text = Tree.apply_inline_text(nodes, path, text)
      focus_path = path

      {:ok,
       %{
         nodes:
           nodes_with_latest_text
           |> insert_at_path(path, Tree.new_node())
           |> Tree.normalize_nodes(),
         focus_path: focus_path
       }}
    end
  end

  def apply(nodes, {:insert_below, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      nodes_with_latest_text = Tree.apply_inline_text(nodes, path, text)
      focus_path = Tree.sibling_path(path)

      {:ok,
       %{
         nodes:
           nodes_with_latest_text
           |> Tree.insert_sibling(path, Tree.new_node())
           |> Tree.normalize_nodes(),
         focus_path: focus_path
       }}
    end
  end

  def apply(nodes, {:focus_previous_sibling, target}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      {:ok, %{nodes: nodes, focus_path: Tree.previous_visual_path(nodes, path)}}
    end
  end

  def apply(nodes, {:focus_first_child_or_next_sibling, target}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      {:ok, %{nodes: nodes, focus_path: Tree.first_child_or_next_available_path(nodes, path)}}
    end
  end

  def apply(nodes, {:item_delete_empty_backward, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      delete_empty_leaf(nodes, path, text, :backward)
    end
  end

  def apply(nodes, {:item_delete_empty_forward, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      delete_empty_leaf(nodes, path, text, :forward)
    end
  end

  def apply(nodes, {:item_delete_empty, target, text}) do
    __MODULE__.apply(nodes, {:item_delete_empty_backward, target, text})
  end

  def apply(nodes, {:item_empty_enter, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      nodes_with_latest_text = Tree.apply_inline_text(nodes, path, text)

      cond do
        length(path) > 1 and Tree.last_child_path?(nodes_with_latest_text, path) ->
          {next_nodes, focus_path} = Tree.outdent_node(nodes_with_latest_text, path)
          {:ok, %{nodes: next_nodes, focus_path: focus_path}}

        true ->
          focus_path = Tree.sibling_path(path)

          {:ok,
           %{
             nodes:
               nodes_with_latest_text
               |> Tree.insert_sibling(path, Tree.new_node())
               |> Tree.normalize_nodes(),
             focus_path: focus_path
           }}
      end
    end
  end

  def apply(nodes, {:toggle_flag, target, flag}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      {:ok,
       %{
         nodes:
           nodes
           |> Tree.update_node(path, fn node ->
             case flag do
               "front" ->
                 if Tree.path_under_front?(nodes, path) or Tree.has_front_descendant?(node) do
                   node
                 else
                   next_front = !node["front"]

                   node
                   |> Map.put("front", next_front)
                   |> Map.put("answer", if(next_front, do: node["answer"], else: false))
                 end

               "answer" ->
                 if node["front"] or Tree.path_under_front?(nodes, path) do
                   Map.put(node, "answer", !node["answer"])
                 else
                   node
                 end

               _ ->
                 node
             end
           end)
           |> Tree.normalize_nodes(),
         focus_path: nil
       }}
    end
  end

  def apply(nodes, {:item_indent, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      nodes_with_latest_text = Tree.apply_inline_text(nodes, path, text)

      case Tree.indent_node(nodes_with_latest_text, path) do
        {:ok, next_nodes, focus_path} ->
          {:ok, %{nodes: next_nodes, focus_path: focus_path}}

        :noop ->
          {:ok, %{nodes: nodes_with_latest_text, focus_path: nil}}
      end
    end
  end

  def apply(nodes, {:item_outdent, target, text}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      nodes_with_latest_text = Tree.apply_inline_text(nodes, path, text)

      if Tree.can_safe_outdent_path?(nodes_with_latest_text, path) do
        {next_nodes, focus_path} = Tree.outdent_node(nodes_with_latest_text, path)
        {:ok, %{nodes: next_nodes, focus_path: focus_path}}
      else
        {:ok, %{nodes: nodes_with_latest_text, focus_path: nil}}
      end
    end
  end

  def apply(nodes, {:add_child, target}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      {:ok,
       %{
         nodes:
           nodes
           |> Tree.update_node(path, fn node ->
             children = node["children"] || []
             Map.put(node, "children", children ++ [Tree.new_node()])
           end)
           |> Tree.normalize_nodes(),
         focus_path: nil
       }}
    end
  end

  def apply(nodes, {:add_sibling, target}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      {:ok,
       %{
         nodes: nodes |> Tree.insert_sibling(path, Tree.new_node()) |> Tree.normalize_nodes(),
         focus_path: nil
       }}
    end
  end

  def apply(nodes, {:remove_node, target}) do
    with {:ok, path} <- resolve_target_path(nodes, target) do
      {:ok,
       %{
         nodes: nodes |> Tree.delete_node(path) |> Tree.normalize_nodes(),
         focus_path: nil
       }}
    end
  end

  def apply(nodes, :append_root) do
    {:ok, %{nodes: Tree.normalize_nodes(nodes ++ [Tree.new_node()]), focus_path: nil}}
  end

  def apply(nodes, {:append_many, imported_nodes}) when is_list(imported_nodes) do
    if imported_nodes == [] do
      :noop
    else
      {:ok, %{nodes: Tree.normalize_nodes(nodes ++ imported_nodes), focus_path: nil}}
    end
  end

  def apply(nodes, {:insert_node, insertion_target, node}) when is_map(node) do
    with {:ok, parent_path, index} <- resolve_insertion_target(insertion_target),
         {:ok, next_nodes, focus_path} <- Tree.insert_node(nodes, parent_path, index, node) do
      {:ok, %{nodes: next_nodes, focus_path: focus_path}}
    else
      :error -> :error
    end
  end

  def apply(nodes, {:move_node, source_target, destination_target}) do
    with {:ok, source_path} <- resolve_target_path(nodes, source_target),
         {:ok, destination_path, position} <-
           resolve_move_destination(nodes, destination_target),
         result <- Tree.move_node(nodes, source_path, destination_path, position) do
      case result do
        {:ok, next_nodes, focus_path} -> {:ok, %{nodes: next_nodes, focus_path: focus_path}}
        :noop -> :noop
        :error -> :error
      end
    else
      :error -> :error
    end
  end

  defp resolve_target_path(_nodes, path) when is_list(path), do: {:ok, path}

  defp resolve_target_path(nodes, %{"node_id" => node_id, "path" => path})
       when is_binary(node_id) and node_id != "" do
    case Tree.path_for_id(nodes, node_id) do
      nil -> resolve_target_path(nodes, path)
      indexes -> {:ok, indexes}
    end
  end

  defp resolve_target_path(nodes, %{node_id: node_id, path: path})
       when is_binary(node_id) and node_id != "" do
    case Tree.path_for_id(nodes, node_id) do
      nil -> resolve_target_path(nodes, path)
      indexes -> {:ok, indexes}
    end
  end

  defp resolve_target_path(nodes, %{"node_id" => node_id})
       when is_binary(node_id) and node_id != "" do
    case Tree.path_for_id(nodes, node_id) do
      nil -> :error
      indexes -> {:ok, indexes}
    end
  end

  defp resolve_target_path(nodes, %{node_id: node_id})
       when is_binary(node_id) and node_id != "" do
    case Tree.path_for_id(nodes, node_id) do
      nil -> :error
      indexes -> {:ok, indexes}
    end
  end

  defp resolve_target_path(_nodes, path) when is_binary(path), do: {:ok, parse_path(path)}

  defp resolve_target_path(_nodes, %{"path" => path}) when is_binary(path),
    do: {:ok, parse_path(path)}

  defp resolve_target_path(_nodes, %{path: path}) when is_binary(path),
    do: {:ok, parse_path(path)}

  defp resolve_target_path(_nodes, _), do: :error

  defp insert_child_first(nodes, path) do
    child_path = path ++ [0]

    nodes =
      nodes
      |> Tree.update_node(path, fn node ->
        children = node["children"] || []
        Map.put(node, "children", [Tree.new_node() | children])
      end)
      |> Tree.normalize_nodes()

    {nodes, child_path}
  end

  defp delete_empty_leaf(nodes, path, text, direction) do
    nodes_with_latest_text = Tree.apply_inline_text(nodes, path, text)
    current = Tree.get_node(nodes_with_latest_text, path)

    cond do
      Tree.node_count(nodes_with_latest_text) <= 1 ->
        :noop

      not is_map(current) ->
        :noop

      String.trim(current["text"] || "") != "" ->
        :noop

      (current["children"] || []) != [] ->
        :noop

      true ->
        focus_target_path =
          case direction do
            :forward ->
              Tree.next_sibling_or_ancestor_next_sibling_path(nodes_with_latest_text, path)

            :backward ->
              Tree.previous_sibling_or_parent_path(path)
          end

        focus_target_id =
          case focus_target_path && Tree.get_node(nodes_with_latest_text, focus_target_path) do
            %{"id" => id} -> id
            _ -> nil
          end

        nodes =
          nodes_with_latest_text
          |> Tree.delete_node(path)
          |> Tree.normalize_nodes()

        focus_path =
          cond do
            is_binary(focus_target_id) -> Tree.path_for_id(nodes, focus_target_id)
            true -> focus_target_path
          end

        {:ok, %{nodes: nodes, focus_path: focus_path}}
    end
  end

  defp insert_at_path(nodes, [idx], node), do: List.insert_at(nodes, idx, node)

  defp insert_at_path(nodes, [idx | rest], node) do
    List.update_at(nodes, idx, fn current ->
      children = insert_at_path(current["children"] || [], rest, node)
      Map.put(current, "children", children)
    end)
  end

  defp resolve_insertion_target(%{"parent_path" => parent_path, "index" => index}) do
    with {:ok, parsed_parent_path} <- parse_non_negative_path(parent_path),
         {:ok, parsed_index} <- parse_non_negative_integer(index) do
      {:ok, parsed_parent_path, parsed_index}
    else
      _ -> :error
    end
  end

  defp resolve_insertion_target(%{parent_path: parent_path, index: index}) do
    with {:ok, parsed_parent_path} <- parse_non_negative_path(parent_path),
         {:ok, parsed_index} <- parse_non_negative_integer(index) do
      {:ok, parsed_parent_path, parsed_index}
    else
      _ -> :error
    end
  end

  defp resolve_insertion_target(_), do: :error

  defp resolve_move_destination(_nodes, %{"position" => "root_end"}) do
    {:ok, nil, :root_end}
  end

  defp resolve_move_destination(_nodes, %{position: "root_end"}) do
    {:ok, nil, :root_end}
  end

  defp resolve_move_destination(nodes, %{"position" => position, "target" => target}) do
    with {:ok, target_path} <- resolve_target_path(nodes, target),
         {:ok, parsed_position} <- parse_move_position(position) do
      {:ok, target_path, parsed_position}
    else
      _ -> :error
    end
  end

  defp resolve_move_destination(nodes, %{position: position, target: target}) do
    with {:ok, target_path} <- resolve_target_path(nodes, target),
         {:ok, parsed_position} <- parse_move_position(position) do
      {:ok, target_path, parsed_position}
    else
      _ -> :error
    end
  end

  defp resolve_move_destination(_nodes, _), do: :error

  defp parse_move_position("before"), do: {:ok, :before}
  defp parse_move_position("after"), do: {:ok, :after}
  defp parse_move_position("inside"), do: {:ok, :inside}
  defp parse_move_position(_), do: :error

  defp parse_non_negative_path(path) when is_list(path) do
    if Enum.all?(path, &(is_integer(&1) and &1 >= 0)), do: {:ok, path}, else: :error
  end

  defp parse_non_negative_path(path) when is_binary(path), do: {:ok, parse_path(path)}
  defp parse_non_negative_path(_path), do: :error

  defp parse_non_negative_integer(index) when is_integer(index) and index >= 0, do: {:ok, index}

  defp parse_non_negative_integer(index) when is_binary(index) do
    case Integer.parse(index) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_non_negative_integer(_index), do: :error

  defp parse_path(path) do
    path
    |> String.split(".", trim: true)
    |> Enum.map(&String.to_integer/1)
  end
end
