defmodule Gakugo.Learning.FlashcardGenerator do
  @moduledoc """
  Generates flashcard content using Ollama for translation practice.
  Creates flashcards with Traditional Chinese (TW) front and Japanese back.
  """

  alias Gakugo.Ollama
  alias Gakugo.Learning
  alias Gakugo.Learning.{Vocabulary, Grammar}

  @doc """
  Generates a flashcard for a vocabulary using a grammar pattern.

  The flashcard format:
  - Front: vocabulary (TW) + sentence using vocabulary in TW
  - Back: vocabulary (JP with furigana) + sentence in JP

  ## Examples

      iex> generate_flashcard(vocabulary, grammar)
      {:ok, %{front: "學生\\n我是學生", back: "学生（がくせい）\\n学生です"}}

  """
  def generate_flashcard(%Vocabulary{} = vocabulary, %Grammar{} = grammar) do
    system_prompt = """
    You are a Japanese language learning assistant specialized in creating flashcards.
    Your task is to generate example sentences for translation practice.

    Rules:
    1. Create a simple, natural sentence using the given vocabulary and grammar pattern
    2. The sentence should be appropriate for beginner to intermediate learners
    3. Use the grammar pattern provided to construct the sentence
    4. For Japanese sentences, add furigana in parentheses after kanji
    """

    user_prompt = """
    Create example sentences for the following:

    Vocabulary:
    - Japanese (target): #{vocabulary.target}
    - Traditional Chinese (from): #{vocabulary.from}
    #{if vocabulary.note, do: "- Note: #{vocabulary.note}", else: ""}

    Grammar pattern: #{grammar.title}
    #{format_grammar_details(grammar.details)}

    Generate:
    1. A sentence in Traditional Chinese using this vocabulary
    2. The same sentence translated to Japanese with furigana in parentheses for kanji
    """

    format_schema = %{
      type: "object",
      properties: %{
        front_sentence: %{
          type: "string",
          description: "A sentence using the vocabulary in Traditional Chinese"
        },
        back_sentence: %{
          type: "string",
          description: "The sentence in Japanese with furigana in parentheses for kanji"
        }
      },
      required: ["front_sentence", "back_sentence"]
    }

    case Ollama.format(user_prompt, system_prompt, format_schema) do
      {:ok, result} ->
        front = "#{vocabulary.from}\n#{result["front_sentence"]}"

        back =
          if vocabulary.note && vocabulary.note != "" do
            "#{vocabulary.target}\n#{result["back_sentence"]}\n\n#{vocabulary.note}"
          else
            "#{vocabulary.target}\n#{result["back_sentence"]}"
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
        generate_flashcard(vocabulary, grammar)
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

  defp format_grammar_details(nil), do: ""
  defp format_grammar_details([]), do: ""

  defp format_grammar_details(details) when is_list(details) do
    details
    |> Enum.map(&format_detail_item/1)
    |> Enum.join("\n")
  end

  defp format_detail_item(%{"detail" => detail} = item) do
    children = Map.get(item, "children", [])

    if children == [] do
      "- #{detail}"
    else
      child_text =
        children
        |> Enum.map(&format_detail_item/1)
        |> Enum.map(&("  " <> &1))
        |> Enum.join("\n")

      "- #{detail}\n#{child_text}"
    end
  end

  defp format_detail_item(_), do: ""
end
