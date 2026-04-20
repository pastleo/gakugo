defmodule Gakugo.Anki.Markdown do
  @moduledoc false

  def render_html(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown, plugins: [MDExGFM], render: [unsafe: false])
  end

  def render_html(_), do: ""

  def preview_summary(markdown) when is_binary(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.find("", &(String.trim(&1) != ""))
    |> normalize_preview_line()
  end

  def preview_summary(_), do: ""

  def wrap_occlusion(answer_html, current_answer?) when is_binary(answer_html) do
    occlusion_class =
      if current_answer?, do: "gakugo-occlusion is-current", else: "gakugo-occlusion is-other"

    """
    <div class="#{occlusion_class}">
      <div class="gakugo-occlusion-mask" aria-hidden="true"></div>
      <div class="gakugo-occlusion-answer">#{answer_html}</div>
    </div>
    """
  end

  def style_attr(nil, nil), do: ""

  def style_attr(text_color_name, background_color_name) do
    text_light = Gakugo.Notebook.Colors.hex(text_color_name, :foreground, :light)
    text_dark = Gakugo.Notebook.Colors.hex(text_color_name, :foreground, :dark)
    bg_light = Gakugo.Notebook.Colors.hex(background_color_name, :background, :light)
    bg_dark = Gakugo.Notebook.Colors.hex(background_color_name, :background, :dark)

    [
      css_var("--gakugo-text-light", text_light),
      css_var("--gakugo-text-dark", text_dark),
      css_var("--gakugo-bg-light", bg_light),
      css_var("--gakugo-bg-dark", bg_dark)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def node_color_classes(node) do
    []
    |> maybe_add_class(is_binary(node["textColor"]), "has-text-color")
    |> maybe_add_class(is_binary(node["backgroundColor"]), "has-background-color")
    |> Enum.join(" ")
  end

  defp normalize_preview_line(line) do
    line
    |> String.trim()
    |> String.replace(~r/^[-*+]\s+/, "")
    |> String.replace(~r/^#+\s+/, "")
    |> String.replace(~r/`([^`]+)`/, "\\1")
    |> String.replace(~r/[*_~]+/, "")
    |> String.replace(~r/!\[[^\]]*\]\([^)]*\)/, "")
    |> String.replace(~r/\[([^\]]+)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/\s+/, " ")
  end

  defp css_var(_name, nil), do: nil
  defp css_var(name, value), do: "#{name}: #{value};"

  defp maybe_add_class(classes, true, class_name), do: [class_name | classes]
  defp maybe_add_class(classes, false, _class_name), do: classes
end
