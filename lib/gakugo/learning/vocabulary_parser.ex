defmodule Gakugo.Learning.VocabularyParser do
  @moduledoc """
  Parses vocabulary from text input using AI-powered extraction.
  Uses language-pair-specific system prompts for accurate parsing.
  """

  alias Gakugo.Ollama
  alias Gakugo.Learning.FromTargetLang

  @doc """
  Parses vocabulary from source text based on the language pair.

  Returns a list of vocabulary maps with :target, :from, and :note keys.

  ## Examples

      iex> parse("日文單字列表...", "JA-from-zh-TW")
      {:ok, [%{"target" => "学生", "from" => "學生", "note" => ""}]}

  """
  def parse(source_text, from_target_lang) when is_binary(source_text) do
    system_prompt = FromTargetLang.vocabulary_parser_system_prompt(from_target_lang)

    format_schema = %{
      type: "object",
      properties: %{
        vocabularies: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              target: %{type: "string"},
              from: %{type: "string"},
              note: %{type: "string"}
            },
            required: ["target", "from", "note"]
          }
        }
      },
      required: ["vocabularies"]
    }

    case Ollama.format(source_text, system_prompt, format_schema) do
      {:ok, %{"vocabularies" => vocabularies}} ->
        {:ok, vocabularies}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
