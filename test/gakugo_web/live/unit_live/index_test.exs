defmodule GakugoWeb.UnitLive.IndexTest do
  use GakugoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gakugo.LearningFixtures

  alias Gakugo.Db

  test "home page shows AI model refresh controls", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#refresh-ai-models-btn")
    assert render(view) =~ "Refresh available AI models"
  end

  test "refresh models button triggers refresh feedback", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#refresh-ai-models-btn")
    |> render_click()

    send(view.pid, :reload_ai_runtime)
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "#flash-info", "Refreshed,")
    assert has_element?(view, "#flash-info", "ollama:")
    assert has_element?(view, "#flash-info", "openai:")
    assert has_element?(view, "#flash-info", "gemini:")
  end

  test "search panel finds notebook items", %{conn: conn} do
    unit = unit_fixture(%{title: "Search Unit"})
    page = unit.id |> Db.get_unit!() |> Map.get(:pages) |> hd()

    {:ok, _page} =
      Db.update_page(page, %{
        title: "Search Page",
        items: [%{"id" => "target-item", "text" => "**needle** in notebook", "depth" => 0}]
      })

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("button[phx-click=toggle_search_panel]")
    |> render_click()

    assert has_element?(view, "#unit-search-panel")

    view
    |> form("#unit-search-form", notebook_search: %{query: "needle"})
    |> render_submit()

    render_async(view, 1_000)

    html = render(view)
    assert html =~ "Search Unit &gt; Search Page &gt; target-item"
    assert html =~ "<strong>"
    assert html =~ "<mark"
    assert html =~ ~s(href="/units/#{unit.id}?page_id=#{page.id}&amp;item_id=target-item")
  end
end
