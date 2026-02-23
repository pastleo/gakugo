defmodule Gakugo.Anki.SyncService do
  @moduledoc """
  Service for syncing Gakugo notebook flashcards to Anki and the sync server.
  """

  import Phoenix.Component, only: [sigil_H: 2]

  alias Gakugo.Anki
  alias Gakugo.Learning

  @gakugo_css """
  .gakugo-card {
    font-family: "Hiragino Sans", "Hiragino Kaku Gothic Pro", "Yu Gothic", "Meiryo", sans-serif;
    font-size: 20px;
    padding: 16px;
    text-align: left;
  }
  .gakugo-notebook {
    margin: 0;
    padding-left: 1.25rem;
  }
  .gakugo-notebook ul {
    margin-top: 0.25rem;
    padding-left: 1.25rem;
  }
  .gakugo-notebook li {
    margin: 0.1rem 0;
  }
  .gakugo-front {
    background: rgba(250, 204, 21, 0.35);
    border-radius: 0.25rem;
    font-weight: 700;
    padding: 0.02rem 0.25rem;
  }
  .gakugo-front-tree {
    background: rgba(251, 191, 36, 0.14);
    border-radius: 0.25rem;
    padding: 0.02rem 0.25rem;
  }
  .gakugo-occlusion {
    display: inline-flex;
    align-items: center;
  }
  .gakugo-occlusion.is-current {
    position: relative;
  }
  .gakugo-occlusion-mask {
    display: inline-block;
    height: 0.9em;
    min-width: 3ch;
    border-radius: 0.25rem;
    vertical-align: baseline;
    background: #e5e7eb;
    background-size: 400% 100%;
  }
  .gakugo-occlusion.is-current .gakugo-occlusion-mask {
    background: linear-gradient(90deg, #f59e0b 20%, #fcd34d 42%, #f59e0b 66%);
    animation: gakugo-skeleton 1.2s ease-in-out infinite;
  }
  .gakugo-card.is-question .gakugo-occlusion-answer {
    display: none;
  }
  .gakugo-card.is-answer .gakugo-occlusion-answer {
    display: none;
  }
  .gakugo-card.is-answer .gakugo-occlusion.is-current .gakugo-occlusion-mask {
    display: none;
  }
  .gakugo-card.is-answer .gakugo-occlusion.is-current .gakugo-occlusion-answer {
    display: inline;
  }
  .gakugo-card.reveal-other-answers .gakugo-occlusion.is-other .gakugo-occlusion-mask {
    display: none;
  }
  .gakugo-card.reveal-other-answers .gakugo-occlusion.is-other .gakugo-occlusion-answer {
    display: inline;
  }
  .gakugo-actions {
    margin-top: 0.9rem;
  }
  .gakugo-card.is-question .gakugo-actions {
    display: none;
  }
  .gakugo-reveal-others-btn {
    border: 1px solid #cbd5e1;
    border-radius: 9999px;
    padding: 0.3rem 0.75rem;
    font-size: 0.8rem;
    line-height: 1;
    background: #f8fafc;
    color: #334155;
    cursor: pointer;
    transition: transform 120ms ease, background-color 120ms ease, box-shadow 120ms ease;
  }
  .gakugo-reveal-others-btn:hover {
    background: #f1f5f9;
    box-shadow: 0 2px 8px rgba(15, 23, 42, 0.08);
  }
  .gakugo-reveal-others-btn:active {
    transform: translateY(1px);
  }
  .nightMode .gakugo-card {
    color: #e5e7eb;
  }
  .nightMode .gakugo-front {
    background: rgba(250, 204, 21, 0.2);
  }
  .nightMode .gakugo-front-tree {
    background: rgba(245, 158, 11, 0.18);
  }
  .nightMode .gakugo-occlusion-mask {
    background: #374151;
  }
  .nightMode .gakugo-occlusion.is-current .gakugo-occlusion-mask {
    background: linear-gradient(90deg, #d97706 20%, #f59e0b 42%, #d97706 66%);
    background-size: 400% 100%;
  }
  .nightMode .gakugo-reveal-others-btn {
    border-color: #475569;
    background: #1e293b;
    color: #e2e8f0;
  }
  .nightMode .gakugo-reveal-others-btn:hover {
    background: #334155;
  }
  @keyframes gakugo-skeleton {
    0% {
      background-position: 100% 50%;
    }
    100% {
      background-position: 0 50%;
    }
  }
  """

  def sync_unit_to_anki(unit_id) do
    unit = Learning.get_unit!(unit_id)
    flashcards = build_notebook_flashcards(unit)
    flashcard_ids = MapSet.new(flashcards, & &1.id)

    with {:ok, _model_id} <- ensure_gakugo_model(),
         {:ok, _deck_id} <- Anki.ensure_deck(unit.title),
         :ok <- sync_flashcards(flashcards, unit.title),
         {:ok, deleted_count} <- delete_orphaned_notes(unit.title, flashcard_ids) do
      {:ok,
       %{synced_count: length(flashcards), deleted_count: deleted_count, deck_name: unit.title}}
    end
  end

  def preview_unit_flashcards(unit) do
    build_notebook_flashcards(unit)
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
    Anki.ensure_model(gakugo_model())
  end

  defp sync_flashcards(flashcards, deck_name) do
    Enum.reduce_while(flashcards, :ok, fn flashcard, _acc ->
      gakugo_tag = identifier_tag(flashcard.id)

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
        "Content" => flashcard.content,
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
        "Content" => flashcard.content
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
      if String.starts_with?(tag, "gakugo-id-") do
        String.replace_prefix(tag, "gakugo-id-", "")
      else
        nil
      end
    end)
  end

  defp identifier_tag(identifier), do: "gakugo-id-#{identifier}"

  defp build_notebook_flashcards(unit) do
    unit.pages
    |> Enum.flat_map(fn page ->
      all_answer_paths =
        page.items
        |> flatten_nodes()
        |> Enum.filter(fn entry -> entry.node["answer"] end)
        |> Enum.map(& &1.path)
        |> MapSet.new()

      flatten_nodes(page.items)
      |> Enum.filter(fn entry -> entry.node["front"] end)
      |> Enum.map(fn entry ->
        current_answer_paths = current_answer_paths(entry)

        content_html =
          page.items
          |> render_html_nodes([], all_answer_paths, current_answer_paths, entry.path)
          |> render_page_content(page.title)

        %{
          id: notebook_identifier(unit.id, page.id, entry.path),
          content: content_html
        }
      end)
    end)
  end

  defp gakugo_model do
    %{
      name: "Gakugo",
      fields: ["Content", "GakugoId"],
      templates: [
        %{
          name: "Card 1",
          qfmt: gakugo_card_template("is-question"),
          afmt: gakugo_card_template("is-answer")
        }
      ],
      css: @gakugo_css
    }
  end

  defp gakugo_card_template(side_class) do
    assigns = %{side_class: side_class}

    ~H"""
    <div class={"gakugo-card " <> @side_class}>
      <div class="content">{"{{Content}}"}</div>
      <div class="gakugo-actions">
        <button
          type="button"
          class="gakugo-reveal-others-btn"
          onmousedown="this.closest('.gakugo-card')?.classList.add('reveal-other-answers')"
          onmouseup="this.closest('.gakugo-card')?.classList.remove('reveal-other-answers')"
          onmouseleave="this.closest('.gakugo-card')?.classList.remove('reveal-other-answers')"
          ontouchstart="this.closest('.gakugo-card')?.classList.add('reveal-other-answers')"
          ontouchend="this.closest('.gakugo-card')?.classList.remove('reveal-other-answers')"
          ontouchcancel="this.closest('.gakugo-card')?.classList.remove('reveal-other-answers')"
        >
          Hold to reveal other answers
        </button>
      </div>
    </div>
    """
    |> heex_to_string()
  end

  defp notebook_identifier(unit_id, page_id, path) do
    path_key = Enum.join(path, "-")
    "unit-#{unit_id}-page-#{page_id}-path-#{path_key}"
  end

  defp flatten_nodes(nodes), do: flatten_nodes(nodes || [], [])

  defp flatten_nodes(nodes, path_prefix) do
    nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn {node, idx} ->
      path = path_prefix ++ [idx]
      [%{node: node, path: path} | flatten_nodes(node["children"] || [], path)]
    end)
  end

  defp descendant_entries(node, path_prefix) do
    node["children"]
    |> Enum.with_index()
    |> Enum.flat_map(fn {child, idx} ->
      path = path_prefix ++ [idx]
      [%{node: child, path: path} | descendant_entries(child, path)]
    end)
  end

  defp current_answer_paths(entry) do
    descendants = descendant_entries(entry.node, entry.path)

    descendant_answers =
      descendants
      |> Enum.filter(fn child -> child.node["answer"] end)
      |> Enum.map(& &1.path)

    entry_answers =
      if entry.node["answer"] do
        [entry.path]
      else
        []
      end

    MapSet.new(entry_answers ++ descendant_answers)
  end

  defp render_html_nodes(nodes, path_prefix, occluded_paths, current_answer_paths, front_path) do
    nodes
    |> Enum.with_index()
    |> Enum.map(fn {node, idx} ->
      path = path_prefix ++ [idx]

      text = node["text"] || "-"

      text_html =
        if MapSet.member?(occluded_paths, path) do
          render_occluded_text(text, MapSet.member?(current_answer_paths, path))
        else
          if node["link"] in [nil, ""] do
            to_html(text)
          else
            render_link(node["link"], text)
          end
        end

      line_classes =
        []
        |> maybe_add_class(path_in_front_tree?(path, front_path), "gakugo-front-tree")
        |> maybe_add_class(path == front_path, "gakugo-front")
        |> Enum.join(" ")

      children_html =
        case node["children"] do
          [] ->
            ""

          nil ->
            ""

          children ->
            children
            |> render_html_nodes(path, occluded_paths, current_answer_paths, front_path)
            |> render_children_list()
        end

      render_list_item(line_classes, text_html, children_html)
    end)
    |> Enum.join("")
  end

  defp render_page_content(body_html, page_title) do
    assigns = %{body_html: body_html, page_title: to_html(page_title)}

    ~H"""
    <div><strong>{Phoenix.HTML.raw(@page_title)}</strong></div>
    <ul class="gakugo-notebook">{Phoenix.HTML.raw(@body_html)}</ul>
    """
    |> heex_to_string()
  end

  defp render_occluded_text(text, current_answer?) do
    width_ch = max(String.length(text), 4)

    occlusion_class =
      if(current_answer?, do: "gakugo-occlusion is-current", else: "gakugo-occlusion is-other")

    assigns = %{answer_html: to_html(text), width_ch: width_ch, occlusion_class: occlusion_class}

    ~H"""
    <span class={@occlusion_class}>
      <span class="gakugo-occlusion-mask skeleton" style={"width: #{@width_ch}ch;"} aria-hidden="true">
      </span>
      <span class="gakugo-occlusion-answer">{Phoenix.HTML.raw(@answer_html)}</span>
    </span>
    """
    |> heex_to_string()
  end

  defp render_link(link, text) do
    assigns = %{href: to_html(link), text_html: to_html(text)}

    ~H"""
    <a href={@href} target="_blank" rel="noreferrer">{Phoenix.HTML.raw(@text_html)}</a>
    """
    |> heex_to_string()
  end

  defp render_children_list(children_html) do
    assigns = %{children_html: children_html}

    ~H"""
    <ul>{Phoenix.HTML.raw(@children_html)}</ul>
    """
    |> heex_to_string()
  end

  defp render_list_item(line_class, text_html, children_html) do
    assigns = %{line_class: line_class, text_html: text_html, children_html: children_html}

    ~H"""
    <li>
      <span class={@line_class}>{Phoenix.HTML.raw(@text_html)}</span>{Phoenix.HTML.raw(@children_html)}
    </li>
    """
    |> heex_to_string()
  end

  defp heex_to_string(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp to_html(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\n", "<br>")
  end

  defp to_html(nil), do: ""

  defp path_in_front_tree?(path, front_path)
       when is_list(path) and is_list(front_path) and length(path) >= length(front_path) do
    Enum.take(path, length(front_path)) == front_path
  end

  defp path_in_front_tree?(_path, _front_path), do: false

  defp maybe_add_class(classes, true, class_name), do: [class_name | classes]
  defp maybe_add_class(classes, false, _class_name), do: classes
end
