defmodule GakugoWeb.UnitLive.IndexTest do
  use GakugoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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
end
