defmodule Gakugo.Anki.Preview do
  @moduledoc false

  def summary(markdown) when is_binary(markdown) do
    markdown
    |> Gakugo.Notebook.Markdown.parse_document()
    |> first_block_summary()
  end

  def summary(_), do: ""

  defp first_block_summary(%MDEx.Document{nodes: nodes}) do
    nodes
    |> Enum.map(&text_content/1)
    |> Enum.find("", &(String.trim(&1) != ""))
    |> normalize_summary_text()
  end

  defp text_content(nodes) when is_list(nodes) do
    nodes
    |> Enum.map(&text_content/1)
    |> Enum.join("")
  end

  defp text_content(%MDEx.SoftBreak{}), do: " "
  defp text_content(%MDEx.LineBreak{}), do: " "
  defp text_content(%MDEx.HtmlInline{}), do: ""
  defp text_content(%MDEx.HtmlBlock{}), do: ""

  defp text_content(%{literal: literal}) when is_binary(literal), do: literal
  defp text_content(%{nodes: nodes}) when is_list(nodes), do: text_content(nodes)
  defp text_content(_), do: ""

  defp normalize_summary_text(text) do
    text
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end
end
