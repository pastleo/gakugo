defmodule Gakugo.AI.Providers.Gemini do
  @moduledoc false

  @behaviour Gakugo.AI.Provider

  @impl true
  def list_models(provider_config) do
    base_url = Keyword.get(provider_config, :base_url)
    api_key = Keyword.get(provider_config, :api_key)

    cond do
      invalid_base_url?(base_url) ->
        {:error, :missing_base_url}

      missing_api_key?(api_key) ->
        {:error, :missing_api_key}

      true ->
        path = "/models?key=#{api_key}"

        with {:ok, %Req.Response{status: 200, body: %{"models" => data}}} <-
               Req.get(join_url(base_url, path), receive_timeout: 10_000) do
          models =
            data
            |> Enum.map(&Map.get(&1, "name"))
            |> Enum.map(fn
              "models/" <> name -> name
              name -> name
            end)
            |> normalize_model_names()

          {:ok, models}
        else
          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:http_error, status, body}}

          {:error, reason} ->
            {:error, reason}

          _ ->
            {:error, :invalid_response}
        end
    end
  end

  @impl true
  def structured(provider_config, model, content, system, format_schema) do
    base_url = Keyword.get(provider_config, :base_url)
    api_key = Keyword.get(provider_config, :api_key)

    cond do
      invalid_base_url?(base_url) ->
        {:error, :missing_base_url}

      missing_api_key?(api_key) ->
        {:error, :missing_api_key}

      true ->
        url = join_url(base_url, "/models/#{model}:generateContent?key=#{api_key}")

        body = %{
          system_instruction: %{parts: [%{text: system}]},
          contents: [%{parts: [%{text: content}]}],
          generationConfig: %{responseMimeType: "application/json", responseSchema: format_schema}
        }

        with {:ok, %Req.Response{status: 200, body: response_body}} <-
               Req.post(url, json: body, receive_timeout: 120_000),
             {:ok, content_text} <- response_text(response_body),
             {:ok, decoded} <- Jason.decode(content_text) do
          {:ok, decoded}
        else
          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:http_error, status, body}}

          {:error, reason} ->
            {:error, reason}

          _ ->
            {:error, :invalid_response}
        end
    end
  end

  @impl true
  def ocr(provider_config, model, image_binary, prompt) do
    base_url = Keyword.get(provider_config, :base_url)
    api_key = Keyword.get(provider_config, :api_key)

    cond do
      invalid_base_url?(base_url) ->
        {:error, :missing_base_url}

      missing_api_key?(api_key) ->
        {:error, :missing_api_key}

      true ->
        url = join_url(base_url, "/models/#{model}:generateContent?key=#{api_key}")

        body = %{
          contents: [
            %{
              parts: [
                %{text: prompt},
                %{inline_data: %{mime_type: "image/png", data: Base.encode64(image_binary)}}
              ]
            }
          ]
        }

        with {:ok, %Req.Response{status: 200, body: response_body}} <-
               Req.post(url, json: body, receive_timeout: 120_000),
             {:ok, content_text} <- response_text(response_body) do
          {:ok, String.trim(content_text)}
        else
          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:http_error, status, body}}

          {:error, reason} ->
            {:error, reason}

          _ ->
            {:error, :invalid_response}
        end
    end
  end

  defp response_text(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]})
       when is_list(parts) do
    text =
      parts
      |> Enum.map(fn
        %{"text" => text} when is_binary(text) -> text
        _ -> ""
      end)
      |> Enum.join("\n")

    if text == "", do: {:error, :invalid_response}, else: {:ok, text}
  end

  defp response_text(_response_body), do: {:error, :invalid_response}

  defp missing_api_key?(api_key), do: not (is_binary(api_key) and String.trim(api_key) != "")

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

  defp normalize_model_names(values) do
    values
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.map(&String.trim/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
