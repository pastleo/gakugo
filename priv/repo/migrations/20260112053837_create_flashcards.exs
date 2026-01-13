defmodule Gakugo.Repo.Migrations.CreateFlashcards do
  use Ecto.Migration

  def change do
    create table(:flashcards) do
      add :front, :text, null: false
      add :back, :text, null: false
      add :unit_id, references(:units, on_delete: :delete_all), null: false
      add :vocabulary_id, references(:vocabularies, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:flashcards, [:unit_id])
    create index(:flashcards, [:vocabulary_id])
    create unique_index(:flashcards, [:unit_id, :vocabulary_id])
  end
end
