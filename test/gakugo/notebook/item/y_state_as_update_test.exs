defmodule Gakugo.Notebook.Item.YStateAsUpdateTest do
  use ExUnit.Case, async: true

  alias Gakugo.Notebook.Item.YStateAsUpdate
  alias Gakugo.Notebook.Outline
  alias Yex.Doc
  alias Yex.XmlFragment

  test "hydrate_text encodes bold markdown" do
    rendered = hydrate_and_render("**bold text**")

    assert rendered == "<paragraph><strong marker=\"*\">bold text</strong></paragraph>"
  end

  test "hydrate_text encodes italic markdown" do
    rendered = hydrate_and_render("*italicized text*")

    assert rendered == "<paragraph><emphasis marker=\"*\">italicized text</emphasis></paragraph>"
  end

  test "hydrate_text encodes inline code markdown" do
    rendered = hydrate_and_render("`inline code`")

    assert rendered == "<paragraph><inlineCode>inline code</inlineCode></paragraph>"
  end

  test "hydrate_text encodes newlines as hardbreaks" do
    rendered = hydrate_and_render("line one\nline two")

    assert rendered ==
             "<paragraph>line one<hardbreak isInline=\"false\"></hardbreak>line two</paragraph>"
  end

  test "hydrate_text preserves escaped markdown hard breaks" do
    rendered = hydrate_and_render("qwer\\\nasdf")

    assert rendered ==
             "<paragraph>qwer<hardbreak isInline=\"false\"></hardbreak>asdf</paragraph>"
  end

  test "hydrate_text encodes highlight markdown" do
    rendered = hydrate_and_render("==highlight==")

    assert rendered == "<paragraph><highlight>highlight</highlight></paragraph>"
  end

  test "hydrate_text encodes styled highlight markdown" do
    rendered =
      hydrate_and_render(~s(==<!-- {"textColor":"yellow","backgroundColor":"red"} -->highlight==))

    assert rendered =~ ~s(<highlight)
    assert rendered =~ ~s(textColor="yellow")
    assert rendered =~ ~s(backgroundColor="red")
    assert rendered =~ ~s(>highlight</highlight>)
  end

  test "hydrate_text preserves text-only highlight background reset" do
    rendered =
      hydrate_and_render(
        ~s(==<!-- {"textColor":"yellow","backgroundColor":"none"} -->highlight==)
      )

    assert rendered =~ ~s(<highlight)
    assert rendered =~ ~s(textColor="yellow")
    assert rendered =~ ~s(backgroundColor="none")
    assert rendered =~ ~s(>highlight</highlight>)
  end

  test "hydrate_text ignores invalid highlight colors" do
    rendered =
      hydrate_and_render(
        ~s(==<!-- {"textColor":"nope","backgroundColor":"also-nope"} -->highlight==)
      )

    assert rendered == "<paragraph><highlight>highlight</highlight></paragraph>"
  end

  test "new_item yStateAsUpdate renders as an empty paragraph" do
    encoded_update = Outline.new_item()["yStateAsUpdate"]

    assert render_update(encoded_update) == "<paragraph></paragraph>"
  end

  test "update_text replaces existing xml content" do
    initial = YStateAsUpdate.hydrate_text("**before**")
    updated = YStateAsUpdate.update_text(initial, "after")

    assert render_update(updated) == "<paragraph>after</paragraph>"
  end

  defp hydrate_and_render(markdown) do
    markdown
    |> YStateAsUpdate.hydrate_text()
    |> render_update()
  end

  defp render_update(encoded_update) do
    y_doc = Doc.new()
    :ok = Yex.apply_update(y_doc, Base.decode64!(encoded_update))
    y_doc |> Doc.get_xml_fragment("prosemirror") |> XmlFragment.to_string()
  end
end
