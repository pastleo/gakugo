defmodule Gakugo.Anki.MarkdownTest do
  use ExUnit.Case, async: true

  alias Gakugo.Anki.Markdown

  describe "preview_summary/1" do
    test "uses parsed markdown text for inline highlights" do
      assert Markdown.preview_summary(
               ~s|123 bold ==plain== ==<!-- {"textColor":"orange","backgroundColor":"rose"} -->aaa==|
             ) == "123 bold plain aaa"
    end

    test "uses the first non-empty rendered block" do
      assert Markdown.preview_summary("\n\n# **Title**\n\nbody") == "Title"
    end
  end

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
      assert html == ""
    end

    test "sanitizes unsafe markdown link urls" do
      html = Markdown.render_html(~s|[x](javascript:alert(1))|)

      refute String.contains?(html, "javascript:")
      refute String.contains?(html, "alert(1)")
      assert String.contains?(html, ">x</a>") or String.contains?(html, ">x</p>")
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

    test "renders inline highlight markdown" do
      html =
        Markdown.render_html(
          ~s|before ==<!-- {"textColor":"orange","backgroundColor":"rose"} -->highlight== after|
        )

      assert String.contains?(html, "<mark")
      assert String.contains?(html, ~s|data-text-color="orange"|)
      assert String.contains?(html, ~s|data-background-color="rose"|)
      assert String.contains?(html, ">highlight</mark>")
      refute String.contains?(html, "==highlight==")
    end
  end

  describe "wrap_occlusion/2" do
    test "keeps answer content in flow before the absolute mask overlay" do
      html = Markdown.wrap_occlusion("<p>multi<br>line answer</p>", true)

      assert String.contains?(html, ~s|class="gakugo-occlusion is-current"|)

      assert String.contains?(
               html,
               ~s|<div class="gakugo-occlusion-answer"><p>multi<br>line answer</p></div>|
             )

      assert String.contains?(
               html,
               ~s|<div class="gakugo-occlusion-mask" aria-hidden="true"></div>|
             )

      assert html =~ ~r/gakugo-occlusion-answer.*gakugo-occlusion-mask/s
    end
  end
end
