defmodule Gakugo.Repo.Migrations.AddPositionToPages do
  use Ecto.Migration

  def up do
    alter table(:pages) do
      add(:position, :integer, null: false, default: 0)
    end

    execute("""
    WITH ordered AS (
      SELECT id, ROW_NUMBER() OVER (PARTITION BY unit_id ORDER BY inserted_at ASC, id ASC) AS pos
      FROM pages
    )
    UPDATE pages
    SET position = (
      SELECT ordered.pos
      FROM ordered
      WHERE ordered.id = pages.id
    )
    """)

    create(index(:pages, [:unit_id, :position]))
  end

  def down do
    drop(index(:pages, [:unit_id, :position]))

    alter table(:pages) do
      remove(:position)
    end
  end
end
