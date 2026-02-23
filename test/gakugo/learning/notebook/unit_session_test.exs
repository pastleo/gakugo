defmodule Gakugo.Learning.Notebook.UnitSessionTest do
  use Gakugo.DataCase, async: true

  alias Gakugo.Learning.Notebook.UnitSession

  test "allocates monotonic versions per unit/page" do
    unit_id = System.unique_integer([:positive])
    page_ref = {123, ~U[2026-02-19 00:00:00Z]}

    assert 0 == UnitSession.current_version(unit_id, page_ref)
    assert {0, 1} == UnitSession.allocate_next_version(unit_id, page_ref, 0)
    assert {1, 2} == UnitSession.allocate_next_version(unit_id, page_ref, 0)
    assert :ok == UnitSession.observe_version(unit_id, page_ref, 9)
    assert {9, 10} == UnitSession.allocate_next_version(unit_id, page_ref, 2)
  end

  test "tracks lock ownership and release semantics" do
    unit_id = System.unique_integer([:positive])

    assert :acquired == UnitSession.acquire_lock(unit_id, 1, "0", "actor-a")
    assert {:locked, "actor-a"} == UnitSession.acquire_lock(unit_id, 1, "0", "actor-b")
    assert :ok == UnitSession.heartbeat_lock(unit_id, 1, "0", "actor-a")
    assert "actor-a" == UnitSession.lock_owner(unit_id, 1, "0")
    assert :released == UnitSession.release_lock(unit_id, 1, "0", "actor-a")
    assert nil == UnitSession.lock_owner(unit_id, 1, "0")
  end

  test "maintains lock refs for same actor" do
    unit_id = System.unique_integer([:positive])

    assert :acquired == UnitSession.acquire_lock(unit_id, 2, "meta.page_title", "actor-a")
    assert :renewed == UnitSession.acquire_lock(unit_id, 2, "meta.page_title", "actor-a")
    assert :released == UnitSession.release_lock(unit_id, 2, "meta.page_title", "actor-a")
    assert "actor-a" == UnitSession.lock_owner(unit_id, 2, "meta.page_title")
    assert :released == UnitSession.release_lock(unit_id, 2, "meta.page_title", "actor-a")
    assert nil == UnitSession.lock_owner(unit_id, 2, "meta.page_title")
  end
end
