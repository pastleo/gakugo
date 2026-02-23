defmodule GakugoWeb.UnitLive.ShowEditImportHelpers do
  alias Gakugo.Learning.Notebook.Tree

  def combine_source_text(source, ocr_text) do
    [String.trim(source || ""), String.trim(ocr_text || "")]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def parse_source(import_type, source, from_target_lang, importer_module, opts \\ []) do
    case import_type do
      "vocabularies" -> importer_module.parse_source(source, from_target_lang, opts)
      _ -> {:error, :unsupported_import_type}
    end
  end

  def parse_ocr_consumed_result(consumed) do
    case consumed do
      [{:ok, text} | _rest] -> {:ok, text}
      [{:error, reason} | _rest] -> {:error, reason}
      _ -> {:error, :empty_ocr_result}
    end
  end

  def vocabulary_nodes(vocabularies) when is_list(vocabularies) do
    vocabularies
    |> Enum.map(&vocabulary_to_node/1)
    |> Enum.reject(&is_nil/1)
  end

  def vocabulary_nodes(_), do: []

  defp vocabulary_to_node(
         %{"vocabulary" => vocabulary_text, "translation" => translation} = vocabulary
       )
       when is_binary(vocabulary_text) and is_binary(translation) do
    vocabulary_text = String.trim(vocabulary_text)
    translation_text = String.trim(translation)

    if vocabulary_text == "" or translation_text == "" do
      nil
    else
      note_text = String.trim(Map.get(vocabulary, "note", ""))

      children =
        [
          Tree.new_node()
          |> Map.put("text", translation_text)
          |> Map.put("answer", false)
        ] ++
          if(note_text == "", do: [], else: [Tree.new_node() |> Map.put("text", note_text)])

      Tree.new_node()
      |> Map.put("text", vocabulary_text)
      |> Map.put("front", true)
      |> Map.put("answer", true)
      |> Map.put("children", children)
    end
  end

  defp vocabulary_to_node(_), do: nil
end
