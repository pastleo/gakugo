defmodule Gakugo.NotebookAction.ParseAsFlashcards do
  @moduledoc false

  alias Gakugo.Notebook.Outline
  alias Gakugo.Notebook.UnitSession
  alias Gakugo.NotebookAction.ParseAsItems

  defstruct [:unit_id, :page_id, :item_id, :insertion_mode, :answer_mode]

  def perform(unit_id, page_id, item_id, insertion_mode, answer_mode)
      when is_integer(unit_id) and is_integer(page_id) and is_binary(item_id) do
    with snapshot <- UnitSession.snapshot(unit_id),
         page when not is_nil(page) <- find_page(snapshot, page_id),
         source when not is_nil(source) <- Enum.find(page.items, &(&1["id"] == item_id)),
         {:ok, parsed_items} <- parse_source_item(source, insertion_mode),
         {:ok, insert_after_item_id} <- insert_after_item_id(page.items, item_id),
         marked_items <- mark_flashcard_items(parsed_items, answer_mode) do
      if marked_items == [] do
        {:ok, %{status: "noop"}}
      else
        intent = %{
          "scope" => "page_content",
          "action" => "insert_many_after",
          "target" => %{"page_id" => page.id, "item_id" => insert_after_item_id},
          "version" => %{"local" => page.version},
          "nodes" => page.items,
          "payload" => %{"items" => marked_items}
        }

        UnitSession.apply_intent(unit_id, "api", intent)
      end
    else
      _ -> {:error, :invalid_params}
    end
  end

  def perform(_, _, _, _, _), do: {:error, :invalid_params}

  defp find_page(snapshot, page_id) do
    Enum.find(snapshot.unit.pages, &(&1.id == page_id))
  end

  defp parse_source_item(source, insertion_mode) when is_map(source) do
    text = Map.get(source, "text", "")
    depth = Outline.item_depth(source)

    case insertion_mode do
      "next_siblings" -> ParseAsItems.parse(text, depth)
      "children" -> ParseAsItems.parse(text, depth + 1)
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

  defp mark_flashcard_items(items, answer_mode) when is_list(items) do
    root_depth = items |> Enum.map(&Outline.item_depth/1) |> Enum.min(fn -> 0 end)

    first_second_depth_ids = first_second_depth_ids(items, root_depth)

    Enum.map(items, fn item ->
      depth = Outline.item_depth(item)
      is_root = depth == root_depth
      is_first_second_depth = Map.get(item, "id") in first_second_depth_ids

      {flashcard, answer} =
        case answer_mode do
          "first_depth" -> {is_root, is_root}
          "first_second_depth_front" -> {is_root, not is_root and not is_first_second_depth}
          "non_first_depth" -> {is_root, not is_root}
          "no_answer" -> {is_root, false}
          _ -> {is_root, false}
        end

      item
      |> Map.put("flashcard", flashcard)
      |> Map.put("answer", answer)
    end)
  end

  defp mark_flashcard_items(_items, _answer_mode), do: []

  defp first_second_depth_ids(items, root_depth) do
    second_depth = root_depth + 1

    items
    |> Enum.reduce({nil, MapSet.new(), MapSet.new()}, fn item,
                                                         {current_root_id, roots_with_child,
                                                          first_child_ids} ->
      depth = Outline.item_depth(item)

      cond do
        depth == root_depth ->
          {Map.get(item, "id"), roots_with_child, first_child_ids}

        depth == second_depth and not is_nil(current_root_id) ->
          if MapSet.member?(roots_with_child, current_root_id) do
            {current_root_id, roots_with_child, first_child_ids}
          else
            {current_root_id, MapSet.put(roots_with_child, current_root_id),
             MapSet.put(first_child_ids, Map.get(item, "id"))}
          end

        depth <= root_depth ->
          {nil, roots_with_child, first_child_ids}

        true ->
          {current_root_id, roots_with_child, first_child_ids}
      end
    end)
    |> elem(2)
    |> MapSet.to_list()
  end
end
