defmodule Gakugo.Learning.FromTargetLang do
  @moduledoc """
  Defines supported language pairs for learning units.
  Each language pair has specific system prompts for AI operations.
  """

  alias Gakugo.Learning.Grammar

  @type t :: String.t()

  @values ["JA-from-zh-TW"]

  @doc """
  Returns all supported language pair values.
  """
  def all, do: @values

  @doc """
  Returns options for select inputs as `{label, value}` tuples.
  """
  def options, do: Enum.map(@values, &{label(&1), &1})

  @doc """
  Returns a human-readable label for a language pair.
  """
  def label("JA-from-zh-TW"), do: "Japanese (from Traditional Chinese)"

  def label(value) do
    raise ArgumentError,
          "Unknown from_target_lang value: #{inspect(value)}. " <>
            "Add a label/1 clause for this value in #{__MODULE__}."
  end

  @doc """
  Returns the system prompt for vocabulary parsing.
  """
  def vocabulary_parser_system_prompt("JA-from-zh-TW") do
    """
    你好，請幫忙從使用者輸入的文字截取出日文單字清單，使用者輸入的文字中每個項目應有 日文原文 以及 中文翻譯，target 爲日文原文（平仮名），from 爲中文翻譯，輸入資料有平假名標示的發音的話以括弧標示在 target 日文原文後方，每個項目剩餘的資料放在 note 中，不要額外補充東西
    """
  end

  def vocabulary_parser_system_prompt(value) do
    raise ArgumentError,
          "Unknown from_target_lang value: #{inspect(value)}. " <>
            "Add a vocabulary_parser_system_prompt/1 clause for this value in #{__MODULE__}."
  end

  @doc """
  Returns the system prompt for flashcard generation.
  """
  def flashcard_system_prompt("JA-from-zh-TW") do
    """
    你好，請幫忙建立一個日文翻譯練習。

    輸入格式說明：
    - 【單字】區塊包含要學習的日文單字（日文）及其中文意思（中文）
    - 【文法】區塊包含可參考的句型及說明

    重要規則：
    - 產生的句子「必須」包含【單字】中的日文，這是最重要的要求
    - 請儘量以【文法】的句型來進行造句，但若不適用可以用其他自然的句型
    - 中文句子也必須自然地包含單字的中文意思

    輸出格式（JSON）：
    - translation_from：繁體中文句子（必須包含單字的意思）
    - translation_target：日文句子（必須包含單字的日文）
    - 可以的話請在 translation_target 使用括弧 "（ひらがな）" 標示漢字讀音
    - 只需要一句句子，不需要其他說明

    例如，若單字日文是「リンゴ」、中文是「蘋果」：
    {"translation_from": "蘋果是紅色的", "translation_target": "リンゴは赤（あか）いです"}
    """
  end

  def flashcard_system_prompt(value) do
    raise ArgumentError,
          "Unknown from_target_lang value: #{inspect(value)}. " <>
            "Add a flashcard_system_prompt/1 clause for this value in #{__MODULE__}."
  end

  @doc """
  Returns the user prompt for flashcard generation.
  """
  def flashcard_user_prompt("JA-from-zh-TW", vocabulary, grammar) do
    """
    【單字】
    日文：#{vocabulary.target}
    中文：#{vocabulary.from}

    【文法】
    #{Grammar.format(grammar)}
    """
  end

  def flashcard_user_prompt(value, _vocabulary, _grammar) do
    raise ArgumentError,
          "Unknown from_target_lang value: #{inspect(value)}. " <>
            "Add a flashcard_user_prompt/3 clause for this value in #{__MODULE__}."
  end

  @doc """
  Validates that a value is a supported language pair.
  Returns true if valid, false otherwise.
  """
  def valid?(value), do: value in @values
end
