defmodule Gakugo.Anki.SimpleNote.Render do
  @moduledoc false

  alias Gakugo.Anki.Markdown
  alias Gakugo.Anki.Source

  def preview_entries(unit) do
    unit
    |> Source.flashcard_sources()
    |> Enum.map(&render_entry/1)
  end

  defp render_entry(source) do
    front_depth = Source.item_depth(source.entry.node)

    content_html =
      source.subtree_entries
      |> Enum.map(fn entry ->
        relative_depth = max(Source.item_depth(entry.node) - front_depth, 0)
        marker = if entry.path == source.entry.path, do: "✦", else: "•"

        marker_class =
          if entry.path == source.entry.path, do: "gakugo-marker is-target", else: "gakugo-marker"

        text_html =
          if MapSet.member?(source.current_answer_paths, entry.path) do
            Markdown.render_html(entry.node["text"])
            |> Markdown.wrap_occlusion(MapSet.member?(source.current_answer_paths, entry.path))
          else
            Markdown.render_html(entry.node["text"])
          end

        node_classes =
          ["gakugo-node", Markdown.node_color_classes(entry.node)]
          |> maybe_add_class(true, "is-tree-focus")
          |> maybe_add_class(entry.path == source.entry.path, "is-target")
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.join(" ")

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
      |> then(fn body_html -> "<ul class=\"gakugo-notebook\">#{body_html}</ul>" end)

    %{
      id: source.id,
      summary: Markdown.preview_summary(source.entry.node["text"]),
      content_html: content_html
    }
  end

  defp maybe_add_class(classes, true, class_name), do: [class_name | classes]
  defp maybe_add_class(classes, false, _class_name), do: classes
end
