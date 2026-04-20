defmodule Gakugo.Notebook.Editor do
  import Kernel, except: [apply: 2]

  alias Gakugo.Notebook.Item.YStateAsUpdate
  alias Gakugo.Notebook.Outline

  def apply(items, {:set_text, target, text}) do
    with {:ok, index} <- resolve_target_index(items, target),
         normalized_items <- Outline.normalize_items(items),
         item when is_map(item) <- Enum.at(normalized_items, index),
         updated_item <- set_item_text(item, text),
         {:ok, next_items} <-
           Outline.validate_items(List.replace_at(normalized_items, index, updated_item)) do
      {:ok, %{nodes: next_items, focus_path: nil}}
    end
  end

  def apply(items, {:toggle_flag, target, flag}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, next_items} <- update_item(items, index, &toggle_item_flag(&1, flag)) do
      {:ok, %{nodes: next_items, focus_path: nil}}
    end
  end

  def apply(items, {:set_item_text_color, target, color}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, next_items} <- update_item(items, index, &Map.put(&1, "textColor", color)) do
      {:ok, %{nodes: next_items, focus_path: nil}}
    end
  end

  def apply(items, {:set_item_background_color, target, color}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, next_items} <- update_item(items, index, &Map.put(&1, "backgroundColor", color)) do
      {:ok, %{nodes: next_items, focus_path: nil}}
    end
  end

  def apply(items, {:text_collab_update, target, payload}) do
    with {:ok, index} <- resolve_target_index(items, target),
         normalized_items <- Outline.normalize_items(items),
         item when is_map(item) <- Enum.at(normalized_items, index),
         {:ok, merged_item} <- apply_text_collab_update(item, payload),
         {:ok, next_items} <-
           Outline.validate_items(List.replace_at(normalized_items, index, merged_item)) do
      {:ok, %{nodes: next_items, focus_path: nil, updated_item: merged_item}}
    else
      _ -> :error
    end
  end

  def apply(items, {:insert_above, target, text}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, synced_items} <- update_item(items, index, &Map.put(&1, "text", text)),
         current_item when is_map(current_item) <- Enum.at(synced_items, index),
         inserted_item <- Outline.new_item() |> Map.put("depth", current_item["depth"]),
         {:ok, next_items} <- insert_item_at(synced_items, index, inserted_item) do
      {:ok, %{nodes: next_items, focus_path: [index]}}
    end
  end

  def apply(items, {:insert_below, target, text}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, synced_items} <- update_item(items, index, &Map.put(&1, "text", text)),
         current_item when is_map(current_item) <- Enum.at(synced_items, index),
         inserted_item <- Outline.new_item() |> Map.put("depth", current_item["depth"]),
         insert_at <- index + 1,
         {:ok, next_items} <- insert_item_at(synced_items, insert_at, inserted_item) do
      {:ok, %{nodes: next_items, focus_path: [insert_at]}}
    end
  end

  def apply(items, {:insert_child_below, target, text}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, synced_items} <- update_item(items, index, &Map.put(&1, "text", text)),
         current_item when is_map(current_item) <- Enum.at(synced_items, index),
         inserted_item <- Outline.new_item() |> Map.put("depth", current_item["depth"] + 1),
         insert_at <- index + 1,
         {:ok, next_items} <- insert_item_at(synced_items, insert_at, inserted_item) do
      {:ok, %{nodes: next_items, focus_path: [insert_at]}}
    end
  end

  def apply(items, {:item_indent, target, text}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, synced_items} <- update_item(items, index, &Map.put(&1, "text", text)) do
      cond do
        index <= 0 ->
          {:ok, %{nodes: synced_items, focus_path: nil}}

        true ->
          previous_depth = synced_items |> Enum.at(index - 1) |> Outline.item_depth()
          current_depth = synced_items |> Enum.at(index) |> Outline.item_depth()

          if current_depth >= previous_depth + 1 do
            {:ok, %{nodes: synced_items, focus_path: nil}}
          else
            {:ok, next_items} =
              update_item(synced_items, index, &Map.put(&1, "depth", current_depth + 1))

            {:ok, %{nodes: next_items, focus_path: [index]}}
          end
      end
    end
  end

  def apply(items, {:item_outdent, target, text}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, synced_items} <- update_item(items, index, &Map.put(&1, "text", text)) do
      current_depth = synced_items |> Enum.at(index) |> Outline.item_depth()

      if current_depth <= 0 do
        {:ok, %{nodes: synced_items, focus_path: nil}}
      else
        case update_item(synced_items, index, &Map.put(&1, "depth", current_depth - 1)) do
          {:ok, next_items} -> {:ok, %{nodes: next_items, focus_path: [index]}}
          :error -> :error
        end
      end
    end
  end

  def apply(items, {:indent_subtree, target, text}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, synced_items} <- update_item(items, index, &Map.put(&1, "text", text)) do
      cond do
        index <= 0 ->
          {:ok, %{nodes: synced_items, focus_path: nil}}

        true ->
          previous_depth = synced_items |> Enum.at(index - 1) |> Outline.item_depth()
          current_depth = synced_items |> Enum.at(index) |> Outline.item_depth()

          if current_depth >= previous_depth + 1 do
            {:ok, %{nodes: synced_items, focus_path: nil}}
          else
            case shift_subtree_depth_at_index(synced_items, index, 1) do
              {:ok, next_items} -> {:ok, %{nodes: next_items, focus_path: [index]}}
              :error -> :error
            end
          end
      end
    end
  end

  def apply(items, {:outdent_subtree, target, text}) do
    with {:ok, index} <- resolve_target_index(items, target),
         {:ok, synced_items} <- update_item(items, index, &Map.put(&1, "text", text)) do
      current_depth = synced_items |> Enum.at(index) |> Outline.item_depth()

      if current_depth <= 0 do
        {:ok, %{nodes: synced_items, focus_path: nil}}
      else
        case shift_subtree_depth_at_index(synced_items, index, -1) do
          {:ok, next_items} -> {:ok, %{nodes: next_items, focus_path: [index]}}
          :error -> :error
        end
      end
    end
  end

  def apply(items, {:add_child, target}) do
    with {:ok, index} <- resolve_target_index(items, target),
         current_item when is_map(current_item) <- Enum.at(Outline.normalize_items(items), index),
         inserted_item <- Outline.new_item() |> Map.put("depth", current_item["depth"] + 1),
         {:ok, next_items} <- insert_item_at(items, index + 1, inserted_item) do
      {:ok, %{nodes: next_items, focus_path: [index + 1]}}
    end
  end

  def apply(items, {:add_sibling, target}) do
    with {:ok, index} <- resolve_target_index(items, target),
         current_item when is_map(current_item) <- Enum.at(Outline.normalize_items(items), index),
         inserted_item <- Outline.new_item() |> Map.put("depth", current_item["depth"]),
         {:ok, next_items} <- insert_item_at(items, index + 1, inserted_item) do
      {:ok, %{nodes: next_items, focus_path: [index + 1]}}
    end
  end

  def apply(items, {:remove_item, target}) do
    with {:ok, index} <- resolve_target_index(items, target) do
      normalized = Outline.normalize_items(items)
      source = Enum.at(normalized, index)
      source_depth = Outline.item_depth(source)

      {prefix, tail} = Enum.split(normalized, index)

      suffix =
        tail
        |> Enum.drop(1)
        |> Enum.drop_while(&(Outline.item_depth(&1) > source_depth))

      next_items = prefix ++ suffix
      next_items = if next_items == [], do: [Outline.new_item()], else: next_items

      case Outline.validate_items(next_items) do
        {:ok, validated_items} ->
          {:ok, %{nodes: validated_items, focus_path: [max(index - 1, 0)]}}

        :error ->
          :error
      end
    end
  end

  def apply(items, :append_root) do
    insert_at = length(Outline.normalize_items(items))

    case insert_item_at(items, insert_at, Outline.new_item()) do
      {:ok, next_items} -> {:ok, %{nodes: next_items, focus_path: [insert_at]}}
      :error -> :error
    end
  end

  def apply(items, {:append_many, imported_items}) when is_list(imported_items) do
    imported_items = imported_items |> List.flatten() |> Enum.map(&normalize_imported_item/1)

    if imported_items == [] do
      :noop
    else
      next_items = Outline.normalize_items(items) ++ imported_items

      case Outline.validate_items(next_items) do
        {:ok, validated_items} -> {:ok, %{nodes: validated_items, focus_path: nil}}
        :error -> :error
      end
    end
  end

  def apply(items, {:insert_many_after, target, inserted_items}) when is_list(inserted_items) do
    with {:ok, index} <- resolve_target_index(items, target) do
      normalized_items = Outline.normalize_items(items)
      inserted_items = inserted_items |> List.flatten() |> Enum.map(&normalize_imported_item/1)
      next_items = List.insert_at(normalized_items, index + 1, inserted_items) |> List.flatten()

      case Outline.validate_items(next_items) do
        {:ok, validated_items} -> {:ok, %{nodes: validated_items, focus_path: [index + 1]}}
        :error -> :error
      end
    end
  end

  def apply(items, {:insert_item, %{"parent_path" => [], "index" => index}, item}) do
    with true <- is_integer(index) and index >= 0,
         {:ok, next_items} <- insert_item_at(items, index, normalize_imported_item(item)) do
      {:ok, %{nodes: next_items, focus_path: [index]}}
    else
      _ -> :error
    end
  end

  def apply(items, {:insert_item, %{parent_path: [], index: index}, item}) do
    apply(items, {:insert_item, %{"parent_path" => [], "index" => index}, item})
  end

  def apply(items, {:move_item, source_target, destination_target}) do
    with {:ok, source_path} <- resolve_target_path(items, source_target),
         {:ok, destination_path, position} <- resolve_move_destination(items, destination_target),
         result <- Outline.move_item(items, source_path, destination_path, position) do
      case result do
        {:ok, next_items, focus_path} -> {:ok, %{nodes: next_items, focus_path: focus_path}}
        :noop -> :noop
        :error -> :error
      end
    else
      _ -> :error
    end
  end

  def apply(items, {:focus_previous, target}) do
    with {:ok, index} <- resolve_target_index(items, target) do
      {:ok, %{nodes: Outline.normalize_items(items), focus_path: [max(index - 1, 0)]}}
    end
  end

  def apply(items, {:focus_next, target}) do
    normalized = Outline.normalize_items(items)

    with {:ok, index} <- resolve_target_index(normalized, target) do
      {:ok, %{nodes: normalized, focus_path: [min(index + 1, length(normalized) - 1)]}}
    end
  end

  def apply(_items, _unknown), do: :error

  defp update_item(items, index, fun) do
    items
    |> Outline.normalize_items()
    |> List.update_at(index, fun)
    |> Outline.validate_items()
  end

  defp shift_subtree_depth_at_index(items, index, depth_delta) when is_integer(index) do
    normalized = Outline.normalize_items(items)

    case Enum.at(normalized, index) do
      nil ->
        :error

      item ->
        descendants = Outline.descendants(normalized, [index])
        subtree = [item | descendants]
        subtree_length = length(subtree)
        {prefix, tail} = Enum.split(normalized, index)
        {_, suffix} = Enum.split(tail, subtree_length)
        next_subtree = shift_subtree_depth(subtree, depth_delta)
        next_items = prefix ++ next_subtree ++ suffix

        case Outline.validate_items(next_items) do
          {:ok, validated_items} -> {:ok, validated_items}
          :error -> :error
        end
    end
  end

  defp shift_subtree_depth(items, depth_delta) do
    Enum.map(items, fn item ->
      Map.update!(item, "depth", fn depth -> max(depth + depth_delta, 0) end)
    end)
  end

  defp insert_item_at(items, index, item) do
    case Outline.insert_item(items, index, item) do
      {:ok, next_items, _index} -> {:ok, next_items}
      :error -> :error
    end
  end

  defp normalize_imported_item(item) do
    item
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> then(fn item_map ->
      Outline.new_item()
      |> Map.merge(
        Map.take(item_map, [
          "id",
          "text",
          "depth",
          "flashcard",
          "answer",
          "front",
          "textColor",
          "backgroundColor"
        ])
      )
      |> normalize_legacy_item_fields()
      |> Map.put(
        "yStateAsUpdate",
        YStateAsUpdate.hydrate_text(Map.get(item_map, "text", ""))
      )
    end)
  end

  defp normalize_legacy_item_fields(item) do
    flashcard = Map.get(item, "flashcard", Map.get(item, "front", false))
    item |> Map.put("flashcard", flashcard) |> Map.delete("front")
  end

  defp set_item_text(item, text) when is_binary(text) do
    item
    |> Map.put("text", text)
    |> Map.put(
      "yStateAsUpdate",
      YStateAsUpdate.update_text(Map.get(item, "yStateAsUpdate"), text)
    )
  end

  defp apply_text_collab_update(item, payload) when is_map(payload) do
    with {:ok, text} <- required_binary_payload_value(payload, "text"),
         {:ok, y_state_as_update} <-
           required_binary_payload_value(payload, "y_state_as_update") do
      {:ok,
       item
       |> Map.put("text", text)
       |> Map.put("yStateAsUpdate", y_state_as_update)}
    else
      _ -> :error
    end
  end

  defp apply_text_collab_update(_item, _payload), do: :error

  defp required_binary_payload_value(payload, key) do
    value =
      case key do
        "text" ->
          Map.get(payload, "text", Map.get(payload, :text))

        "y_state_as_update" ->
          Map.get(payload, "y_state_as_update", Map.get(payload, :y_state_as_update))
      end

    if is_binary(value) do
      {:ok, value}
    else
      :error
    end
  end

  defp toggle_item_flag(item, "flashcard"), do: Map.put(item, "flashcard", !item["flashcard"])
  defp toggle_item_flag(item, "front"), do: toggle_item_flag(item, "flashcard")
  defp toggle_item_flag(item, "answer"), do: Map.put(item, "answer", !item["answer"])
  defp toggle_item_flag(item, _flag), do: item

  defp resolve_target_index(items, target) do
    with {:ok, [index]} <- resolve_target_path(items, target) do
      {:ok, index}
    else
      _ -> :error
    end
  end

  defp resolve_target_path(_items, [idx]) when is_integer(idx), do: {:ok, [idx]}

  defp resolve_target_path(items, %{"item_id" => item_id, "path" => path})
       when is_binary(item_id) and item_id != "" do
    case Outline.path_for_id(items, item_id) do
      nil -> resolve_target_path(items, path)
      indexes -> {:ok, indexes}
    end
  end

  defp resolve_target_path(items, %{item_id: item_id, path: path})
       when is_binary(item_id) and item_id != "" do
    case Outline.path_for_id(items, item_id) do
      nil -> resolve_target_path(items, path)
      indexes -> {:ok, indexes}
    end
  end

  defp resolve_target_path(items, %{"item_id" => item_id})
       when is_binary(item_id) and item_id != "" do
    case Outline.path_for_id(items, item_id) do
      nil -> :error
      indexes -> {:ok, indexes}
    end
  end

  defp resolve_target_path(items, %{item_id: item_id})
       when is_binary(item_id) and item_id != "" do
    case Outline.path_for_id(items, item_id) do
      nil -> :error
      indexes -> {:ok, indexes}
    end
  end

  defp resolve_target_path(_items, path) when is_binary(path), do: {:ok, parse_path(path)}

  defp resolve_target_path(_items, %{"path" => path}) when is_binary(path),
    do: {:ok, parse_path(path)}

  defp resolve_target_path(_items, %{path: path}) when is_binary(path),
    do: {:ok, parse_path(path)}

  defp resolve_target_path(_items, _), do: :error

  defp resolve_move_destination(_items, %{"position" => "root_end"}), do: {:ok, nil, :root_end}
  defp resolve_move_destination(_items, %{position: "root_end"}), do: {:ok, nil, :root_end}

  defp resolve_move_destination(items, %{"target" => target} = destination) do
    with {:ok, target_path} <- resolve_target_path(items, target),
         {:ok, position} <- resolve_move_position(destination) do
      {:ok, target_path, position}
    end
  end

  defp resolve_move_destination(items, %{target: target} = destination) do
    with {:ok, target_path} <- resolve_target_path(items, target),
         {:ok, position} <- resolve_move_position(destination) do
      {:ok, target_path, position}
    end
  end

  defp resolve_move_destination(_items, _), do: :error

  defp resolve_move_position(%{"position" => "before"}), do: {:ok, :before}
  defp resolve_move_position(%{position: "before"}), do: {:ok, :before}
  defp resolve_move_position(%{"position" => "after_as_peer"}), do: {:ok, :after_as_peer}
  defp resolve_move_position(%{position: "after_as_peer"}), do: {:ok, :after_as_peer}
  defp resolve_move_position(%{"position" => "after_as_child"}), do: {:ok, :after_as_child}
  defp resolve_move_position(%{position: "after_as_child"}), do: {:ok, :after_as_child}
  defp resolve_move_position(%{"position" => "after"}), do: {:ok, :after_as_peer}
  defp resolve_move_position(%{position: "after"}), do: {:ok, :after_as_peer}
  defp resolve_move_position(_), do: {:ok, :after_as_peer}

  defp parse_path(path) do
    path
    |> String.split(".", trim: true)
    |> Enum.map(&String.to_integer/1)
  end
end
