defmodule Gakugo.Learning.Notebook.PageVersionRegistry do
  @moduledoc false

  alias Gakugo.Learning.Notebook.UnitSession

  def current_version(unit_id, page_ref) do
    UnitSession.current_version(unit_id, page_ref)
  end

  def allocate_next(unit_id, page_ref, local_version) do
    UnitSession.allocate_next_version(unit_id, page_ref, local_version)
  end

  def observe(unit_id, page_ref, version) do
    UnitSession.observe_version(unit_id, page_ref, version)
  end

  def drop_page(unit_id, page_ref) do
    UnitSession.drop_page(unit_id, page_ref)
  end
end
