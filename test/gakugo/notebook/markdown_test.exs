defmodule Gakugo.Notebook.MarkdownTest do
  use ExUnit.Case, async: true

  alias Gakugo.Notebook.Markdown

  test "to_html renders default highlight markdown" do
    rendered = Markdown.to_html("==highlight==")

    assert rendered =~ "<mark"
    assert rendered =~ "highlight"
  end

  test "to_html renders text-only highlight background reset" do
    rendered =
      Markdown.to_html(~s(==<!-- {"textColor":"yellow","backgroundColor":"none"} -->highlight==))

    assert rendered =~ ~s(data-text-color="yellow")
    assert rendered =~ ~s(data-background-color="none")
    assert rendered =~ "--gakugo-inline-bg-light: transparent;"
    assert rendered =~ "--gakugo-inline-bg-dark: transparent;"
  end

  test "to_html ignores invalid highlight colors" do
    rendered =
      Markdown.to_html(~s(==<!-- {"textColor":"bad","backgroundColor":"worse"} -->highlight==))

    refute rendered =~ "data-text-color"
    refute rendered =~ "data-background-color"
  end
end
