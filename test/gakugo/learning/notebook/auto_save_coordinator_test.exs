defmodule Gakugo.Learning.Notebook.AutoSaveCoordinatorTest do
  use ExUnit.Case, async: true

  alias Gakugo.Learning.Notebook.AutoSaveCoordinator

  test "queue_unit stores attrs and schedules timer" do
    state = base_state()

    next_state = AutoSaveCoordinator.queue_unit(state, %{"title" => "Unit"}, 0, self())

    assert next_state.pending_unit_attrs == %{"title" => "Unit"}
    refute is_nil(next_state.unit_auto_save_timer)
    assert_receive :auto_save_unit
    assert AutoSaveCoordinator.unsaved_changes?(next_state)
  end

  test "clear_unit clears attrs and timer" do
    state = AutoSaveCoordinator.queue_unit(base_state(), %{"title" => "Unit"}, 10_000)

    next_state = AutoSaveCoordinator.clear_unit(state)

    assert next_state.pending_unit_attrs == nil
    assert next_state.unit_auto_save_timer == nil
  end

  test "queue_page upserts pending attrs and replaces timer" do
    state = base_state()

    first = AutoSaveCoordinator.queue_page(state, 1, %{"title" => "A"}, 10_000)
    first_timer = first.page_auto_save_timers[1]

    second = AutoSaveCoordinator.queue_page(first, 1, %{"title" => "B"}, 10_000)
    second_timer = second.page_auto_save_timers[1]

    assert second.pending_page_attrs[1] == %{"title" => "B"}
    refute first_timer == second_timer
    assert AutoSaveCoordinator.unsaved_changes?(second)
  end

  test "clear_page removes timer and pending attrs for page" do
    state =
      base_state()
      |> AutoSaveCoordinator.queue_page(1, %{"title" => "A"}, 10_000)
      |> AutoSaveCoordinator.queue_page(2, %{"title" => "B"}, 10_000)

    next_state = AutoSaveCoordinator.clear_page(state, 1)

    refute Map.has_key?(next_state.pending_page_attrs, 1)
    refute Map.has_key?(next_state.page_auto_save_timers, 1)
    assert Map.has_key?(next_state.pending_page_attrs, 2)
  end

  test "pending attrs accessors return current values" do
    state =
      base_state()
      |> AutoSaveCoordinator.queue_unit(%{"title" => "Unit"}, 10_000)
      |> AutoSaveCoordinator.queue_page(1, %{"title" => "Page"}, 10_000)

    assert AutoSaveCoordinator.pending_unit_attrs(state) == %{"title" => "Unit"}
    assert AutoSaveCoordinator.pending_page_attrs(state, 1) == %{"title" => "Page"}
    assert AutoSaveCoordinator.pending_page_attrs(state, 2) == nil
  end

  test "unsaved_changes? false when nothing pending" do
    refute AutoSaveCoordinator.unsaved_changes?(base_state())
  end

  defp base_state do
    %{
      pending_unit_attrs: nil,
      pending_page_attrs: %{},
      unit_auto_save_timer: nil,
      page_auto_save_timers: %{}
    }
  end
end
