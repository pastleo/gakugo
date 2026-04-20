defmodule Gakugo.NotebookAction.ParseAsFlashcardsTest do
  use Gakugo.DataCase, async: false

  alias Gakugo.Db
  alias Gakugo.NotebookAction.ParseAsFlashcards

  import Gakugo.LearningFixtures

  setup do
    stop_all_unit_sessions()
    :ok
  end

  test "perform marks root items as flashcards with answers" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{
            "id" => "id-source",
            "text" => "* vol 1\n  * xxx\n* vol 2\n  * xxx",
            "depth" => 0,
            "flashcard" => false,
            "answer" => false
          }
        ]
      })

    assert {:ok, %{kind: "page_updated", page: %{items: reply_items}}} =
             ParseAsFlashcards.perform(
               unit.id,
               page.id,
               "id-source",
               "next_siblings",
               "first_depth"
             )

    assert Enum.map(reply_items, & &1["text"]) == [
             "* vol 1\n  * xxx\n* vol 2\n  * xxx",
             "vol 1",
             "xxx",
             "vol 2",
             "xxx"
           ]

    assert Enum.map(reply_items, & &1["flashcard"]) == [false, true, false, true, false]
    assert Enum.map(reply_items, & &1["answer"]) == [false, true, false, true, false]
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
