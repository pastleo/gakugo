defmodule Gakugo.Learning.Notebook.TranslationPracticeGenerator do
  @moduledoc false

  alias Gakugo.AI.Client
  alias Gakugo.Learning.FromTargetLang

  @format_schema %{
    type: "object",
    properties: %{
      translation_from: %{type: "string"},
      translation_target: %{type: "string"}
    },
    required: ["translation_from", "translation_target"]
  }

  def generate_translation_practice(vocabulary, grammar_context, from_target_lang, opts \\ [])

  def generate_translation_practice(vocabulary, grammar_context, from_target_lang, opts)
      when is_binary(vocabulary) and is_binary(grammar_context) and is_binary(from_target_lang) and
             is_list(opts) do
    vocabulary_text = String.trim(vocabulary)
    grammar_text = String.trim(grammar_context)

    cond do
      vocabulary_text == "" ->
        {:error, :empty_vocabulary}

      grammar_text == "" ->
        {:error, :empty_grammar_context}

      true ->
        system_prompt = FromTargetLang.translation_practice_system_prompt(from_target_lang)

        user_prompt =
          FromTargetLang.translation_practice_user_prompt(
            from_target_lang,
            vocabulary_text,
            grammar_text
          )

        case Client.structured(
               user_prompt,
               system_prompt,
               @format_schema,
               Keyword.put_new(opts, :usage, :generation)
             ) do
          {:ok,
           %{"translation_from" => translation_from, "translation_target" => translation_target}}
          when is_binary(translation_from) and is_binary(translation_target) ->
            {:ok,
             %{
               "translation_from" => String.trim(translation_from),
               "translation_target" => String.trim(translation_target)
             }}

          {:ok, response} ->
            {:error, {:unexpected_response, response}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def generate_translation_practice(_vocabulary, _grammar_context, _from_target_lang, _opts),
    do: {:error, :invalid_input}
end
