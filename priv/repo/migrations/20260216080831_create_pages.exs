defmodule Gakugo.Repo.Migrations.CreatePages do
  use Ecto.Migration

  def up do
    create table(:pages) do
      add(:title, :string, null: false)
      add(:items, {:array, :map}, null: false, default: [])
      add(:unit_id, references(:units, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:pages, [:unit_id]))
  end

  def down do
    drop(index(:pages, [:unit_id]))
    drop(table(:pages))
  end
end
