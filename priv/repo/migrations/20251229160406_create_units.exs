defmodule Gakugo.Repo.Migrations.CreateUnits do
  use Ecto.Migration

  def change do
    create table(:units) do
      add :title, :string
      add :target_lang, :string
      add :from_lang, :string

      timestamps(type: :utc_datetime)
    end
  end
end
