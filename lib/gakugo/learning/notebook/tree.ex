defmodule Gakugo.Learning.Notebook.Tree do
  def new_node do
    %{
      "id" => Ecto.UUID.generate(),
      "text" => "",
      "front" => false,
      "answer" => false,
      "link" => "",
      "children" => []
    }
  end

  def normalize_nodes(nodes) when is_list(nodes) do
    cleaned = Enum.map(nodes, &normalize_node(&1, false))
    if cleaned == [], do: [new_node()], else: cleaned
  end

  def normalize_nodes(_), do: [new_node()]

  def get_node(nodes, [idx]), do: Enum.at(nodes, idx)

  def get_node(nodes, [idx | rest]) do
    case Enum.at(nodes, idx) do
      nil -> nil
      node -> get_node(node["children"] || [], rest)
    end
  end

  def sibling_path(path) do
    List.replace_at(path, length(path) - 1, List.last(path) + 1)
  end

  def apply_inline_text(nodes, _indexes, nil), do: nodes

  def apply_inline_text(nodes, indexes, text) do
    nodes
    |> update_node(indexes, fn node -> Map.put(node, "text", text) end)
    |> normalize_nodes()
  end

  def outdent_node(nodes, path) do
    node = get_node(nodes, path)
    parent_path = Enum.drop(path, -1)
    grandparent_path = Enum.drop(path, -2)
    parent_idx = Enum.at(path, -2)

    nodes =
      nodes
      |> delete_node(path)
      |> insert_sibling(parent_path, node)
      |> normalize_nodes()

    focus_path = grandparent_path ++ [parent_idx + 1]
    {nodes, focus_path}
  end

  def indent_node(nodes, path) when is_list(path) do
    current_idx = List.last(path)

    if current_idx <= 0 do
      :noop
    else
      previous_sibling_path = List.replace_at(path, length(path) - 1, current_idx - 1)
      node = get_node(nodes, path)

      if is_nil(node) do
        :noop
      else
        nodes_after_delete = delete_node(nodes, path)
        previous_sibling = get_node(nodes_after_delete, previous_sibling_path)

        if is_nil(previous_sibling) do
          :noop
        else
          next_child_idx = length(previous_sibling["children"] || [])

          nodes_after_indent =
            update_node(nodes_after_delete, previous_sibling_path, fn sibling ->
              children = sibling["children"] || []
              Map.put(sibling, "children", children ++ [node])
            end)

          {:ok, normalize_nodes(nodes_after_indent), previous_sibling_path ++ [next_child_idx]}
        end
      end
    end
  end

  def node_count(nodes), do: length(depth_first_paths(nodes))

  def previous_path(nodes, current_path) do
    paths = depth_first_paths(nodes)

    case Enum.find_index(paths, fn path -> path == current_path end) do
      nil -> List.first(paths) || [0]
      0 -> List.first(paths) || [0]
      index -> Enum.at(paths, index - 1)
    end
  end

  def path_for_id(nodes, node_id) when is_binary(node_id) and node_id != "" do
    do_path_for_id(nodes, node_id, [])
  end

  def path_for_id(_, _), do: nil

  def can_indent_path?(path), do: List.last(path) > 0

  def can_outdent_path?(path), do: length(path) > 1

  def extract_node(nodes, path) when is_list(path) do
    case get_node(nodes, path) do
      nil -> :error
      node -> {:ok, node, delete_node(nodes, path)}
    end
  end

  def extract_node(_nodes, _path), do: :error

  def insert_node(nodes, parent_path, index, node)
      when is_list(parent_path) and is_integer(index) and index >= 0 and is_map(node) do
    case insert_node_at_path(nodes, parent_path, index, node) do
      {:ok, next_nodes, inserted_index} ->
        focus_path = parent_path ++ [inserted_index]
        {:ok, normalize_nodes(next_nodes), focus_path}

      :error ->
        :error
    end
  end

  def insert_node(_nodes, _parent_path, _index, _node), do: :error

  def move_node(nodes, source_path, nil, :root_end) when is_list(source_path) do
    with {:ok, node, nodes_without_source} <- extract_node(nodes, source_path),
         {:ok, next_nodes, focus_path} <-
           insert_node(nodes_without_source, [], length(nodes_without_source), node) do
      {:ok, next_nodes, focus_path}
    else
      :error -> :error
    end
  end

  def move_node(nodes, source_path, destination_path, position)
      when is_list(source_path) and is_list(destination_path) do
    with {:ok, parent_path, insertion_index} <-
           destination_parent_and_index(nodes, destination_path, position),
         false <- same_or_descendant_path?(source_path, destination_path),
         {:ok, node, nodes_without_source} <- extract_node(nodes, source_path),
         {:ok, adjusted_parent_path} <- adjust_parent_path_after_delete(parent_path, source_path),
         adjusted_index <- adjust_insertion_index(insertion_index, parent_path, source_path),
         {:ok, next_nodes, focus_path} <-
           insert_node(nodes_without_source, adjusted_parent_path, adjusted_index, node) do
      {:ok, next_nodes, focus_path}
    else
      true -> :noop
      :error -> :error
    end
  end

  def move_node(_nodes, _source_path, _destination_path, _position), do: :error

  def update_node(nodes, [idx], fun), do: List.update_at(nodes, idx, fun)

  def update_node(nodes, [idx | rest], fun) do
    List.update_at(nodes, idx, fn node ->
      children = update_node(node["children"] || [], rest, fun)
      Map.put(node, "children", children)
    end)
  end

  def insert_sibling(nodes, [idx], new_node), do: List.insert_at(nodes, idx + 1, new_node)

  def insert_sibling(nodes, [idx | rest], new_node) do
    List.update_at(nodes, idx, fn node ->
      children = insert_sibling(node["children"] || [], rest, new_node)
      Map.put(node, "children", children)
    end)
  end

  def delete_node(nodes, [idx]), do: List.delete_at(nodes, idx)

  def delete_node(nodes, [idx | rest]) do
    List.update_at(nodes, idx, fn node ->
      children = delete_node(node["children"] || [], rest)
      Map.put(node, "children", children)
    end)
  end

  def path_under_front?(nodes, indexes) when is_list(indexes) do
    indexes
    |> ancestor_paths()
    |> Enum.any?(fn path ->
      case get_node(nodes, path) do
        %{"front" => true} -> true
        _ -> false
      end
    end)
  end

  def path_under_front?(_, _), do: false

  def has_front_descendant?(%{"children" => children}) when is_list(children) do
    Enum.any?(children, fn child ->
      child["front"] or has_front_descendant?(child)
    end)
  end

  def has_front_descendant?(%{children: children}) when is_list(children) do
    Enum.any?(children, fn child ->
      child["front"] or has_front_descendant?(child)
    end)
  end

  def has_front_descendant?(_), do: false

  defp depth_first_paths(nodes), do: depth_first_paths(nodes, [])

  defp do_path_for_id(nodes, node_id, prefix) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce_while(nil, fn {node, idx}, _acc ->
      path = prefix ++ [idx]

      cond do
        node_id_value(node) == node_id ->
          {:halt, path}

        true ->
          case do_path_for_id(normalize_node_children(node), node_id, path) do
            nil -> {:cont, nil}
            found_path -> {:halt, found_path}
          end
      end
    end)
  end

  defp normalize_node_children(%{"children" => children}) when is_list(children), do: children
  defp normalize_node_children(%{children: children}) when is_list(children), do: children
  defp normalize_node_children(_), do: []

  defp depth_first_paths(nodes, prefix) do
    nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn {node, idx} ->
      path = prefix ++ [idx]
      [path | depth_first_paths(node["children"] || [], path)]
    end)
  end

  defp normalize_node(node, in_front_branch) do
    front = normalize_node_front(node) and not in_front_branch

    %{
      "id" => normalize_node_id(node),
      "text" => normalize_node_text(node),
      "front" => front,
      "answer" => normalize_node_answer(node),
      "link" => normalize_node_link(node),
      "children" => normalize_node_children(node, in_front_branch or front)
    }
  end

  defp normalize_node_text(%{"text" => text}) when is_binary(text), do: text
  defp normalize_node_text(%{text: text}) when is_binary(text), do: text
  defp normalize_node_text(_), do: ""

  defp normalize_node_id(%{"id" => id}) when is_binary(id) and id != "", do: id
  defp normalize_node_id(%{id: id}) when is_binary(id) and id != "", do: id
  defp normalize_node_id(_), do: Ecto.UUID.generate()

  defp node_id_value(%{"id" => id}) when is_binary(id) and id != "", do: id
  defp node_id_value(%{id: id}) when is_binary(id) and id != "", do: id
  defp node_id_value(_), do: nil

  defp normalize_node_front(%{"front" => front}) when is_boolean(front), do: front
  defp normalize_node_front(%{front: front}) when is_boolean(front), do: front
  defp normalize_node_front(_), do: false

  defp normalize_node_answer(%{"answer" => answer}) when is_boolean(answer), do: answer
  defp normalize_node_answer(%{answer: answer}) when is_boolean(answer), do: answer
  defp normalize_node_answer(_), do: false

  defp normalize_node_link(%{"link" => link}) when is_binary(link), do: String.trim(link)
  defp normalize_node_link(%{link: link}) when is_binary(link), do: String.trim(link)
  defp normalize_node_link(_), do: ""

  defp normalize_node_children(%{"children" => children}, in_front_branch) when is_list(children),
    do: Enum.map(children, &normalize_node(&1, in_front_branch))

  defp normalize_node_children(%{children: children}, in_front_branch) when is_list(children),
    do: Enum.map(children, &normalize_node(&1, in_front_branch))

  defp normalize_node_children(_, _), do: []

  defp ancestor_paths(indexes) when is_list(indexes) do
    indexes
    |> Enum.drop(-1)
    |> Enum.with_index(1)
    |> Enum.map(fn {_idx, length} -> Enum.take(indexes, length) end)
  end

  defp ancestor_paths(_), do: []

  defp insert_node_at_path(nodes, [], index, node) do
    safe_index = min(index, length(nodes))
    {:ok, List.insert_at(nodes, safe_index, node), safe_index}
  end

  defp insert_node_at_path(nodes, [idx | rest], index, node) do
    case Enum.at(nodes, idx) do
      nil ->
        :error

      current ->
        children = current["children"] || []

        case insert_node_at_path(children, rest, index, node) do
          {:ok, next_children, inserted_index} ->
            next_nodes =
              List.update_at(nodes, idx, fn current_node ->
                Map.put(current_node, "children", next_children)
              end)

            {:ok, next_nodes, inserted_index}

          :error ->
            :error
        end
    end
  end

  defp destination_parent_and_index(nodes, destination_path, :before) do
    case get_node(nodes, destination_path) do
      nil -> :error
      _node -> {:ok, Enum.drop(destination_path, -1), List.last(destination_path)}
    end
  end

  defp destination_parent_and_index(nodes, destination_path, :after) do
    case get_node(nodes, destination_path) do
      nil ->
        :error

      _node ->
        {:ok, Enum.drop(destination_path, -1), List.last(destination_path) + 1}
    end
  end

  defp destination_parent_and_index(nodes, destination_path, :inside) do
    case get_node(nodes, destination_path) do
      nil -> :error
      node -> {:ok, destination_path, length(node["children"] || [])}
    end
  end

  defp destination_parent_and_index(_nodes, _destination_path, _position), do: :error

  defp same_or_descendant_path?(source_path, destination_path) do
    source_length = length(source_path)

    source_length <= length(destination_path) and
      Enum.take(destination_path, source_length) == source_path
  end

  defp adjust_parent_path_after_delete(parent_path, source_path) do
    if same_or_descendant_path?(source_path, parent_path) do
      :error
    else
      {:ok,
       Enum.with_index(parent_path)
       |> Enum.map(fn {segment, idx} ->
         source_segment = Enum.at(source_path, idx)

         if idx < length(source_path) and segment > source_segment and
              Enum.take(parent_path, idx) == Enum.take(source_path, idx) do
           segment - 1
         else
           segment
         end
       end)}
    end
  end

  defp adjust_insertion_index(index, parent_path, source_path) do
    source_parent = Enum.drop(source_path, -1)
    source_index = List.last(source_path)

    if source_parent == parent_path and source_index < index do
      index - 1
    else
      index
    end
  end
end
