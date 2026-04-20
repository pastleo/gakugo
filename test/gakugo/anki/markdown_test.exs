defmodule Gakugo.Anki.MarkdownTest do
  use ExUnit.Case, async: true

  alias Gakugo.Anki.Markdown

  describe "render_html/1" do
    test "does not render raw script tags" do
      html = Markdown.render_html("before\n\n<script>alert(1)</script>\n\nafter")

      refute String.contains?(html, "<script")
      refute String.contains?(html, "alert(1)")
      assert String.contains?(html, "<p>before</p>")
      assert String.contains?(html, "<p>after</p>")
    end

    test "does not preserve raw html with inline handlers" do
      html = Markdown.render_html(~s|<div onclick="alert(1)">hello</div>|)

      refute String.contains?(html, ~s(onclick=))
      refute String.contains?(html, "<div")
      refute String.contains?(html, "alert(1)")
      assert html == "<!-- raw HTML omitted -->"
    end

    test "renders normal markdown" do
      html = Markdown.render_html("# Title\n\n*italic*\n\n- one\n- two")

      assert String.contains?(html, "<h1>Title</h1>")
      assert String.contains?(html, "<em>italic</em>")
      assert String.contains?(html, "<li>one</li>")
      assert String.contains?(html, "<li>two</li>")
    end

    test "renders gfm tables" do
      html = Markdown.render_html("| a | b |\n|---|---|\n| 1 | 2 |")

      assert String.contains?(html, "<table>")
      assert String.contains?(html, "<thead>")
      assert String.contains?(html, "<tbody>")
      assert String.contains?(html, "<td>1</td>")
      assert String.contains?(html, "<td>2</td>")
    end
  end
end
