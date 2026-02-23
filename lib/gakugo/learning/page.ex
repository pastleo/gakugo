defmodule Gakugo.Learning.Page do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pages" do
    field(:title, :string)
    field(:items, {:array, :map}, default: [])
    field(:position, :integer, default: 0)

    belongs_to(:unit, Gakugo.Learning.Unit)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(page, attrs) do
    page
    |> cast(attrs, [:title, :items, :unit_id])
    |> validate_required([:title, :unit_id])
    |> foreign_key_constraint(:unit_id)
  end
end
