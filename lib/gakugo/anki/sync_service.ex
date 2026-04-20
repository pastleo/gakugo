defmodule Gakugo.Anki.SyncService do
  @moduledoc """
  Compatibility wrapper around the rebuilt Anki API.
  """

  alias Gakugo.Anki
  alias Gakugo.Db

  def sync_unit_to_anki(unit_id) do
    unit_id
    |> Db.get_unit!()
    |> Anki.sync_unit(note_type: "page_note", delete_orphans?: true)
  end

  def preview_unit_flashcards(unit) do
    with {:ok, preview} <- Anki.preview_unit(unit, note_type: "page_note") do
      Enum.map(preview.entries, fn entry -> %{id: entry.id, content: entry.content_html} end)
    end
  end

  def sync_all_units_to_anki do
    units = Db.list_units()

    results =
      Enum.map(units, fn unit ->
        case sync_unit_to_anki(unit.id) do
          {:ok, result} -> {:ok, unit.id, result}
          {:error, reason} -> {:error, unit.id, reason}
        end
      end)

    successes = Enum.count(results, fn {status, _, _} -> status == :ok end)
    failures = Enum.count(results, fn {status, _, _} -> status == :error end)

    {:ok, %{successes: successes, failures: failures, details: results}}
  end

  def sync_to_server, do: Anki.sync_to_server()
  def full_upload_to_server, do: Anki.full_upload_to_server()
  def full_download_from_server, do: Anki.full_download_from_server()
end
