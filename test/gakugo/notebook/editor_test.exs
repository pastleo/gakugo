defmodule Gakugo.Notebook.EditorTest do
  use ExUnit.Case, async: false

  alias Gakugo.Notebook.Editor
  alias Gakugo.Notebook.Outline

  test "set_text updates target item text and refreshes editor state" do
    nodes = [make_node("old", "id-old", 0)]

    assert {:ok, %{nodes: next_nodes, focus_path: nil}} =
             Editor.apply(nodes, {:set_text, [0], "new"})

    assert Outline.get_item(next_nodes, [0])["text"] == "new"
    assert is_binary(Outline.get_item(next_nodes, [0])["yStateAsUpdate"])
  end

  test "legacy policy intents return error" do
    nodes = [make_node("row", "id-row", 0)]

    assert :error == Editor.apply(nodes, {:item_enter, [0], "row"})
    assert :error == Editor.apply(nodes, {:item_empty_enter, [0], ""})
    assert :error == Editor.apply(nodes, {:item_delete_empty, [0], ""})
    assert :error == Editor.apply(nodes, {:item_delete_empty_backward, [0], ""})
    assert :error == Editor.apply(nodes, {:item_delete_empty_forward, [0], ""})
  end

  test "insert_above inserts a same-depth item before the target" do
    nodes = [make_node("root", "id-root", 0)]

    assert {:ok, %{nodes: next_nodes, focus_path: [0]}} =
             Editor.apply(nodes, {:insert_above, [0], "root"})

    assert Outline.get_item(next_nodes, [0])["depth"] == 0
    assert Outline.get_item(next_nodes, [1])["text"] == "root"
  end

  test "insert_below inserts a same-depth item after the target" do
    nodes = [make_node("root", "id-root", 0)]

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(nodes, {:insert_below, [0], "root"})

    assert Outline.get_item(next_nodes, [1])["depth"] == 0
    assert Outline.get_item(next_nodes, [0])["text"] == "root"
  end

  test "insert_child_below inserts directly after the target at depth + 1" do
    nodes = [make_node("root", "id-root", 0)]

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(nodes, {:insert_child_below, [0], "root"})

    assert Outline.get_item(next_nodes, [1])["depth"] == 1
    assert Outline.get_item(next_nodes, [0])["text"] == "root"
  end

  test "text_collab_update requires text and y_state_as_update, and stores them" do
    [item] = Outline.normalize_items([make_node("old", "id-old", 0)])

    assert :error ==
             Editor.apply(
               [item],
               {:text_collab_update, %{"item_id" => "id-old"},
                %{y_state_as_update: "opaque-state"}}
             )

    assert :error ==
             Editor.apply(
               [item],
               {:text_collab_update, %{"item_id" => "id-old"}, %{text: "new"}}
             )

    assert {:ok, %{nodes: next_nodes, updated_item: updated_item}} =
             Editor.apply(
               [item],
               {:text_collab_update, %{"item_id" => "id-old"},
                %{y_state_as_update: "opaque-state", text: "new"}}
             )

    assert Outline.get_item(next_nodes, [0])["text"] == "new"
    assert Outline.get_item(next_nodes, [0])["yStateAsUpdate"] == "opaque-state"
    assert updated_item["text"] == "new"
    assert updated_item["yStateAsUpdate"] == "opaque-state"
  end

  test "item_indent and item_outdent only affect selected item" do
    nodes = [make_node("A", "id-a", 0), make_node("B", "id-b", 0), make_node("C", "id-c", 1)]

    assert {:ok, %{nodes: indented}} =
             Editor.apply(nodes, {:item_indent, %{"item_id" => "id-b"}, "B"})

    assert Enum.map(indented, & &1["depth"]) == [0, 1, 1]

    assert {:ok, %{nodes: outdented}} =
             Editor.apply(indented, {:item_outdent, %{"item_id" => "id-b"}, "B"})

    assert Enum.map(outdented, & &1["depth"]) == [0, 0, 1]
  end

  test "remove_item keeps one blank item when deleting the last row" do
    assert {:ok, %{nodes: [node], focus_path: [0]}} =
             Editor.apply([make_node("only", "id-only", 0)], {:remove_item, [0]})

    assert node["text"] == ""
    assert node["depth"] == 0
  end

  test "indent_subtree and outdent_subtree move the selected subtree together" do
    nodes = [
      make_node("A", "id-a", 0),
      make_node("B", "id-b", 0),
      make_node("C", "id-c", 1),
      make_node("D", "id-d", 1)
    ]

    assert {:ok, %{nodes: indented}} =
             Editor.apply(nodes, {:indent_subtree, %{"item_id" => "id-b"}, "B"})

    assert Enum.map(indented, & &1["depth"]) == [0, 1, 2, 2]

    assert {:ok, %{nodes: outdented}} =
             Editor.apply(indented, {:outdent_subtree, %{"item_id" => "id-b"}, "B"})

    assert Enum.map(outdented, & &1["depth"]) == [0, 0, 1, 1]
  end

  test "add_child add_sibling remove_item and append_root commands work" do
    nodes = [make_node("first", "id-first", 0)]

    assert {:ok, %{nodes: with_child}} =
             Editor.apply(nodes, {:add_child, %{"item_id" => "id-first"}})

    assert Outline.get_item(with_child, [1])["depth"] == 1

    assert {:ok, %{nodes: with_sibling}} =
             Editor.apply(with_child, {:add_sibling, %{"item_id" => "id-first"}})

    assert Outline.get_item(with_sibling, [1])["depth"] == 0

    assert {:ok, %{nodes: without_first}} =
             Editor.apply(with_sibling, {:remove_item, %{"item_id" => "id-first"}})

    assert length(without_first) == 2

    assert {:ok, %{nodes: appended}} = Editor.apply(without_first, :append_root)
    assert List.last(appended)["depth"] == 0
  end

  test "append_many appends flat imported items" do
    nodes = [make_node("existing", "id-existing", 0)]
    imported = [make_node("word", "id-word", 0), make_node("translation", "id-translation", 1)]

    assert {:ok, %{nodes: merged, focus_path: nil}} =
             Editor.apply(nodes, {:append_many, imported})

    assert Enum.map(merged, & &1["text"]) == ["existing", "word", "translation"]
    assert Enum.all?(merged, &is_binary(&1["yStateAsUpdate"]))
  end

  test "move_item keeps moved item at the target sibling depth" do
    nodes = [make_node("A", "id-a", 0), make_node("B", "id-b", 0), make_node("C", "id-c", 1)]

    assert {:ok, %{nodes: next_nodes, focus_path: [2]}} =
             Editor.apply(
               nodes,
               {:move_item, %{"item_id" => "id-c"}, %{"target" => %{"item_id" => "id-b"}}}
             )

    assert Enum.map(next_nodes, & &1["text"]) == ["A", "B", "C"]
    assert Enum.at(next_nodes, 2)["depth"] == 0
  end

  defp make_node(text, id, depth) do
    %{
      "id" => id,
      "text" => text,
      "depth" => depth,
      "flashcard" => false,
      "answer" => false,
      "link" => ""
    }
  end
end
