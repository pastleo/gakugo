defmodule GakugoWeb.UnitLive.ShowEditTest do
  use GakugoWeb.ConnCase, async: false

  import Gakugo.LearningFixtures
  import Phoenix.LiveViewTest

  alias Gakugo.Learning

  defmodule NotebookImporterStub do
    def parse_source(source, from_target_lang), do: parse_source(source, from_target_lang, [])

    def parse_source(_source, _from_target_lang, _opts) do
      {:ok,
       [
         %{"vocabulary" => "情報（じょうほう）", "translation" => "情報、資訊", "note" => ""},
         %{"vocabulary" => "興味（きょうみ）", "translation" => "興趣", "note" => ""}
       ]}
    end

    def import_from_image(image_binary, from_target_lang),
      do: import_from_image(image_binary, from_target_lang, [])

    def import_from_image(_image_binary, _from_target_lang, _opts), do: {:ok, []}
  end

  defmodule NotebookImporterModelEchoStub do
    def parse_source(source, from_target_lang) do
      parse_source(source, from_target_lang, [])
    end

    def parse_source(_source, _from_target_lang, opts) do
      model = opts |> Keyword.get(:model, "unknown") |> to_string()

      {:ok,
       [
         %{
           "vocabulary" => "model:#{model}",
           "translation" => "translated by #{model}",
           "note" => ""
         }
       ]}
    end

    def import_from_image(_image_binary, _from_target_lang), do: {:ok, []}
    def import_from_image(_image_binary, _from_target_lang, _opts), do: {:ok, []}
  end

  defmodule NotebookTranslationPracticeGeneratorStub do
    def generate_translation_practice(vocabulary, grammar_context, from_target_lang) do
      generate_translation_practice(vocabulary, grammar_context, from_target_lang, [])
    end

    def generate_translation_practice(vocabulary, grammar_context, _from_target_lang, _opts) do
      {:ok,
       %{
         "translation_from" => "題目：#{vocabulary} / #{grammar_context}",
         "translation_target" => "答案：#{vocabulary}"
       }}
    end
  end

  defmodule NotebookTranslationPracticeGeneratorModelEchoStub do
    def generate_translation_practice(vocabulary, grammar_context, from_target_lang) do
      generate_translation_practice(vocabulary, grammar_context, from_target_lang, [])
    end

    def generate_translation_practice(vocabulary, grammar_context, _from_target_lang, opts) do
      model = opts |> Keyword.get(:model, "unknown") |> to_string()

      {:ok,
       %{
         "translation_from" => "#{model} 題目：#{vocabulary} / #{grammar_context}",
         "translation_target" => "#{model} 答案：#{vocabulary}"
       }}
    end
  end

  test "renders notebook shell", %{conn: conn} do
    unit = unit_fixture()
    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    assert has_element?(view, "#unit-title-form")
    assert has_element?(view, "#flashcards-panel-toggle")
    assert has_element?(view, "#unit-generate-panel-toggle")
    assert has_element?(view, "#unit-options-panel-toggle")
    assert has_element?(view, "#unit-import-panel-toggle")
    refute has_element?(view, "#unit-drawer-toggle[checked]")
    assert has_element?(view, "#add-page-btn")
    assert has_element?(view, "textarea[id$='-0']")
  end

  test "navbar toggles side panels", %{conn: conn} do
    unit = unit_fixture()
    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    refute has_element?(view, "#unit-drawer-toggle[checked]")
    refute has_element?(view, "#unit-options-panel")

    view |> element("#flashcards-panel-toggle") |> render_click()
    assert has_element?(view, "#unit-drawer-toggle[checked]")
    assert has_element?(view, "#flashcards-panel")

    view |> element("#unit-generate-panel-toggle") |> render_click()
    assert has_element?(view, "#unit-generate-panel")
    assert has_element?(view, "#unit-generate-form")
    assert has_element?(view, "#generate-translation-practice-btn")
    assert has_element?(view, "#unit-generate-form select[name='generate[output_mode]']")
    assert has_element?(view, "#unit-generate-form select[name='generate[ai_model]']")

    view |> element("#unit-options-panel-toggle") |> render_click()
    assert has_element?(view, "#unit-options-panel")
    assert has_element?(view, "#unit-quick-help")

    view |> element("#unit-import-panel-toggle") |> render_click()
    assert has_element?(view, "#unit-import-panel")
    assert has_element?(view, "#unit-import-form")
    assert has_element?(view, "#parse-import-btn")
    assert has_element?(view, "#unit-import-form select[name='import[ai_model]']")
    assert has_element?(view, "#unit-import-form select[name='import[ocr_model]']")

    view |> element("#close-drawer-btn") |> render_click()
    refute has_element?(view, "#unit-drawer-toggle[checked]")
    refute has_element?(view, "#unit-options-panel")
    refute has_element?(view, "#unit-import-panel")
    refute has_element?(view, "#unit-generate-panel")
  end

  test "open generate from item prefills vocabulary", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(page, %{
        title: page.title,
        items: [
          %{
            "id" => "vocab-node",
            "text" => "興味（きょうみ）",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view
    |> element("#generate-from-item-#{page.id}-0")
    |> render_click()

    assert has_element?(view, "#unit-generate-panel")

    assert has_element?(
             view,
             "#unit-generate-form input[name='generate[vocabulary]'][value='興味（きょうみ）']"
           )
  end

  test "generate translation practice appends under source item", %{conn: conn} do
    previous_generator = Application.get_env(:gakugo, :notebook_translation_practice_generator)

    Application.put_env(
      :gakugo,
      :notebook_translation_practice_generator,
      NotebookTranslationPracticeGeneratorStub
    )

    on_exit(fn ->
      if is_nil(previous_generator) do
        Application.delete_env(:gakugo, :notebook_translation_practice_generator)
      else
        Application.put_env(
          :gakugo,
          :notebook_translation_practice_generator,
          previous_generator
        )
      end
    end)

    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    vocab_page = hd(unit.pages)

    {:ok, grammar_page} =
      Learning.create_page(%{
        "unit_id" => unit.id,
        "title" => "Grammar",
        "items" => [
          %{
            "id" => "grammar-root",
            "text" => "grammar 1",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => [
              %{
                "id" => "grammar-child",
                "text" => "grammar 1 detail 1",
                "front" => false,
                "answer" => false,
                "link" => "",
                "children" => [
                  %{
                    "id" => "grammar-leaf",
                    "text" => "grammar 1 detail 1 example 1",
                    "front" => false,
                    "answer" => false,
                    "link" => "",
                    "children" => []
                  }
                ]
              }
            ]
          }
        ]
      })

    {:ok, _page} =
      Learning.update_page(vocab_page, %{
        title: vocab_page.title,
        items: [
          %{
            "id" => "vocab-node",
            "text" => "興味（きょうみ）",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view
    |> element("#generate-from-item-#{vocab_page.id}-0")
    |> render_click()

    view
    |> element("#unit-generate-form")
    |> render_submit(%{
      "generate" => %{
        "type" => "translation_practice",
        "vocabulary" => "興味（きょうみ）",
        "grammar_page_id" => to_string(grammar_page.id)
      }
    })

    assert has_element?(view, "#flash-info", "Generated translation practice")
    assert has_element?(view, "#item-input-#{vocab_page.id}-0-0", "題目：興味（きょうみ）")
    assert has_element?(view, "#item-input-#{vocab_page.id}-0-0-0", "答案：興味（きょうみ）")
  end

  test "generate from navbar can append to selected page root", %{conn: conn} do
    previous_generator = Application.get_env(:gakugo, :notebook_translation_practice_generator)

    Application.put_env(
      :gakugo,
      :notebook_translation_practice_generator,
      NotebookTranslationPracticeGeneratorStub
    )

    on_exit(fn ->
      if is_nil(previous_generator) do
        Application.delete_env(:gakugo, :notebook_translation_practice_generator)
      else
        Application.put_env(
          :gakugo,
          :notebook_translation_practice_generator,
          previous_generator
        )
      end
    end)

    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    default_page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(default_page, %{
        "title" => default_page.title,
        "items" => [
          %{
            "id" => "grammar-root",
            "text" => "文法A",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      })

    {:ok, second_page} =
      Learning.create_page(%{
        "unit_id" => unit.id,
        "title" => "Page 2",
        "items" => [
          %{
            "id" => "page-two-root",
            "text" => "existing",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view
    |> element("#unit-generate-panel-toggle")
    |> render_click()

    view
    |> element("#unit-generate-form")
    |> render_submit(%{
      "generate" => %{
        "type" => "translation_practice",
        "vocabulary" => "興味（きょうみ）",
        "grammar_page_id" => to_string(default_page.id),
        "output_mode" => "page_root",
        "output_page_id" => to_string(second_page.id)
      }
    })

    assert has_element?(view, "#page-card-#{second_page.id} textarea", "題目：興味（きょうみ）")
    assert has_element?(view, "#page-card-#{second_page.id} textarea", "答案：興味（きょうみ）")
    refute has_element?(view, "#page-card-#{default_page.id} textarea", "題目：興味（きょうみ）")
  end

  test "generate uses selected ai model from drawer", %{conn: conn} do
    previous_generator = Application.get_env(:gakugo, :notebook_translation_practice_generator)

    Application.put_env(
      :gakugo,
      :notebook_translation_practice_generator,
      NotebookTranslationPracticeGeneratorModelEchoStub
    )

    on_exit(fn ->
      if is_nil(previous_generator) do
        Application.delete_env(:gakugo, :notebook_translation_practice_generator)
      else
        Application.put_env(
          :gakugo,
          :notebook_translation_practice_generator,
          previous_generator
        )
      end
    end)

    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(page, %{
        "title" => page.title,
        "items" => [
          %{
            "id" => "grammar-root",
            "text" => "文法A",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view |> element("#unit-generate-panel-toggle") |> render_click()

    view
    |> element("#unit-generate-form")
    |> render_submit(%{
      "generate" => %{
        "type" => "translation_practice",
        "vocabulary" => "興味（きょうみ）",
        "ai_model" => "gpt-4.1-mini",
        "grammar_page_id" => to_string(page.id),
        "output_mode" => "page_root",
        "output_page_id" => to_string(page.id)
      }
    })

    assert has_element?(view, "#page-card-#{page.id} textarea", "gpt-4.1-mini 題目：興味（きょうみ）")
    assert has_element?(view, "#page-card-#{page.id} textarea", "gpt-4.1-mini 答案：興味（きょうみ）")
  end

  test "parse import requires source text", %{conn: conn} do
    unit = unit_fixture()
    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view |> element("#unit-import-panel-toggle") |> render_click()

    view
    |> element("#unit-import-form")
    |> render_submit(%{"import" => %{"type" => "vocabularies", "page_id" => "", "source" => ""}})

    assert has_element?(view, "#unit-import-panel")
    assert has_element?(view, "#flash-error", "Enter source text or upload image before parsing")
  end

  test "parse import appends flashcard-ready notebook nodes", %{conn: conn} do
    previous_importer = Application.get_env(:gakugo, :notebook_importer)
    Application.put_env(:gakugo, :notebook_importer, NotebookImporterStub)

    on_exit(fn ->
      if is_nil(previous_importer) do
        Application.delete_env(:gakugo, :notebook_importer)
      else
        Application.put_env(:gakugo, :notebook_importer, previous_importer)
      end
    end)

    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view |> element("#unit-import-panel-toggle") |> render_click()

    view
    |> element("#unit-import-form")
    |> render_submit(%{
      "import" => %{
        "type" => "vocabularies",
        "page_id" => to_string(page.id),
        "source" => "- 情報（じょうほう）\n  - 情報、資訊\n- 興趣\n  - 興味（きょうみ）"
      }
    })

    assert has_element?(view, "#flash-info", "Imported 2 vocabularies")
    assert has_element?(view, "textarea[id$='-1']", "情報（じょうほう）")
    assert has_element?(view, "textarea[id$='-1-0']", "情報、資訊")
    assert has_element?(view, "#item-options-#{page.id}-1 summary", "F")
    refute has_element?(view, "#item-options-#{page.id}-1-0 summary", "A")

    assert has_element?(view, "textarea[id$='-2']", "興味（きょうみ）")
    assert has_element?(view, "textarea[id$='-2-0']", "興趣")
    assert has_element?(view, "#item-options-#{page.id}-2 summary", "F")
  end

  test "parse import uses selected ai model from drawer", %{conn: conn} do
    previous_importer = Application.get_env(:gakugo, :notebook_importer)
    Application.put_env(:gakugo, :notebook_importer, NotebookImporterModelEchoStub)

    on_exit(fn ->
      if is_nil(previous_importer) do
        Application.delete_env(:gakugo, :notebook_importer)
      else
        Application.put_env(:gakugo, :notebook_importer, previous_importer)
      end
    end)

    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view |> element("#unit-import-panel-toggle") |> render_click()

    view
    |> element("#unit-import-form")
    |> render_submit(%{
      "import" => %{
        "type" => "vocabularies",
        "ai_model" => "gemini-2.0-flash",
        "ocr_model" => "gemini-2.0-flash",
        "page_id" => to_string(page.id),
        "source" => "source"
      }
    })

    assert has_element?(view, "#page-card-#{page.id} textarea", "model:gemini-2.0-flash")
    assert has_element?(view, "#page-card-#{page.id} textarea", "translated by gemini-2.0-flash")
  end

  test "items inside a flashcard branch use answer mode", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(page, %{items: notebook_items_with_nested_front(), title: page.title})

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    assert has_element?(view, "#item-options-#{page.id}-0-0-0 input[phx-value-flag='answer']")
    refute has_element?(view, "#item-options-#{page.id}-0-0-0 input[phx-value-flag='front']")

    refute has_element?(
             view,
             "#item-options-#{page.id}-0-0-0 input[phx-value-flag='answer'][checked]"
           )

    render_hook(view, "toggle_item_flag", %{path: "0.0.0", flag: "answer", page_id: page.id})

    assert has_element?(
             view,
             "#item-options-#{page.id}-0-0-0 input[phx-value-flag='answer'][checked]"
           )
  end

  test "flashcard item itself can be marked as answer", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    refute has_element?(view, "#item-options-#{page.id}-0 input[phx-value-flag='answer']")

    render_hook(view, "toggle_item_flag", %{path: "0", flag: "front", page_id: page.id})

    assert has_element?(view, "#item-options-#{page.id}-0 input[phx-value-flag='front'][checked]")
    assert has_element?(view, "#item-options-#{page.id}-0 input[phx-value-flag='answer']")

    render_hook(view, "toggle_item_flag", %{path: "0", flag: "answer", page_id: page.id})

    assert has_element?(view, "#item-options-#{page.id}-0 input[phx-value-flag='front'][checked]")

    assert has_element?(
             view,
             "#item-options-#{page.id}-0 input[phx-value-flag='answer'][checked]"
           )
  end

  test "item option badge distinguishes question answer and both", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(page, %{items: notebook_items_with_q_a_and_f(), title: page.title})

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    assert has_element?(view, "#item-options-#{page.id}-0 summary", "Q")
    assert has_element?(view, "#item-options-#{page.id}-0-0 summary", "A")
    assert has_element?(view, "#item-options-#{page.id}-1 summary", "F")
  end

  test "valid item link shows open external action", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view
    |> element("form[phx-change='edit_node_link']")
    |> render_change(%{"path" => "0", "link" => "https://example.com", "page_id" => page.id})

    assert has_element?(view, "a[title='Open external link'][href='https://example.com']")
  end

  test "item with flashcard children cannot be set as flashcard", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(page, %{items: notebook_items_with_front_child(), title: page.title})

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    refute has_element?(view, "#item-options-#{page.id}-0 input[phx-value-flag='front']")

    assert has_element?(
             view,
             "#flashcard-disabled-hint-#{page.id}-0",
             "Has flashcard children."
           )
  end

  test "item keybinding events add and remove nested item", %{conn: conn} do
    unit = unit_fixture()
    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view
    |> element("form[phx-change='edit_node_text']")
    |> render_change(%{"path" => "0", "text" => "hello"})

    render_hook(view, "item_enter", %{"path" => "0"})
    assert has_element?(view, "textarea[id$='-0-0']")

    render_hook(view, "item_delete_empty", %{"path" => "0.0"})
    refute has_element?(view, "textarea[id$='-0-0']")
  end

  test "tab and shift-tab keybinding events indent and outdent", %{conn: conn} do
    unit = unit_fixture()
    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    render_hook(view, "item_enter", %{"path" => "0", "text" => ""})

    assert has_element?(view, "textarea[id$='-1']")

    render_hook(view, "item_indent", %{"path" => "1", "text" => "second"})
    assert has_element?(view, "textarea[id$='-0-0']")

    render_hook(view, "item_outdent", %{"path" => "0.0", "text" => "second"})
    assert has_element?(view, "textarea[id$='-1']")
  end

  test "edit_node_text prefers node_id over path", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(page, %{items: notebook_items_with_ids(), title: page.title})

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    render_hook(view, "edit_node_text", %{
      "node_id" => "node-1",
      "path" => "1",
      "text" => "updated by id",
      "page_id" => page.id
    })

    assert has_element?(view, "textarea[id$='-0']", "updated by id")
    assert has_element?(view, "textarea[id$='-1']", "second")
  end

  test "item_enter supports node_id-only payload", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(page, %{items: notebook_items_with_ids(), title: page.title})

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    render_hook(view, "item_enter", %{
      "node_id" => "node-1",
      "page_id" => page.id,
      "text" => "first"
    })

    assert has_element?(view, "textarea[id$='-0-0']")
  end

  test "page card delete uses confirmation and removes selected page", %{conn: conn} do
    unit = unit_fixture()
    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view |> element("#add-page-btn") |> render_click()

    unit = Learning.get_unit!(unit.id)
    second_page_id = List.last(unit.pages).id

    assert has_element?(
             view,
             "#delete-page-#{second_page_id}[data-confirm='Delete this page and all its items?']"
           )

    view |> element("#delete-page-#{second_page_id}") |> render_click()
    refute has_element?(view, "#page-card-#{second_page_id}")
  end

  test "page move up/down buttons reorder page cards", %{conn: conn} do
    unit = unit_fixture()
    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view |> element("#add-page-btn") |> render_click()
    view |> element("#add-page-btn") |> render_click()

    unit = Learning.get_unit!(unit.id)
    [first_page, second_page, third_page] = unit.pages

    assert has_element?(view, "#move-page-up-#{first_page.id}[disabled]")
    refute has_element?(view, "#move-page-down-#{first_page.id}[disabled]")
    assert has_element?(view, "#move-page-down-#{third_page.id}[disabled]")

    view
    |> element("#move-page-up-#{third_page.id}")
    |> render_click()

    reordered_ids = Learning.get_unit!(unit.id).pages |> Enum.map(& &1.id)
    assert reordered_ids == [first_page.id, third_page.id, second_page.id]

    view
    |> element("#move-page-down-#{third_page.id}")
    |> render_click()

    restored_ids = Learning.get_unit!(unit.id).pages |> Enum.map(& &1.id)
    assert restored_ids == [first_page.id, second_page.id, third_page.id]
  end

  test "move_item reorders items within the same page", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(page, %{items: notebook_items_with_ids(), title: page.title})

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    render_hook(view, "move_item", %{
      "source_page_id" => page.id,
      "source_node_id" => "node-2",
      "target_page_id" => page.id,
      "target_node_id" => "node-1",
      "position" => "before"
    })

    assert has_element?(view, "#item-input-#{page.id}-0", "second")
    assert has_element?(view, "#item-input-#{page.id}-1", "first")
  end

  test "move_item supports cross-page move to root end", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page_one = hd(unit.pages)

    {:ok, page_two} =
      Learning.create_page(%{
        "unit_id" => unit.id,
        "title" => "Page 2",
        "items" => notebook_items_with_ids("target")
      })

    {:ok, _page} =
      Learning.update_page(page_one, %{
        items: notebook_items_with_ids("source"),
        title: page_one.title
      })

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    render_hook(view, "move_item", %{
      "source_page_id" => page_one.id,
      "source_node_id" => "source-node-1",
      "target_page_id" => page_two.id,
      "position" => "root_end"
    })

    assert has_element?(view, "#item-input-#{page_one.id}-0", "source second")
    assert has_element?(view, "#item-input-#{page_two.id}-2", "source first")
  end

  test "flashcard without answer items still appears in flashcard list", %{
    conn: conn
  } do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, _page} =
      Learning.update_page(page, %{items: notebook_items_without_answer(), title: page.title})

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view |> element("#flashcards-panel-toggle") |> render_click()

    assert has_element?(view, "#flashcards-panel", "front note")
    refute has_element?(view, "#flashcards-panel", "child note")
  end

  test "flashcard preview includes cards from all pages", %{
    conn: conn
  } do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    first_page = hd(unit.pages)

    {:ok, _first_page} =
      Learning.update_page(first_page, %{
        items: notebook_items_with_answer("page one"),
        title: first_page.title
      })

    {:ok, second_page} =
      Learning.create_page(%{
        "unit_id" => unit.id,
        "title" => "Page 2",
        "items" => notebook_items_with_answer("page two")
      })

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    view |> element("#flashcards-panel-toggle") |> render_click()

    assert has_element?(view, "#flashcards-panel", "page one")
    assert has_element?(view, "#flashcards-panel", "page two")
    assert has_element?(view, "#flashcards-panel", "page one front")
    assert has_element?(view, "#flashcards-panel", "page two front")

    assert has_element?(view, "#page-card-#{second_page.id}")
  end

  test "two sessions converge after notebook edit", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")
    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    Phoenix.PubSub.subscribe(Gakugo.PubSub, "unit:notebook:#{unit.id}")

    render_hook(view_one, "edit_node_text", %{
      "path" => "0",
      "text" => "shared edit",
      "page_id" => page.id
    })

    assert_receive {:notebook_operation, _operation}
    _ = :sys.get_state(view_two.pid)

    assert has_element?(view_two, "textarea[id$='-0']", "shared edit")
  end

  test "duplicate op_id operation is applied only once", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    operation = %{
      unit_id: unit.id,
      page_id: page.id,
      actor_id: "remote-tab",
      op_id: "same-op-id",
      base_version: 0,
      version: 1,
      command: {:item_enter, "0", "dedupe"},
      meta: %{}
    }

    send(view.pid, {:notebook_operation, operation})
    send(view.pid, {:notebook_operation, operation})
    _ = :sys.get_state(view.pid)

    assert has_element?(view, "textarea[id$='-0-0']")
    refute has_element?(view, "textarea[id$='-0-1']")
  end

  test "stale version operation is ignored", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view, _html} = live(conn, ~p"/units/#{unit.id}")

    send(
      view.pid,
      {:notebook_operation,
       %{
         unit_id: unit.id,
         page_id: page.id,
         actor_id: "remote-tab",
         op_id: "newer-op",
         base_version: 0,
         version: 1,
         command: {:edit_text, "0", "newest text"},
         meta: %{}
       }}
    )

    send(
      view.pid,
      {:notebook_operation,
       %{
         unit_id: unit.id,
         page_id: page.id,
         actor_id: "remote-tab",
         op_id: "stale-op",
         base_version: 0,
         version: 1,
         command: {:edit_text, "0", "stale text"},
         meta: %{}
       }}
    )

    _ = :sys.get_state(view.pid)

    assert has_element?(view, "textarea[id$='-0']", "newest text")
    refute has_element?(view, "textarea[id$='-0']", "stale text")
  end

  test "add page reflects to another session", %{conn: conn} do
    unit = unit_fixture()

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")
    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    view_one |> element("#add-page-btn") |> render_click()
    _ = :sys.get_state(view_two.pid)

    unit = Learning.get_unit!(unit.id)
    second_page_id = List.last(unit.pages).id

    assert has_element?(view_two, "#page-card-#{second_page_id}")
  end

  test "delete page reflects to another session", %{conn: conn} do
    unit = unit_fixture()

    {:ok, page} =
      Learning.create_page(%{
        "unit_id" => unit.id,
        "title" => "Page 2",
        "items" => [
          %{"text" => "", "front" => false, "answer" => false, "link" => "", "children" => []}
        ]
      })

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")
    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    assert has_element?(view_two, "#page-card-#{page.id}")

    view_one |> element("#delete-page-#{page.id}") |> render_click()
    _ = :sys.get_state(view_two.pid)

    refute has_element?(view_two, "#page-card-#{page.id}")
  end

  test "late-joined session receives subsequent notebook updates", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")

    render_hook(view_one, "edit_node_text", %{
      "path" => "0",
      "text" => "first change",
      "page_id" => page.id
    })

    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    render_hook(view_one, "edit_node_text", %{
      "path" => "0",
      "text" => "second change",
      "page_id" => page.id
    })

    _ = :sys.get_state(view_two.pid)

    assert has_element?(view_two, "textarea[id$='-0']", "second change")
  end

  test "early session receives updates from later session", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")

    render_hook(view_one, "edit_node_text", %{
      "path" => "0",
      "text" => "first tab baseline",
      "page_id" => page.id
    })

    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    render_hook(view_two, "edit_node_text", %{
      "path" => "0",
      "text" => "second tab update",
      "page_id" => page.id
    })

    _ = :sys.get_state(view_one.pid)

    assert has_element?(view_one, "textarea[id$='-0']", "second tab update")
  end

  test "late-joined session converges on dependent operations", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")

    render_hook(view_one, "item_enter", %{
      "path" => "0",
      "text" => "root",
      "page_id" => page.id
    })

    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    render_hook(view_one, "edit_node_text", %{
      "path" => "0.0",
      "text" => "child from op2",
      "page_id" => page.id
    })

    _ = :sys.get_state(view_two.pid)

    assert has_element?(view_two, "textarea[id$='-0-0']", "child from op2")
  end

  test "item lock disables peer editing and blocks conflicting edits", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")
    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    render_hook(view_one, "item_lock_acquire", %{
      "path" => "0",
      "page_id" => page.id
    })

    _ = :sys.get_state(view_two.pid)

    assert has_element?(view_two, "textarea[id$='-0'][disabled]")
    assert has_element?(view_two, "#item-locked-badge-#{page.id}-0")

    render_hook(view_two, "edit_node_text", %{
      "path" => "0",
      "text" => "blocked edit",
      "page_id" => page.id
    })

    _ = :sys.get_state(view_one.pid)

    refute has_element?(view_one, "textarea[id$='-0']", "blocked edit")

    render_hook(view_one, "item_lock_release", %{
      "path" => "0",
      "page_id" => page.id
    })

    _ = :sys.get_state(view_two.pid)

    refute has_element?(view_two, "textarea[id$='-0'][disabled]")
  end

  test "unit and page title inputs lock while another collaborator focuses them", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")
    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    render_hook(view_one, "item_lock_acquire", %{
      "path" => "meta.unit_title",
      "page_id" => 0
    })

    _ = :sys.get_state(view_two.pid)
    assert has_element?(view_two, "#unit-title-input[disabled]")

    render_hook(view_one, "item_lock_release", %{
      "path" => "meta.unit_title",
      "page_id" => 0
    })

    _ = :sys.get_state(view_two.pid)
    refute has_element?(view_two, "#unit-title-input[disabled]")

    render_hook(view_one, "item_lock_acquire", %{
      "path" => "meta.page_title",
      "page_id" => page.id
    })

    _ = :sys.get_state(view_two.pid)
    assert has_element?(view_two, "#page-title-input-#{page.id}[disabled]")
  end

  test "saved unit title and language pair reload in other sessions", %{conn: conn} do
    unit = unit_fixture()

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")
    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    view_one |> element("#unit-options-panel-toggle") |> render_click()

    view_one
    |> element("#unit-options-form")
    |> render_change(%{
      "unit" => %{
        "title" => "Shared notebook title",
        "from_target_lang" => unit.from_target_lang
      }
    })

    send(view_one.pid, :auto_save_unit)
    _ = :sys.get_state(view_one.pid)
    _ = :sys.get_state(view_two.pid)

    assert has_element?(view_two, "#unit-title-input[value='Shared notebook title']")

    view_two |> element("#unit-options-panel-toggle") |> render_click()

    assert has_element?(
             view_two,
             "#unit-options-form select[name='unit[from_target_lang]'] option[value='#{unit.from_target_lang}'][selected]"
           )
  end

  test "saved page title reloads in other sessions", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")
    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    view_one
    |> element("#page-form-#{page.id}")
    |> render_change(%{"page_id" => page.id, "page" => %{"title" => "Synced page title"}})

    send(view_one.pid, {:auto_save_page, page.id})
    _ = :sys.get_state(view_one.pid)
    _ = :sys.get_state(view_two.pid)

    assert has_element?(view_two, "#page-title-input-#{page.id}[value='Synced page title']")
  end

  test "can append root item from page footer while first item is locked", %{conn: conn} do
    unit = unit_fixture()
    unit = Learning.get_unit!(unit.id)
    page = hd(unit.pages)

    {:ok, view_one, _html} = live(conn, ~p"/units/#{unit.id}")
    {:ok, view_two, _html} = live(Phoenix.ConnTest.build_conn(), ~p"/units/#{unit.id}")

    render_hook(view_one, "item_lock_acquire", %{
      "path" => "0",
      "page_id" => page.id
    })

    _ = :sys.get_state(view_two.pid)

    assert has_element?(view_two, "textarea[id$='-0'][disabled]")

    view_two
    |> element("#add-item-last-#{page.id}")
    |> render_click()

    _ = :sys.get_state(view_two.pid)

    assert has_element?(view_two, "textarea[id$='-1']")
  end

  defp notebook_items_without_answer do
    [
      %{
        "text" => "front note",
        "front" => true,
        "answer" => false,
        "link" => "",
        "children" => [
          %{
            "text" => "child note",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      }
    ]
  end

  defp notebook_items_with_answer(label) do
    [
      %{
        "text" => "#{label} front",
        "front" => true,
        "answer" => false,
        "link" => "",
        "children" => [
          %{
            "text" => "#{label} answer",
            "front" => false,
            "answer" => true,
            "link" => "",
            "children" => []
          }
        ]
      }
    ]
  end

  defp notebook_items_with_nested_front do
    [
      %{
        "text" => "root front",
        "front" => true,
        "answer" => false,
        "link" => "",
        "children" => [
          %{
            "text" => "child normal",
            "front" => false,
            "answer" => false,
            "link" => "",
            "children" => [
              %{
                "text" => "grandchild flashcard",
                "front" => true,
                "answer" => false,
                "link" => "",
                "children" => []
              }
            ]
          }
        ]
      }
    ]
  end

  defp notebook_items_with_q_a_and_f do
    [
      %{
        "text" => "question",
        "front" => true,
        "answer" => false,
        "link" => "",
        "children" => [
          %{
            "text" => "answer",
            "front" => false,
            "answer" => true,
            "link" => "",
            "children" => []
          }
        ]
      },
      %{
        "text" => "flashcard and answer",
        "front" => true,
        "answer" => true,
        "link" => "",
        "children" => []
      }
    ]
  end

  defp notebook_items_with_front_child do
    [
      %{
        "text" => "hello 2",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => [
          %{
            "text" => "world 2",
            "front" => true,
            "answer" => false,
            "link" => "",
            "children" => []
          }
        ]
      }
    ]
  end

  defp notebook_items_with_ids(prefix \\ "") do
    id_prefix = if prefix == "", do: "", else: "#{prefix}-"
    text_prefix = if prefix == "", do: "", else: "#{prefix} "

    [
      %{
        "id" => "#{id_prefix}node-1",
        "text" => "#{text_prefix}first",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => []
      },
      %{
        "id" => "#{id_prefix}node-2",
        "text" => "#{text_prefix}second",
        "front" => false,
        "answer" => false,
        "link" => "",
        "children" => []
      }
    ]
  end
end
