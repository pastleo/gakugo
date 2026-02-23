defmodule Gakugo.AI.Client do
  @moduledoc false

  alias Gakugo.AI.Config
  alias Gakugo.AI.Providers.Gemini
  alias Gakugo.AI.Providers.Ollama
  alias Gakugo.AI.Providers.OpenAI

  @providers [:ollama, :openai, :gemini]

  def structured(content, system, format_schema, opts \\ [])
      when is_binary(content) and is_binary(system) and is_map(format_schema) and is_list(opts) do
    usage = Keyword.get(opts, :usage, :parse)

    with {:ok, provider, model} <- resolve_provider_and_model(usage, opts),
         {:ok, provider_module} <- provider_module(provider) do
      provider_module.structured(
        Config.provider_config(provider),
        model,
        content,
        system,
        format_schema
      )
    end
  end

  def ocr(image_binary, opts \\ []) when is_binary(image_binary) and is_list(opts) do
    with {:ok, provider, model} <- resolve_provider_and_model(:ocr, opts),
         prompt = Keyword.get(opts, :prompt, "Extract all visible text from this image."),
         {:ok, provider_module} <- provider_module(provider) do
      provider_module.ocr(Config.provider_config(provider), model, image_binary, prompt)
    end
  end

  def list_models(provider) when provider in @providers do
    with {:ok, provider_module} <- provider_module(provider) do
      provider_module.list_models(Config.provider_config(provider))
    end
  end

  def list_models(_provider), do: {:error, :invalid_provider}

  defp resolve_provider_and_model(usage, opts) do
    provider = Keyword.get(opts, :provider) || Config.usage_provider(usage)
    model = Keyword.get(opts, :model) || Config.usage_model(usage)

    cond do
      provider not in @providers ->
        {:error, :invalid_provider}

      not (is_binary(model) and String.trim(model) != "") ->
        {:error, :missing_model}

      true ->
        {:ok, provider, String.trim(model)}
    end
  end

  defp provider_module(:ollama), do: {:ok, Ollama}
  defp provider_module(:openai), do: {:ok, OpenAI}
  defp provider_module(:gemini), do: {:ok, Gemini}
  defp provider_module(_provider), do: {:error, :invalid_provider}
end
