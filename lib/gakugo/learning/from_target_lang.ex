defmodule Gakugo.Learning.FromTargetLang do
  @moduledoc """
  Defines supported language pairs for learning units.
  Each language pair has specific system prompts for AI operations.
  """

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
  Returns the system prompt for notebook import parsing.
  """
  def notebook_import_system_prompt("JA-from-zh-TW") do
    """
    你好，請幫忙從使用者輸入的文字截取出日文單字清單。
    每個單字包含日文（平仮名）、以及繁體中文翻譯。
    請輸出欄位 vocabulary（日文原文，若有讀音使用全形括弧附在後方）、translation（繁體中文翻譯）、note（補充）。
    若輸入中日文與中文順序顛倒，仍要自動辨識並修正，確保 vocabulary 一定是日文、translation 一定是繁體中文。
    每個項目剩餘的補充資料放在 note 中，不要額外補充任何說明。
    輸入通常接近 markdown 巢狀清單（例如：* 日本語（にほんご） -> * 日文），但也要盡量容錯解析。
    """
  end

  def notebook_import_system_prompt(value) do
    raise ArgumentError,
          "Unknown from_target_lang value: #{inspect(value)}. " <>
            "Add a notebook_import_system_prompt/1 clause for this value in #{__MODULE__}."
  end

  @doc """
  Returns the OCR extraction prompt for notebook import.
  """
  def notebook_ocr_import_system_prompt("JA-from-zh-TW") do
    """
    請完整擷取圖片中的文字，保留原本換行與順序，不要翻譯、不要總結。
    若有日文假名與漢字請原樣保留，若有繁體中文也請原樣保留。
    請只輸出擷取到的純文字內容，不要加上任何解釋。
    """
  end

  def notebook_ocr_import_system_prompt(value) do
    raise ArgumentError,
          "Unknown from_target_lang value: #{inspect(value)}. " <>
            "Add a notebook_ocr_import_system_prompt/1 clause for this value in #{__MODULE__}."
  end

  @doc """
  Returns the system prompt for notebook translation practice generation.
  """
  def translation_practice_system_prompt("JA-from-zh-TW") do
    """
    你好，請幫忙建立一個日文翻譯練習句。

    輸入格式說明：
    - 【單字】是必須包含在句子裡的日文詞彙
    - 【文法】是參考的文法分支（由上到下）

    重要規則：
    - 請務必讓日文句子包含【單字】
    - 請盡量套用【文法】的語感與結構
    - 中文句子要自然、可作為翻譯練習題目

    輸出格式（JSON）：
    - translation_from：繁體中文句子
    - translation_target：日文句子
    - 只輸出一句，不要附加任何說明
    """
  end

  def translation_practice_system_prompt(value) do
    raise ArgumentError,
          "Unknown from_target_lang value: #{inspect(value)}. " <>
            "Add a translation_practice_system_prompt/1 clause for this value in #{__MODULE__}."
  end

  @doc """
  Returns the user prompt for notebook translation practice generation.
  """
  def translation_practice_user_prompt("JA-from-zh-TW", vocabulary_text, grammar_text) do
    """
    【單字】
    #{vocabulary_text}

    【文法】
    #{grammar_text}
    """
  end

  def translation_practice_user_prompt(value, _vocabulary_text, _grammar_text) do
    raise ArgumentError,
          "Unknown from_target_lang value: #{inspect(value)}. " <>
            "Add a translation_practice_user_prompt/3 clause for this value in #{__MODULE__}."
  end

  @doc """
  Validates that a value is a supported language pair.
  Returns true if valid, false otherwise.
  """
  def valid?(value), do: value in @values
end
