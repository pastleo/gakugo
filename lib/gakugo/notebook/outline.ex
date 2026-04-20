defmodule Gakugo.Notebook.Outline do
  @moduledoc false

  alias Gakugo.Notebook.Item.YStateAsUpdate

  def new_item do
    %{
      "id" => Ecto.UUID.generate(),
      "text" => "",
      "depth" => 0,
      "flashcard" => false,
      "answer" => false,
      "textColor" => nil,
      "backgroundColor" => nil,
      "yStateAsUpdate" => YStateAsUpdate.empty_y_state_as_update()
    }
  end

  def normalize_items(items) when is_list(items) do
    items =
      items
      |> Enum.flat_map(&flatten_legacy_item(&1, 0))
      |> Enum.map(&normalize_item/1)

    if items == [], do: [new_item()], else: items
  end

  def normalize_items(_), do: [new_item()]

  def validate_items(items) when is_list(items) do
    normalized = normalize_items(items)

    case normalized do
      [] -> {:ok, [new_item()]}
      [first | rest] -> validate_depths(rest, [Map.put(first, "depth", 0)], 0)
    end
  end

  def validate_items(_), do: {:ok, [new_item()]}

  def get_item(items, [idx]) when is_integer(idx), do: Enum.at(items, idx)
  def get_item(_items, _path), do: nil

  def item_count(items), do: length(normalize_items(items))

  def db_update_item_attrs(item) when is_map(item) do
    item
    |> normalize_item()
    |> Map.take(["id", "text", "depth", "flashcard", "answer", "textColor", "backgroundColor"])
  end

  def db_update_item_attrs(_item), do: db_update_item_attrs(new_item())

  def path_for_id(items, item_id) when is_binary(item_id) and item_id != "" do
    items
    |> normalize_items()
    |> Enum.find_index(&(normalize_id(&1) == item_id))
    |> case do
      nil -> nil
      idx -> [idx]
    end
  end

  def path_for_id(_, _), do: nil

  def can_indent_path?([idx]) when is_integer(idx), do: idx > 0
  def can_indent_path?(_), do: false

  def item_depth(item) when is_map(item) do
    item
    |> Map.get("depth", Map.get(item, :depth, 0))
    |> normalize_depth()
  end

  def item_depth(_), do: 0

  def descendants(items, [idx]) when is_integer(idx) do
    normalized = normalize_items(items)

    case Enum.at(normalized, idx) do
      nil ->
        []

      item ->
        depth = item_depth(item)

        normalized
        |> Enum.drop(idx + 1)
        |> Enum.take_while(&(item_depth(&1) > depth))
    end
  end

  def descendants(_items, _path), do: []

  def has_flashcard_descendant?(items, path) do
    items
    |> descendants(path)
    |> Enum.any?(&Map.get(&1, "flashcard", false))
  end

  def insert_item(items, index, item) when is_integer(index) and index >= 0 and is_map(item) do
    normalized = normalize_items(items)
    safe_index = min(index, length(normalized))
    next_items = List.insert_at(normalized, safe_index, normalize_item(item))

    case validate_items(next_items) do
      {:ok, validated} -> {:ok, validated, safe_index}
      :error -> :error
    end
  end

  def insert_item(_items, _index, _item), do: :error

  def move_item(items, source_path, nil, :root_end) when is_list(source_path) do
    normalized = normalize_items(items)

    with {:ok, source_idx} <- index_from_path(source_path),
         {segment, rest_items, _source_depth} <- pop_subtree(normalized, source_idx),
         adjusted_segment <- shift_subtree_depth(segment, 0),
         next_items <- rest_items ++ adjusted_segment,
         {:ok, validated} <- validate_items(next_items) do
      {:ok, validated, [length(validated) - length(adjusted_segment)]}
    else
      _ -> :error
    end
  end

  def move_item(items, source_path, destination_path, position)
      when is_list(source_path) and is_list(destination_path) and
             position in [:before, :after, :after_as_peer, :after_as_child] do
    normalized = normalize_items(items)

    with {:ok, source_idx} <- index_from_path(source_path),
         {:ok, destination_idx} <- index_from_path(destination_path),
         false <- subtree_contains_index?(normalized, source_idx, destination_idx),
         destination when is_map(destination) <- Enum.at(normalized, destination_idx),
         {segment, rest_items, source_depth} <- pop_subtree(normalized, source_idx) do
      adjusted_destination_idx =
        if source_idx < destination_idx do
          destination_idx - length(segment)
        else
          destination_idx
        end

      {target_depth, insert_at} =
        case position do
          :before ->
            {item_depth(destination), adjusted_destination_idx}

          :after_as_child ->
            {item_depth(destination) + 1, adjusted_destination_idx + 1}

          pos when pos in [:after, :after_as_peer] ->
            peer_index = subtree_end_index(rest_items, adjusted_destination_idx) + 1
            {item_depth(destination), peer_index}
        end

      adjusted_segment = shift_subtree_depth(segment, target_depth - source_depth)
      next_items = List.insert_at(rest_items, insert_at, adjusted_segment) |> List.flatten()

      case validate_items(next_items) do
        {:ok, validated} -> {:ok, validated, [insert_at]}
        :error -> :error
      end
    else
      true -> :noop
      _ -> :error
    end
  end

  def move_item(_items, _source_path, _destination_path, _position), do: :error

  defp pop_subtree(items, source_idx) do
    source = Enum.at(items, source_idx)
    source_depth = item_depth(source)

    segment_length =
      items
      |> Enum.drop(source_idx + 1)
      |> Enum.take_while(&(item_depth(&1) > source_depth))
      |> length()
      |> Kernel.+(1)

    {prefix, tail} = Enum.split(items, source_idx)
    {segment, suffix} = Enum.split(tail, segment_length)

    {segment, prefix ++ suffix, source_depth}
  end

  defp subtree_end_index(items, index) do
    case Enum.at(items, index) do
      nil ->
        index

      item ->
        depth = item_depth(item)

        items
        |> Enum.drop(index + 1)
        |> Enum.take_while(&(item_depth(&1) > depth))
        |> length()
        |> Kernel.+(index)
    end
  end

  defp shift_subtree_depth(segment, depth_delta) do
    Enum.map(segment, fn item ->
      Map.update!(item, "depth", fn depth -> max(depth + depth_delta, 0) end)
    end)
  end

  defp subtree_contains_index?(items, source_idx, target_idx) do
    case Enum.at(items, source_idx) do
      nil ->
        false

      source ->
        source_depth = item_depth(source)

        target_idx == source_idx or
          (target_idx > source_idx and
             items
             |> Enum.slice((source_idx + 1)..target_idx)
             |> Enum.all?(fn item -> item_depth(item) > source_depth end))
    end
  end

  defp validate_depths([], acc, _prev_depth), do: {:ok, acc}

  defp validate_depths([item | rest], acc, prev_depth) do
    depth = item_depth(item)

    if depth <= prev_depth + 1 do
      validate_depths(rest, acc ++ [Map.put(item, "depth", depth)], depth)
    else
      :error
    end
  end

  defp flatten_legacy_item(item, depth) when is_map(item) do
    current =
      item
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put("depth", Map.get(item, "depth", Map.get(item, :depth, depth)))
      |> Map.drop(["children", "link"])
      |> normalize_legacy_flags()

    children = item |> Map.get("children", Map.get(item, :children, [])) |> List.wrap()
    [current | Enum.flat_map(children, &flatten_legacy_item(&1, depth + 1))]
  end

  defp flatten_legacy_item(_item, _depth), do: []

  defp normalize_item(item) when is_map(item) do
    text = normalize_text(item)

    %{
      "id" => normalize_id(item) || Ecto.UUID.generate(),
      "text" => text,
      "depth" => normalize_depth(Map.get(item, "depth", Map.get(item, :depth, 0))),
      "flashcard" =>
        normalize_boolean(
          Map.get(
            item,
            "flashcard",
            Map.get(item, :flashcard, Map.get(item, "front", Map.get(item, :front, false)))
          )
        ),
      "answer" => normalize_boolean(Map.get(item, "answer", Map.get(item, :answer, false))),
      "textColor" => normalize_color(Map.get(item, "textColor", Map.get(item, :textColor))),
      "backgroundColor" =>
        normalize_color(Map.get(item, "backgroundColor", Map.get(item, :backgroundColor))),
      "yStateAsUpdate" => normalize_y_state_as_update(item)
    }
  end

  defp normalize_item(_), do: new_item()

  defp normalize_legacy_flags(item) do
    flashcard = Map.get(item, "flashcard", Map.get(item, "front", false))
    item |> Map.put("flashcard", flashcard) |> Map.delete("front")
  end

  defp normalize_text(%{"text" => text}) when is_binary(text), do: text
  defp normalize_text(%{text: text}) when is_binary(text), do: text
  defp normalize_text(_), do: ""

  defp normalize_boolean(value) when is_boolean(value), do: value
  defp normalize_boolean(_), do: false

  defp normalize_color(nil), do: nil

  defp normalize_color(value) when is_binary(value) do
    if Gakugo.Notebook.Colors.valid_name?(value) do
      value
    else
      nil
    end
  end

  defp normalize_color(_), do: nil

  defp normalize_depth(depth) when is_integer(depth) and depth >= 0, do: depth

  defp normalize_depth(depth) when is_binary(depth) do
    case Integer.parse(depth) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp normalize_depth(_), do: 0

  defp normalize_id(%{"id" => id}) when is_binary(id) and id != "", do: id
  defp normalize_id(%{id: id}) when is_binary(id) and id != "", do: id
  defp normalize_id(_), do: nil

  defp normalize_y_state_as_update(item) do
    case Map.get(item, "yStateAsUpdate", Map.get(item, :yStateAsUpdate)) do
      value when is_binary(value) -> value
      _ -> YStateAsUpdate.hydrate_text(normalize_text(item))
    end
  end

  defp index_from_path([idx]) when is_integer(idx) and idx >= 0, do: {:ok, idx}
  defp index_from_path(_), do: :error
end
