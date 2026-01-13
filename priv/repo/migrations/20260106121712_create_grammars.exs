defmodule Gakugo.Repo.Migrations.CreateGrammars do
  use Ecto.Migration

  def change do
    create table(:grammars) do
      add :title, :string, null: false
      add :details, :text
      add :unit_id, references(:units, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:grammars, [:unit_id])
  end
end
