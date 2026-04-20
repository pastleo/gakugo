defmodule Gakugo.NotebookAction.ParseAsItemsTest do
  use Gakugo.DataCase, async: false

  alias Gakugo.Db
  alias Gakugo.NotebookAction.ParseAsItems

  import Gakugo.LearningFixtures

  setup do
    stop_all_unit_sessions()
    :ok
  end

  test "parses markdown blocks into notebook items" do
    assert {:ok, items} =
             ParseAsItems.parse("## hello\n\n* item 1\n  * item 2\n* item 3")

    assert Enum.map(items, & &1["text"]) == ["## hello", "item 1", "item 2", "item 3"]
    assert Enum.map(items, & &1["depth"]) == [0, 0, 1, 0]
    assert Enum.all?(items, &is_binary(&1["yStateAsUpdate"]))
  end

  test "preserves inline markdown formatting in parsed items" do
    assert {:ok, items} = ParseAsItems.parse("- **経過**（~けいか~）\n  - 経過")

    assert Enum.map(items, & &1["text"]) == ["**経過**（~~けいか~~）", "経過"]
  end

  test "rebases parsed roots for child insertion" do
    assert {:ok, items} = ParseAsItems.parse("* child", 2)
    assert Enum.map(items, & &1["depth"]) == [2]
  end

  test "perform inserts parsed items through the runtime session" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{
            "id" => "id-source",
            "text" => "## hello\n\n* item 1\n  * item 2\n* item 3",
            "depth" => 0,
            "flashcard" => false,
            "answer" => false
          }
        ]
      })

    assert {:ok, %{kind: "page_updated", page: %{items: reply_items}}} =
             ParseAsItems.perform(unit.id, page.id, "id-source", "next_siblings")

    assert Enum.map(reply_items, & &1["text"]) == [
             "## hello\n\n* item 1\n  * item 2\n* item 3",
             "## hello",
             "item 1",
             "item 2",
             "item 3"
           ]

    assert Enum.all?(reply_items, &is_binary(&1["yStateAsUpdate"]))
  end

  defp stop_all_unit_sessions do
    for {_, pid, _, _} <-
          DynamicSupervisor.which_children(Gakugo.Notebook.UnitSession.Supervisor) do
      ref = Process.monitor(pid)

      :ok = DynamicSupervisor.terminate_child(Gakugo.Notebook.UnitSession.Supervisor, pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end
end
