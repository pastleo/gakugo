defmodule Gakugo.Learning.Notebook.AutoSaveCoordinator do
  def pending_unit_attrs(state), do: Map.get(state, :pending_unit_attrs)

  def pending_page_attrs(state, page_id) do
    state
    |> Map.get(:pending_page_attrs, %{})
    |> Map.get(page_id)
  end

  def queue_unit(state, attrs, timeout_ms, pid \\ self()) do
    cancel_timer(Map.get(state, :unit_auto_save_timer))

    timer = Process.send_after(pid, :auto_save_unit, timeout_ms)

    state
    |> Map.put(:pending_unit_attrs, attrs)
    |> Map.put(:unit_auto_save_timer, timer)
  end

  def clear_unit(state) do
    cancel_timer(Map.get(state, :unit_auto_save_timer))

    state
    |> Map.put(:pending_unit_attrs, nil)
    |> Map.put(:unit_auto_save_timer, nil)
  end

  def queue_page(state, page_id, attrs, timeout_ms, pid \\ self()) do
    timers = Map.get(state, :page_auto_save_timers, %{})
    pending = Map.get(state, :pending_page_attrs, %{})

    timers
    |> Map.get(page_id)
    |> cancel_timer()

    next_timer = Process.send_after(pid, {:auto_save_page, page_id}, timeout_ms)

    state
    |> Map.put(:pending_page_attrs, Map.put(pending, page_id, attrs))
    |> Map.put(:page_auto_save_timers, Map.put(timers, page_id, next_timer))
  end

  def clear_page(state, page_id) do
    timers = Map.get(state, :page_auto_save_timers, %{})
    pending = Map.get(state, :pending_page_attrs, %{})

    timers
    |> Map.get(page_id)
    |> cancel_timer()

    state
    |> Map.put(:pending_page_attrs, Map.delete(pending, page_id))
    |> Map.put(:page_auto_save_timers, Map.delete(timers, page_id))
  end

  def unsaved_changes?(state) do
    not is_nil(Map.get(state, :pending_unit_attrs)) or
      map_size(Map.get(state, :pending_page_attrs, %{})) > 0
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    Process.cancel_timer(timer)
    :ok
  end
end
