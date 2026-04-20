defmodule Gakugo.Anki.Source do
  @moduledoc false

  alias Gakugo.Notebook.Outline

  def flashcard_sources(unit) do
    unit.pages
    |> Enum.flat_map(fn page ->
      entries = flatten_nodes(page.items)
      all_answer_paths = answer_paths(entries)

      entries
      |> Enum.filter(& &1.node["flashcard"])
      |> Enum.map(fn entry ->
        subtree_entries = descendant_entries(entries, entry)

        %{
          id: notebook_identifier(unit.id, page.id, entry.path),
          unit: unit,
          page: page,
          entries: entries,
          subtree_entries: [entry | subtree_entries],
          entry: entry,
          all_answer_paths: all_answer_paths,
          current_answer_paths: current_answer_paths(entry, subtree_entries)
        }
      end)
    end)
  end

  def flatten_nodes(nodes) do
    nodes
    |> Outline.normalize_items()
    |> Enum.with_index()
    |> Enum.map(fn {node, idx} -> %{node: node, path: [idx]} end)
  end

  def item_depth(node) when is_map(node) do
    case Map.get(node, "depth", 0) do
      depth when is_integer(depth) and depth >= 0 -> depth
      _ -> 0
    end
  end

  def item_depth(_node), do: 0

  def descendant_entries(entries, entry) do
    current_depth = item_depth(entry.node)
    current_index = List.first(entry.path)

    entries
    |> Enum.drop(current_index + 1)
    |> Enum.take_while(fn candidate -> item_depth(candidate.node) > current_depth end)
  end

  defp answer_paths(entries) do
    entries
    |> Enum.filter(& &1.node["answer"])
    |> Enum.map(& &1.path)
    |> MapSet.new()
  end

  defp current_answer_paths(entry, subtree_entries) do
    entry_answers = if entry.node["answer"], do: [entry.path], else: []

    descendant_answers =
      subtree_entries
      |> Enum.reject(&(&1.path == entry.path))
      |> Enum.filter(& &1.node["answer"])
      |> Enum.map(& &1.path)

    MapSet.new(entry_answers ++ descendant_answers)
  end

  defp notebook_identifier(unit_id, page_id, path) do
    path_key = Enum.join(path, "-")
    "unit-#{unit_id}-page-#{page_id}-path-#{path_key}"
  end
end
