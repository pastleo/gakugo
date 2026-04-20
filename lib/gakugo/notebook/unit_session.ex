defmodule Gakugo.Notebook.UnitSession do
  @moduledoc false

  use GenServer

  alias Gakugo.Db
  alias Gakugo.Notebook.UnitSession
  alias Gakugo.Notebook.Editor
  alias Gakugo.Notebook.Outline

  defstruct title: "Getting Started", from_target_lang: "JA-from-zh-TW"

  @changeset_types %{title: :string, from_target_lang: :string}
  @registry Gakugo.Notebook.UnitSession.Registry
  @supervisor Gakugo.Notebook.UnitSession.Supervisor
  @idle_timeout_ms 30_000
  @auto_save_ms 1200

  def start_link(unit_id) when is_integer(unit_id) do
    GenServer.start_link(__MODULE__, unit_id, name: via(unit_id))
  end

  def ensure_started(unit_id) when is_integer(unit_id) do
    case Registry.lookup(@registry, unit_id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        spec = %{
          id: {__MODULE__, unit_id},
          start: {__MODULE__, :start_link, [unit_id]},
          restart: :transient
        }

        case DynamicSupervisor.start_child(@supervisor, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def heartbeat(unit_id, actor_id) when is_integer(unit_id) and is_binary(actor_id) do
    call(unit_id, {:heartbeat, actor_id})
  end

  def flush_unit(unit_id) when is_integer(unit_id), do: call(unit_id, :flush_unit)

  def flush_page(unit_id, page_id) when is_integer(unit_id),
    do: call(unit_id, {:flush_page, page_id})

  def apply_intent(unit_id, actor_id, intent)
      when is_integer(unit_id) and is_binary(actor_id) and is_map(intent) do
    call(unit_id, {:apply_intent, actor_id, normalize_intent(intent)})
  end

  def snapshot(unit_id) when is_integer(unit_id) do
    call(unit_id, :snapshot)
  end

  def changeset(unit_session, attrs \\ %{}) do
    Ecto.Changeset.cast({unit_session, @changeset_types}, attrs, Map.keys(@changeset_types))
  end

  def change_unit_session(%UnitSession{} = unit_session, attrs) do
    changeset(unit_session, attrs)
  end

  @spec change_unit_session(
          map(),
          :invalid | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: Ecto.Changeset.t()
  def change_unit_session(%{} = unit_session, attrs) do
    %UnitSession{
      title: Map.get(unit_session, :title) || Map.get(unit_session, "title"),
      from_target_lang:
        Map.get(unit_session, :from_target_lang) || Map.get(unit_session, "from_target_lang")
    }
    |> changeset(attrs)
  end

  def change_unit_session(%UnitSession{} = unit_session),
    do: change_unit_session(unit_session, %{})

  def change_unit_session(%{} = unit_session), do: change_unit_session(unit_session, %{})

  def current_version(unit_id, page_id) when is_integer(unit_id) do
    call(unit_id, {:current_version, page_id})
  end

  def allocate_next_version(unit_id, page_id, local_version) when is_integer(unit_id) do
    call(unit_id, {:allocate_next_version, page_id, local_version})
  end

  def observe_version(unit_id, page_id, version) when is_integer(unit_id) do
    call(unit_id, {:observe_version, page_id, version})
  end

  def drop_page(unit_id, page_id) when is_integer(unit_id) do
    call(unit_id, {:drop_page, page_id})
  end

  @impl true
  @spec init(any()) ::
          {:ok,
           %{
             actor_heartbeats: %{},
             actor_monitors: %{},
             actor_pids: %{},
             monitor_actors: %{},
             page_auto_save_timers: %{},
             unit: nil | [map()] | %{optional(atom()) => any()},
             unit_auto_save_timer: nil,
             unit_id: any()
           }, 30000}
  @spec init(any()) ::
          {:ok,
           %{
             actor_heartbeats: %{},
             actor_monitors: %{},
             actor_pids: %{},
             monitor_actors: %{},
             page_auto_save_timers: %{},
             unit: nil | [map()] | %{optional(atom()) => any()},
             unit_auto_save_timer: nil,
             unit_id: any()
           }, 30000}
  def init(unit_id) do
    unit = Db.get_unit!(unit_id) |> runtime_unit_from_ecto()

    {:ok,
     %{
       unit_id: unit_id,
       unit: unit,
       actor_heartbeats: %{},
       actor_pids: %{},
       actor_monitors: %{},
       monitor_actors: %{},
       unit_auto_save_timer: nil,
       page_auto_save_timers: %{}
     }, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:heartbeat, actor_id}, {pid, _tag}, runtime_state) do
    runtime_state =
      runtime_state
      |> touch_actor_presence(actor_id, pid)
      |> put_in([:actor_heartbeats, actor_id], now_ms())

    {:reply, :ok, runtime_state, @idle_timeout_ms}
  end

  @impl true
  def handle_call(
        {:apply_intent, actor_id, intent},
        _from,
        runtime_state
      ) do
    handle_intent(runtime_state, actor_id, intent)
  end

  @impl true
  def handle_call(:snapshot, _from, runtime_state) do
    {:reply,
     %{
       unit_id: runtime_state.unit_id,
       unit: runtime_state.unit
     }, runtime_state, @idle_timeout_ms}
  end

  @impl true
  def handle_call(:flush_unit, _from, runtime_state) do
    {:reply, :ok, persist_unit_save(runtime_state), @idle_timeout_ms}
  end

  @impl true
  def handle_call({:flush_page, page_id}, _from, runtime_state) do
    {:reply, :ok, persist_page_save(runtime_state, page_id), @idle_timeout_ms}
  end

  @impl true
  def handle_call({:current_version, page_id}, _from, runtime_state) do
    {:reply, current_runtime_page_version(runtime_state.unit, page_id), runtime_state,
     @idle_timeout_ms}
  end

  @impl true
  def handle_call({:allocate_next_version, page_id, local_version}, _from, runtime_state) do
    current_version = current_runtime_page_version(runtime_state.unit, page_id)
    base_version = max(current_version, normalize_version(local_version))
    next_version = base_version + 1
    next_state = put_runtime_page_version(runtime_state, page_id, next_version)

    {:reply, {base_version, next_version}, next_state, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:observe_version, page_id, version}, _from, runtime_state) do
    current_version = current_runtime_page_version(runtime_state.unit, page_id)
    next_version = max(current_version, normalize_version(version))

    {:reply, :ok, put_runtime_page_version(runtime_state, page_id, next_version),
     @idle_timeout_ms}
  end

  @impl true
  def handle_call({:drop_page, page_id}, _from, runtime_state) do
    {:reply, :ok, %{runtime_state | unit: delete_runtime_page(runtime_state.unit, page_id)},
     @idle_timeout_ms}
  end

  @impl true
  def handle_info(:auto_save_unit, runtime_state) do
    {:noreply, persist_unit_save(runtime_state), @idle_timeout_ms}
  end

  @impl true
  def handle_info({:auto_save_page, page_id}, runtime_state) do
    {:noreply, persist_page_save(runtime_state, page_id), @idle_timeout_ms}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, runtime_state) do
    case Map.get(runtime_state.monitor_actors, ref) do
      nil ->
        {:noreply, runtime_state, @idle_timeout_ms}

      actor_id ->
        runtime_state =
          runtime_state
          |> remove_monitor(ref)
          |> remove_actor_presence(actor_id)

        {:noreply, runtime_state, @idle_timeout_ms}
    end
  end

  @impl true
  def handle_info(:timeout, runtime_state) do
    now = now_ms()

    {actor_heartbeats, stale_actor_ids} =
      prune_inactive_actors(runtime_state.actor_heartbeats, now)

    runtime_state =
      Enum.reduce(
        stale_actor_ids,
        %{runtime_state | actor_heartbeats: actor_heartbeats},
        fn actor_id, acc ->
          remove_actor_presence(acc, actor_id)
        end
      )

    has_pending_saves =
      not is_nil(runtime_state.unit_auto_save_timer) or
        map_size(runtime_state.page_auto_save_timers) > 0

    if map_size(runtime_state.actor_heartbeats) == 0 and not has_pending_saves do
      {:stop, :normal, runtime_state}
    else
      {:noreply, runtime_state, @idle_timeout_ms}
    end
  end

  defp persist_unit_save(%{unit_auto_save_timer: nil} = runtime_state), do: runtime_state

  defp persist_unit_save(runtime_state) do
    attrs = db_update_unit_attrs(runtime_state.unit)

    _ = Db.update_unit(Db.get_unit!(runtime_state.unit_id), attrs)

    cancel_unit_timer(runtime_state)
  end

  defp persist_page_save(runtime_state, page_id) do
    if Map.has_key?(runtime_state.page_auto_save_timers, page_id) do
      case find_runtime_page(runtime_state.unit, page_id) do
        nil ->
          clear_page_pending(runtime_state, page_id)

        page ->
          attrs = db_update_page_attrs(page)

          _ =
            try do
              db_page = Db.get_page!(page_id)
              Db.update_page(db_page, attrs)
            rescue
              Ecto.NoResultsError -> :error
            end

          clear_page_pending(runtime_state, page_id)
      end
    else
      runtime_state
    end
  end

  defp handle_intent(
         runtime_state,
         actor_id,
         %{"scope" => "page_content", "action" => action} = intent
       )
       when action != "move_item" do
    with {:ok, command, action} <- page_content_command(intent),
         {:ok, page_id} <- target_page_id(intent),
         page when not is_nil(page) <- find_runtime_page(runtime_state.unit, page_id) do
      editor_items =
        if action in ["text_collab_update", "set_text"],
          do: page.items,
          else: intent_nodes(intent)

      case Editor.apply(editor_items, command) do
        {:ok, result} ->
          current_version = current_runtime_page_version(runtime_state.unit, page_id)
          base_version = max(current_version, intent_local_version(intent))
          next_version = base_version + 1
          updated_page = %{page | items: result.nodes, version: next_version}
          next_unit = upsert_runtime_page(runtime_state.unit, page_id, updated_page)

          operation = %{
            unit_id: runtime_state.unit_id,
            page_id: page_id,
            actor_id: actor_id,
            op_id: Ecto.UUID.generate(),
            scope: "page_content",
            action: action,
            target: intent_target(intent),
            payload: intent_payload(intent),
            version: next_version,
            command: command,
            result: page_updated_result(updated_page),
            meta: %{local: true, scope: "page_content"}
          }

          next_state =
            %{runtime_state | unit: next_unit}
            |> schedule_page_save(page_id, actor_id, @auto_save_ms)

          broadcast_notebook_operation(runtime_state.unit_id, operation)

          {:reply, {:ok, operation.result}, next_state, @idle_timeout_ms}

        :noop ->
          {:reply, {:error, :noop}, runtime_state, @idle_timeout_ms}

        :error ->
          {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
      end
    else
      _ -> {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
    end
  end

  defp handle_intent(
         runtime_state,
         actor_id,
         %{"scope" => "page_content", "action" => "move_item"} = intent
       ) do
    with {:ok, source_page_id} <- move_item_source_page_id(intent),
         {:ok, target_page_id} <- target_page_id(intent),
         source_page when not is_nil(source_page) <-
           find_runtime_page(runtime_state.unit, source_page_id),
         target_page when not is_nil(target_page) <-
           find_runtime_page(runtime_state.unit, target_page_id),
         {:ok, source_item_id} <- move_item_source_item_id(intent),
         source_target = move_item_source_target(intent),
         destination_target = move_item_destination_target(intent),
         source_nodes = Outline.normalize_items(source_page.items),
         target_nodes = Outline.normalize_items(target_page.items) do
      source_subtree = moved_subtree(source_nodes, source_item_id)

      with [_ | _] <- source_subtree do
        source_intent_version = intent_source_version(intent) || intent_local_version(intent)
        target_intent_version = intent_local_version(intent)
        source_current_version = current_runtime_page_version(runtime_state.unit, source_page_id)
        target_current_version = current_runtime_page_version(runtime_state.unit, target_page_id)
        source_next_version = max(source_current_version, source_intent_version) + 1
        target_next_version = max(target_current_version, target_intent_version) + 1

        if source_page_id == target_page_id do
          case Editor.apply(source_nodes, {:move_item, source_target, destination_target}) do
            {:ok, result} ->
              updated_page = %{source_page | items: result.nodes, version: source_next_version}
              next_unit = upsert_runtime_page(runtime_state.unit, source_page_id, updated_page)

              operation = %{
                unit_id: runtime_state.unit_id,
                page_id: source_page_id,
                actor_id: actor_id,
                op_id: Ecto.UUID.generate(),
                scope: "page_content",
                action: "move_item",
                target: intent_target(intent),
                payload: intent_payload(intent),
                version: source_next_version,
                command: {:move_item, source_target, destination_target},
                result: page_updated_result(updated_page),
                meta: %{local: true, scope: "page_content"}
              }

              next_state =
                %{runtime_state | unit: next_unit}
                |> schedule_page_save(source_page_id, actor_id, @auto_save_ms)
                |> upsert_runtime_page(source_page_id, updated_page)

              broadcast_notebook_operation(runtime_state.unit_id, operation)
              {:reply, {:ok, operation.result}, next_state, @idle_timeout_ms}

            :noop ->
              {:reply, {:error, :noop}, runtime_state, @idle_timeout_ms}

            :error ->
              {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
          end
        else
          case Editor.apply(source_nodes, {:remove_item, source_target}) do
            {:ok, source_result} ->
              case insert_moved_subtree_into_target(target_nodes, source_subtree, intent) do
                {:ok, target_result} ->
                  next_source_nodes = source_result.nodes
                  next_target_nodes = target_result.nodes

                  source_page_after = %{
                    source_page
                    | items: next_source_nodes,
                      version: source_next_version
                  }

                  target_page_after = %{
                    target_page
                    | items: next_target_nodes,
                      version: target_next_version
                  }

                  next_unit =
                    runtime_state.unit
                    |> upsert_runtime_page(source_page_id, source_page_after)
                    |> upsert_runtime_page(target_page_id, target_page_after)

                  operation = %{
                    unit_id: runtime_state.unit_id,
                    page_id: target_page_id,
                    actor_id: actor_id,
                    op_id: Ecto.UUID.generate(),
                    scope: "page_content",
                    action: "move_item",
                    target: intent_target(intent),
                    payload: intent_payload(intent),
                    version: target_next_version,
                    command: {:move_item, source_target, destination_target},
                    result: pages_list_updated_result(next_unit),
                    meta: %{local: true, scope: "page_content"}
                  }

                  next_state =
                    %{runtime_state | unit: next_unit}
                    |> schedule_page_save(source_page_id, actor_id, @auto_save_ms)
                    |> schedule_page_save(target_page_id, actor_id, @auto_save_ms)
                    |> upsert_runtime_page(source_page_id, source_page_after)
                    |> upsert_runtime_page(target_page_id, target_page_after)

                  broadcast_notebook_operation(runtime_state.unit_id, operation)
                  {:reply, {:ok, operation.result}, next_state, @idle_timeout_ms}

                _ ->
                  {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
              end

            :noop ->
              {:reply, {:error, :noop}, runtime_state, @idle_timeout_ms}

            :error ->
              {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
          end
        end
      else
        _ -> {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
      end
    else
      _ -> {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
    end
  end

  defp handle_intent(runtime_state, actor_id, %{"scope" => "page_meta"} = intent) do
    with {:ok, page_id} <- target_page_id(intent),
         payload = intent_payload(intent),
         title when is_binary(title) <- Map.get(payload, "title"),
         page when not is_nil(page) <- find_runtime_page(runtime_state.unit, page_id) do
      current_version = current_runtime_page_version(runtime_state.unit, page_id)
      next_version = current_version + 1
      updated_page = %{page | title: title, version: next_version}
      next_unit = upsert_runtime_page(runtime_state.unit, page_id, updated_page)

      operation = %{
        unit_id: runtime_state.unit_id,
        page_id: page_id,
        actor_id: actor_id,
        op_id: Ecto.UUID.generate(),
        scope: "page_meta",
        action: "set_page_title",
        target: intent_target(intent),
        payload: payload,
        version: next_version,
        command: {:update_page_meta, %{"title" => title, "items" => page.items}},
        result: page_updated_result(updated_page),
        meta: %{local: true, scope: "page_meta"}
      }

      next_state =
        %{runtime_state | unit: next_unit}
        |> schedule_page_save(page_id, actor_id, @auto_save_ms)

      broadcast_notebook_operation(runtime_state.unit_id, operation)

      {:reply, {:ok, operation.result}, next_state, @idle_timeout_ms}
    else
      _ -> {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
    end
  end

  defp handle_intent(runtime_state, actor_id, %{"scope" => "unit_meta"} = intent) do
    payload = intent_payload(intent)
    attrs = Map.take(payload, ["title", "from_target_lang"])

    next_state =
      runtime_state
      |> schedule_unit_save(actor_id, @auto_save_ms)
      |> update_runtime_unit(attrs)

    operation = %{
      unit_id: runtime_state.unit_id,
      actor_id: actor_id,
      op_id: Ecto.UUID.generate(),
      scope: "unit_meta",
      action: "update_unit_meta",
      target: intent_target(intent),
      payload: payload,
      command: {:update_unit_meta, attrs},
      result: unit_meta_updated_result(next_state.unit),
      meta: %{local: true, scope: "unit_meta"}
    }

    broadcast_notebook_operation(runtime_state.unit_id, operation)

    {:reply, {:ok, operation.result}, next_state, @idle_timeout_ms}
  end

  defp handle_intent(
         runtime_state,
         actor_id,
         %{"scope" => "page_list", "action" => "add_page"} = intent
       ) do
    attrs = %{
      "unit_id" => runtime_state.unit_id,
      "title" => "Page #{length(runtime_state.unit.pages) + 1}",
      "items" => [Outline.new_item()]
    }

    case Db.create_page(attrs) do
      {:ok, page} ->
        runtime_page = runtime_page_from_ecto(page)

        next_state = %{
          runtime_state
          | unit: %{runtime_state.unit | pages: runtime_state.unit.pages ++ [runtime_page]}
        }

        operation =
          page_list_operation(
            runtime_state.unit_id,
            actor_id,
            intent,
            {:add_page, attrs},
            next_state.unit
          )

        broadcast_notebook_operation(runtime_state.unit_id, operation)
        {:reply, {:ok, operation.result}, next_state, @idle_timeout_ms}

      {:error, _changeset} ->
        {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
    end
  end

  defp handle_intent(
         runtime_state,
         actor_id,
         %{"scope" => "page_list", "action" => "delete_page"} = intent
       ) do
    with {:ok, page_id} <- target_page_id(intent),
         page when not is_nil(page) <- find_runtime_page(runtime_state.unit, page_id),
         {:ok, db_page} <- db_page_by_id(page_id) do
      case Db.delete_page(db_page) do
        {:ok, _page} ->
          next_state = %{runtime_state | unit: delete_runtime_page(runtime_state.unit, page_id)}

          operation =
            page_list_operation(
              runtime_state.unit_id,
              actor_id,
              intent,
              {:delete_page, page_id},
              next_state.unit
            )

          broadcast_notebook_operation(runtime_state.unit_id, operation)
          {:reply, {:ok, operation.result}, next_state, @idle_timeout_ms}

        {:error, _changeset} ->
          {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
      end
    else
      _ -> {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
    end
  end

  defp handle_intent(
         runtime_state,
         actor_id,
         %{"scope" => "page_list", "action" => "move_page"} = intent
       ) do
    with {:ok, page_id} <- target_page_id(intent),
         page when not is_nil(page) <- find_runtime_page(runtime_state.unit, page_id),
         {:ok, db_page} <- db_page_by_id(page_id),
         direction when direction in ["up", "down"] <-
           Map.get(intent_payload(intent), "direction") do
      direction_atom = if direction == "up", do: :up, else: :down

      case Db.move_page(db_page, direction_atom) do
        {:ok, :moved} ->
          next_state = %{
            runtime_state
            | unit: move_runtime_page(runtime_state.unit, page_id, direction_atom)
          }

          operation =
            page_list_operation(
              runtime_state.unit_id,
              actor_id,
              intent,
              {:move_page, page_id, direction},
              next_state.unit
            )

          broadcast_notebook_operation(runtime_state.unit_id, operation)
          {:reply, {:ok, operation.result}, next_state, @idle_timeout_ms}

        {:error, _reason} ->
          {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
      end
    else
      _ -> {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}
    end
  end

  defp handle_intent(runtime_state, _actor_id, _intent),
    do: {:reply, {:error, :invalid_params}, runtime_state, @idle_timeout_ms}

  defp schedule_unit_save(runtime_state, _actor_id, timeout_ms) do
    cancel_timer(runtime_state.unit_auto_save_timer)
    timer = Process.send_after(self(), :auto_save_unit, timeout_ms)

    %{runtime_state | unit_auto_save_timer: timer}
  end

  defp schedule_page_save(runtime_state, page_id, _actor_id, timeout_ms) do
    timers = runtime_state.page_auto_save_timers
    cancel_timer(Map.get(timers, page_id))
    timer = Process.send_after(self(), {:auto_save_page, page_id}, timeout_ms)

    %{runtime_state | page_auto_save_timers: Map.put(timers, page_id, timer)}
  end

  defp broadcast_notebook_operation(unit_id, operation) do
    Phoenix.PubSub.broadcast(
      Gakugo.PubSub,
      notebook_topic(unit_id),
      {:notebook_operation, operation}
    )
  end

  defp clear_page_pending(runtime_state, page_id) do
    timer = Map.get(runtime_state.page_auto_save_timers, page_id)
    cancel_timer(timer)

    %{
      runtime_state
      | page_auto_save_timers: Map.delete(runtime_state.page_auto_save_timers, page_id)
    }
  end

  defp cancel_unit_timer(runtime_state) do
    cancel_timer(runtime_state.unit_auto_save_timer)
    %{runtime_state | unit_auto_save_timer: nil}
  end

  defp update_runtime_unit(runtime_state, attrs) do
    unit =
      runtime_state.unit
      |> maybe_put_unit_attr(:title, attrs, "title")
      |> maybe_put_unit_attr(:from_target_lang, attrs, "from_target_lang")

    %{runtime_state | unit: unit}
  end

  defp upsert_runtime_page(%{unit: unit} = runtime_state, page_id, page) do
    %{runtime_state | unit: upsert_runtime_page(unit, page_id, page)}
  end

  defp upsert_runtime_page(%{pages: pages} = unit, page_id, page) do
    if Enum.any?(pages, fn current -> current.id == page_id end) do
      %{
        unit
        | pages:
            Enum.map(pages, fn current -> if current.id == page_id, do: page, else: current end)
      }
    else
      %{unit | pages: pages ++ [page]}
    end
  end

  defp delete_runtime_page(%{pages: pages} = unit, page_id) do
    %{unit | pages: Enum.reject(pages, fn page -> page.id == page_id end)}
  end

  defp move_runtime_page(%{pages: pages} = unit, page_id, direction)
       when direction in [:up, :down] do
    current_index = Enum.find_index(pages, fn page -> page.id == page_id end)

    case {direction, current_index} do
      {_, nil} ->
        unit

      {:up, index} when index <= 0 ->
        unit

      {:down, index} when index >= length(pages) - 1 ->
        unit

      {:up, index} ->
        page = Enum.at(pages, index)
        reordered = pages |> List.delete_at(index) |> List.insert_at(index - 1, page)
        %{unit | pages: reordered}

      {:down, index} ->
        page = Enum.at(pages, index)
        reordered = pages |> List.delete_at(index) |> List.insert_at(index + 1, page)
        %{unit | pages: reordered}
    end
  end

  defp maybe_put_unit_attr(unit, field, attrs, key) do
    case Map.get(attrs, key) do
      nil -> unit
      value -> Map.put(unit, field, value)
    end
  end

  defp notebook_topic(unit_id), do: "unit:notebook:#{unit_id}"

  defp put_runtime_page_version(runtime_state, page_id, version),
    do: %{runtime_state | unit: update_runtime_page_version(runtime_state.unit, page_id, version)}

  defp current_runtime_page_version(unit, page_id) do
    case find_runtime_page(unit, page_id) do
      %{version: version} when is_integer(version) and version >= 0 -> version
      _ -> 0
    end
  end

  defp update_runtime_page_version(%{pages: pages} = unit, page_id, version) do
    %{
      unit
      | pages:
          Enum.map(pages, fn page ->
            if page.id == page_id, do: %{page | version: version}, else: page
          end)
    }
  end

  defp touch_actor_presence(runtime_state, actor_id, pid) do
    case Map.get(runtime_state.actor_pids, actor_id) do
      ^pid ->
        runtime_state

      nil ->
        ref = Process.monitor(pid)

        %{
          runtime_state
          | actor_pids: Map.put(runtime_state.actor_pids, actor_id, pid),
            actor_monitors: Map.put(runtime_state.actor_monitors, actor_id, ref),
            monitor_actors: Map.put(runtime_state.monitor_actors, ref, actor_id)
        }

      _other_pid ->
        ref = Map.get(runtime_state.actor_monitors, actor_id)
        _ = if is_reference(ref), do: Process.demonitor(ref, [:flush]), else: :ok
        new_ref = Process.monitor(pid)

        %{
          runtime_state
          | actor_pids: Map.put(runtime_state.actor_pids, actor_id, pid),
            actor_monitors: Map.put(runtime_state.actor_monitors, actor_id, new_ref),
            monitor_actors:
              runtime_state.monitor_actors |> Map.delete(ref) |> Map.put(new_ref, actor_id)
        }
    end
  end

  defp remove_actor_presence(runtime_state, actor_id) do
    ref = Map.get(runtime_state.actor_monitors, actor_id)
    _ = if is_reference(ref), do: Process.demonitor(ref, [:flush]), else: :ok

    %{
      runtime_state
      | actor_heartbeats: Map.delete(runtime_state.actor_heartbeats, actor_id),
        actor_pids: Map.delete(runtime_state.actor_pids, actor_id),
        actor_monitors: Map.delete(runtime_state.actor_monitors, actor_id),
        monitor_actors: Map.delete(runtime_state.monitor_actors, ref)
    }
  end

  defp remove_monitor(runtime_state, ref) do
    %{runtime_state | monitor_actors: Map.delete(runtime_state.monitor_actors, ref)}
  end

  defp call(unit_id, message) do
    with {:ok, _pid} <- ensure_started(unit_id) do
      GenServer.call(via(unit_id), message)
    end
  end

  defp via(unit_id), do: {:via, Registry, {@registry, unit_id}}

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    Process.cancel_timer(timer)
    :ok
  end

  defp prune_inactive_actors(actor_heartbeats, now) do
    Enum.reduce(actor_heartbeats, {%{}, []}, fn {actor_id, last_seen_at}, {kept, stale} ->
      if now - last_seen_at >= @idle_timeout_ms do
        {kept, [actor_id | stale]}
      else
        {Map.put(kept, actor_id, last_seen_at), stale}
      end
    end)
  end

  defp normalize_version(version) when is_integer(version) and version >= 0, do: version
  defp normalize_version(_version), do: 0

  defp normalize_intent(%{} = intent) do
    Map.new(intent, fn {key, value} -> {to_string(key), normalize_intent(value)} end)
  end

  defp normalize_intent(list) when is_list(list), do: Enum.map(list, &normalize_intent/1)
  defp normalize_intent(value), do: value

  defp intent_target(intent), do: Map.get(intent, "target", %{})
  defp intent_payload(intent), do: Map.get(intent, "payload", %{})

  defp intent_local_version(intent) do
    case Map.get(intent, "version", %{}) do
      %{"local" => version} -> normalize_version(version)
      %{local: version} -> normalize_version(version)
      _ -> 0
    end
  end

  defp intent_source_version(intent) do
    case Map.get(intent, "version", %{}) do
      %{"source" => version} -> normalize_version(version)
      %{source: version} -> normalize_version(version)
      _ -> nil
    end
  end

  defp target_page_id(intent) do
    case Map.get(intent_target(intent), "page_id") || Map.get(intent_target(intent), :page_id) do
      nil ->
        {:error, :invalid_params}

      page_id when is_integer(page_id) ->
        {:ok, page_id}

      page_id when is_binary(page_id) ->
        case Integer.parse(page_id) do
          {parsed, ""} -> {:ok, parsed}
          _ -> {:error, :invalid_params}
        end

      _ ->
        {:error, :invalid_params}
    end
  end

  defp move_item_source_page_id(intent) do
    source_page_id =
      Map.get(intent_payload(intent), "source_page_id") ||
        Map.get(intent_payload(intent), :source_page_id)

    target_page_id =
      Map.get(intent_payload(intent), "target_page_id") ||
        Map.get(intent_payload(intent), :target_page_id) ||
        case target_page_id(intent) do
          {:ok, page_id} -> page_id
          _ -> nil
        end

    cond do
      is_integer(source_page_id) -> {:ok, source_page_id}
      is_binary(source_page_id) -> parse_page_id(source_page_id)
      is_integer(target_page_id) -> {:ok, target_page_id}
      is_binary(target_page_id) -> parse_page_id(target_page_id)
      true -> {:error, :invalid_params}
    end
  end

  defp move_item_source_item_id(intent) do
    case Map.get(intent_payload(intent), "source_item_id") ||
           Map.get(intent_payload(intent), :source_item_id) do
      item_id when is_binary(item_id) and item_id != "" -> {:ok, item_id}
      _ -> {:error, :invalid_params}
    end
  end

  defp move_item_source_target(intent) do
    with {:ok, source_item_id} <- move_item_source_item_id(intent) do
      %{"item_id" => source_item_id}
    end
  end

  defp move_item_destination_target(intent) do
    payload = intent_payload(intent)
    position = Map.get(payload, "position") || Map.get(payload, :position)
    target_item_id = Map.get(payload, "target_item_id") || Map.get(payload, :target_item_id)

    cond do
      position == "root_end" ->
        %{"position" => position}

      position in ["before", "after", "after_as_peer", "after_as_child"] and
        is_binary(target_item_id) and target_item_id != "" ->
        %{"position" => position, "target" => %{"item_id" => target_item_id}}

      is_binary(target_item_id) and target_item_id != "" ->
        %{"target" => %{"item_id" => target_item_id}}

      true ->
        Map.get(payload, "destination") || Map.get(payload, :destination) ||
          Map.get(payload, "target") || Map.get(payload, :target) || %{}
    end
  end

  defp insert_moved_subtree_into_target(target_nodes, moved_subtree, intent) do
    payload = intent_payload(intent)
    position = Map.get(payload, "position") || Map.get(payload, :position)
    target_item_id = Map.get(payload, "target_item_id") || Map.get(payload, :target_item_id)
    normalized_target = Outline.normalize_items(target_nodes)

    case {position, target_item_id} do
      {pos, _} when pos in ["root_end", nil] ->
        next_items = normalized_target ++ shift_subtree_depth(moved_subtree, 0)

        case Outline.validate_items(next_items) do
          {:ok, validated} ->
            focus_path = [length(validated) - length(moved_subtree)]
            {:ok, %{nodes: validated, focus_path: focus_path}}

          :error ->
            :error
        end

      {pos, item_id}
      when pos in ["before", "after", "after_as_peer", "after_as_child"] and
             is_binary(item_id) and item_id != "" ->
        case Outline.path_for_id(normalized_target, item_id) do
          [index] ->
            destination_node = Enum.at(normalized_target, index)
            depth = if is_map(destination_node), do: destination_node["depth"] || 0, else: 0

            {target_depth, insert_at} =
              case pos do
                "before" ->
                  {depth, index}

                "after_as_child" ->
                  {depth + 1, index + 1}

                pos when pos in ["after", "after_as_peer"] ->
                  {depth, subtree_end_index(normalized_target, index) + 1}
              end

            inserted = shift_subtree_depth(moved_subtree, target_depth)

            next_items =
              List.insert_at(normalized_target, insert_at, inserted)
              |> List.flatten()

            case Outline.validate_items(next_items) do
              {:ok, validated} -> {:ok, %{nodes: validated, focus_path: [insert_at]}}
              :error -> :error
            end

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp moved_subtree(nodes, item_id) when is_binary(item_id) and item_id != "" do
    normalized = Outline.normalize_items(nodes)

    case Outline.path_for_id(normalized, item_id) do
      [idx] ->
        source = Enum.at(normalized, idx)
        descendants = Outline.descendants(normalized, [idx])
        [source | descendants]

      _ ->
        []
    end
  end

  defp moved_subtree(_nodes, _item_id), do: []

  defp shift_subtree_depth([], _target_depth), do: []

  defp shift_subtree_depth([root | rest], target_depth) do
    source_depth = root["depth"] || 0
    delta = target_depth - source_depth

    Enum.map([root | rest], fn node ->
      Map.update!(node, "depth", fn depth -> max(depth + delta, 0) end)
    end)
  end

  defp subtree_end_index(items, index) do
    case Enum.at(items, index) do
      nil ->
        index

      item ->
        depth = item["depth"] || 0

        items
        |> Enum.drop(index + 1)
        |> Enum.take_while(fn next_item -> (next_item["depth"] || 0) > depth end)
        |> length()
        |> Kernel.+(index)
    end
  end

  defp find_runtime_page(%{pages: pages}, page_id) do
    Enum.find(pages, fn page -> page.id == page_id end)
  end

  defp db_page_by_id(page_id) when is_integer(page_id) do
    {:ok, Db.get_page!(page_id)}
  rescue
    Ecto.NoResultsError -> :error
  end

  defp parse_page_id(page_id) when is_integer(page_id), do: {:ok, page_id}

  defp parse_page_id(page_id) when is_binary(page_id) do
    case Integer.parse(page_id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_params}
    end
  end

  defp parse_page_id(_page_id), do: {:error, :invalid_params}

  defp intent_nodes(intent),
    do: Map.get(intent, "nodes", Map.get(intent_payload(intent), "nodes", []))

  defp page_content_command(%{"action" => "set_text"} = intent) do
    {:ok,
     {:set_text, editor_target_from_intent(intent), Map.get(intent_payload(intent), "text", "")},
     "set_text"}
  end

  defp page_content_command(%{"action" => "set_item_text_color"} = intent) do
    with {:ok, color} <- notebook_color_payload_value(intent_payload(intent)) do
      {:ok, {:set_item_text_color, editor_target_from_intent(intent), color},
       "set_item_text_color"}
    end
  end

  defp page_content_command(%{"action" => "set_item_background_color"} = intent) do
    with {:ok, color} <- notebook_color_payload_value(intent_payload(intent)) do
      {:ok, {:set_item_background_color, editor_target_from_intent(intent), color},
       "set_item_background_color"}
    end
  end

  defp page_content_command(%{"action" => "toggle_flag"} = intent) do
    {:ok,
     {:toggle_flag, editor_target_from_intent(intent),
      Map.get(intent_payload(intent), "flag", "")}, "toggle_flag"}
  end

  defp page_content_command(%{"action" => "insert_above"} = intent) do
    {:ok,
     {:insert_above, editor_target_from_intent(intent),
      Map.get(intent_payload(intent), "text", "")}, "insert_above"}
  end

  defp page_content_command(%{"action" => "insert_below"} = intent) do
    {:ok,
     {:insert_below, editor_target_from_intent(intent),
      Map.get(intent_payload(intent), "text", "")}, "insert_below"}
  end

  defp page_content_command(%{"action" => "insert_child_below"} = intent) do
    {:ok,
     {:insert_child_below, editor_target_from_intent(intent),
      Map.get(intent_payload(intent), "text", "")}, "insert_child_below"}
  end

  defp page_content_command(%{"action" => "indent_item"} = intent) do
    {:ok,
     {:item_indent, editor_target_from_intent(intent),
      Map.get(intent_payload(intent), "text", "")}, "indent_item"}
  end

  defp page_content_command(%{"action" => "outdent_item"} = intent) do
    {:ok,
     {:item_outdent, editor_target_from_intent(intent),
      Map.get(intent_payload(intent), "text", "")}, "outdent_item"}
  end

  defp page_content_command(%{"action" => "indent_subtree"} = intent) do
    {:ok,
     {:indent_subtree, editor_target_from_intent(intent),
      Map.get(intent_payload(intent), "text", "")}, "indent_subtree"}
  end

  defp page_content_command(%{"action" => "outdent_subtree"} = intent) do
    {:ok,
     {:outdent_subtree, editor_target_from_intent(intent),
      Map.get(intent_payload(intent), "text", "")}, "outdent_subtree"}
  end

  defp page_content_command(%{"action" => "add_root_item"} = intent) do
    case Map.get(intent_payload(intent), "position") do
      "first" ->
        {:ok, {:insert_item, %{"parent_path" => [], "index" => 0}, Outline.new_item()},
         "add_root_item"}

      _ ->
        {:ok, :append_root, "add_root_item"}
    end
  end

  defp page_content_command(%{"action" => "remove_item"} = intent) do
    {:ok, {:remove_item, editor_target_from_intent(intent)}, "remove_item"}
  end

  defp page_content_command(%{"action" => "append_many"} = intent) do
    {:ok, {:append_many, Map.get(intent_payload(intent), "items", [])}, "append_many"}
  end

  defp page_content_command(%{"action" => "insert_many_after"} = intent) do
    {:ok,
     {:insert_many_after, editor_target_from_intent(intent),
      Map.get(intent_payload(intent), "items", [])}, "insert_many_after"}
  end

  defp page_content_command(%{"action" => "text_collab_update"} = intent) do
    payload = intent_payload(intent)

    case {Map.get(payload, "text"), Map.get(payload, "y_state_as_update")} do
      {text, y_state_as_update} when is_binary(text) and is_binary(y_state_as_update) ->
        {:ok,
         {:text_collab_update, editor_target_from_intent(intent),
          %{text: text, y_state_as_update: y_state_as_update}}, "text_collab_update"}

      _ ->
        :error
    end
  end

  defp page_content_command(_intent), do: :error

  defp notebook_color_payload_value(payload) do
    case Map.get(payload, "color") do
      nil ->
        {:ok, nil}

      color when is_binary(color) ->
        if Gakugo.Notebook.Colors.valid_name?(color) do
          {:ok, color}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp editor_target_from_intent(intent) do
    target = intent_target(intent)

    cond do
      Map.has_key?(target, "item_id") and Map.has_key?(target, "path") ->
        %{"item_id" => target["item_id"], "path" => target["path"]}

      Map.has_key?(target, "item_id") ->
        %{"item_id" => target["item_id"]}

      Map.has_key?(target, "path") ->
        target["path"]

      true ->
        nil
    end
  end

  defp page_list_operation(unit_id, actor_id, intent, command, unit) do
    %{
      unit_id: unit_id,
      actor_id: actor_id,
      op_id: Ecto.UUID.generate(),
      scope: Map.get(intent, "scope"),
      action: Map.get(intent, "action"),
      target: intent_target(intent),
      payload: intent_payload(intent),
      command: command,
      result: pages_list_updated_result(unit)
    }
  end

  defp page_updated_result(page) do
    %{kind: "page_updated", page: page}
  end

  defp pages_list_updated_result(unit) do
    %{kind: "pages_list_updated", pages: unit.pages}
  end

  defp unit_meta_updated_result(unit) do
    %{kind: "unit_meta_updated", unit: client_unit_payload(unit)}
  end

  defp client_unit_payload(unit) do
    %{
      id: unit.id,
      title: unit.title,
      from_target_lang: unit.from_target_lang
    }
  end

  defp runtime_unit_from_ecto(unit) do
    %{
      id: unit.id,
      title: unit.title,
      from_target_lang: unit.from_target_lang,
      pages: Enum.map(unit.pages || [], &runtime_page_from_ecto/1)
    }
  end

  defp runtime_page_from_ecto(page) do
    %{
      id: page.id,
      title: page.title,
      version: 0,
      inserted_at: page.inserted_at,
      unit_id: page.unit_id,
      position: page.position,
      items: Outline.normalize_items(page.items || [])
    }
  end

  defp db_update_unit_attrs(unit) do
    %{
      "title" => unit.title,
      "from_target_lang" => unit.from_target_lang
    }
  end

  defp db_update_page_attrs(page) do
    %{
      "title" => page.title,
      "items" => Enum.map(page.items, &Outline.db_update_item_attrs/1)
    }
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
