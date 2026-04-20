defmodule Mix.Tasks.Gakugo.MigrateNotebookItems do
  use Mix.Task

  @shortdoc "Migrates page.items to flat outline flashcard format"

  alias Gakugo.Db.Page
  alias Gakugo.Notebook.Outline
  alias Gakugo.Repo

  import Ecto.Query

  @moduledoc """
  Rewrites persisted `pages.items` into the current notebook outline shape.

  Current target item shape:

      %{
        "id" => uuid,
        "text" => "",
        "depth" => 0,
        "flashcard" => false,
        "answer" => false,
        "textColor" => nil,
        "backgroundColor" => nil
      }

  Behavior:
  - flattens legacy nested `children`
  - renames legacy `front` -> `flashcard`
  - removes legacy `link`
  - ensures valid flat depth ordering through Outline.normalize_items/1

  Usage:

      mix gakugo.migrate_notebook_items --dry-run
      mix gakugo.migrate_notebook_items
  """

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    dry_run? = Enum.member?(args, "--dry-run")

    pages = Repo.all(from page in Page, select: %{id: page.id, items: page.items})

    {changed_count, skipped_count} =
      Enum.reduce(pages, {0, 0}, fn page, {changed_acc, skipped_acc} ->
        migrated_items = Outline.normalize_items(page.items || [])

        if migrated_items == (page.items || []) do
          {changed_acc, skipped_acc + 1}
        else
          maybe_update_page(page.id, migrated_items, dry_run?)
          {changed_acc + 1, skipped_acc}
        end
      end)

    Mix.shell().info(summary_text(dry_run?, changed_count, skipped_count, length(pages)))
  end

  defp maybe_update_page(_page_id, _items, true), do: :ok

  defp maybe_update_page(page_id, items, false) do
    from(page in Page, where: page.id == ^page_id)
    |> Repo.update_all(set: [items: items])
  end

  defp summary_text(dry_run?, changed_count, skipped_count, total_count) do
    mode = if dry_run?, do: "dry-run", else: "updated"

    "Notebook item migration #{mode}: changed=#{changed_count} skipped=#{skipped_count} total=#{total_count}"
  end
end
