defmodule Gakugo.Anki do
  @moduledoc """
  High-level Anki API for notebook-derived flashcard preview and sync.
  """

  alias Gakugo.Anki.NoteType
  alias Gakugo.Anki.PythonGenServer
  alias Gakugo.Anki.Source

  def note_type_options, do: NoteType.options()

  def default_note_type, do: NoteType.default_id()

  def preview_unit(unit, opts \\ []) when is_map(unit) do
    with {:ok, note_type} <- note_type_module(opts) do
      entries = preview_entries(unit, note_type, progress_callback(opts))

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
    progress = progress_callback(opts)
    client = anki_client(opts)

    with {:ok, note_type} <- note_type_module(opts),
         _ <- report_progress(progress, %{stage: :ensure_model, total: nil, processed: 0}),
         {:ok, _model_id} <- client.ensure_model(note_type.model()),
         _ <- report_progress(progress, %{stage: :ensure_deck, total: nil, processed: 0}),
         {:ok, _deck_id} <- client.ensure_deck(unit.title),
         {:ok, preview} <- preview_unit(unit, opts),
         :ok <- sync_entries(client, unit, note_type, preview.entries, progress),
         {:ok, deleted_count} <- delete_orphans(client, unit, preview.entries, delete_orphans?) do
      report_progress(progress, %{
        stage: :done,
        total: length(preview.entries),
        processed: length(preview.entries),
        synced: length(preview.entries),
        deleted: deleted_count
      })

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
    progress = progress_callback(opts)

    with _ <- report_progress(progress, %{stage: :download, total: nil, processed: 0}),
         {:ok, download_result} <- sync_from_server(),
         _ <- report_progress(progress, %{stage: :render, total: nil, processed: 0}),
         {:ok, sync_result} <- sync_unit(unit, opts),
         _ <-
           report_progress(progress, %{
             stage: :upload,
             total: sync_result.synced_count,
             processed: sync_result.synced_count,
             synced: sync_result.synced_count,
             deleted: sync_result.deleted_count
           }),
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

  defp preview_entries(unit, note_type, progress) do
    sources = Source.flashcard_sources(unit)
    total = length(sources)

    report_progress(progress, %{stage: :collected, total: total, processed: 0})

    sources
    |> Enum.with_index(1)
    |> Enum.map(fn {source, rendered_count} ->
      entry = note_type.render_module().render_source(source)
      report_progress(progress, %{stage: :rendered, total: total, processed: rendered_count})
      entry
    end)
  end

  defp sync_entries(client, unit, note_type, entries, progress) do
    total = length(entries)

    entries
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {entry, synced_count}, _acc ->
      source_item_id = entry.id

      case client.find_notes(identity_query(unit, source_item_id)) do
        {:ok, []} ->
          note = %{
            model_name: note_type.model_name(),
            deck_name: unit.title,
            fields: %{"Content" => entry.content_html, "GakugoId" => source_item_id},
            tags: base_tags()
          }

          case client.add_note(note) do
            {:ok, _note_id} ->
              report_progress(progress, %{
                stage: :synced,
                total: total,
                processed: synced_count,
                synced: synced_count
              })

              {:cont, :ok}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        {:ok, [note_id | _]} ->
          note = %{
            id: note_id,
            deck_name: unit.title,
            fields: %{"Content" => entry.content_html, "GakugoId" => source_item_id},
            tags: base_tags()
          }

          case client.update_note(note) do
            :ok ->
              report_progress(progress, %{
                stage: :synced,
                total: total,
                processed: synced_count,
                synced: synced_count
              })

              {:cont, :ok}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp delete_orphans(_client, _unit, _entries, false), do: {:ok, 0}

  defp delete_orphans(client, unit, entries, true) do
    valid_ids = MapSet.new(entries, & &1.id)

    with {:ok, anki_note_ids} <- client.find_notes(unit_gakugo_query(unit)) do
      orphaned_note_ids =
        anki_note_ids
        |> Enum.filter(fn note_id ->
          case client.get_note(note_id) do
            {:ok, %{"fields" => fields}} ->
              case Map.get(fields, "GakugoId") do
                nil -> false
                flashcard_id -> not MapSet.member?(valid_ids, flashcard_id)
              end

            _ ->
              false
          end
        end)

      Enum.each(orphaned_note_ids, &client.delete_note/1)
      {:ok, length(orphaned_note_ids)}
    end
  end

  defp base_tags, do: ["gakugo"]

  defp identity_query(unit, source_item_id),
    do: "#{unit_gakugo_query(unit)} GakugoId:#{quoted_search_value(source_item_id)}"

  defp unit_gakugo_query(unit), do: "deck:#{quoted_search_value(unit.title)} tag:gakugo"

  defp quoted_search_value(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> then(&~s("#{&1}"))
  end

  defp anki_client(opts), do: Keyword.get(opts, :anki_client, __MODULE__)

  defp progress_callback(opts), do: Keyword.get(opts, :progress_callback)

  defp report_progress(nil, _progress), do: :ok
  defp report_progress(progress_callback, progress), do: progress_callback.(progress)
end
