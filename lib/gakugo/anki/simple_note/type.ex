defmodule Gakugo.Anki.SimpleNote.Type do
  @moduledoc false

  alias Gakugo.Anki.NoteType

  def id, do: "simple_note"
  def label, do: "Item subtree"
  def model_name, do: "Gakugo::SimpleNote"
  def render_module, do: Gakugo.Anki.SimpleNote.Render

  def model do
    %{
      name: model_name(),
      fields: ["Content", "GakugoId"],
      templates: [
        %{
          name: "Card 1",
          qfmt: NoteType.card_template("is-question"),
          afmt: NoteType.card_template("is-answer")
        }
      ],
      css: NoteType.shared_css()
    }
  end
end
