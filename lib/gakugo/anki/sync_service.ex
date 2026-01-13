defmodule Gakugo.Anki.SyncService do
  @moduledoc """
  Service for syncing Gakugo flashcards to Anki and the sync server.
  """

  alias Gakugo.Learning
  alias Gakugo.Anki

  @gakugo_model %{
    name: "Gakugo",
    fields: ["Front", "Back", "GakugoId"],
    templates: [
      %{
        name: "Card 1",
        qfmt: """
        <div class="gakugo-card">
          <div class="front">{{Front}}</div>
        </div>
        """,
        afmt: """
        <div class="gakugo-card">
          <div class="front">{{Front}}</div>
          <hr id="answer">
          <div class="back">{{Back}}</div>
        </div>
        """
      }
    ],
    css: """
    .gakugo-card {
      font-family: "Hiragino Sans", "Hiragino Kaku Gothic Pro", "Yu Gothic", "Meiryo", sans-serif;
      font-size: 24px;
      text-align: center;
      color: #333;
      background: #fafafa;
      padding: 20px;
    }
    .gakugo-card .front {
      font-size: 28px;
      margin-bottom: 10px;
    }
    .gakugo-card .back {
      font-size: 24px;
      color: #555;
    }
    """
  }

  def sync_unit_to_anki(unit_id) do
    unit = Learning.get_unit!(unit_id)
    flashcards = Learning.list_flashcards_for_unit(unit_id)
    flashcard_ids = MapSet.new(flashcards, & &1.id)

    with {:ok, _model_id} <- ensure_gakugo_model(),
         {:ok, _deck_id} <- Anki.ensure_deck(unit.title),
         :ok <- sync_flashcards(flashcards, unit.title),
         {:ok, deleted_count} <- delete_orphaned_notes(unit.title, flashcard_ids) do
      {:ok,
       %{synced_count: length(flashcards), deleted_count: deleted_count, deck_name: unit.title}}
    end
  end

  def sync_all_units_to_anki do
    units = Learning.list_units()

    results =
      Enum.map(units, fn unit ->
        case sync_unit_to_anki(unit.id) do
          {:ok, result} -> {:ok, unit.id, result}
          {:error, reason} -> {:error, unit.id, reason}
        end
      end)

    successes = Enum.filter(results, fn {status, _, _} -> status == :ok end)
    failures = Enum.filter(results, fn {status, _, _} -> status == :error end)

    {:ok, %{successes: length(successes), failures: length(failures), details: results}}
  end

  def sync_to_server do
    case Anki.sync() do
      {:ok, %{"status" => "full_sync"}} ->
        Anki.full_upload()

      {:ok, %{"status" => "full_upload"}} ->
        Anki.full_upload()

      other ->
        other
    end
  end

  def full_upload_to_server do
    Anki.full_upload()
  end

  def full_download_from_server do
    Anki.full_download()
  end

  defp ensure_gakugo_model do
    Anki.ensure_model(@gakugo_model)
  end

  defp sync_flashcards(flashcards, deck_name) do
    Enum.reduce_while(flashcards, :ok, fn flashcard, _acc ->
      gakugo_tag = "gakugo-fc-#{flashcard.id}"

      case find_existing_note(gakugo_tag) do
        {:ok, []} ->
          add_new_note(flashcard, deck_name, gakugo_tag)

        {:ok, [note_id | _]} ->
          update_existing_note(note_id, flashcard, deck_name, gakugo_tag)

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp find_existing_note(gakugo_tag) do
    Anki.find_notes("tag:#{gakugo_tag}")
  end

  defp add_new_note(flashcard, deck_name, gakugo_tag) do
    note = %{
      model_name: "Gakugo",
      deck_name: deck_name,
      fields: %{
        "Front" => to_html(flashcard.front),
        "Back" => to_html(flashcard.back),
        "GakugoId" => gakugo_tag
      },
      tags: ["gakugo", gakugo_tag]
    }

    case Anki.add_note(note) do
      {:ok, _note_id} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp update_existing_note(note_id, flashcard, deck_name, gakugo_tag) do
    note = %{
      id: note_id,
      fields: %{
        "Front" => to_html(flashcard.front),
        "Back" => to_html(flashcard.back)
      },
      deck_name: deck_name,
      tags: ["gakugo", gakugo_tag]
    }

    case Anki.update_note(note) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp delete_orphaned_notes(deck_name, valid_flashcard_ids) do
    with {:ok, anki_note_ids} <- Anki.find_notes("deck:\"#{deck_name}\" tag:gakugo") do
      orphaned_note_ids =
        anki_note_ids
        |> Enum.filter(fn note_id ->
          case Anki.get_note(note_id) do
            {:ok, %{"tags" => tags}} ->
              flashcard_id = extract_flashcard_id_from_tags(tags)
              flashcard_id != nil and not MapSet.member?(valid_flashcard_ids, flashcard_id)

            _ ->
              false
          end
        end)

      Enum.each(orphaned_note_ids, &Anki.delete_note/1)
      {:ok, length(orphaned_note_ids)}
    end
  end

  defp extract_flashcard_id_from_tags(tags) do
    tags
    |> Enum.find_value(fn tag ->
      case Regex.run(~r/^gakugo-fc-(\d+)$/, tag) do
        [_, id_str] -> String.to_integer(id_str)
        _ -> nil
      end
    end)
  end

  defp to_html(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\n", "<br>")
  end

  defp to_html(nil), do: ""
end
