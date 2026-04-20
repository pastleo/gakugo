defmodule Gakugo.Anki do
  @moduledoc """
  High-level Anki API for notebook-derived flashcard preview and sync.
  """

  alias Gakugo.Anki.NoteType
  alias Gakugo.Anki.PythonGenServer

  def note_type_options, do: NoteType.options()

  def default_note_type, do: NoteType.default_id()

  def preview_unit(unit, opts \\ []) when is_map(unit) do
    with {:ok, note_type} <- note_type_module(opts) do
      entries = note_type.render_module().preview_entries(unit)

      {:ok,
       %{
         note_type: note_type.id(),
         entry_count: length(entries),
         entries: entries
       }}
    end
  end

  def sync_unit(unit, opts \\ []) when is_map(unit) do
    delete_orphans? = Keyword.get(opts, :delete_orphans?, true)

    with {:ok, note_type} <- note_type_module(opts),
         {:ok, _model_id} <- ensure_model(note_type.model()),
         {:ok, _deck_id} <- ensure_deck(unit.title),
         {:ok, preview} <- preview_unit(unit, opts),
         :ok <- sync_entries(unit, note_type, preview.entries),
         {:ok, deleted_count} <- delete_orphans(unit, note_type, preview.entries, delete_orphans?) do
      {:ok,
       %{
         synced_count: length(preview.entries),
         deleted_count: deleted_count,
         deck_name: unit.title,
         note_type: note_type.id()
       }}
    end
  end

  def sync_unit_via_server(unit, opts \\ []) when is_map(unit) do
    :ok = PythonGenServer.ensure_started()

    with {:ok, download_result} <- sync_from_server(),
         {:ok, sync_result} <- sync_unit(unit, opts),
         {:ok, upload_result} <- sync_to_server() do
      {:ok,
       %{
         download: download_result,
         sync: sync_result,
         upload: upload_result
       }}
    end
  end

  def sync_to_server do
    :ok = PythonGenServer.ensure_started()

    case sync() do
      {:ok, %{"status" => status}} when status in ["full_sync", "full_upload"] ->
        full_upload()

      other ->
        other
    end
  end

  def sync_from_server do
    :ok = PythonGenServer.ensure_started()

    case sync() do
      {:ok, %{"status" => status}} when status in ["full_sync", "full_download", "full_upload"] ->
        full_download()

      other ->
        other
    end
  end

  def full_upload_to_server, do: full_upload()
  def full_download_from_server, do: full_download()

  def ensure_deck(deck_name), do: PythonGenServer.ensure_deck(deck_name)
  def list_decks, do: PythonGenServer.list_decks()
  def ensure_model(model), do: PythonGenServer.ensure_model(model)
  def list_models, do: PythonGenServer.list_models()
  def add_note(note), do: PythonGenServer.add_note(note)
  def update_note(note), do: PythonGenServer.update_note(note)
  def delete_note(note_id), do: PythonGenServer.delete_note(note_id)
  def find_notes(query), do: PythonGenServer.find_notes(query)
  def get_note(note_id), do: PythonGenServer.get_note(note_id)
  def sync, do: PythonGenServer.sync()
  def full_upload, do: PythonGenServer.full_upload()
  def full_download, do: PythonGenServer.full_download()

  defp note_type_module(opts) do
    {:ok,
     opts
     |> Keyword.get(:note_type, default_note_type())
     |> NoteType.fetch!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp sync_entries(unit, note_type, entries) do
    Enum.reduce_while(entries, :ok, fn entry, _acc ->
      gakugo_tag = identity_tag(entry.id)

      case find_notes("tag:#{gakugo_tag}") do
        {:ok, []} ->
          note = %{
            model_name: note_type.model_name(),
            deck_name: unit.title,
            fields: %{"Content" => entry.content_html, "GakugoId" => gakugo_tag},
            tags: base_tags(unit, note_type, gakugo_tag)
          }

          case add_note(note) do
            {:ok, _note_id} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:ok, [note_id | _]} ->
          note = %{
            id: note_id,
            deck_name: unit.title,
            fields: %{"Content" => entry.content_html},
            tags: base_tags(unit, note_type, gakugo_tag)
          }

          case update_note(note) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp delete_orphans(_unit, _note_type, _entries, false), do: {:ok, 0}

  defp delete_orphans(unit, note_type, entries, true) do
    valid_ids = MapSet.new(entries, & &1.id)

    query =
      "deck:\"#{unit.title}\" tag:gakugo tag:gakugo-unit-#{unit.id} tag:gakugo-note-type-#{note_type.id()}"

    with {:ok, anki_note_ids} <- find_notes(query) do
      orphaned_note_ids =
        anki_note_ids
        |> Enum.filter(fn note_id ->
          case get_note(note_id) do
            {:ok, %{"tags" => tags}} ->
              case extract_identity_tag(tags) do
                nil -> false
                flashcard_id -> not MapSet.member?(valid_ids, flashcard_id)
              end

            _ ->
              false
          end
        end)

      Enum.each(orphaned_note_ids, &delete_note/1)
      {:ok, length(orphaned_note_ids)}
    end
  end

  defp base_tags(unit, note_type, gakugo_tag) do
    ["gakugo", "gakugo-unit-#{unit.id}", "gakugo-note-type-#{note_type.id()}", gakugo_tag]
  end

  defp identity_tag(identifier), do: "gakugo-id-#{identifier}"

  defp extract_identity_tag(tags) do
    Enum.find_value(tags, fn tag ->
      if String.starts_with?(tag, "gakugo-id-") do
        String.replace_prefix(tag, "gakugo-id-", "")
      end
    end)
  end
end
