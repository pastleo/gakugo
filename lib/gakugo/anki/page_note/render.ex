defmodule Gakugo.Anki.PageNote.Render do
  @moduledoc false

  alias Gakugo.Anki.Markdown
  alias Gakugo.Anki.Source

  def preview_entries(unit) do
    unit
    |> Source.flashcard_sources()
    |> Enum.map(&render_entry/1)
  end

  defp render_entry(source) do
    content_html =
      source.entries
      |> render_html_nodes(
        source.all_answer_paths,
        source.current_answer_paths,
        source.entry.path
      )
      |> render_page_content(source.page.title)

    %{
      id: source.id,
      summary: Markdown.preview_summary(source.entry.node["text"]),
      content_html: content_html
    }
  end

  defp render_html_nodes(entries, occluded_paths, current_answer_paths, front_path) do
    focused_paths = focused_tree_paths(entries, front_path)

    front_depth =
      entries
      |> Enum.find_value(0, fn entry ->
        if entry.path == front_path, do: Source.item_depth(entry.node)
      end)

    entries
    |> Enum.map(fn entry ->
      relative_depth = max(Source.item_depth(entry.node) - front_depth, 0)

      text_html =
        if MapSet.member?(occluded_paths, entry.path) do
          Markdown.render_html(entry.node["text"])
          |> Markdown.wrap_occlusion(MapSet.member?(current_answer_paths, entry.path))
        else
          Markdown.render_html(entry.node["text"])
        end

      node_classes =
        ["gakugo-node", Markdown.node_color_classes(entry.node)]
        |> maybe_add_class(MapSet.member?(focused_paths, entry.path), "is-tree-focus")
        |> maybe_add_class(entry.path == front_path, "is-target")
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")

      marker = if entry.path == front_path, do: "✦", else: "•"

      marker_class =
        if entry.path == front_path, do: "gakugo-marker is-target", else: "gakugo-marker"

      style_attr = Markdown.style_attr(entry.node["textColor"], entry.node["backgroundColor"])

      """
      <li style="margin-left: #{relative_depth * 1.25}rem;">
        <div class="gakugo-row">
          <span class="#{marker_class}">#{marker}</span>
          <div class="#{node_classes}" style="#{style_attr}">#{text_html}</div>
        </div>
      </li>
      """
    end)
    |> Enum.join("")
  end

  defp render_page_content(body_html, page_title) do
    """
    <div class="gakugo-page-header">
      <strong class="gakugo-page-title">#{Phoenix.HTML.html_escape(page_title) |> Phoenix.HTML.safe_to_string()}</strong>
      <button
        type="button"
        class="gakugo-toggle-answers-btn"
        onclick="var card=this.closest('.gakugo-card'); if(card){card.classList.toggle('reveal-other-answers'); this.classList.toggle('is-active');}"
      >
        Toggle revealing other answers
      </button>
      <script>
        (function () {
          var script = document.currentScript;
          var button = script && script.previousElementSibling;
          var card = button && button.closest('.gakugo-card');
          if (button && card && !card.classList.contains('is-answer')) {
            button.remove();
          }
        })();
      </script>
    </div>
    <ul class="gakugo-notebook">#{body_html}</ul>
    """
  end

  defp maybe_add_class(classes, true, class_name), do: [class_name | classes]
  defp maybe_add_class(classes, false, _class_name), do: classes

  defp focused_tree_paths(entries, front_path) do
    front_entry = Enum.find(entries, &(&1.path == front_path))

    case front_entry do
      nil ->
        MapSet.new()

      entry ->
        entries
        |> Source.descendant_entries(entry)
        |> Enum.map(& &1.path)
        |> then(fn descendant_paths -> MapSet.new([front_path | descendant_paths]) end)
    end
  end
end
