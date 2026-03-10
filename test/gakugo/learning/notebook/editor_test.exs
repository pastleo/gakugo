defmodule Gakugo.Learning.Notebook.EditorTest do
  use ExUnit.Case, async: true

  alias Gakugo.Learning.Notebook.Editor
  alias Gakugo.Learning.Notebook.Tree

  test "edit_text updates target node text" do
    nodes = [make_node("old")]

    assert {:ok, %{nodes: next_nodes, focus_path: nil}} =
             Editor.apply(nodes, {:edit_text, [0], "new"})

    assert Tree.get_node(next_nodes, [0])["text"] == "new"
  end

  test "edit_text prefers node_id over path when both are provided" do
    nodes = [make_node("first", "id-first"), make_node("second", "id-second")]

    assert {:ok, %{nodes: next_nodes}} =
             Editor.apply(
               nodes,
               {:edit_text, %{"node_id" => "id-first", "path" => "1"}, "updated"}
             )

    assert Tree.get_node(next_nodes, [0])["text"] == "updated"
    assert Tree.get_node(next_nodes, [1])["text"] == "second"
  end

  test "edit_text falls back to path when node_id is missing" do
    nodes = [make_node("first", "id-first"), make_node("second", "id-second")]

    assert {:ok, %{nodes: next_nodes}} =
             Editor.apply(
               nodes,
               {:edit_text, %{"node_id" => "missing", "path" => "1"}, "updated"}
             )

    assert Tree.get_node(next_nodes, [1])["text"] == "updated"
  end

  test "item_enter on non-empty node appends child and focuses it" do
    nodes = [make_node("root")]

    assert {:ok, %{nodes: next_nodes, focus_path: [0, 0]}} =
             Editor.apply(nodes, {:item_enter, [0], "root"})

    assert Tree.get_node(next_nodes, [0, 0])["text"] == ""
  end

  test "item_enter on empty root inserts sibling" do
    nodes = [make_node("")]

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(nodes, {:item_enter, [0], ""})

    assert length(next_nodes) == 2
    assert Tree.get_node(next_nodes, [1])["text"] == ""
  end

  test "item_enter on empty nested node outdents" do
    nodes = [
      %{
        "text" => "root",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("")]
      }
    ]

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(nodes, {:item_enter, [0, 0], ""})

    assert Tree.get_node(next_nodes, [1])["text"] == ""
  end

  test "item_delete_empty returns noop when there is only one node" do
    assert :noop = Editor.apply([make_node("")], {:item_delete_empty, [0], ""})
  end

  test "item_delete_empty_backward removes node and focuses previous sibling or parent" do
    nodes = [make_node("a"), make_node("", "b")]

    assert {:ok, %{nodes: next_nodes, focus_path: [0]}} =
             Editor.apply(nodes, {:item_delete_empty_backward, [1], ""})

    assert length(next_nodes) == 1
    assert Tree.get_node(next_nodes, [0])["text"] == "a"
  end

  test "item_delete_empty_forward removes node and focuses next sibling" do
    nodes = [make_node("", "a"), make_node("b", "b")]

    assert {:ok, %{nodes: next_nodes, focus_path: [0]}} =
             Editor.apply(nodes, {:item_delete_empty_forward, [0], ""})

    assert length(next_nodes) == 1
    assert Tree.get_node(next_nodes, [0])["id"] == "b"
  end

  test "item_delete_empty_backward focuses parent when there is no previous sibling" do
    nodes = [
      %{
        "id" => "root",
        "text" => "root",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("", "child")]
      }
    ]

    assert {:ok, %{nodes: next_nodes, focus_path: [0]}} =
             Editor.apply(nodes, {:item_delete_empty_backward, %{"node_id" => "child"}, ""})

    assert Tree.get_node(next_nodes, [0])["id"] == "root"
  end

  test "item_delete_empty_forward focuses parent next sibling when no next sibling exists" do
    nodes = [
      %{
        "id" => "root",
        "text" => "root",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("", "child")]
      },
      make_node("after-root", "after-root")
    ]

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(nodes, {:item_delete_empty_forward, %{"node_id" => "child"}, ""})

    assert Tree.get_node(next_nodes, [1])["id"] == "after-root"
  end

  test "item_delete_empty returns noop when target has children" do
    nodes = [
      %{
        "id" => "root",
        "text" => "",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("child", "child")]
      },
      make_node("after", "after")
    ]

    assert :noop = Editor.apply(nodes, {:item_delete_empty_backward, %{"node_id" => "root"}, ""})
    assert :noop = Editor.apply(nodes, {:item_delete_empty_forward, %{"node_id" => "root"}, ""})
  end

  test "item_enter supports node_id-only targeting" do
    nodes = [make_node("root", "root-id")]

    assert {:ok, %{nodes: next_nodes, focus_path: [0, 0]}} =
             Editor.apply(nodes, {:item_enter, %{"node_id" => "root-id"}, "root"})

    assert Tree.get_node(next_nodes, [0, 0])["text"] == ""
  end

  test "item_delete_empty prefers node_id over path" do
    nodes = [make_node("first", "id-first"), make_node("", "id-second")]

    assert {:ok, %{nodes: next_nodes, focus_path: [0]}} =
             Editor.apply(
               nodes,
               {:item_delete_empty, %{"node_id" => "id-second", "path" => "0"}, ""}
             )

    assert length(next_nodes) == 1
    assert Tree.get_node(next_nodes, [0])["text"] == "first"
  end

  test "insert_child_first prepends child and focuses it" do
    nodes = [
      %{
        "id" => "root",
        "text" => "root",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("existing-child", "child-1")]
      }
    ]

    assert {:ok, %{nodes: next_nodes, focus_path: [0, 0]}} =
             Editor.apply(nodes, {:insert_child_first, [0], "root"})

    assert Tree.get_node(next_nodes, [0, 0])["text"] == ""
    assert Tree.get_node(next_nodes, [0, 1])["id"] == "child-1"
  end

  test "insert_above inserts sibling before current path and focuses it" do
    nodes = [make_node("first", "id-first"), make_node("second", "id-second")]

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(nodes, {:insert_above, %{"node_id" => "id-second"}, "second"})

    assert Tree.get_node(next_nodes, [0])["id"] == "id-first"
    assert Tree.get_node(next_nodes, [1])["text"] == ""
    assert Tree.get_node(next_nodes, [2])["id"] == "id-second"
  end

  test "insert_below inserts sibling after current path and focuses it" do
    nodes = [make_node("first", "id-first"), make_node("second", "id-second")]

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(nodes, {:insert_below, %{"node_id" => "id-first"}, "first"})

    assert Tree.get_node(next_nodes, [0])["id"] == "id-first"
    assert Tree.get_node(next_nodes, [1])["text"] == ""
    assert Tree.get_node(next_nodes, [2])["id"] == "id-second"
  end

  test "item_empty_enter outdents when node is the last child" do
    nodes = [
      %{
        "id" => "root",
        "text" => "root",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("", "child-id")]
      }
    ]

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(nodes, {:item_empty_enter, %{"node_id" => "child-id"}, ""})

    assert Tree.get_node(next_nodes, [1])["id"] == "child-id"
  end

  test "item_empty_enter inserts below when node is not the last child" do
    nodes = [
      %{
        "id" => "root",
        "text" => "root",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("", "child-id"), make_node("after", "after-id")]
      }
    ]

    assert {:ok, %{nodes: next_nodes, focus_path: [0, 1]}} =
             Editor.apply(nodes, {:item_empty_enter, %{"node_id" => "child-id"}, ""})

    assert Tree.get_node(next_nodes, [0, 0])["id"] == "child-id"
    assert Tree.get_node(next_nodes, [0, 1])["text"] == ""
    assert Tree.get_node(next_nodes, [0, 2])["id"] == "after-id"
  end

  test "focus_previous_sibling follows the visual previous item" do
    nodes = [
      %{
        "id" => "root",
        "text" => "root",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [
          make_node("first", "id-first"),
          %{
            "id" => "id-second",
            "text" => "second",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => [make_node("deep", "id-deep")]
          }
        ]
      },
      make_node("third", "id-third")
    ]

    assert {:ok, %{nodes: ^nodes, focus_path: [0, 0]}} =
             Editor.apply(nodes, {:focus_previous_sibling, %{"node_id" => "id-second"}})

    assert {:ok, %{nodes: ^nodes, focus_path: [0]}} =
             Editor.apply(nodes, {:focus_previous_sibling, %{"node_id" => "id-first"}})

    assert {:ok, %{nodes: ^nodes, focus_path: [0, 1, 0]}} =
             Editor.apply(nodes, {:focus_previous_sibling, %{"node_id" => "id-third"}})
  end

  test "focus_first_child_or_next_sibling prefers first child then next available sibling" do
    nodes = [
      %{
        "id" => "root",
        "text" => "root",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("child", "child-id")]
      },
      make_node("sibling", "sibling-id")
    ]

    assert {:ok, %{nodes: ^nodes, focus_path: [0, 0]}} =
             Editor.apply(nodes, {:focus_first_child_or_next_sibling, %{"node_id" => "root"}})

    assert {:ok, %{nodes: ^nodes, focus_path: [1]}} =
             Editor.apply(nodes, {:focus_first_child_or_next_sibling, %{"node_id" => "child-id"}})

    assert {:ok, %{nodes: ^nodes, focus_path: nil}} =
             Editor.apply(
               nodes,
               {:focus_first_child_or_next_sibling, %{"node_id" => "sibling-id"}}
             )
  end

  test "toggle_flag front is blocked under front ancestor" do
    nodes = [
      %{
        "id" => "root",
        "text" => "root",
        "front" => true,
        "answer" => false,
        "link" => "",
        "children" => [make_node("child", "child")]
      }
    ]

    assert {:ok, %{nodes: next_nodes}} =
             Editor.apply(nodes, {:toggle_flag, %{"node_id" => "child"}, "front"})

    refute Tree.get_node(next_nodes, [0, 0])["front"]
  end

  test "toggle_flag answer keeps front on front node" do
    nodes = [
      %{
        "id" => "front",
        "text" => "front",
        "front" => true,
        "answer" => false,
        "link" => "",
        "children" => []
      }
    ]

    assert {:ok, %{nodes: next_nodes}} =
             Editor.apply(nodes, {:toggle_flag, %{"node_id" => "front"}, "answer"})

    assert Tree.get_node(next_nodes, [0])["front"]
    assert Tree.get_node(next_nodes, [0])["answer"]
  end

  test "toggle_flag front off clears answer on same node" do
    nodes = [
      %{
        "id" => "front",
        "text" => "front",
        "front" => true,
        "answer" => true,
        "link" => "",
        "children" => []
      }
    ]

    assert {:ok, %{nodes: next_nodes}} =
             Editor.apply(nodes, {:toggle_flag, %{"node_id" => "front"}, "front"})

    refute Tree.get_node(next_nodes, [0])["front"]
    refute Tree.get_node(next_nodes, [0])["answer"]
  end

  test "item_indent noops on first sibling" do
    nodes = [make_node("only", "id-only")]

    assert {:ok, %{nodes: next_nodes, focus_path: nil}} =
             Editor.apply(nodes, {:item_indent, %{"node_id" => "id-only"}, "only"})

    assert next_nodes == Tree.normalize_nodes(nodes)
  end

  test "item_outdent noops on root path" do
    nodes = [make_node("root", "id-root")]

    assert {:ok, %{nodes: next_nodes, focus_path: nil}} =
             Editor.apply(nodes, {:item_outdent, %{"node_id" => "id-root"}, "root"})

    assert next_nodes == Tree.normalize_nodes(nodes)
  end

  test "add_child add_sibling remove_node and append_root commands work" do
    nodes = [make_node("first", "id-first")]

    assert {:ok, %{nodes: with_child}} =
             Editor.apply(nodes, {:add_child, %{"node_id" => "id-first"}})

    assert Tree.get_node(with_child, [0, 0])["text"] == ""

    assert {:ok, %{nodes: with_sibling}} =
             Editor.apply(with_child, {:add_sibling, %{"node_id" => "id-first"}})

    assert length(with_sibling) == 2

    assert {:ok, %{nodes: without_first}} =
             Editor.apply(with_sibling, {:remove_node, %{"node_id" => "id-first"}})

    assert length(without_first) == 1

    assert {:ok, %{nodes: appended}} = Editor.apply(without_first, :append_root)
    assert length(appended) == 2
  end

  test "append_many appends imported nodes" do
    nodes = [make_node("existing", "id-existing")]
    imported = [make_node("word", "id-word"), make_node("translation", "id-translation")]

    assert {:ok, %{nodes: merged, focus_path: nil}} =
             Editor.apply(nodes, {:append_many, imported})

    assert length(merged) == 3
    assert Tree.get_node(merged, [1])["text"] == "word"
    assert Tree.get_node(merged, [2])["text"] == "translation"
  end

  test "append_many noops on empty input" do
    nodes = [make_node("existing", "id-existing")]
    assert :noop = Editor.apply(nodes, {:append_many, []})
  end

  test "move_node reorders sibling before another node" do
    nodes = [make_node("A", "id-a"), make_node("B", "id-b"), make_node("C", "id-c")]

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(
               nodes,
               {:move_node, %{"node_id" => "id-c"},
                %{"position" => "before", "target" => %{"node_id" => "id-b"}}}
             )

    assert Enum.map(next_nodes, & &1["text"]) == ["A", "C", "B"]
  end

  test "insert_node inserts imported node at target index" do
    nodes = [make_node("A", "id-a"), make_node("B", "id-b")]
    inserted = make_node("X", "id-x")

    assert {:ok, %{nodes: next_nodes, focus_path: [1]}} =
             Editor.apply(
               nodes,
               {:insert_node, %{"parent_path" => [], "index" => 1}, inserted}
             )

    assert Enum.map(next_nodes, & &1["text"]) == ["A", "X", "B"]
  end

  defp make_node(text, id \\ nil) do
    %{
      "id" => id,
      "text" => text,
      "front" => false,
      "answer" => false,
      "link" => "",
      "children" => []
    }
  end
end
