defmodule Gakugo.Notebook.UnitSessionTest do
  use Gakugo.DataCase, async: false

  alias Gakugo.Db
  alias Gakugo.Notebook.UnitSession
  alias Yex.Doc
  alias Yex.XmlFragment

  import Gakugo.LearningFixtures

  setup do
    stop_all_unit_sessions()
    :ok
  end

  test "allocates monotonic versions per unit/page" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    assert 0 == UnitSession.current_version(unit.id, page.id)
    assert {0, 1} == UnitSession.allocate_next_version(unit.id, page.id, 0)
    assert {1, 2} == UnitSession.allocate_next_version(unit.id, page.id, 0)
    assert :ok == UnitSession.observe_version(unit.id, page.id, 9)
    assert {9, 10} == UnitSession.allocate_next_version(unit.id, page.id, 2)
  end

  test "moves an item within a page through canonical intent" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{"id" => "id-a", "text" => "A", "depth" => 0, "flashcard" => false, "answer" => false},
          %{"id" => "id-b", "text" => "B", "depth" => 0, "flashcard" => false, "answer" => false},
          %{"id" => "id-c", "text" => "C", "depth" => 1, "flashcard" => false, "answer" => false}
        ]
      })

    intent = %{
      "scope" => "page_content",
      "action" => "move_item",
      "target" => %{
        "page_id" => page.id,
        "item_id" => "id-b"
      },
      "version" => %{"local" => 0},
      "payload" => %{
        "source_page_id" => page.id,
        "source_item_id" => "id-c",
        "target_page_id" => page.id,
        "target_item_id" => "id-b"
      }
    }

    assert {:ok, %{kind: "page_updated", page: %{items: reply_items}}} =
             UnitSession.apply_intent(unit.id, "actor-1", intent)

    assert Enum.map(reply_items, & &1["id"]) == ["id-a", "id-b", "id-c"]
    assert Enum.at(reply_items, 2)["depth"] == 0

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))

    assert Enum.map(snapshot_page.items, & &1["id"]) == ["id-a", "id-b", "id-c"]
    assert Enum.at(snapshot_page.items, 2)["depth"] == 0

    :ok = UnitSession.flush_page(unit.id, page.id)
    assert Enum.map(Db.get_page!(page.id).items, & &1["id"]) == ["id-a", "id-b", "id-c"]
  end

  test "indent_subtree moves the selected subtree through canonical intent" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{"id" => "id-a", "text" => "A", "depth" => 0, "flashcard" => false, "answer" => false},
          %{"id" => "id-b", "text" => "B", "depth" => 0, "flashcard" => false, "answer" => false},
          %{"id" => "id-c", "text" => "C", "depth" => 1, "flashcard" => false, "answer" => false},
          %{"id" => "id-d", "text" => "D", "depth" => 1, "flashcard" => false, "answer" => false}
        ]
      })

    intent = %{
      "scope" => "page_content",
      "action" => "indent_subtree",
      "target" => %{
        "page_id" => page.id,
        "item_id" => "id-b"
      },
      "version" => %{"local" => 0},
      "nodes" => page.items,
      "payload" => %{
        "text" => "B"
      }
    }

    assert {:ok, %{kind: "page_updated", page: %{items: reply_items}}} =
             UnitSession.apply_intent(unit.id, "actor-1", intent)

    assert Enum.map(reply_items, & &1["depth"]) == [0, 1, 2, 2]

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))

    assert Enum.map(snapshot_page.items, & &1["depth"]) == [0, 1, 2, 2]
  end

  test "insert_child_below inserts a child through canonical intent" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{"id" => "id-a", "text" => "A", "depth" => 0, "flashcard" => false, "answer" => false}
        ]
      })

    intent = %{
      "scope" => "page_content",
      "action" => "insert_child_below",
      "target" => %{
        "page_id" => page.id,
        "item_id" => "id-a"
      },
      "version" => %{"local" => 0},
      "nodes" => page.items,
      "payload" => %{
        "text" => "A"
      }
    }

    assert {:ok, %{kind: "page_updated", page: %{items: reply_items}}} =
             UnitSession.apply_intent(unit.id, "actor-1", intent)

    inserted_id = reply_items |> Enum.at(1) |> Map.fetch!("id")

    assert Enum.map(reply_items, & &1["depth"]) == [0, 1]
    assert Enum.map(reply_items, & &1["id"]) == ["id-a", inserted_id]
  end

  test "moves an item across pages through canonical intent" do
    unit = unit_fixture()
    [source_page] = Db.get_unit!(unit.id).pages

    {:ok, target_page} =
      Db.create_page(%{
        "unit_id" => unit.id,
        "title" => "Page 2",
        "items" => [
          %{"id" => "id-x", "text" => "X", "depth" => 0, "flashcard" => false, "answer" => false}
        ]
      })

    {:ok, source_page} =
      Db.update_page(source_page, %{
        "title" => source_page.title,
        "items" => [
          %{"id" => "id-a", "text" => "A", "depth" => 0, "flashcard" => false, "answer" => false},
          %{"id" => "id-b", "text" => "B", "depth" => 0, "flashcard" => false, "answer" => false},
          %{"id" => "id-c", "text" => "C", "depth" => 1, "flashcard" => false, "answer" => false}
        ]
      })

    {:ok, target_page} =
      Db.update_page(target_page, %{
        "title" => target_page.title,
        "items" => [
          %{"id" => "id-x", "text" => "X", "depth" => 0, "flashcard" => false, "answer" => false}
        ]
      })

    intent = %{
      "scope" => "page_content",
      "action" => "move_item",
      "target" => %{
        "page_id" => target_page.id,
        "item_id" => "id-x"
      },
      "version" => %{"local" => 0, "source" => 0},
      "payload" => %{
        "source_page_id" => source_page.id,
        "source_item_id" => "id-c",
        "target_page_id" => target_page.id,
        "target_item_id" => "id-x"
      }
    }

    assert {:ok, %{kind: "pages_list_updated", pages: reply_pages}} =
             UnitSession.apply_intent(unit.id, "actor-2", intent)

    source_reply = Enum.find(reply_pages, &(&1.id == source_page.id))
    target_reply = Enum.find(reply_pages, &(&1.id == target_page.id))

    assert Enum.map(source_reply.items, & &1["id"]) == ["id-a", "id-b"]
    assert Enum.map(target_reply.items, & &1["id"]) == ["id-x", "id-c"]
    assert Enum.at(target_reply.items, 1)["depth"] == 0

    snapshot = UnitSession.snapshot(unit.id)
    source_snapshot = Enum.find(snapshot.unit.pages, &(&1.id == source_page.id))
    target_snapshot = Enum.find(snapshot.unit.pages, &(&1.id == target_page.id))

    assert Enum.map(source_snapshot.items, & &1["id"]) == ["id-a", "id-b"]
    assert Enum.map(target_snapshot.items, & &1["id"]) == ["id-x", "id-c"]
    assert Enum.at(target_snapshot.items, 1)["depth"] == 0

    :ok = UnitSession.flush_page(unit.id, source_page.id)
    :ok = UnitSession.flush_page(unit.id, target_page.id)

    assert Enum.map(Db.get_page!(source_page.id).items, & &1["id"]) == ["id-a", "id-b"]
    assert Enum.map(Db.get_page!(target_page.id).items, & &1["id"]) == ["id-x", "id-c"]
  end

  test "deletes a page through canonical intent without crashing" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    intent = %{
      "scope" => "page_list",
      "action" => "delete_page",
      "target" => %{"unit_id" => unit.id, "page_id" => page.id},
      "payload" => %{}
    }

    assert {:ok, %{kind: "pages_list_updated", pages: reply_pages}} =
             UnitSession.apply_intent(unit.id, "actor-2", intent)

    assert reply_pages == []
    assert [] == UnitSession.snapshot(unit.id).unit.pages
    assert_raise Ecto.NoResultsError, fn -> Db.get_page!(page.id) end
  end

  test "rejects malformed intents with invalid_params" do
    unit = unit_fixture()

    assert {:error, :invalid_params} =
             UnitSession.apply_intent(unit.id, "actor-3", %{"scope" => "page_content"})
  end

  test "keeps canonical unit and page state in the session snapshot" do
    unit = unit_fixture()
    snapshot = UnitSession.snapshot(unit.id)
    initial_page_count = length(snapshot.unit.pages)

    assert snapshot.unit.id == unit.id
    assert initial_page_count >= 1

    {:ok, _result} =
      UnitSession.apply_intent(unit.id, "actor-4", %{
        "scope" => "unit_meta",
        "action" => "update_unit_meta",
        "target" => %{"unit_id" => unit.id},
        "payload" => %{"title" => "Canonical Unit", "from_target_lang" => unit.from_target_lang}
      })

    {:ok, _result} =
      UnitSession.apply_intent(unit.id, "actor-4", %{
        "scope" => "page_list",
        "action" => "add_page",
        "target" => %{"unit_id" => unit.id},
        "payload" => %{}
      })

    snapshot = UnitSession.snapshot(unit.id)

    assert snapshot.unit.title == "Canonical Unit"
    assert length(snapshot.unit.pages) == initial_page_count + 1

    assert Enum.at(snapshot.unit.pages, initial_page_count).title ==
             "Page #{initial_page_count + 1}"
  end

  test "subsequent intents read from runtime snapshot state rather than stale database state" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, _result} =
      UnitSession.apply_intent(unit.id, "actor-5", %{
        "scope" => "page_meta",
        "action" => "update_page_meta",
        "target" => %{"page_id" => page.id},
        "payload" => %{"title" => "Runtime Page Title"}
      })

    snapshot = UnitSession.snapshot(unit.id)
    runtime_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))

    assert runtime_page.title == "Runtime Page Title"
    assert Db.get_page!(page.id).title != "Runtime Page Title"

    {:ok, %{kind: "page_updated", page: updated_page}} =
      UnitSession.apply_intent(unit.id, "actor-5", %{
        "scope" => "page_content",
        "action" => "add_root_item",
        "target" => %{"page_id" => page.id},
        "version" => %{"local" => runtime_page.version},
        "nodes" => runtime_page.items,
        "payload" => %{}
      })

    assert updated_page.title == "Runtime Page Title"
  end

  test "flush persists canonical runtime snapshot state to the database" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, _result} =
      UnitSession.apply_intent(unit.id, "actor-6", %{
        "scope" => "unit_meta",
        "action" => "update_unit_meta",
        "target" => %{"unit_id" => unit.id},
        "payload" => %{
          "title" => "Persisted Canonical Unit",
          "from_target_lang" => unit.from_target_lang
        }
      })

    {:ok, _result} =
      UnitSession.apply_intent(unit.id, "actor-6", %{
        "scope" => "page_meta",
        "action" => "update_page_meta",
        "target" => %{"page_id" => page.id},
        "payload" => %{"title" => "Persisted Canonical Page"}
      })

    :ok = UnitSession.flush_unit(unit.id)
    :ok = UnitSession.flush_page(unit.id, page.id)

    assert Db.get_unit!(unit.id).title == "Persisted Canonical Unit"
    assert Db.get_page!(page.id).title == "Persisted Canonical Page"
  end

  test "snapshot returns plain-data pages with runtime fields instead of raw Ecto structs" do
    unit = unit_fixture()
    snapshot = UnitSession.snapshot(unit.id)
    page = hd(snapshot.unit.pages)

    assert is_map(snapshot.unit)
    refute match?(%Db.Unit{}, snapshot.unit)

    assert is_map(page)
    refute match?(%Db.Page{}, page)

    assert is_integer(page.id)
    assert is_binary(page.title)
    assert is_list(page.items)
    assert is_integer(page.version)
  end

  test "set_text updates reply, snapshot, database, and keeps runtime editor state hydrated" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{
            "id" => "id-a",
            "text" => "Original",
            "depth" => 0,
            "flashcard" => false,
            "answer" => false
          }
        ]
      })

    {:ok, %{kind: "page_updated", page: reply_page}} =
      UnitSession.apply_intent(unit.id, "actor-7", %{
        "scope" => "page_content",
        "action" => "set_text",
        "target" => %{
          "page_id" => page.id,
          "item_id" => "id-a"
        },
        "version" => %{"local" => 0},
        "nodes" => page.items,
        "payload" => %{"text" => "Updated"}
      })

    assert Enum.at(reply_page.items, 0)["text"] == "Updated"
    assert is_binary(Enum.at(reply_page.items, 0)["yStateAsUpdate"])

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))
    assert Enum.at(snapshot_page.items, 0)["text"] == "Updated"
    assert is_binary(Enum.at(snapshot_page.items, 0)["yStateAsUpdate"])

    :ok = UnitSession.flush_page(unit.id, page.id)
    assert Enum.at(Db.get_page!(page.id).items, 0)["text"] == "Updated"
    refute Map.has_key?(Enum.at(Db.get_page!(page.id).items, 0), "yStateAsUpdate")
  end

  test "toggle_flag updates reply, snapshot, and database after flush" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{
            "id" => "id-a",
            "text" => "Card",
            "depth" => 0,
            "flashcard" => false,
            "answer" => false
          }
        ]
      })

    {:ok, %{kind: "page_updated", page: reply_page}} =
      UnitSession.apply_intent(unit.id, "actor-8", %{
        "scope" => "page_content",
        "action" => "toggle_flag",
        "target" => %{
          "page_id" => page.id,
          "item_id" => "id-a"
        },
        "version" => %{"local" => 0},
        "nodes" => page.items,
        "payload" => %{"flag" => "flashcard"}
      })

    assert Enum.at(reply_page.items, 0)["flashcard"] == true

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))
    assert Enum.at(snapshot_page.items, 0)["flashcard"] == true

    :ok = UnitSession.flush_page(unit.id, page.id)
    assert Enum.at(Db.get_page!(page.id).items, 0)["flashcard"] == true
  end

  test "text_collab_update requires text and y_state_as_update and keeps runtime editor state out of persisted attrs" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{
            "id" => "id-a",
            "text" => "Original",
            "depth" => 0,
            "flashcard" => false,
            "answer" => false
          }
        ]
      })

    assert {:error, :invalid_params} =
             UnitSession.apply_intent(unit.id, "actor-9", %{
               "scope" => "page_content",
               "action" => "text_collab_update",
               "target" => %{
                 "page_id" => page.id,
                 "item_id" => "id-a"
               },
               "version" => %{"local" => 0},
               "nodes" => page.items,
               "payload" => %{"y_state_as_update" => "opaque-state"}
             })

    assert {:error, :invalid_params} =
             UnitSession.apply_intent(unit.id, "actor-9", %{
               "scope" => "page_content",
               "action" => "text_collab_update",
               "target" => %{
                 "page_id" => page.id,
                 "item_id" => "id-a"
               },
               "version" => %{"local" => 0},
               "nodes" => page.items,
               "payload" => %{"text" => "Updated via collab"}
             })

    {:ok, %{kind: "page_updated", page: reply_page}} =
      UnitSession.apply_intent(unit.id, "actor-9", %{
        "scope" => "page_content",
        "action" => "text_collab_update",
        "target" => %{
          "page_id" => page.id,
          "item_id" => "id-a"
        },
        "version" => %{"local" => 0},
        "nodes" => page.items,
        "payload" => %{"y_state_as_update" => "opaque-state", "text" => "Updated via collab"}
      })

    assert Enum.at(reply_page.items, 0)["text"] == "Updated via collab"
    assert Enum.at(reply_page.items, 0)["yStateAsUpdate"] == "opaque-state"

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))
    assert Enum.at(snapshot_page.items, 0)["text"] == "Updated via collab"
    assert Enum.at(snapshot_page.items, 0)["yStateAsUpdate"] == "opaque-state"

    :ok = UnitSession.flush_page(unit.id, page.id)

    persisted_item = Enum.at(Db.get_page!(page.id).items, 0)
    assert persisted_item["text"] == "Updated via collab"
    refute Map.has_key?(persisted_item, "yStateAsUpdate")
  end

  test "set_text updates canonical text and refreshes runtime editor state" do
    unit = unit_fixture()
    {page, _runtime_item} = create_single_item_page(unit, "Original")

    {:ok, %{kind: "page_updated", page: reply_page}} =
      UnitSession.apply_intent(unit.id, "actor-set-text", %{
        "scope" => "page_content",
        "action" => "set_text",
        "target" => %{"page_id" => page.id, "item_id" => "id-a"},
        "version" => %{"local" => 0},
        "nodes" => page.items,
        "payload" => %{"text" => "Updated via set_text"}
      })

    assert_item_text_and_protocol_state(
      reply_page,
      "Updated via set_text",
      reply_page.items |> hd() |> Map.fetch!("yStateAsUpdate")
    )

    assert is_binary(hd(reply_page.items)["yStateAsUpdate"])

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))

    assert_item_text_and_protocol_state(
      snapshot_page,
      "Updated via set_text",
      snapshot_page.items |> hd() |> Map.fetch!("yStateAsUpdate")
    )

    assert is_binary(hd(snapshot_page.items)["yStateAsUpdate"])
  end

  test "hydrates runtime editor state from markdown on session init" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{
            "id" => "id-a",
            "text" => "# Hello\n\nThis is ~~hydrated~~ markdown.\nNext line.",
            "depth" => 0,
            "flashcard" => false,
            "answer" => false
          }
        ]
      })

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))
    item = hd(snapshot_page.items)

    assert is_binary(item["yStateAsUpdate"])
    assert item["yStateAsUpdate"] != ""

    y_doc = Doc.new()
    assert :ok = Yex.apply_update(y_doc, Base.decode64!(item["yStateAsUpdate"]))

    fragment = Doc.get_xml_fragment(y_doc, "prosemirror")
    rendered = XmlFragment.to_string(fragment)

    assert rendered =~ "<heading"
    assert rendered =~ "<paragraph"
    assert rendered =~ "Hello"
    assert rendered =~ "hydrated"
    assert rendered =~ "strike_through"
    assert rendered =~ "hardbreak"
    assert rendered =~ ~s(isInline="false")
  end

  test "text_collab_update requires text and y_state_as_update, and updates canonical state" do
    unit = unit_fixture()
    {page, _runtime_item} = create_single_item_page(unit, "Original")

    assert {:error, :invalid_params} =
             UnitSession.apply_intent(unit.id, "actor-collab", %{
               "scope" => "page_content",
               "action" => "text_collab_update",
               "target" => %{"page_id" => page.id, "item_id" => "id-a"},
               "version" => %{"local" => 0},
               "payload" => %{"y_state_as_update" => "opaque-state"}
             })

    assert {:error, :invalid_params} =
             UnitSession.apply_intent(unit.id, "actor-collab", %{
               "scope" => "page_content",
               "action" => "text_collab_update",
               "target" => %{"page_id" => page.id, "item_id" => "id-a"},
               "version" => %{"local" => 0},
               "payload" => %{"text" => "Updated via collab"}
             })

    {:ok, %{kind: "page_updated", page: reply_page}} =
      UnitSession.apply_intent(unit.id, "actor-collab", %{
        "scope" => "page_content",
        "action" => "text_collab_update",
        "target" => %{"page_id" => page.id, "item_id" => "id-a"},
        "version" => %{"local" => 0},
        "payload" => %{"y_state_as_update" => "opaque-state", "text" => "Updated via collab"}
      })

    assert_item_text_and_protocol_state(reply_page, "Updated via collab", "opaque-state")

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))
    assert_item_text_and_protocol_state(snapshot_page, "Updated via collab", "opaque-state")
  end

  test "set_text then text_collab_update keeps protocol state in sync" do
    unit = unit_fixture()
    {page, _runtime_item} = create_single_item_page(unit, "Original")

    {:ok, %{kind: "page_updated", page: set_text_page}} =
      UnitSession.apply_intent(unit.id, "actor-sequence-1", %{
        "scope" => "page_content",
        "action" => "set_text",
        "target" => %{"page_id" => page.id, "item_id" => "id-a"},
        "version" => %{"local" => 0},
        "nodes" => page.items,
        "payload" => %{"text" => "After set_text"}
      })

    assert_item_text_and_protocol_state(
      set_text_page,
      "After set_text",
      set_text_page.items |> hd() |> Map.fetch!("yStateAsUpdate")
    )

    assert is_binary(hd(set_text_page.items)["yStateAsUpdate"])

    {:ok, %{kind: "page_updated", page: reply_page}} =
      UnitSession.apply_intent(unit.id, "actor-sequence-1", %{
        "scope" => "page_content",
        "action" => "text_collab_update",
        "target" => %{"page_id" => page.id, "item_id" => "id-a"},
        "version" => %{"local" => set_text_page.version},
        "payload" => %{"y_state_as_update" => "opaque-state-2", "text" => "After collab"}
      })

    assert_item_text_and_protocol_state(reply_page, "After collab", "opaque-state-2")

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))
    assert_item_text_and_protocol_state(snapshot_page, "After collab", "opaque-state-2")
  end

  test "text_collab_update then set_text keeps protocol state in sync" do
    unit = unit_fixture()
    {page, _runtime_item} = create_single_item_page(unit, "Original")

    {:ok, %{kind: "page_updated", page: collab_page}} =
      UnitSession.apply_intent(unit.id, "actor-sequence-2", %{
        "scope" => "page_content",
        "action" => "text_collab_update",
        "target" => %{"page_id" => page.id, "item_id" => "id-a"},
        "version" => %{"local" => 0},
        "payload" => %{"y_state_as_update" => "opaque-state-1", "text" => "After collab"}
      })

    assert_item_text_and_protocol_state(collab_page, "After collab", "opaque-state-1")

    {:ok, %{kind: "page_updated", page: reply_page}} =
      UnitSession.apply_intent(unit.id, "actor-sequence-2", %{
        "scope" => "page_content",
        "action" => "set_text",
        "target" => %{"page_id" => page.id, "item_id" => "id-a"},
        "version" => %{"local" => collab_page.version},
        "nodes" => collab_page.items,
        "payload" => %{"text" => "After set_text"}
      })

    assert_item_text_and_protocol_state(
      reply_page,
      "After set_text",
      reply_page.items |> hd() |> Map.fetch!("yStateAsUpdate")
    )

    assert is_binary(hd(reply_page.items)["yStateAsUpdate"])

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))

    assert_item_text_and_protocol_state(
      snapshot_page,
      "After set_text",
      snapshot_page.items |> hd() |> Map.fetch!("yStateAsUpdate")
    )

    assert is_binary(hd(snapshot_page.items)["yStateAsUpdate"])
  end

  test "set_text intent returns hydrated editor state that matches new markdown" do
    unit = unit_fixture()
    {page, _runtime_item} = create_single_item_page(unit, "Original")

    {:ok, %{kind: "page_updated", page: reply_page}} =
      UnitSession.apply_intent(unit.id, "actor-set-text-hydration", %{
        "scope" => "page_content",
        "action" => "set_text",
        "target" => %{"page_id" => page.id, "item_id" => "id-a"},
        "version" => %{"local" => 0},
        "nodes" => page.items,
        "payload" => %{"text" => "qwer\\\nasdf"}
      })

    item = hd(reply_page.items)
    y_doc = Doc.new()

    assert :ok = Yex.apply_update(y_doc, Base.decode64!(item["yStateAsUpdate"]))

    rendered = y_doc |> Doc.get_xml_fragment("prosemirror") |> XmlFragment.to_string()

    assert rendered ==
             "<paragraph>qwer<hardbreak isInline=\"false\"></hardbreak>asdf</paragraph>"
  end

  test "add_root_item updates reply, snapshot, and database after flush" do
    unit = unit_fixture()
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{
            "id" => "id-a",
            "text" => "Existing",
            "depth" => 0,
            "flashcard" => false,
            "answer" => false
          }
        ]
      })

    {:ok, %{kind: "page_updated", page: reply_page}} =
      UnitSession.apply_intent(unit.id, "actor-9", %{
        "scope" => "page_content",
        "action" => "add_root_item",
        "target" => %{"page_id" => page.id},
        "version" => %{"local" => 0},
        "nodes" => page.items,
        "payload" => %{}
      })

    assert length(reply_page.items) == 2

    snapshot = UnitSession.snapshot(unit.id)
    snapshot_page = Enum.find(snapshot.unit.pages, &(&1.id == page.id))
    assert length(snapshot_page.items) == 2

    :ok = UnitSession.flush_page(unit.id, page.id)
    assert length(Db.get_page!(page.id).items) == 2
  end

  defp stop_all_unit_sessions do
    for {_, pid, _, _} <-
          DynamicSupervisor.which_children(Gakugo.Notebook.UnitSession.Supervisor) do
      ref = Process.monitor(pid)

      :ok =
        DynamicSupervisor.terminate_child(Gakugo.Notebook.UnitSession.Supervisor, pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    end
  end

  defp create_single_item_page(unit, text) do
    page = hd(Db.get_unit!(unit.id).pages)

    {:ok, page} =
      Db.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{
            "id" => "id-a",
            "text" => text,
            "depth" => 0,
            "flashcard" => false,
            "answer" => false
          }
        ]
      })

    runtime_item =
      unit.id
      |> UnitSession.snapshot()
      |> then(fn snapshot -> Enum.find(snapshot.unit.pages, &(&1.id == page.id)) end)
      |> then(fn runtime_page -> hd(runtime_page.items) end)

    {page, runtime_item}
  end

  defp assert_item_text_and_protocol_state(page, expected_text, expected_y_state_as_update) do
    item = hd(page.items)

    assert item["text"] == expected_text
    assert is_binary(expected_y_state_as_update)
    assert Map.get(item, "yStateAsUpdate") == expected_y_state_as_update
  end
end
