defmodule Gakugo.Notebook.Markdown do
  @moduledoc false

  alias Gakugo.Notebook.Markdown.HighlightPlugin

  def parse_document(text) when is_binary(text) do
    MDEx.parse_document!(text, plugins: [MDExGFM, HighlightPlugin])
  end

  def parse_document(_), do: MDEx.parse_document!("", plugins: [MDExGFM, HighlightPlugin])

  def to_html(text, opts \\ [])

  def to_html(text, opts) when is_binary(text) and is_list(opts) do
    text
    |> parse_document()
    |> HighlightPlugin.render_document()
    |> maybe_omit_raw_html(Keyword.get(opts, :raw_html, :omit))
    |> MDEx.to_html!(render: [unsafe: true], sanitize: sanitize_options())
  rescue
    _ -> escape_html(text)
  end

  def to_html(_, _), do: ""

  defp maybe_omit_raw_html(document, :allow), do: document
  defp maybe_omit_raw_html(document, :omit), do: omit_raw_html(document)

  defp omit_raw_html(%{nodes: nodes} = node) when is_list(nodes) do
    %{node | nodes: omit_raw_html_nodes(nodes)}
  end

  defp omit_raw_html(node), do: node

  defp omit_raw_html_nodes(nodes) do
    nodes
    |> Enum.map(&omit_raw_html_node/1)
    |> Enum.reject(&is_nil/1)
  end

  defp omit_raw_html_node(%MDEx.HtmlInline{literal: literal} = node) do
    if safe_generated_highlight_html?(literal), do: node, else: nil
  end

  defp omit_raw_html_node(%MDEx.HtmlBlock{}), do: nil

  defp omit_raw_html_node(%{nodes: nodes} = node) when is_list(nodes) do
    %{node | nodes: omit_raw_html_nodes(nodes)}
  end

  defp omit_raw_html_node(node), do: node

  defp safe_generated_highlight_html?("</mark>"), do: true

  defp safe_generated_highlight_html?(literal) when is_binary(literal) do
    Regex.match?(
      ~r/^<mark(?: data-text-color="[a-z]+")?(?: data-background-color="(?:[a-z]+|none)")?(?: style="(?:--gakugo-inline-(?:text|bg)-(?:light|dark): (?:#[0-9a-fA-F]{6}|transparent); ?)+")?>$/,
      literal
    )
  end

  defp safe_generated_highlight_html?(_), do: false

  defp sanitize_options do
    MDEx.Document.default_sanitize_options()
    |> Keyword.update!(:tag_attributes, fn tag_attributes ->
      Map.update(
        tag_attributes,
        "mark",
        ["data-text-color", "data-background-color", "style"],
        &Enum.uniq(&1 ++ ["data-text-color", "data-background-color", "style"])
      )
    end)
  end

  defp escape_html(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\n", "<br>")
  end
end
