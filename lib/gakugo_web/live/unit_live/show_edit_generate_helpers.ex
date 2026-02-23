defmodule GakugoWeb.UnitLive.ShowEditGenerateHelpers do
  alias Gakugo.Learning.Notebook.Tree

  def random_deepest_grammar_branch(page_states, grammar_page_id) do
    state = Map.get(page_states, grammar_page_id)

    if is_nil(state) do
      {:error, :empty_grammar_page}
    else
      case deepest_branch_text(state.nodes) do
        nil -> {:error, :empty_grammar_page}
        branch_text -> {:ok, branch_text}
      end
    end
  end

  def normalize_translation_result(%{"translation_from" => from, "translation_target" => target})
      when is_binary(from) and is_binary(target) do
    translation_from = String.trim(from)
    translation_target = String.trim(target)

    if translation_from == "" or translation_target == "" do
      {:error, :empty_translation_result}
    else
      {:ok, translation_from, translation_target}
    end
  end

  def normalize_translation_result(_result), do: {:error, :invalid_translation_result}

  def translation_practice_node(translation_from, translation_target) do
    Tree.new_node()
    |> Map.put("text", translation_from)
    |> Map.put("front", true)
    |> Map.put("answer", false)
    |> Map.put("children", [
      Tree.new_node() |> Map.put("text", translation_target) |> Map.put("answer", true)
    ])
  end

  def build_insert_under_source_command(nodes, node_id, generated_node)
      when is_list(nodes) and is_binary(node_id) do
    case Tree.path_for_id(nodes, node_id) do
      nil ->
        :error

      parent_path ->
        parent_node = Tree.get_node(nodes, parent_path)
        insert_index = parent_node |> Map.get("children", []) |> length()

        {:ok,
         {:insert_node, %{"parent_path" => parent_path, "index" => insert_index}, generated_node}}
    end
  end

  def build_insert_under_source_command(_nodes, _node_id, _generated_node), do: :error

  defp deepest_branch_text(nodes) do
    candidates =
      nodes
      |> deepest_leaf_paths()
      |> Enum.map(&branch_text_for_path(nodes, &1))
      |> Enum.reject(&is_nil/1)

    case candidates do
      [] -> nil
      _ -> Enum.random(candidates)
    end
  end

  defp deepest_leaf_paths(nodes) do
    nodes
    |> deepest_leaf_paths([], [])
    |> Enum.group_by(&length/1)
    |> case do
      grouped when map_size(grouped) == 0 -> []
      grouped -> grouped |> Map.keys() |> Enum.max() |> then(&Map.get(grouped, &1, []))
    end
  end

  defp deepest_leaf_paths([], _path, acc), do: acc

  defp deepest_leaf_paths(nodes, path, acc) do
    Enum.reduce(Enum.with_index(nodes), acc, fn {node, idx}, nested_acc ->
      next_path = path ++ [idx]
      children = node["children"] || []

      if children == [] do
        [next_path | nested_acc]
      else
        deepest_leaf_paths(children, next_path, nested_acc)
      end
    end)
  end

  defp branch_text_for_path(nodes, leaf_path) do
    branch_lines =
      leaf_path
      |> Enum.with_index(1)
      |> Enum.map(fn {_idx, depth} -> Enum.take(leaf_path, depth) end)
      |> Enum.map(fn branch_path -> {length(branch_path), Tree.get_node(nodes, branch_path)} end)
      |> Enum.reduce([], fn
        {_depth, nil}, acc ->
          acc

        {depth, node}, acc ->
          text = String.trim(node["text"] || "")

          if text == "" do
            acc
          else
            ["#{String.duplicate("  ", depth - 1)}- #{text}" | acc]
          end
      end)
      |> Enum.reverse()

    case branch_lines do
      [] -> nil
      _ -> Enum.join(branch_lines, "\n")
    end
  end
end
