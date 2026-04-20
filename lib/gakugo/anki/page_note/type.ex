defmodule Gakugo.Anki.PageNote.Type do
  @moduledoc false

  alias Gakugo.Anki.NoteType

  def id, do: "page_note"
  def label, do: "Full page"
  def model_name, do: "Gakugo::PageNote"
  def render_module, do: Gakugo.Anki.PageNote.Render

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
