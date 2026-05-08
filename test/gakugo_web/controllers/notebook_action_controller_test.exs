defmodule GakugoWeb.NotebookActionControllerTest do
  use GakugoWeb.ConnCase, async: false

  import Gakugo.LearningFixtures

  alias Gakugo.Db

  setup do
    stop_all_unit_sessions()
    :ok
  end

  test "POST /api/notebook_action/parse_as_items", %{conn: conn} do
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

    conn =
      conn
      |> init_test_session(%{})
      |> put_req_header("x-csrf-token", Plug.CSRFProtection.get_csrf_token())

    response =
      post(conn, "/api/notebook_action/parse_as_items", %{
        "unit_id" => unit.id,
        "page_id" => page.id,
        "item_id" => "id-source",
        "insertion_mode" => "next_siblings"
      })

    assert %{"kind" => "page_updated"} = json_response(response, 200)
  end

  test "POST /api/notebook_action/parse_as_flashcards", %{conn: conn} do
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

    conn =
      conn
      |> init_test_session(%{})
      |> put_req_header("x-csrf-token", Plug.CSRFProtection.get_csrf_token())

    response =
      post(conn, "/api/notebook_action/parse_as_flashcards", %{
        "unit_id" => unit.id,
        "page_id" => page.id,
        "item_id" => "id-source",
        "insertion_mode" => "next_siblings",
        "answer_mode" => "first_depth"
      })

    assert %{"kind" => "page_updated"} = json_response(response, 200)
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
