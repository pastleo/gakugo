defmodule Gakugo.Anki.SyncServiceTest do
  use Gakugo.DataCase, async: true

  alias Gakugo.Anki
  alias Gakugo.Anki.SyncService
  alias Gakugo.Db

  import Gakugo.LearningFixtures

  describe "preview_unit/2" do
    test "builds one preview entry per flashcard source with first-line summaries" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Db.update_page(page, %{
          items: [
            %{"text" => "# flashcard without answer\nsecond line", "flashcard" => true},
            %{
              "text" => "flashcard with answer",
              "flashcard" => true,
              "children" => [
                %{"text" => "revealed **answer**", "answer" => true}
              ]
            }
          ]
        })

      _second_page =
        page_fixture(%{
          unit_id: unit.id,
          title: "Page 2",
          items: [
            %{"text" => "another flashcard", "flashcard" => true}
          ]
        })

      {:ok, preview} =
        unit.id
        |> Db.get_unit!()
        |> Anki.preview_unit(note_type: "page_note")

      assert preview.entry_count == 3

      assert Enum.map(preview.entries, & &1.summary) == [
               "flashcard without answer",
               "flashcard with answer",
               "another flashcard"
             ]

      assert Enum.any?(preview.entries, fn entry ->
               String.contains?(entry.content_html, "<h1>flashcard without answer</h1>")
             end)

      assert Enum.any?(preview.entries, fn entry ->
               String.contains?(entry.content_html, "gakugo-occlusion-answer")
             end)
    end

    test "page_note keeps whole page context while simple_note keeps only the subtree" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Db.update_page(page, %{
          items: [
            %{
              "text" => "flashcard root",
              "flashcard" => true,
              "children" => [
                %{"text" => "child one"},
                %{"text" => "child two"}
              ]
            },
            %{"text" => "outside node"}
          ]
        })

      unit = Db.get_unit!(unit.id)

      {:ok, page_preview} = Anki.preview_unit(unit, note_type: "page_note")
      {:ok, simple_preview} = Anki.preview_unit(unit, note_type: "simple_note")

      [page_entry] = page_preview.entries
      [simple_entry] = simple_preview.entries

      assert String.contains?(page_entry.content_html, "flashcard root")
      assert String.contains?(page_entry.content_html, "child one")
      assert String.contains?(page_entry.content_html, "child two")
      assert String.contains?(page_entry.content_html, "outside node")

      assert String.contains?(simple_entry.content_html, "flashcard root")
      assert String.contains?(simple_entry.content_html, "child one")
      assert String.contains?(simple_entry.content_html, "child two")
      refute String.contains?(simple_entry.content_html, "outside node")
    end

    test "page_note renders color styles, target marker, and reveal toggle" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Db.update_page(page, %{
          items: [
            %{
              "text" => "target item",
              "flashcard" => true,
              "textColor" => "blue",
              "backgroundColor" => "amber",
              "children" => [
                %{"text" => "child answer", "answer" => true, "backgroundColor" => "green"}
              ]
            },
            %{"text" => "outside node"}
          ]
        })

      unit = Db.get_unit!(unit.id)
      {:ok, preview} = Anki.preview_unit(unit, note_type: "page_note")
      [entry] = preview.entries

      assert String.contains?(entry.content_html, "Toggle revealing other answers")
      assert String.contains?(entry.content_html, "gakugo-marker is-target")
      assert String.contains?(entry.content_html, "gakugo-node")
      assert String.contains?(entry.content_html, "has-text-color")
      assert String.contains?(entry.content_html, "has-background-color")
      assert String.contains?(entry.content_html, "is-tree-focus")
      assert String.contains?(entry.content_html, "is-target")
      assert String.contains?(entry.content_html, "--gakugo-text-light: #1d4ed8;")
      assert String.contains?(entry.content_html, "--gakugo-bg-light: #fef3c7;")
      assert String.contains?(entry.content_html, "--gakugo-bg-light: #dcfce7;")

      template = Gakugo.Anki.NoteType.card_template("is-question")
      assert String.contains?(template, "scrollIntoView")
    end
  end

  describe "preview_unit_flashcards/1" do
    test "keeps compatibility wrapper output for legacy callers" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Db.update_page(page, %{
          items: [
            %{"text" => "legacy flashcard", "flashcard" => true}
          ]
        })

      [card] = unit.id |> Db.get_unit!() |> SyncService.preview_unit_flashcards()

      assert Map.keys(card) |> Enum.sort() == [:content, :id]
      assert String.contains?(card.content, "legacy flashcard")
    end
  end
end
