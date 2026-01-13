defmodule Gakugo.Learning.Unit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "units" do
    field :title, :string
    field :target_lang, :string
    field :from_lang, :string

    has_many :grammars, Gakugo.Learning.Grammar
    has_many :vocabularies, Gakugo.Learning.Vocabulary
    has_many :flashcards, Gakugo.Learning.Flashcard

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(unit, attrs) do
    unit
    |> cast(attrs, [:title, :target_lang, :from_lang])
    |> validate_required([:title, :target_lang, :from_lang])
  end
end
