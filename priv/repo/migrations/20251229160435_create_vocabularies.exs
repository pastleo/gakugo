defmodule Gakugo.Repo.Migrations.CreateVocabularies do
  use Ecto.Migration

  def change do
    create table(:vocabularies) do
      add :target, :string
      add :from, :string
      add :note, :text
      add :unit_id, references(:units, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:vocabularies, [:unit_id])
  end
end
