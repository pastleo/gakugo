defmodule GakugoWeb.UnitLive.ShowEditMoveHelpers do
  alias Gakugo.Learning.Notebook.Tree

  def move_item(socket, params, opts) when is_map(params) do
    parse_page_id = Keyword.fetch!(opts, :parse_page_id)
    page_by_id = Keyword.fetch!(opts, :page_by_id)
    apply_command = Keyword.fetch!(opts, :apply_local_editor_command_with_result)
    normalize_path = Keyword.fetch!(opts, :normalize_path)

    with {:ok, source_page_id} <- parse_page_id.(Map.get(params, "source_page_id")),
         source_page when not is_nil(source_page) <-
           page_by_id.(socket.assigns.unit, source_page_id),
         source_state when not is_nil(source_state) <-
           Map.get(socket.assigns.page_states, source_page_id),
         {:ok, source_path} <-
           resolve_payload_path(source_state.nodes, params, "source", normalize_path),
         source_node when not is_nil(source_node) <-
           Tree.get_node(source_state.nodes, source_path),
         {:ok, target_page_id} <-
           parse_page_id.(Map.get(params, "target_page_id", Map.get(params, "source_page_id"))) do
      if source_page_id == target_page_id do
        command = {:move_node, move_source_target(params), move_destination_target(params)}
        {_status, next_socket} = apply_command.(socket, source_page, source_state, command)
        next_socket
      else
        move_item_across_pages(
          socket,
          params,
          source_page,
          source_state,
          target_page_id,
          source_node,
          page_by_id,
          apply_command,
          normalize_path
        )
      end
    else
      _ -> socket
    end
  end

  def move_item(socket, _params, _opts), do: socket

  defp move_item_across_pages(
         socket,
         params,
         source_page,
         source_state,
         target_page_id,
         source_node,
         page_by_id,
         apply_command,
         normalize_path
       ) do
    with target_page when not is_nil(target_page) <-
           page_by_id.(socket.assigns.unit, target_page_id),
         target_state when not is_nil(target_state) <-
           Map.get(socket.assigns.page_states, target_page_id),
         {:ok, target_parent_path, target_index} <-
           resolve_cross_page_destination(target_state.nodes, params, normalize_path),
         {:ok, socket_after_remove} <-
           remove_source_node_for_move(
             socket,
             source_page,
             source_state,
             move_source_target(params),
             apply_command
           ),
         refreshed_target_state when not is_nil(refreshed_target_state) <-
           Map.get(socket_after_remove.assigns.page_states, target_page_id),
         {:ok, socket_after_insert} <-
           insert_moved_node(
             socket_after_remove,
             target_page,
             refreshed_target_state,
             target_parent_path,
             target_index,
             source_node,
             apply_command
           ) do
      socket_after_insert
    else
      _ -> socket
    end
  end

  defp remove_source_node_for_move(socket, page, state, source_target, apply_command) do
    case apply_command.(socket, page, state, {:remove_node, source_target}) do
      {:ok, next_socket} -> {:ok, next_socket}
      {_status, next_socket} -> {:error, next_socket}
    end
  end

  defp insert_moved_node(socket, page, state, parent_path, index, node, apply_command) do
    command = {:insert_node, %{"parent_path" => parent_path, "index" => index}, node}

    case apply_command.(socket, page, state, command) do
      {:ok, next_socket} -> {:ok, next_socket}
      {_status, next_socket} -> {:error, next_socket}
    end
  end

  defp resolve_cross_page_destination(nodes, params, normalize_path) do
    case Map.get(params, "position", "after") do
      "root_end" ->
        {:ok, [], length(nodes)}

      position when position in ["before", "after", "inside"] ->
        with {:ok, target_path} <- resolve_payload_path(nodes, params, "target", normalize_path),
             target_node when not is_nil(target_node) <- Tree.get_node(nodes, target_path) do
          case position do
            "before" -> {:ok, Enum.drop(target_path, -1), List.last(target_path)}
            "after" -> {:ok, Enum.drop(target_path, -1), List.last(target_path) + 1}
            "inside" -> {:ok, target_path, length(target_node["children"] || [])}
          end
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp resolve_payload_path(nodes, params, prefix, normalize_path) do
    node_id = Map.get(params, "#{prefix}_node_id")
    path = Map.get(params, "#{prefix}_path")

    cond do
      is_binary(node_id) and node_id != "" ->
        case Tree.path_for_id(nodes, node_id) do
          nil -> parse_payload_path(path, normalize_path)
          indexes -> {:ok, indexes}
        end

      true ->
        parse_payload_path(path, normalize_path)
    end
  end

  defp parse_payload_path(path, normalize_path) when is_binary(path) do
    case normalize_path.(path) do
      [] -> :error
      indexes -> {:ok, indexes}
    end
  end

  defp parse_payload_path(_path, _normalize_path), do: :error

  defp move_source_target(params) do
    %{}
    |> maybe_put_node_id(Map.get(params, "source_node_id"))
    |> maybe_put_path(Map.get(params, "source_path"))
  end

  defp move_destination_target(params) do
    position = Map.get(params, "position", "after")

    if position == "root_end" do
      %{"position" => "root_end"}
    else
      target =
        %{}
        |> maybe_put_node_id(Map.get(params, "target_node_id"))
        |> maybe_put_path(Map.get(params, "target_path"))

      %{"position" => position, "target" => target}
    end
  end

  defp maybe_put_node_id(target, node_id) when is_binary(node_id) and node_id != "",
    do: Map.put(target, "node_id", node_id)

  defp maybe_put_node_id(target, _node_id), do: target

  defp maybe_put_path(target, path) when is_binary(path) and path != "",
    do: Map.put(target, "path", path)

  defp maybe_put_path(target, _path), do: target
end
