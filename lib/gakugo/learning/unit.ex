defmodule Gakugo.Learning.Unit do
  use Ecto.Schema
  import Ecto.Changeset

  alias Gakugo.Learning.FromTargetLang

  schema "units" do
    field(:title, :string)
    field(:from_target_lang, :string)
    field(:deleted_at, :utc_datetime)

    has_many(:pages, Gakugo.Learning.Page)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(unit, attrs) do
    unit
    |> cast(attrs, [:title, :from_target_lang])
    |> validate_required([:title, :from_target_lang])
    |> validate_inclusion(:from_target_lang, FromTargetLang.all())
  end
end
