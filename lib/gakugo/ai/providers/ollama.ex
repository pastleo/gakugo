defmodule Gakugo.AI.Providers.Ollama do
  @moduledoc false

  @behaviour Gakugo.AI.Provider

  @impl true
  def list_models(provider_config) do
    base_url = Keyword.get(provider_config, :base_url)
    host_header = Keyword.get(provider_config, :host_header)

    if invalid_base_url?(base_url) do
      {:error, :missing_base_url}
    else
      headers = if present?(host_header), do: [{"host", host_header}], else: []

      with {:ok, %Req.Response{status: 200, body: %{"models" => models}}} <-
             Req.get(join_url(base_url, "/api/tags"), headers: headers, receive_timeout: 10_000) do
        model_names =
          models
          |> Enum.map(&Map.get(&1, "name"))
          |> normalize_model_names()

        {:ok, model_names}
      else
        {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_error, status, body}}
        {:error, reason} -> {:error, reason}
        _ -> {:error, :invalid_response}
      end
    end
  end

  @impl true
  def structured(provider_config, model, content, system, format_schema) do
    with {:ok, body} <-
           chat(provider_config,
             model: model,
             messages: [%{role: "system", content: system}, %{role: "user", content: content}],
             stream: false,
             format: format_schema
           ),
         %{"message" => %{"content" => json_content}} <- body,
         {:ok, decoded} <- Jason.decode(json_content) do
      {:ok, decoded}
    else
      {:error, reason} -> {:error, reason}
      {:ok, response} -> {:error, {:unexpected_response, response}}
      _ -> {:error, :invalid_response}
    end
  end

  @impl true
  def ocr(provider_config, model, image_binary, prompt) do
    with {:ok, %{"message" => %{"content" => text}}} when is_binary(text) <-
           chat(provider_config,
             model: model,
             messages: [%{role: "user", content: prompt, images: [Base.encode64(image_binary)]}],
             stream: false
           ) do
      {:ok, String.trim(text)}
    else
      {:ok, response} -> {:error, {:unexpected_response, response}}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  end

  defp chat(provider_config, opts) do
    base_url = Keyword.get(provider_config, :base_url)
    host_header = Keyword.get(provider_config, :host_header)

    if invalid_base_url?(base_url) do
      {:error, :missing_base_url}
    else
      model = Keyword.fetch!(opts, :model)
      messages = Keyword.fetch!(opts, :messages)
      stream = Keyword.get(opts, :stream, false)
      format = Keyword.get(opts, :format)

      body =
        %{model: model, messages: messages, stream: stream}
        |> maybe_put(:format, format)

      headers = if present?(host_header), do: [{"host", host_header}], else: []

      case Req.post(join_url(base_url, "/api/chat"),
             json: body,
             receive_timeout: 120_000,
             headers: headers
           ) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          {:ok, response_body}

        {:ok, %Req.Response{status: status, body: response_body}} ->
          {:error, {:http_error, status, response_body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp invalid_base_url?(value) do
    case URI.parse(value || "") do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        false

      _ ->
        true
    end
  end

  defp join_url(base_url, suffix) when is_binary(base_url) and is_binary(suffix) do
    String.trim_trailing(base_url, "/") <> suffix
  end

  defp join_url(_base_url, suffix), do: suffix

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp normalize_model_names(values) do
    values
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.map(&String.trim/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
