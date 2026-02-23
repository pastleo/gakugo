defmodule Gakugo.Repo.Migrations.AddDeletedAtToUnits do
  use Ecto.Migration

  def change do
    alter table(:units) do
      add(:deleted_at, :utc_datetime)
    end

    create(index(:units, [:deleted_at]))
  end
end
