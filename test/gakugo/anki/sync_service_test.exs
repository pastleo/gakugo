defmodule Gakugo.Anki.SyncServiceTest do
  use Gakugo.DataCase, async: true

  alias Gakugo.Anki
  alias Gakugo.Anki.SyncService
  alias Gakugo.Db
  alias Gakugo.Notebook.Outline

  import Gakugo.LearningFixtures

  defmodule FakeAnkiClient do
    def ensure_model(_model), do: {:ok, 1}
    def ensure_deck(_deck_name), do: {:ok, 1}

    def find_notes(query) do
      update_state(fn state -> Map.update!(state, :queries, &[query | &1]) end)

      state = state()

      result =
        Enum.find_value(state.find_results, [], fn {pattern, note_ids} ->
          if String.contains?(query, pattern), do: note_ids
        end)

      {:ok, result}
    end

    def add_note(note) do
      update_state(fn state -> Map.update!(state, :added, &[note | &1]) end)
      {:ok, 10_001}
    end

    def update_note(note) do
      update_state(fn state -> Map.update!(state, :updated, &[note | &1]) end)
      :ok
    end

    def get_note(note_id), do: {:ok, Map.fetch!(state().notes, note_id)}

    def delete_note(note_id) do
      update_state(fn state -> Map.update!(state, :deleted, &[note_id | &1]) end)
      :ok
    end

    defp state, do: Process.get(:fake_anki_state)
    defp update_state(fun), do: Process.put(:fake_anki_state, fun.(state()))
  end

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
      refute String.contains?(entry.content_html, "button.remove")
      assert String.contains?(entry.content_html, "gakugo-marker is-target")
      assert String.contains?(entry.content_html, "gakugo-node")
      assert String.contains?(entry.content_html, "gakugo-occlusion-answer")
      assert String.contains?(entry.content_html, "gakugo-occlusion-mask")
      assert entry.content_html =~ ~r/gakugo-occlusion-answer.*gakugo-occlusion-mask/s
      assert String.contains?(entry.content_html, "has-text-color")
      assert String.contains?(entry.content_html, "has-background-color")
      assert String.contains?(entry.content_html, "is-tree-focus")
      assert String.contains?(entry.content_html, "is-target")
      assert String.contains?(entry.content_html, "--gakugo-text-light: #1d4ed8;")
      assert String.contains?(entry.content_html, "--gakugo-bg-light: #fef3c7;")
      assert String.contains?(entry.content_html, "--gakugo-bg-light: #dcfce7;")

      template = Gakugo.Anki.NoteType.card_template("is-question")
      assert String.contains?(template, "scrollIntoView")

      css = Gakugo.Anki.NoteType.shared_css()

      assert css =~
               ~r/\.gakugo-card\.is-question .*?\.gakugo-toggle-answers-btn \{\n  visibility: hidden;\n  pointer-events: none;/s

      assert css =~ ~r/\.gakugo-occlusion-mask \{.*position: absolute;.*inset: 0;/s
      assert css =~ ~r/\.gakugo-occlusion-answer \{.*display: block;.*visibility: hidden;/s

      assert css =~
               ~r/\.gakugo-card\.is-answer .*?\.gakugo-occlusion-answer \{\n  visibility: visible;/s
    end

    test "uses stable source item id instead of notebook path for flashcard identity" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Db.update_page(page, %{
          items: [
            %{"id" => "source-flashcard", "text" => "stable flashcard", "flashcard" => true},
            %{"id" => "sibling", "text" => "sibling"}
          ]
        })

      {:ok, preview} = unit.id |> Db.get_unit!() |> Anki.preview_unit(note_type: "page_note")
      [entry] = preview.entries

      assert entry.id == "source-flashcard"
      refute String.contains?(entry.id, "path")
      refute String.contains?(entry.id, "page")
    end

    test "reports preview collection and rendering progress" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)
      test_pid = self()

      {:ok, _updated_page} =
        Db.update_page(page, %{
          items: [
            %{"id" => "first", "text" => "first flashcard", "flashcard" => true},
            %{"id" => "second", "text" => "second flashcard", "flashcard" => true}
          ]
        })

      {:ok, preview} =
        unit.id
        |> Db.get_unit!()
        |> Anki.preview_unit(
          note_type: "page_note",
          progress_callback: fn progress -> send(test_pid, {:preview_progress, progress}) end
        )

      assert preview.entry_count == 2
      assert_receive {:preview_progress, %{stage: :collected, total: 2, processed: 0}}
      assert_receive {:preview_progress, %{stage: :rendered, total: 2, processed: 1}}
      assert_receive {:preview_progress, %{stage: :rendered, total: 2, processed: 2}}
    end

    test "keeps flashcard identity stable when the source item is reordered" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)

      items = [
        %{"id" => "source-flashcard", "text" => "stable flashcard", "flashcard" => true},
        %{"id" => "middle", "text" => "middle"},
        %{"id" => "destination", "text" => "destination"}
      ]

      {:ok, page} = Db.update_page(page, %{items: items})

      {:ok, initial_preview} =
        unit.id |> Db.get_unit!() |> Anki.preview_unit(note_type: "page_note")

      [initial_entry] = initial_preview.entries

      assert initial_entry.id == "source-flashcard"

      {:ok, moved_items, _focus_path} = Outline.move_item(page.items, [0], [2], :after)
      {:ok, _updated_page} = Db.update_page(page, %{items: moved_items})

      {:ok, moved_preview} =
        unit.id |> Db.get_unit!() |> Anki.preview_unit(note_type: "page_note")

      [moved_entry] = moved_preview.entries

      assert moved_entry.id == initial_entry.id
      assert moved_entry.id == "source-flashcard"
    end

    test "keeps flashcard identity stable when the source item moves to another page" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      source_page = hd(unit.pages)

      target_page =
        page_fixture(%{
          unit_id: unit.id,
          title: "Target Page",
          items: [%{"id" => "target-existing", "text" => "target existing"}]
        })

      source_item = %{
        "id" => "source-flashcard",
        "text" => "stable flashcard",
        "flashcard" => true
      }

      {:ok, source_page} =
        Db.update_page(source_page, %{
          items: [source_item, %{"id" => "source-existing", "text" => "source existing"}]
        })

      {:ok, initial_preview} =
        unit.id |> Db.get_unit!() |> Anki.preview_unit(note_type: "page_note")

      [initial_entry] = initial_preview.entries

      assert initial_entry.id == "source-flashcard"

      {:ok, _updated_source_page} =
        Db.update_page(source_page, %{
          items: [%{"id" => "source-existing", "text" => "source existing"}]
        })

      {:ok, _updated_target_page} =
        Db.update_page(target_page, %{
          items: [%{"id" => "target-existing", "text" => "target existing"}, source_item]
        })

      {:ok, moved_preview} =
        unit.id |> Db.get_unit!() |> Anki.preview_unit(note_type: "page_note")

      [moved_entry] = moved_preview.entries

      assert moved_entry.id == initial_entry.id
      assert moved_entry.id == "source-flashcard"
      assert String.contains?(moved_entry.content_html, "Target Page")
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

  describe "sync_unit/2" do
    test "writes only the static gakugo tag on new notes" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Db.update_page(page, %{
          items: [
            %{"id" => "source-flashcard", "text" => "stable flashcard", "flashcard" => true}
          ]
        })

      put_fake_anki_state(%{find_results: []})

      {:ok, result} =
        unit.id
        |> Db.get_unit!()
        |> Anki.sync_unit(
          note_type: "page_note",
          delete_orphans?: false,
          anki_client: FakeAnkiClient
        )

      assert result.synced_count == 1

      [added_note] = fake_anki_state().added
      assert added_note.tags == ["gakugo"]
      assert added_note.fields["GakugoId"] == "source-flashcard"

      [identity_query] = fake_anki_state().queries
      assert String.contains?(identity_query, "deck:\"")
      assert String.contains?(identity_query, "tag:gakugo")
      assert String.contains?(identity_query, "GakugoId:\"source-flashcard\"")
      refute String.contains?(identity_query, "gakugo-id-")
      refute String.contains?(identity_query, "gakugo-unit-")
      refute String.contains?(identity_query, "gakugo-note-type-")
    end

    test "updates existing notes by GakugoId field instead of dynamic identity tags" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Db.update_page(page, %{
          items: [%{"id" => "existing-card", "text" => "updated text", "flashcard" => true}]
        })

      put_fake_anki_state(%{find_results: [{"GakugoId:\"existing-card\"", [123]}]})

      {:ok, result} =
        unit.id
        |> Db.get_unit!()
        |> Anki.sync_unit(
          note_type: "page_note",
          delete_orphans?: false,
          anki_client: FakeAnkiClient
        )

      assert result.synced_count == 1
      assert fake_anki_state().added == []

      [updated_note] = fake_anki_state().updated
      assert updated_note.id == 123
      assert updated_note.tags == ["gakugo"]
      assert updated_note.fields["GakugoId"] == "existing-card"

      [identity_query] = fake_anki_state().queries
      assert String.contains?(identity_query, "GakugoId:\"existing-card\"")
      refute String.contains?(identity_query, "gakugo-id-existing-card")
    end

    test "deletes orphans by comparing deck-scoped gakugo notes against GakugoId fields" do
      unit = unit_fixture()
      unit = Db.get_unit!(unit.id)
      page = hd(unit.pages)

      {:ok, _updated_page} =
        Db.update_page(page, %{
          items: [%{"id" => "current-card", "text" => "current text", "flashcard" => true}]
        })

      put_fake_anki_state(%{
        find_results: [
          {"GakugoId:\"current-card\"", [1]},
          {"tag:gakugo", [1, 2, 3]}
        ],
        notes: %{
          1 => %{"fields" => %{"GakugoId" => "current-card"}, "tags" => ["gakugo"]},
          2 => %{"fields" => %{"GakugoId" => "removed-card"}, "tags" => ["gakugo"]},
          3 => %{"fields" => %{}, "tags" => ["gakugo"]}
        }
      })

      {:ok, result} =
        unit.id
        |> Db.get_unit!()
        |> Anki.sync_unit(
          note_type: "page_note",
          delete_orphans?: true,
          anki_client: FakeAnkiClient
        )

      assert result.deleted_count == 1
      assert fake_anki_state().deleted == [2]

      orphan_query = Enum.at(fake_anki_state().queries, 1)
      assert String.contains?(orphan_query, "deck:\"")
      assert String.contains?(orphan_query, "tag:gakugo")
      refute String.contains?(orphan_query, "GakugoId:")
      refute String.contains?(orphan_query, "gakugo-unit-")
      refute String.contains?(orphan_query, "gakugo-note-type-")
    end
  end

  defp put_fake_anki_state(attrs) do
    Process.put(
      :fake_anki_state,
      Map.merge(
        %{
          find_results: [],
          notes: %{},
          added: [],
          updated: [],
          deleted: [],
          queries: []
        },
        attrs
      )
    )
  end

  defp fake_anki_state do
    state = Process.get(:fake_anki_state)

    %{
      state
      | added: Enum.reverse(state.added),
        updated: Enum.reverse(state.updated),
        queries: Enum.reverse(state.queries)
    }
  end
end
