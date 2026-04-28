defmodule Gakugo.Notebook.Markdown.HighlightPlugin do
  @moduledoc false

  alias Gakugo.Notebook.Colors
  alias Gakugo.Notebook.Markdown.HighlightNode
  alias MDEx.Document

  def attach(document, _options \\ []) do
    document
    |> Document.append_steps(normalize_highlights: &normalize_highlights/1)
  end

  def render_document(document) do
    render_document_node(document)
  end

  defp normalize_highlights(document) do
    MDEx.traverse_and_update(document, fn
      %{nodes: nodes} = node -> %{node | nodes: collapse_highlights(nodes)}
      node -> node
    end)
  end

  defp collapse_highlights(nodes) when is_list(nodes) do
    do_collapse_highlights(nodes, [])
  end

  defp do_collapse_highlights([], acc), do: Enum.reverse(acc)

  defp do_collapse_highlights([%MDEx.Text{literal: literal} = opener | tail], acc) do
    case String.split(literal, "==", parts: 2) do
      [prefix, rest] when prefix != literal ->
        case consume_highlight(tail, [], nil, rest) do
          {:ok, highlight_node, remainder} ->
            do_collapse_highlights(remainder, [highlight_node | maybe_text(prefix) ++ acc])

          :error ->
            do_collapse_highlights(tail, [opener | acc])
        end

      _ ->
        do_collapse_highlights(tail, [opener | acc])
    end
  end

  defp do_collapse_highlights([node | tail], acc) do
    do_collapse_highlights(tail, [node | acc])
  end

  defp consume_highlight(nodes, collected, attrs, pending_text) when is_binary(pending_text) do
    case String.split(pending_text, "==", parts: 2) do
      [content, rest_text] when rest_text != pending_text ->
        highlight = build_highlight(Enum.reverse(collected) ++ maybe_text(content), attrs)
        {:ok, highlight, maybe_text(rest_text) ++ nodes}

      _ ->
        consume_highlight(nodes, [maybe_text(pending_text) | collected], attrs, nil)
    end
  end

  defp consume_highlight([], _collected, _attrs, nil), do: :error

  defp consume_highlight([%MDEx.HtmlInline{literal: literal} = node | rest], collected, nil, nil) do
    case parse_comment_attrs(literal) do
      {:ok, attrs} -> consume_highlight(rest, collected, attrs, nil)
      :error -> consume_highlight(rest, [node | collected], nil, nil)
    end
  end

  defp consume_highlight([%MDEx.Text{literal: literal} = node | rest], collected, attrs, nil) do
    case String.split(literal, "==", parts: 2) do
      [content, rest_text] when rest_text != literal ->
        highlight = build_highlight(Enum.reverse(collected) ++ maybe_text(content), attrs)
        {:ok, highlight, maybe_text(rest_text) ++ rest}

      _ ->
        consume_highlight(rest, [node | collected], attrs, nil)
    end
  end

  defp consume_highlight([node | rest], collected, attrs, nil) do
    consume_highlight(rest, [node | collected], attrs, nil)
  end

  defp build_highlight(nodes, attrs) do
    %HighlightNode{
      nodes: nodes,
      text_color: Map.get(attrs || %{}, :text_color),
      background_color: Map.get(attrs || %{}, :background_color)
    }
  end

  defp parse_comment_attrs(literal) when is_binary(literal) do
    with [payload] <- Regex.run(~r/^<!--\s*(\{.*\})\s*-->$/, literal, capture: :all_but_first),
         {:ok, attrs} <- Jason.decode(payload) do
      {:ok, normalize_attrs(attrs)}
    else
      _ -> :error
    end
  end

  defp parse_comment_attrs(_), do: :error

  defp normalize_attrs(attrs) when is_map(attrs) do
    %{}
    |> put_color(:text_color, Map.get(attrs, "textColor"))
    |> put_color(:background_color, Map.get(attrs, "backgroundColor"))
  end

  defp normalize_attrs(_), do: %{}

  defp put_color(map, _key, value) when not is_binary(value), do: map

  defp put_color(map, :background_color, "none"), do: Map.put(map, :background_color, "none")

  defp put_color(map, key, value) do
    if Colors.valid_name?(value), do: Map.put(map, key, value), else: map
  end

  defp maybe_text(""), do: []
  defp maybe_text(text), do: [%MDEx.Text{literal: text}]

  defp render_document_node(%{nodes: nodes} = doc) when is_list(nodes) do
    %{doc | nodes: render_nodes(nodes)}
  end

  defp render_document_node(doc), do: doc

  defp render_nodes(nodes) when is_list(nodes) do
    Enum.reduce(nodes, [], fn node, acc -> acc ++ List.wrap(render_node(node)) end)
  end

  defp render_node(%HighlightNode{} = node) do
    [
      %MDEx.HtmlInline{literal: open_tag(node)}
      | render_nodes(node.nodes)
    ] ++ [%MDEx.HtmlInline{literal: "</mark>"}]
  end

  defp render_node(%{nodes: nodes} = node) when is_list(nodes) do
    %{node | nodes: render_nodes(nodes)}
  end

  defp render_node(node), do: node

  defp open_tag(%HighlightNode{text_color: text_color, background_color: background_color}) do
    data_attrs =
      [
        if(text_color, do: ~s(data-text-color="#{text_color}")),
        if(background_color, do: ~s(data-background-color="#{background_color}"))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    style_parts =
      [
        inline_color_vars(text_color, :foreground),
        inline_color_vars(background_color, :background)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    attrs =
      [
        data_attrs,
        if(style_parts == "", do: nil, else: ~s(style="#{style_parts}"))
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    if attrs == "" do
      "<mark>"
    else
      "<mark " <> attrs <> ">"
    end
  end

  defp inline_color_vars(nil, _role), do: []

  defp inline_color_vars("none", :background),
    do: ["--gakugo-inline-bg-light: transparent;", "--gakugo-inline-bg-dark: transparent;"]

  defp inline_color_vars(color, role) do
    [
      "--gakugo-inline-#{inline_role_name(role)}-light: #{Colors.hex(color, role, :light)};",
      "--gakugo-inline-#{inline_role_name(role)}-dark: #{Colors.hex(color, role, :dark)};"
    ]
  end

  defp inline_role_name(:foreground), do: "text"
  defp inline_role_name(:background), do: "bg"
end
