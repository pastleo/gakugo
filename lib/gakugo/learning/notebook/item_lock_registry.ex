defmodule Gakugo.Learning.Notebook.ItemLockRegistry do
  @moduledoc false

  alias Gakugo.Learning.Notebook.UnitSession

  def acquire(unit_id, page_id, lock_path, actor_id) do
    UnitSession.acquire_lock(unit_id, page_id, lock_path, actor_id)
  end

  def heartbeat(unit_id, page_id, lock_path, actor_id) do
    UnitSession.heartbeat_lock(unit_id, page_id, lock_path, actor_id)
  end

  def release(unit_id, page_id, lock_path, actor_id) do
    UnitSession.release_lock(unit_id, page_id, lock_path, actor_id)
  end

  def release_actor(unit_id, actor_id) do
    UnitSession.release_actor(unit_id, actor_id)
  end

  def release_page(unit_id, page_id) do
    UnitSession.release_page(unit_id, page_id)
  end

  def lock_owner(unit_id, page_id, lock_path) do
    UnitSession.lock_owner(unit_id, page_id, lock_path)
  end

  def locks_for_unit(unit_id) do
    UnitSession.locks_for_unit(unit_id)
  end
end
