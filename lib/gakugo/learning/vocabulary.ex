defmodule Gakugo.Learning.Vocabulary do
  use Ecto.Schema
  import Ecto.Changeset

  schema "vocabularies" do
    field :target, :string
    field :from, :string
    field :note, :string
    belongs_to :unit, Gakugo.Learning.Unit

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(vocabulary, attrs) do
    vocabulary
    |> cast(attrs, [:target, :from, :note, :unit_id])
    |> validate_required([:target, :from, :unit_id])
  end
end
