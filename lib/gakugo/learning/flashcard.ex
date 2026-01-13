defmodule Gakugo.Learning.Flashcard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "flashcards" do
    field :front, :string
    field :back, :string
    belongs_to :unit, Gakugo.Learning.Unit
    belongs_to :vocabulary, Gakugo.Learning.Vocabulary

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flashcard, attrs) do
    flashcard
    |> cast(attrs, [:front, :back, :unit_id, :vocabulary_id])
    |> validate_required([:front, :back, :unit_id, :vocabulary_id])
    |> foreign_key_constraint(:unit_id)
    |> foreign_key_constraint(:vocabulary_id)
    |> unique_constraint([:unit_id, :vocabulary_id])
  end
end
