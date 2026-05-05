defmodule GakugoWeb.UnitLive.FlashcardPanelTest do
  use GakugoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gakugo.LearningFixtures

  alias Gakugo.Db

  setup do
    stop_all_unit_sessions()
    :ok
  end

  test "opens with async preview loading state and supports manual refresh", %{conn: conn} do
    unit = unit_fixture()
    unit = Db.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _updated_page} =
      Db.update_page(page, %{
        items: [
          %{"id" => "flashcard-source", "text" => "async preview card", "flashcard" => true}
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    loading_html =
      view
      |> element("#unit-flashcards-panel-toggle")
      |> render_click()

    assert loading_html =~ "flashcard-refresh-preview-btn"
    assert loading_html =~ "Collecting cards"

    rendered_html = render_async(view, 1_000)

    assert rendered_html =~ "async preview card"
    assert rendered_html =~ "1 cards"

    refresh_html =
      view
      |> element("#flashcard-refresh-preview-btn")
      |> render_click()

    assert refresh_html =~ "Rendering preview in the background"

    refreshed_html = render_async(view, 1_000)

    assert refreshed_html =~ "async preview card"
    assert refreshed_html =~ "1 cards"
  end

  defp stop_all_unit_sessions do
    for {_, pid, _, _} <-
          DynamicSupervisor.which_children(Gakugo.Notebook.UnitSession.Supervisor) do
      ref = Process.monitor(pid)

      :ok =
        DynamicSupervisor.terminate_child(Gakugo.Notebook.UnitSession.Supervisor, pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end
end
