defmodule GakugoWeb.NotebookActionController do
  use GakugoWeb, :controller

  alias Gakugo.NotebookAction.ParseAsFlashcards
  alias Gakugo.NotebookAction.ParseAsItems

  def parse_as_items(conn, params) do
    with {:ok, unit_id} <- required_integer(params, "unit_id"),
         {:ok, page_id} <- required_integer(params, "page_id"),
         {:ok, item_id} <- required_binary(params, "item_id"),
         {:ok, insertion_mode} <- required_insertion_mode(params),
         {:ok, reply} <- ParseAsItems.perform(unit_id, page_id, item_id, insertion_mode) do
      json(conn, reply)
    else
      {:error, reason} -> json(conn, invalid_params_reply(reason))
      _ -> json(conn, invalid_params_reply("invalid parameters"))
    end
  end

  def parse_as_flashcards(conn, params) do
    with {:ok, unit_id} <- required_integer(params, "unit_id"),
         {:ok, page_id} <- required_integer(params, "page_id"),
         {:ok, item_id} <- required_binary(params, "item_id"),
         {:ok, insertion_mode} <- required_insertion_mode(params),
         {:ok, answer_mode} <- required_answer_mode(params),
         {:ok, reply} <-
           ParseAsFlashcards.perform(unit_id, page_id, item_id, insertion_mode, answer_mode) do
      json(conn, reply)
    else
      {:error, reason} -> json(conn, invalid_params_reply(reason))
      _ -> json(conn, invalid_params_reply("invalid parameters"))
    end
  end

  defp required_integer(params, key) do
    case Map.get(params, key) do
      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> {:ok, int}
          _ -> {:error, "invalid parameters"}
        end

      _ ->
        {:error, "invalid parameters"}
    end
  end

  defp required_binary(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "invalid parameters"}
    end
  end

  defp required_insertion_mode(params) do
    case Map.get(params, "insertion_mode") do
      mode when mode in ["next_siblings", "children"] -> {:ok, mode}
      _ -> {:error, "invalid parameters"}
    end
  end

  defp required_answer_mode(params) do
    case Map.get(params, "answer_mode") do
      mode when mode in ["first_depth", "non_first_depth", "no_answer"] -> {:ok, mode}
      _ -> {:error, "invalid parameters"}
    end
  end

  defp invalid_params_reply(reason), do: %{status: "invalid_params", reason: reason}
end
