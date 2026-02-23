defmodule Gakugo.Learning.Notebook.Importer do
  @moduledoc false

  alias Gakugo.AI.Client
  alias Gakugo.Learning.FromTargetLang

  @format_schema %{
    type: "object",
    properties: %{
      vocabularies: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            vocabulary: %{type: "string"},
            translation: %{type: "string"},
            note: %{type: "string"}
          },
          required: ["vocabulary", "translation", "note"]
        }
      }
    },
    required: ["vocabularies"]
  }

  def parse_source(source_text, from_target_lang, opts \\ [])

  def parse_source(source_text, from_target_lang, opts)
      when is_binary(source_text) and is_binary(from_target_lang) and is_list(opts) do
    system_prompt = FromTargetLang.notebook_import_system_prompt(from_target_lang)

    case Client.structured(
           source_text,
           system_prompt,
           @format_schema,
           Keyword.put_new(opts, :usage, :parse)
         ) do
      {:ok, %{"vocabularies" => vocabularies}} ->
        {:ok, normalize_vocabulary_entries(vocabularies)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def parse_source(_source_text, _from_target_lang, _opts), do: {:error, :invalid_source}

  def import_from_image(image_binary, from_target_lang, opts \\ [])

  def import_from_image(image_binary, from_target_lang, opts)
      when is_binary(image_binary) and byte_size(image_binary) > 0 and is_binary(from_target_lang) and
             is_list(opts) do
    ocr_opts = Keyword.put_new(opts, :from_target_lang, from_target_lang)

    with {:ok, ocr_text} <- extract_text_from_image(image_binary, ocr_opts),
         {:ok, vocabularies} <- parse_source(ocr_text, from_target_lang, opts) do
      {:ok, vocabularies}
    end
  end

  def import_from_image(_image_binary, _from_target_lang, _opts), do: {:error, :invalid_image}

  def extract_text_from_image(image_binary, opts \\ [])

  def extract_text_from_image(image_binary, opts)
      when is_binary(image_binary) and byte_size(image_binary) > 0 and is_list(opts) do
    from_target_lang = Keyword.get(opts, :from_target_lang)

    prompt =
      if is_binary(from_target_lang) do
        FromTargetLang.notebook_ocr_import_system_prompt(from_target_lang)
      else
        "Extract all visible text from this image. Preserve line breaks and original order."
      end

    case Client.ocr(image_binary, Keyword.put(opts, :prompt, prompt)) do
      {:ok, text} when is_binary(text) ->
        {:ok, String.trim(text)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def extract_text_from_image(_image_binary, _opts), do: {:error, :invalid_image}

  defp normalize_vocabulary_entries(vocabularies) when is_list(vocabularies) do
    vocabularies
    |> Enum.map(&normalize_vocabulary_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_vocabulary_entries(_vocabularies), do: []

  defp normalize_vocabulary_entry(vocabulary) when is_map(vocabulary) do
    raw_vocabulary = Map.get(vocabulary, "vocabulary") || ""
    raw_translation = Map.get(vocabulary, "translation") || ""
    note = vocabulary |> Map.get("note", "") |> to_string() |> String.trim()

    vocabulary_text = raw_vocabulary |> to_string() |> String.trim()
    translation_text = raw_translation |> to_string() |> String.trim()

    if vocabulary_text == "" or translation_text == "" do
      nil
    else
      %{"vocabulary" => vocabulary_text, "translation" => translation_text, "note" => note}
    end
  end

  defp normalize_vocabulary_entry(_vocabulary), do: nil
end
