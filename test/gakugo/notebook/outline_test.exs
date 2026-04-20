defmodule Gakugo.Notebook.OutlineTest do
  use ExUnit.Case, async: true

  alias Gakugo.Notebook.Outline

  test "normalize_items ensures at least one item" do
    [node] = Outline.normalize_items([])
    assert is_binary(node["id"])
    assert node["depth"] == 0

    [node] = Outline.normalize_items(nil)
    assert is_binary(node["id"])
    assert node["depth"] == 0
  end

  test "normalize_items preserves existing id, depth, and protocol state fields" do
    [item] = Outline.normalize_items([%{"id" => "node-1", "text" => "root", "depth" => 1}])
    assert item["id"] == "node-1"
    assert item["depth"] == 1
    assert is_binary(item["yStateAsUpdate"])
  end

  test "db_update_item_attrs omits runtime-only editor state" do
    [item] = Outline.normalize_items([%{"id" => "node-1", "text" => "root", "depth" => 1}])

    refute Map.has_key?(Outline.db_update_item_attrs(item), "yStateAsUpdate")
  end

  test "item_depth reads atom-keyed depth fields" do
    assert Outline.item_depth(%{depth: 2}) == 2
  end

  test "validate_items enforces root depth and no upward gap larger than one" do
    assert {:ok, [first, second]} =
             Outline.validate_items([
               %{"text" => "A", "depth" => 0},
               %{"text" => "B", "depth" => 1}
             ])

    assert first["depth"] == 0
    assert second["depth"] == 1

    assert :error =
             Outline.validate_items([
               %{"text" => "A", "depth" => 0},
               %{"text" => "B", "depth" => 2}
             ])
  end

  test "get_item and path_for_id use flat indexes" do
    nodes = [make_node("A", "id-a", 0), make_node("B", "id-b", 1)]

    assert Outline.get_item(nodes, [1])["text"] == "B"
    assert Outline.path_for_id(nodes, "id-b") == [1]
    assert Outline.path_for_id(nodes, "missing") == nil
  end

  test "has_flashcard_descendant? checks following deeper items" do
    nodes = [
      make_node("A", "id-a", 0),
      make_node("B", "id-b", 1, true),
      make_node("C", "id-c", 0)
    ]

    assert Outline.has_flashcard_descendant?(nodes, [0])
    refute Outline.has_flashcard_descendant?(nodes, [1])
  end

  test "move_item moves item after target at the same level" do
    nodes = [make_node("A", "id-a", 0), make_node("B", "id-b", 0), make_node("C", "id-c", 1)]

    assert {:ok, next_nodes, [2]} = Outline.move_item(nodes, [2], [1], :after)
    assert Enum.map(next_nodes, & &1["text"]) == ["A", "B", "C"]
    assert Enum.at(next_nodes, 2)["depth"] == 0
  end

  defp make_node(text, id, depth, flashcard \\ false) do
    %{"id" => id, "text" => text, "depth" => depth, "flashcard" => flashcard, "answer" => false}
  end
end
