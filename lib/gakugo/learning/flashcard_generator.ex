defmodule Gakugo.Learning.FlashcardGenerator do
  @moduledoc """
  Generates flashcard content using Ollama for translation practice.
  Creates flashcards based on the unit's language pair settings.
  """

  alias Gakugo.Ollama
  alias Gakugo.Learning
  alias Gakugo.Learning.{Vocabulary, Grammar, FromTargetLang}

  @doc """
  Generates a flashcard for a vocabulary using a grammar pattern.

  The flashcard format depends on the unit's from_target_lang setting.

  ## Examples

      iex> generate_flashcard(vocabulary, grammar, "JA-from-zh-TW")
      {:ok, %{front: "學生\\n我是學生", back: "学生（がくせい）\\n学生です"}}

  """
  def generate_flashcard(%Vocabulary{} = vocabulary, %Grammar{} = grammar, from_target_lang) do
    system_prompt = FromTargetLang.flashcard_system_prompt(from_target_lang)
    user_prompt = FromTargetLang.flashcard_user_prompt(from_target_lang, vocabulary, grammar)

    format_schema = %{
      type: "object",
      properties: %{
        translation_from: %{ type: "string" },
        translation_target: %{type: "string"}
      },
      required: ["translation_from", "translation_target"]
    }


    case Ollama.format(user_prompt, system_prompt, format_schema) do
      {:ok, result} ->
        front = "#{vocabulary.from}\n#{result["translation_from"]}"

        back =
          if vocabulary.note && vocabulary.note != "" do
            "#{vocabulary.target}\n#{result["translation_target"]}\n\n#{vocabulary.note}"
          else
            "#{vocabulary.target}\n#{result["translation_target"]}"
          end

        {:ok, %{front: front, back: back}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates and saves a flashcard for a vocabulary.

  Picks a random grammar from the unit to use for sentence generation.
  If no grammars exist, creates a simple vocabulary-only flashcard.

  ## Examples

      iex> generate_and_save_flashcard(vocabulary, unit)
      {:ok, %Flashcard{}}

  """
  def generate_and_save_flashcard(%Vocabulary{} = vocabulary, unit) do
    grammars = unit.grammars || []

    result =
      if grammars == [] do
        {:ok,
         %{
           front: vocabulary.from,
           back: vocabulary.target
         }}
      else
        grammar = Enum.random(grammars)
        generate_flashcard(vocabulary, grammar, unit.from_target_lang)
      end

    case result do
      {:ok, %{front: front, back: back}} ->
        Learning.upsert_flashcard(%{
          unit_id: vocabulary.unit_id,
          vocabulary_id: vocabulary.id,
          front: front,
          back: back
        })

      {:error, reason} ->
        {:error, reason}
    end
  end
end
