defmodule Gakugo.Learning.Notebook.UnitSession do
  @moduledoc false

  use GenServer

  alias Gakugo.Learning
  alias Gakugo.Learning.Notebook.Editor
  alias Gakugo.Learning.Notebook.Tree

  @registry Gakugo.Learning.Notebook.UnitSession.Registry
  @supervisor Gakugo.Learning.Notebook.UnitSession.Supervisor
  @lock_lease_ms 15_000
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

  def queue_unit_save(unit_id, attrs, actor_id, timeout_ms \\ @auto_save_ms)
      when is_integer(unit_id) and is_map(attrs) and is_binary(actor_id) and
             is_integer(timeout_ms) and
             timeout_ms > 0 do
    call(unit_id, {:queue_unit_save, attrs, actor_id, timeout_ms})
  end

  def queue_page_save(unit_id, page_id, attrs, actor_id, timeout_ms \\ @auto_save_ms)
      when is_integer(unit_id) and is_integer(page_id) and is_map(attrs) and is_binary(actor_id) and
             is_integer(timeout_ms) and timeout_ms > 0 do
    call(unit_id, {:queue_page_save, page_id, attrs, actor_id, timeout_ms})
  end

  def clear_page_save(unit_id, page_id) when is_integer(unit_id) and is_integer(page_id) do
    call(unit_id, {:clear_page_save, page_id})
  end

  def prune_page_saves(unit_id, existing_page_ids)
      when is_integer(unit_id) and is_list(existing_page_ids) do
    call(unit_id, {:prune_page_saves, existing_page_ids})
  end

  def flush_unit(unit_id) when is_integer(unit_id), do: call(unit_id, :flush_unit)

  def flush_page(unit_id, page_id) when is_integer(unit_id),
    do: call(unit_id, {:flush_page, page_id})

  def unsaved_changes?(unit_id) when is_integer(unit_id), do: call(unit_id, :unsaved_changes?)

  def apply_intent(unit_id, actor_id, page_id, page_ref, nodes, local_version, command)
      when is_integer(unit_id) and is_binary(actor_id) and is_integer(page_id) do
    call(unit_id, {:apply_intent, actor_id, page_id, page_ref, nodes, local_version, command})
  end

  def current_version(unit_id, page_ref) when is_integer(unit_id) do
    call(unit_id, {:current_version, page_ref})
  end

  def allocate_next_version(unit_id, page_ref, local_version) when is_integer(unit_id) do
    call(unit_id, {:allocate_next_version, page_ref, local_version})
  end

  def observe_version(unit_id, page_ref, version) when is_integer(unit_id) do
    call(unit_id, {:observe_version, page_ref, version})
  end

  def drop_page(unit_id, page_ref) when is_integer(unit_id) do
    call(unit_id, {:drop_page, page_ref})
  end

  def acquire_lock(unit_id, page_id, lock_path, actor_id) when is_integer(unit_id) do
    call(unit_id, {:acquire_lock, page_id, lock_path, actor_id})
  end

  def heartbeat_lock(unit_id, page_id, lock_path, actor_id) when is_integer(unit_id) do
    call(unit_id, {:heartbeat_lock, page_id, lock_path, actor_id})
  end

  def release_lock(unit_id, page_id, lock_path, actor_id) when is_integer(unit_id) do
    call(unit_id, {:release_lock, page_id, lock_path, actor_id})
  end

  def release_actor(unit_id, actor_id) when is_integer(unit_id) and is_binary(actor_id) do
    call(unit_id, {:release_actor, actor_id})
  end

  def release_page(unit_id, page_id) when is_integer(unit_id) do
    call(unit_id, {:release_page, page_id})
  end

  def lock_owner(unit_id, page_id, lock_path) when is_integer(unit_id) do
    call(unit_id, {:lock_owner, page_id, lock_path})
  end

  def locks_for_unit(unit_id) when is_integer(unit_id) do
    call(unit_id, :locks_for_unit)
  end

  @impl true
  def init(unit_id) do
    {:ok,
     %{
       unit_id: unit_id,
       versions: %{},
       locks: %{},
       actor_heartbeats: %{},
       actor_pids: %{},
       actor_monitors: %{},
       monitor_actors: %{},
       pending_unit_attrs: nil,
       pending_unit_actor_id: nil,
       unit_auto_save_timer: nil,
       pending_page_attrs: %{},
       pending_page_actor_ids: %{},
       page_auto_save_timers: %{}
     }, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:heartbeat, actor_id}, {pid, _tag}, state) do
    state =
      state
      |> touch_actor_presence(actor_id, pid)
      |> put_in([:actor_heartbeats, actor_id], now_ms())

    {:reply, :ok, state, @idle_timeout_ms}
  end

  @impl true
  def handle_call(
        {:apply_intent, actor_id, page_id, page_ref, nodes, local_version, command},
        _from,
        state
      ) do
    {locks, _changed?} = prune_expired_locks(state.locks)

    case command_target_lock_path(nodes, command) do
      nil ->
        apply_intent_with_editor(
          state,
          locks,
          actor_id,
          page_id,
          page_ref,
          nodes,
          local_version,
          command
        )

      lock_path ->
        case lock_owner_from(locks, page_id, lock_path) do
          nil ->
            apply_intent_with_editor(
              state,
              locks,
              actor_id,
              page_id,
              page_ref,
              nodes,
              local_version,
              command
            )

          ^actor_id ->
            apply_intent_with_editor(
              state,
              locks,
              actor_id,
              page_id,
              page_ref,
              nodes,
              local_version,
              command
            )

          _other ->
            {:reply, :blocked, %{state | locks: locks}, @idle_timeout_ms}
        end
    end
  end

  @impl true
  def handle_call({:queue_unit_save, attrs, actor_id, timeout_ms}, _from, state) do
    cancel_timer(state.unit_auto_save_timer)
    timer = Process.send_after(self(), :auto_save_unit, timeout_ms)

    {:reply, :ok,
     %{
       state
       | pending_unit_attrs: attrs,
         pending_unit_actor_id: actor_id,
         unit_auto_save_timer: timer
     }, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:queue_page_save, page_id, attrs, actor_id, timeout_ms}, _from, state) do
    timers = state.page_auto_save_timers
    cancel_timer(Map.get(timers, page_id))
    timer = Process.send_after(self(), {:auto_save_page, page_id}, timeout_ms)

    {:reply, :ok,
     %{
       state
       | pending_page_attrs: Map.put(state.pending_page_attrs, page_id, attrs),
         pending_page_actor_ids: Map.put(state.pending_page_actor_ids, page_id, actor_id),
         page_auto_save_timers: Map.put(timers, page_id, timer)
     }, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:clear_page_save, page_id}, _from, state) do
    {:reply, :ok, clear_page_pending(state, page_id), @idle_timeout_ms}
  end

  @impl true
  def handle_call({:prune_page_saves, existing_page_ids}, _from, state) do
    existing_page_id_set = MapSet.new(existing_page_ids)

    pruned_timers =
      Enum.reduce(state.page_auto_save_timers, %{}, fn {page_id, timer}, acc ->
        if MapSet.member?(existing_page_id_set, page_id) do
          Map.put(acc, page_id, timer)
        else
          cancel_timer(timer)
          acc
        end
      end)

    pruned_pending_attrs =
      state.pending_page_attrs
      |> Enum.filter(fn {page_id, _attrs} -> MapSet.member?(existing_page_id_set, page_id) end)
      |> Map.new()

    pruned_pending_actor_ids =
      state.pending_page_actor_ids
      |> Enum.filter(fn {page_id, _actor_id} -> MapSet.member?(existing_page_id_set, page_id) end)
      |> Map.new()

    {:reply, :ok,
     %{
       state
       | pending_page_attrs: pruned_pending_attrs,
         pending_page_actor_ids: pruned_pending_actor_ids,
         page_auto_save_timers: pruned_timers
     }, @idle_timeout_ms}
  end

  @impl true
  def handle_call(:flush_unit, _from, state) do
    {:reply, :ok, persist_unit_save(state), @idle_timeout_ms}
  end

  @impl true
  def handle_call({:flush_page, page_id}, _from, state) do
    {:reply, :ok, persist_page_save(state, page_id), @idle_timeout_ms}
  end

  @impl true
  def handle_call(:unsaved_changes?, _from, state) do
    unsaved_changes? =
      not is_nil(state.pending_unit_attrs) or map_size(state.pending_page_attrs) > 0

    {:reply, unsaved_changes?, state, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:current_version, page_ref}, _from, state) do
    {:reply, Map.get(state.versions, page_ref, 0), state, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:allocate_next_version, page_ref, local_version}, _from, state) do
    current_version = Map.get(state.versions, page_ref, 0)
    base_version = max(current_version, normalize_version(local_version))
    next_version = base_version + 1
    versions = Map.put(state.versions, page_ref, next_version)

    {:reply, {base_version, next_version}, %{state | versions: versions}, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:observe_version, page_ref, version}, _from, state) do
    current_version = Map.get(state.versions, page_ref, 0)
    next_version = max(current_version, normalize_version(version))
    versions = Map.put(state.versions, page_ref, next_version)

    {:reply, :ok, %{state | versions: versions}, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:drop_page, page_ref}, _from, state) do
    {:reply, :ok, %{state | versions: Map.delete(state.versions, page_ref)}, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:acquire_lock, page_id, lock_path, actor_id}, _from, state) do
    {locks, _changed?} = prune_expired_locks(state.locks)
    key = {page_id, lock_path}

    case Map.get(locks, key) do
      nil ->
        lock = %{actor_id: actor_id, expires_at_ms: now_ms() + @lock_lease_ms, refs: 1}
        {:reply, :acquired, %{state | locks: Map.put(locks, key, lock)}, @idle_timeout_ms}

      %{actor_id: ^actor_id} = lock ->
        renewed = %{lock | expires_at_ms: now_ms() + @lock_lease_ms, refs: lock_refs(lock) + 1}
        {:reply, :renewed, %{state | locks: Map.put(locks, key, renewed)}, @idle_timeout_ms}

      %{actor_id: owner_actor_id} ->
        {:reply, {:locked, owner_actor_id}, %{state | locks: locks}, @idle_timeout_ms}
    end
  end

  @impl true
  def handle_call({:heartbeat_lock, page_id, lock_path, actor_id}, _from, state) do
    {locks, _changed?} = prune_expired_locks(state.locks)
    key = {page_id, lock_path}

    case Map.get(locks, key) do
      %{actor_id: ^actor_id} = lock ->
        renewed = %{lock | expires_at_ms: now_ms() + @lock_lease_ms}
        {:reply, :ok, %{state | locks: Map.put(locks, key, renewed)}, @idle_timeout_ms}

      _ ->
        {:reply, :missing, %{state | locks: locks}, @idle_timeout_ms}
    end
  end

  @impl true
  def handle_call({:release_lock, page_id, lock_path, actor_id}, _from, state) do
    {locks, _changed?} = prune_expired_locks(state.locks)
    key = {page_id, lock_path}

    case Map.get(locks, key) do
      %{actor_id: ^actor_id} = lock ->
        refs = lock_refs(lock)

        if refs <= 1 do
          {:reply, :released, %{state | locks: Map.delete(locks, key)}, @idle_timeout_ms}
        else
          next_lock = %{lock | refs: refs - 1}
          {:reply, :released, %{state | locks: Map.put(locks, key, next_lock)}, @idle_timeout_ms}
        end

      _ ->
        {:reply, :noop, %{state | locks: locks}, @idle_timeout_ms}
    end
  end

  @impl true
  def handle_call({:release_actor, actor_id}, _from, state) do
    {locks, _changed?} = prune_expired_locks(state.locks)

    filtered_locks =
      Enum.reject(locks, fn {{_page_id, _lock_path}, lock} ->
        lock.actor_id == actor_id
      end)
      |> Map.new()

    state = %{state | locks: filtered_locks}
    state = remove_actor_presence(state, actor_id)
    changed? = map_size(filtered_locks) != map_size(locks)

    {:reply, changed?, state, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:release_page, page_id}, _from, state) do
    {locks, _changed?} = prune_expired_locks(state.locks)

    filtered_locks =
      Enum.reject(locks, fn {{lock_page_id, _lock_path}, _lock} ->
        lock_page_id == page_id
      end)
      |> Map.new()

    changed? = map_size(filtered_locks) != map_size(locks)
    {:reply, changed?, %{state | locks: filtered_locks}, @idle_timeout_ms}
  end

  @impl true
  def handle_call({:lock_owner, page_id, lock_path}, _from, state) do
    {locks, _changed?} = prune_expired_locks(state.locks)
    owner = locks |> Map.get({page_id, lock_path}) |> owner_from_lock()
    {:reply, owner, %{state | locks: locks}, @idle_timeout_ms}
  end

  @impl true
  def handle_call(:locks_for_unit, _from, state) do
    {locks, _changed?} = prune_expired_locks(state.locks)

    unit_locks =
      locks
      |> Map.new(fn {{page_id, lock_path}, lock} ->
        {{page_id, lock_path}, lock.actor_id}
      end)

    {:reply, unit_locks, %{state | locks: locks}, @idle_timeout_ms}
  end

  @impl true
  def handle_info(:auto_save_unit, state) do
    {:noreply, persist_unit_save(state), @idle_timeout_ms}
  end

  @impl true
  def handle_info({:auto_save_page, page_id}, state) do
    {:noreply, persist_page_save(state, page_id), @idle_timeout_ms}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitor_actors, ref) do
      nil ->
        {:noreply, state, @idle_timeout_ms}

      actor_id ->
        state =
          state
          |> remove_monitor(ref)
          |> release_actor_locks(actor_id)
          |> remove_actor_presence(actor_id)

        {:noreply, state, @idle_timeout_ms}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    now = now_ms()
    {locks, _changed?} = prune_expired_locks(state.locks)
    {actor_heartbeats, stale_actor_ids} = prune_inactive_actors(state.actor_heartbeats, now)

    state =
      Enum.reduce(
        stale_actor_ids,
        %{state | locks: locks, actor_heartbeats: actor_heartbeats},
        fn actor_id, acc ->
          acc
          |> release_actor_locks(actor_id)
          |> remove_actor_presence(actor_id)
        end
      )

    has_pending_saves =
      not is_nil(state.pending_unit_attrs) or map_size(state.pending_page_attrs) > 0

    if map_size(state.actor_heartbeats) == 0 and map_size(state.locks) == 0 and
         not has_pending_saves do
      {:stop, :normal, state}
    else
      {:noreply, state, @idle_timeout_ms}
    end
  end

  defp persist_unit_save(%{pending_unit_attrs: nil} = state), do: state

  defp persist_unit_save(state) do
    attrs = state.pending_unit_attrs
    actor_id = fallback_actor_id(state.pending_unit_actor_id)

    state =
      state
      |> cancel_unit_timer()
      |> Map.put(:pending_unit_attrs, nil)
      |> Map.put(:pending_unit_actor_id, nil)

    case Learning.update_unit(Learning.get_unit!(state.unit_id), attrs) do
      {:ok, _unit} ->
        broadcast_unit_meta_changed(state.unit_id, actor_id, "unit")
        state

      {:error, _changeset} ->
        state
    end
  end

  defp persist_page_save(state, page_id) do
    attrs = Map.get(state.pending_page_attrs, page_id)

    if is_nil(attrs) do
      state
    else
      actor_id = state.pending_page_actor_ids |> Map.get(page_id) |> fallback_actor_id()

      state = clear_page_pending(state, page_id)

      persisted? =
        try do
          case Learning.update_page(Learning.get_page!(page_id), attrs) do
            {:ok, _page} -> true
            {:error, _changeset} -> false
          end
        rescue
          Ecto.NoResultsError -> false
        end

      if persisted? do
        broadcast_unit_meta_changed(state.unit_id, actor_id, "page")
      end

      state
    end
  end

  defp clear_page_pending(state, page_id) do
    timer = Map.get(state.page_auto_save_timers, page_id)
    cancel_timer(timer)

    %{
      state
      | pending_page_attrs: Map.delete(state.pending_page_attrs, page_id),
        pending_page_actor_ids: Map.delete(state.pending_page_actor_ids, page_id),
        page_auto_save_timers: Map.delete(state.page_auto_save_timers, page_id)
    }
  end

  defp cancel_unit_timer(state) do
    cancel_timer(state.unit_auto_save_timer)
    %{state | unit_auto_save_timer: nil}
  end

  defp broadcast_unit_meta_changed(unit_id, actor_id, scope) do
    message = %{
      unit_id: unit_id,
      actor_id: actor_id,
      op_id: Ecto.UUID.generate(),
      scope: scope
    }

    Phoenix.PubSub.broadcast(
      Gakugo.PubSub,
      notebook_topic(unit_id),
      {:unit_meta_changed, message}
    )
  end

  defp fallback_actor_id(actor_id) when is_binary(actor_id) and actor_id != "", do: actor_id
  defp fallback_actor_id(_actor_id), do: "unit-session"

  defp notebook_topic(unit_id), do: "unit:notebook:#{unit_id}"

  defp touch_actor_presence(state, actor_id, pid) do
    case Map.get(state.actor_pids, actor_id) do
      ^pid ->
        state

      nil ->
        ref = Process.monitor(pid)

        %{
          state
          | actor_pids: Map.put(state.actor_pids, actor_id, pid),
            actor_monitors: Map.put(state.actor_monitors, actor_id, ref),
            monitor_actors: Map.put(state.monitor_actors, ref, actor_id)
        }

      _other_pid ->
        ref = Map.get(state.actor_monitors, actor_id)
        _ = if is_reference(ref), do: Process.demonitor(ref, [:flush]), else: :ok
        new_ref = Process.monitor(pid)

        %{
          state
          | actor_pids: Map.put(state.actor_pids, actor_id, pid),
            actor_monitors: Map.put(state.actor_monitors, actor_id, new_ref),
            monitor_actors: state.monitor_actors |> Map.delete(ref) |> Map.put(new_ref, actor_id)
        }
    end
  end

  defp remove_actor_presence(state, actor_id) do
    ref = Map.get(state.actor_monitors, actor_id)
    _ = if is_reference(ref), do: Process.demonitor(ref, [:flush]), else: :ok

    %{
      state
      | actor_heartbeats: Map.delete(state.actor_heartbeats, actor_id),
        actor_pids: Map.delete(state.actor_pids, actor_id),
        actor_monitors: Map.delete(state.actor_monitors, actor_id),
        monitor_actors: Map.delete(state.monitor_actors, ref)
    }
  end

  defp remove_monitor(state, ref) do
    %{state | monitor_actors: Map.delete(state.monitor_actors, ref)}
  end

  defp release_actor_locks(state, actor_id) do
    locks =
      Enum.reject(state.locks, fn {{_page_id, _lock_path}, lock} ->
        lock.actor_id == actor_id
      end)
      |> Map.new()

    %{state | locks: locks}
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

  defp prune_expired_locks(locks) do
    now = now_ms()

    kept_locks =
      Enum.reject(locks, fn {_key, lock} -> lock.expires_at_ms <= now end)
      |> Map.new()

    {kept_locks, map_size(kept_locks) != map_size(locks)}
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

  defp apply_intent_with_editor(
         state,
         locks,
         actor_id,
         page_id,
         page_ref,
         nodes,
         local_version,
         command
       ) do
    case Editor.apply(nodes, command) do
      {:ok, result} ->
        current_version = Map.get(state.versions, page_ref, 0)
        base_version = max(current_version, normalize_version(local_version))
        next_version = base_version + 1

        operation = %{
          unit_id: state.unit_id,
          page_id: page_id,
          actor_id: actor_id,
          op_id: Ecto.UUID.generate(),
          base_version: base_version,
          version: next_version,
          command: command,
          nodes: result.nodes,
          meta: %{local: true}
        }

        next_state = %{
          state
          | versions: Map.put(state.versions, page_ref, next_version),
            locks: locks
        }

        {:reply,
         {:ok,
          %{
            operation: operation,
            nodes: result.nodes,
            focus_path: result.focus_path,
            version: next_version
          }}, next_state, @idle_timeout_ms}

      :noop ->
        {:reply, :noop, %{state | locks: locks}, @idle_timeout_ms}

      :error ->
        {:reply, :error, %{state | locks: locks}, @idle_timeout_ms}
    end
  end

  defp command_target_lock_path(_nodes, :append_root), do: nil

  defp command_target_lock_path(nodes, {_kind, target}), do: target_lock_path(nodes, target)

  defp command_target_lock_path(nodes, {_kind, target, _value}),
    do: target_lock_path(nodes, target)

  defp command_target_lock_path(_nodes, _command), do: nil

  defp target_lock_path(nodes, %{"node_id" => node_id})
       when is_binary(node_id) and node_id != "" do
    case Tree.path_for_id(nodes, node_id) do
      nil -> nil
      path -> path_to_string(path)
    end
  end

  defp target_lock_path(nodes, %{node_id: node_id}) when is_binary(node_id) and node_id != "" do
    case Tree.path_for_id(nodes, node_id) do
      nil -> nil
      path -> path_to_string(path)
    end
  end

  defp target_lock_path(_nodes, path) when is_binary(path), do: normalize_lock_path(path)

  defp target_lock_path(_nodes, path) when is_list(path) do
    if Enum.all?(path, &(is_integer(&1) and &1 >= 0)), do: path_to_string(path), else: nil
  end

  defp target_lock_path(_nodes, _target), do: nil

  defp normalize_lock_path(path) when is_binary(path) do
    trimmed = String.trim(path)

    cond do
      trimmed == "" -> nil
      Regex.match?(~r/^\d+(\.\d+)*$/, trimmed) -> trimmed
      Regex.match?(~r/^[a-zA-Z0-9_.:-]+$/, trimmed) -> trimmed
      true -> nil
    end
  end

  defp lock_owner_from(locks, page_id, lock_path),
    do: locks |> Map.get({page_id, lock_path}) |> owner_from_lock()

  defp path_to_string(path), do: Enum.join(path, ".")

  defp normalize_version(version) when is_integer(version) and version >= 0, do: version
  defp normalize_version(_version), do: 0

  defp owner_from_lock(nil), do: nil
  defp owner_from_lock(lock), do: lock.actor_id

  defp lock_refs(%{refs: refs}) when is_integer(refs) and refs > 0, do: refs
  defp lock_refs(_lock), do: 1

  defp now_ms, do: System.monotonic_time(:millisecond)
end
