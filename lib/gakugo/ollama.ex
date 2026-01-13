defmodule Gakugo.Ollama do
  @moduledoc """
  Client for interacting with Ollama API.
  """

  @doc """
  Sends a chat request to Ollama.

  ## Options

    * `:model` - The model to use (required)
    * `:messages` - List of message maps with `:role` and `:content` keys (required)
    * `:stream` - Whether to stream the response (default: false)
    * `:format` - Response format, e.g. "json" (optional)

  ## Examples

      iex> Gakugo.Ollama.chat(
      ...>   model: "gpt-oss:20b",
      ...>   messages: [%{role: "user", content: "Tell me about Canada in one line"}],
      ...>   format: "json"
      ...> )
      {:ok, %{"message" => %{"role" => "assistant", "content" => "..."}, ...}}

  """
  def chat(opts) do
    model = Keyword.fetch!(opts, :model)
    messages = Keyword.fetch!(opts, :messages)
    stream = Keyword.get(opts, :stream, false)
    format = Keyword.get(opts, :format)

    body =
      %{
        model: model,
        messages: messages,
        stream: stream
      }
      |> maybe_put(:format, format)

    config = Application.fetch_env!(:gakugo, :ollama)
    url = "#{config[:base_url]}/api/chat"
    headers = [{"host", config[:host_header]}]

    case Req.post(url, json: body, receive_timeout: 120_000, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a chat request to Ollama with structured format output.

  This is a convenience function that wraps `chat/1` to request a structured
  JSON response according to the provided format schema. The JSON content from
  the response is automatically decoded and returned.

  ## Parameters

    * `content` - The user message content (string)
    * `system` - The system message to set context/instructions (string)
    * `format` - JSON schema map defining the expected response structure

  ## Examples

      iex> format = %{
      ...>   type: "object",
      ...>   properties: %{
      ...>     name: %{type: "string"},
      ...>     capital: %{type: "string"},
      ...>     languages: %{
      ...>       type: "array",
      ...>       items: %{type: "string"}
      ...>     }
      ...>   },
      ...>   required: ["name", "capital", "languages"]
      ...> }
      iex> Gakugo.Ollama.format(
      ...>   "Tell me about Canada.",
      ...>   "You are a helpful geography assistant.",
      ...>   format
      ...> )
      {:ok, %{"name" => "Canada", "capital" => "Ottawa", "languages" => ["English", "French"]}}

  """
  def format(content, system, format) do
    model = Application.fetch_env!(:gakugo, :ollama)[:model]

    case chat(
           model: model,
           messages: [%{role: "system", content: system}, %{role: "user", content: content}],
           stream: false,
           format: format
         ) do
      {:ok, %{"message" => %{"content" => json_content}}} ->
        case Jason.decode(json_content) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  def test() do
    format = %{
      type: "object",
      properties: %{
        name: %{type: "string"},
        capital: %{type: "string"},
        languages: %{
          type: "array",
          items: %{type: "string"}
        }
      },
      required: ["name", "capital", "languages"]
    }

    Gakugo.Ollama.format(
      "Tell me about Canada.",
      "You are a helpful geography assistant.",
      format
    )
  end
end
