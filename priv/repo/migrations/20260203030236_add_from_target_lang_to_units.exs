defmodule Gakugo.Repo.Migrations.AddFromTargetLangToUnits do
  use Ecto.Migration

  def change do
    alter table(:units) do
      add :from_target_lang, :string, null: false, default: "JA-from-zh-TW"
    end

    # Remove old columns after adding new one with default
    alter table(:units) do
      remove :target_lang, :string
      remove :from_lang, :string
    end
  end
end
