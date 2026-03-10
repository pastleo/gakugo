defmodule Gakugo.Learning.Notebook.TreeTest do
  use ExUnit.Case, async: true

  alias Gakugo.Learning.Notebook.Tree

  test "normalize_nodes ensures at least one node" do
    [node] = Tree.normalize_nodes([])
    assert is_binary(node["id"])
    assert node["id"] != ""

    [node] = Tree.normalize_nodes(nil)
    assert is_binary(node["id"])
    assert node["id"] != ""
  end

  test "normalize_nodes preserves existing node id and backfills missing ids" do
    nodes = [
      %{
        "id" => "node-1",
        "text" => "root",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [
          %{"text" => "child", "front" => false, "answer" => false, "children" => []}
        ]
      }
    ]

    [root] = Tree.normalize_nodes(nodes)
    [child] = root["children"]

    assert root["id"] == "node-1"
    assert is_binary(child["id"])
    assert child["id"] != ""
  end

  test "normalize_nodes enforces front-branch constraint" do
    nodes = [
      %{
        "text" => "front",
        "front" => true,
        "answer" => false,
        "link" => "",
        "children" => [
          %{"text" => "nested front", "front" => true, "answer" => false, "children" => []}
        ]
      }
    ]

    [root] = Tree.normalize_nodes(nodes)
    [child] = root["children"]

    assert root["front"]
    refute child["front"]
  end

  test "indent_node moves node under previous sibling" do
    nodes = [make_node("A"), make_node("B")]

    assert {:ok, next_nodes, focus_path} = Tree.indent_node(nodes, [1])

    assert focus_path == [0, 0]
    assert length(next_nodes) == 1
    assert Tree.get_node(next_nodes, [0, 0])["text"] == "B"
  end

  test "outdent_node moves nested node to parent sibling" do
    nodes = [
      %{
        "text" => "A",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("B")]
      }
    ]

    {next_nodes, focus_path} = Tree.outdent_node(nodes, [0, 0])

    assert focus_path == [1]
    assert Tree.get_node(next_nodes, [1])["text"] == "B"
  end

  test "apply_inline_text updates node text" do
    nodes = [make_node("old")]
    next_nodes = Tree.apply_inline_text(nodes, [0], "new")
    assert Tree.get_node(next_nodes, [0])["text"] == "new"
  end

  test "node_count and previous_path are depth-first" do
    nodes = [
      %{
        "text" => "A",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("B")]
      },
      make_node("C")
    ]

    assert Tree.node_count(nodes) == 3
    assert Tree.previous_path(nodes, [1]) == [0, 0]
  end

  test "sibling and child focus helpers return structural neighbors" do
    nodes = [
      %{
        "id" => "root",
        "text" => "A",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("B", "child")]
      },
      make_node("C", "sibling")
    ]

    assert Tree.previous_sibling_path([1]) == [0]
    assert Tree.previous_sibling_path([0]) == nil
    assert Tree.first_child_path(nodes, [0]) == [0, 0]
    assert Tree.next_sibling_path(nodes, [0, 0]) == nil
    assert Tree.next_sibling_path(nodes, [0]) == [1]
    assert Tree.first_child_or_next_sibling_path(nodes, [0]) == [0, 0]
    assert Tree.first_child_or_next_sibling_path(nodes, [0, 0]) == nil
    assert Tree.first_child_or_next_sibling_path(nodes, [1]) == nil
    assert Tree.previous_sibling_or_parent_path([0, 0]) == [0]
    assert Tree.previous_sibling_or_parent_path([1]) == [0]
    assert Tree.previous_visual_path(nodes, [0, 0]) == [0]
    assert Tree.previous_visual_path(nodes, [1]) == [0, 0]
    assert Tree.next_sibling_or_ancestor_next_sibling_path(nodes, [0, 0]) == [1]
    assert Tree.next_sibling_or_ancestor_next_sibling_path(nodes, [0]) == [1]
    assert Tree.first_child_or_next_available_path(nodes, [0]) == [0, 0]
    assert Tree.first_child_or_next_available_path(nodes, [0, 0]) == [1]
    assert Tree.last_child_path?(nodes, [0, 0])
    refute Tree.last_child_path?(nodes, [0])
  end

  test "path_under_front? detects ancestors with front" do
    nodes = [
      %{
        "text" => "A",
        "front" => true,
        "answer" => false,
        "link" => "",
        "children" => [make_node("B")]
      }
    ]

    assert Tree.path_under_front?(nodes, [0, 0])
    refute Tree.path_under_front?(nodes, [0])
  end

  test "path_for_id finds nested node path" do
    nodes = [
      %{
        "id" => "root",
        "text" => "A",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [
          %{
            "id" => "child",
            "text" => "B",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      }
    ]

    assert Tree.path_for_id(nodes, "root") == [0]
    assert Tree.path_for_id(nodes, "child") == [0, 0]
    assert Tree.path_for_id(nodes, "missing") == nil
  end

  test "has_front_descendant? checks descendants only" do
    node =
      %{
        "text" => "A",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [make_node("B", true)]
      }

    assert Tree.has_front_descendant?(node)
    refute Tree.has_front_descendant?(make_node("A", true))
  end

  defp make_node(text, front \\ false) do
    %{"text" => text, "front" => front, "answer" => false, "link" => "", "children" => []}
  end
end
