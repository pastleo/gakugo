defmodule GakugoWeb.UnitLive.ShowEdit do
  use GakugoWeb, :live_view

  alias Gakugo.Anki.SyncService
  alias Gakugo.AI.Config, as: AIConfig
  alias Gakugo.Learning
  alias Gakugo.Learning.Notebook.Editor
  alias Gakugo.Learning.Notebook.ItemLockRegistry
  alias Gakugo.Learning.Notebook.PageVersionRegistry
  alias Gakugo.Learning.Notebook.Importer
  alias Gakugo.Learning.Notebook.TranslationPracticeGenerator
  alias Gakugo.Learning.Notebook.UnitSession
  alias Gakugo.Learning.FromTargetLang
  alias Gakugo.Learning.Notebook.Tree
  alias GakugoWeb.UnitLive.ShowEditFormHelpers
  alias GakugoWeb.UnitLive.ShowEditHelpers
  alias GakugoWeb.UnitLive.ShowEditGenerateHelpers
  alias GakugoWeb.UnitLive.ShowEditImportHelpers
  alias GakugoWeb.UnitLive.ShowEditMoveHelpers

  @auto_save_ms 1200
  @unit_session_heartbeat_ms 10_000
  @max_seen_ops 512
  @unit_title_lock_page_id 0
  @unit_title_lock_path "meta.unit_title"
  @page_title_lock_path "meta.page_title"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    unit = ensure_unit_has_page(Learning.get_unit!(id))
    default_page_id = default_page_id_from_unit(unit)

    import_values = %{
      "type" => "vocabularies",
      "source" => "",
      "ai_model" => default_model_value(:parse),
      "ocr_model" => default_model_value(:ocr),
      "page_id" => to_string(default_page_id)
    }

    generate_values = %{
      "type" => "translation_practice",
      "vocabulary" => "",
      "ai_model" => default_model_value(:generation),
      "grammar_page_id" => to_string(default_page_id),
      "output_mode" => "page_root",
      "output_page_id" => to_string(default_page_id)
    }

    socket =
      socket
      |> assign(:page_title, "Unit Notebook")
      |> assign(:unit, unit)
      |> assign(:from_target_lang_options, FromTargetLang.options())
      |> assign(:meta_values, %{
        "title" => unit.title,
        "from_target_lang" => unit.from_target_lang
      })
      |> assign(:meta_form, to_form(Learning.change_unit(unit)))
      |> assign(:page_states, build_page_states(unit))
      |> assign(:active_drawer, nil)
      |> assign(:has_unsaved_changes, false)
      |> assign(:syncing_to_anki, false)
      |> assign(:focused_path, nil)
      |> assign(:actor_id, Ecto.UUID.generate())
      |> assign(:seen_op_ids, MapSet.new())
      |> assign(:seen_op_order, :queue.new())
      |> assign(:item_locks, ItemLockRegistry.locks_for_unit(unit.id))
      |> assign(:import_values, import_values)
      |> assign(:import_form, to_form(import_values, as: :import))
      |> assign(:parsing_import, false)
      |> assign(:generate_values, generate_values)
      |> assign(:generate_form, to_form(generate_values, as: :generate))
      |> assign(:generating_translation_practice, false)
      |> assign(:generate_source_item, nil)
      |> allow_upload(:import_image,
        accept: ~w(.png .jpg .jpeg .webp),
        max_entries: 1,
        max_file_size: 8_000_000,
        auto_upload: true
      )

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Gakugo.PubSub, notebook_topic(unit.id))
        touch_unit_session(socket)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    flashcard_unit = unit_for_flashcard_preview(assigns)
    flashcard_fronts_by_page = build_flashcard_fronts_by_page(flashcard_unit)
    ai_runtime = AIConfig.runtime_snapshot()
    generate_ai_model_options = generate_ai_model_options(assigns, ai_runtime)
    import_ai_model_options = import_ai_model_options(assigns, ai_runtime)
    import_ocr_model_options = import_ocr_model_options(assigns, ai_runtime)

    assigns =
      assigns
      |> assign(:unit_title_lock_page_id, @unit_title_lock_page_id)
      |> assign(:unit_title_lock_path, @unit_title_lock_path)
      |> assign(:page_title_lock_path, @page_title_lock_path)
      |> assign(:unit_title_locked_by_other, unit_title_locked_by_other?(assigns))
      |> assign(:flashcard_fronts_by_page, flashcard_fronts_by_page)
      |> assign(:ai_runtime, ai_runtime)
      |> assign(:pages, pages_for_render(assigns))
      |> assign(:page_options, page_options(assigns))
      |> assign(:generate_ai_model_options, generate_ai_model_options)
      |> assign(:import_ai_model_options, import_ai_model_options)
      |> assign(:import_ocr_model_options, import_ocr_model_options)
      |> assign(:generate_models_available, models_available?(generate_ai_model_options))
      |> assign(:generate_model_error, usage_error(ai_runtime, generate_ai_model_options))
      |> assign(:import_parse_models_available, models_available?(import_ai_model_options))
      |> assign(:import_parse_model_error, usage_error(ai_runtime, import_ai_model_options))
      |> assign(:import_ocr_models_available, models_available?(import_ocr_model_options))
      |> assign(:import_ocr_model_error, usage_error(ai_runtime, import_ocr_model_options))
      |> assign(:generate_source_item_label, generate_source_item_label(assigns))
      |> assign(:generate_output_hint, generate_output_hint(assigns))

    ~H"""
    <Layouts.app flash={@flash} main_container_class="mx-auto w-full max-w-[1320px] space-y-4">
      <:header>
        <header class="sticky top-0 z-40 border-b border-base-300/70 bg-base-100/95 backdrop-blur-xl">
          <nav class="mx-auto flex w-full max-w-[1320px] flex-col items-stretch gap-3 px-4 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-6 lg:px-8">
            <div class="flex min-w-0 items-center gap-3 sm:flex-1">
              <.link
                navigate={~p"/"}
                class="group shrink-0 rounded-xl border border-base-300 bg-base-100 p-1.5 transition hover:bg-base-200"
                title="Back to units"
              >
                <img src={~p"/images/logo.svg"} width="28" alt="Home" class="size-7" />
              </.link>

              <.form
                for={@meta_form}
                id="unit-title-form"
                phx-change="validate_meta"
                class="min-w-0 flex-1"
              >
                <input
                  id="unit-title-input"
                  type="text"
                  name="unit[title]"
                  value={@meta_values["title"]}
                  data-page-id={@unit_title_lock_page_id}
                  data-lock-path={@unit_title_lock_path}
                  disabled={@unit_title_locked_by_other}
                  phx-hook="CollaborativeInputLock"
                  placeholder="Notebook title"
                  phx-debounce="250"
                  class="w-full border-0 border-b border-base-content/30 bg-transparent px-1 py-1 text-lg font-semibold text-base-content outline-hidden transition focus:border-primary disabled:cursor-not-allowed disabled:text-base-content/45"
                />
                <input
                  type="hidden"
                  name="unit[from_target_lang]"
                  value={@meta_values["from_target_lang"]}
                />
              </.form>
            </div>

            <div class="grid grid-cols-4 gap-1 sm:flex sm:items-center sm:gap-2">
              <button
                id="unit-options-panel-toggle"
                type="button"
                phx-click="toggle_drawer"
                phx-value-panel="options"
                class={[
                  "w-full rounded-xl border px-2 py-1.5 text-[11px] font-medium transition sm:w-auto sm:px-3 sm:text-sm",
                  @active_drawer == "options" && "border-primary/40 bg-primary/12 text-primary",
                  @active_drawer != "options" &&
                    "border-base-300 text-base-content/80 hover:bg-base-200"
                ]}
              >
                Options
              </button>

              <button
                id="unit-import-panel-toggle"
                type="button"
                phx-click="toggle_drawer"
                phx-value-panel="import"
                class={[
                  "w-full rounded-xl border px-2 py-1.5 text-[11px] font-medium transition sm:w-auto sm:px-3 sm:text-sm",
                  @active_drawer == "import" && "border-primary/40 bg-primary/12 text-primary",
                  @active_drawer != "import" &&
                    "border-base-300 text-base-content/80 hover:bg-base-200"
                ]}
              >
                Import
              </button>

              <button
                id="unit-generate-panel-toggle"
                type="button"
                phx-click="toggle_drawer"
                phx-value-panel="generate"
                class={[
                  "w-full rounded-xl border px-2 py-1.5 text-[11px] font-medium transition sm:w-auto sm:px-3 sm:text-sm",
                  @active_drawer == "generate" && "border-primary/40 bg-primary/12 text-primary",
                  @active_drawer != "generate" &&
                    "border-base-300 text-base-content/80 hover:bg-base-200"
                ]}
              >
                Generate
              </button>

              <button
                id="flashcards-panel-toggle"
                type="button"
                phx-click="toggle_drawer"
                phx-value-panel="flashcards"
                class={[
                  "w-full rounded-xl border px-2 py-1.5 text-[11px] font-medium transition sm:w-auto sm:px-3 sm:text-sm",
                  @active_drawer == "flashcards" && "border-primary/40 bg-primary/12 text-primary",
                  @active_drawer != "flashcards" &&
                    "border-base-300 text-base-content/80 hover:bg-base-200"
                ]}
              >
                Flashcards
              </button>
            </div>
          </nav>
        </header>
      </:header>

      <div class="drawer drawer-end">
        <input
          id="unit-drawer-toggle"
          type="checkbox"
          class="drawer-toggle"
          checked={@active_drawer in ["flashcards", "generate", "options", "import"]}
        />

        <div class="drawer-content">
          <section id="notebook-pages" phx-hook="NotebookDnd" class="space-y-4">
            <article
              :for={page <- @pages}
              id={"page-card-#{page.id}"}
              data-dnd-page={page.id}
              class="rounded-3xl border border-base-300 bg-base-100 p-5 shadow-sm transition"
            >
              <div class="mb-3 flex items-start justify-between gap-3">
                <div class="min-w-0 grow">
                  <.form for={page.form} id={"page-form-#{page.id}"} phx-change="validate_page">
                    <input type="hidden" name="page_id" value={page.id} />
                    <input
                      id={"page-title-input-#{page.id}"}
                      type="text"
                      name="page[title]"
                      value={page.title}
                      data-page-id={page.id}
                      data-lock-path={@page_title_lock_path}
                      disabled={page.title_locked_by_other}
                      phx-hook="CollaborativeInputLock"
                      phx-debounce="250"
                      class="w-full border-0 border-b border-base-content/30 bg-transparent px-1 py-1 text-lg font-semibold text-base-content outline-hidden transition focus:border-primary disabled:cursor-not-allowed disabled:text-base-content/45"
                    />
                  </.form>
                </div>

                <div class="flex items-center gap-1">
                  <details class="relative">
                    <summary
                      class="inline-flex list-none items-center gap-1 rounded-md border border-base-300 px-2 py-1 text-xs font-medium text-base-content/80 transition hover:bg-base-200 marker:hidden"
                      title="Add item"
                    >
                      <.icon name="hero-plus" class="size-3.5" />
                      <span class="hidden sm:inline">Add item</span>
                    </summary>

                    <div class="absolute right-0 top-8 z-20 w-40 rounded-lg border border-base-300 bg-base-100 p-1.5 shadow-lg">
                      <button
                        id={"add-item-first-#{page.id}"}
                        type="button"
                        phx-click="add_root_item"
                        phx-value-page_id={page.id}
                        phx-value-position="first"
                        class="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200"
                      >
                        <.icon name="hero-arrow-up" class="size-3.5" /> Add to first
                      </button>

                      <button
                        id={"add-item-last-#{page.id}"}
                        type="button"
                        phx-click="add_root_item"
                        phx-value-page_id={page.id}
                        phx-value-position="last"
                        class="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200"
                      >
                        <.icon name="hero-arrow-down" class="size-3.5" /> Add to last
                      </button>
                    </div>
                  </details>

                  <details class="relative">
                    <summary
                      class="inline-flex list-none items-center rounded-md border border-base-300 p-1 text-base-content/80 transition hover:bg-base-200 marker:hidden"
                      title="Page actions"
                    >
                      <.icon name="hero-ellipsis-horizontal" class="size-4" />
                    </summary>

                    <div class="absolute right-0 top-8 z-20 w-40 rounded-lg border border-base-300 bg-base-100 p-1.5 shadow-lg">
                      <button
                        id={"move-page-up-#{page.id}"}
                        type="button"
                        phx-click="move_page"
                        phx-value-page_id={page.id}
                        phx-value-direction="up"
                        disabled={!page.can_move_up}
                        class="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-35"
                        title="Move page up"
                      >
                        <.icon name="hero-chevron-up" class="size-3.5" /> Move up
                      </button>

                      <button
                        id={"move-page-down-#{page.id}"}
                        type="button"
                        phx-click="move_page"
                        phx-value-page_id={page.id}
                        phx-value-direction="down"
                        disabled={!page.can_move_down}
                        class="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-base-content transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-35"
                        title="Move page down"
                      >
                        <.icon name="hero-chevron-down" class="size-3.5" /> Move down
                      </button>

                      <button
                        id={"delete-page-#{page.id}"}
                        type="button"
                        phx-click="delete_page"
                        phx-value-page_id={page.id}
                        data-confirm="Delete this page and all its items?"
                        class="inline-flex w-full items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs text-error transition hover:bg-error/12"
                        title="Delete page"
                      >
                        <.icon name="hero-x-mark" class="size-3.5" /> Delete
                      </button>
                    </div>
                  </details>
                </div>
              </div>

              <ul
                id={"notebook-tree-#{page.id}"}
                data-dnd-page={page.id}
                class="space-y-2 text-sm text-base-content"
              >
                <.node_editor
                  :for={{node, idx} <- Enum.with_index(page.nodes)}
                  node={node}
                  page_id={page.id}
                  path={[idx]}
                  parent_front={false}
                  in_front_branch={false}
                  actor_id={@actor_id}
                  item_locks={@item_locks}
                />
              </ul>
            </article>

            <button
              id="add-page-btn"
              type="button"
              phx-click="add_page"
              class="rounded-xl border border-dashed border-base-300 px-4 py-2 text-sm font-medium text-base-content/80 transition hover:border-primary/45 hover:bg-primary/8 hover:text-primary"
            >
              <.icon name="hero-plus" class="size-4" /> New Page
            </button>
          </section>
        </div>

        <div class="drawer-side z-50">
          <label
            for="unit-drawer-toggle"
            class="drawer-overlay"
            aria-label="close sidebar"
            phx-click="close_drawer"
          >
          </label>

          <section class="h-full w-[22rem] overflow-y-auto border-l border-base-300 bg-base-100 p-5 shadow-2xl">
            <div class="mb-4 flex items-center justify-between">
              <h2 class="text-sm font-semibold text-base-content">
                {drawer_title(@active_drawer)}
              </h2>

              <button
                id="close-drawer-btn"
                type="button"
                phx-click="close_drawer"
                class="rounded-md p-1 text-base-content/70 transition hover:bg-base-200"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <%= cond do %>
              <% @active_drawer == "options" -> %>
                <.unit_options_panel
                  meta_form={@meta_form}
                  from_target_lang_options={@from_target_lang_options}
                  meta_values={@meta_values}
                />
              <% @active_drawer == "generate" -> %>
                <.generate_panel
                  generate_form={@generate_form}
                  generating_translation_practice={@generating_translation_practice}
                  page_options={@page_options}
                  generate_ai_model_options={@generate_ai_model_options}
                  generate_models_available={@generate_models_available}
                  generate_model_error={@generate_model_error}
                  generate_source_item_label={@generate_source_item_label}
                  generate_output_hint={@generate_output_hint}
                />
              <% @active_drawer == "import" -> %>
                <.import_panel
                  import_form={@import_form}
                  uploads={@uploads}
                  parsing_import={@parsing_import}
                  page_options={@page_options}
                  import_ai_model_options={@import_ai_model_options}
                  import_ocr_model_options={@import_ocr_model_options}
                  import_parse_models_available={@import_parse_models_available}
                  import_parse_model_error={@import_parse_model_error}
                  import_ocr_models_available={@import_ocr_models_available}
                  import_ocr_model_error={@import_ocr_model_error}
                />
              <% true -> %>
                <.flashcards_panel
                  syncing_to_anki={@syncing_to_anki}
                  flashcard_fronts_by_page={@flashcard_fronts_by_page}
                />
            <% end %>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr(:meta_form, :any, required: true)
  attr(:from_target_lang_options, :list, required: true)
  attr(:meta_values, :map, required: true)

  defp unit_options_panel(assigns) do
    ~H"""
    <div id="unit-options-panel">
      <p class="text-xs text-base-content/65">
        Configure language pair and notebook behavior.
      </p>

      <.form
        for={@meta_form}
        id="unit-options-form"
        phx-change="validate_meta"
        class="mt-4 space-y-4"
      >
        <.input
          field={@meta_form[:from_target_lang]}
          type="select"
          label="Language pair"
          options={@from_target_lang_options}
          phx-debounce="250"
        />
        <input type="hidden" name="unit[title]" value={@meta_values["title"]} />
      </.form>

      <section id="unit-quick-help" class="mt-6 rounded-xl border border-base-300 bg-base-200/25 p-4">
        <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
          Quick help
        </h3>
        <ul class="mt-2 space-y-1 text-xs text-base-content/70">
          <li>Enter: child item</li>
          <li>Shift+Enter: newline</li>
          <li>Backspace/Delete on empty: remove item</li>
        </ul>
      </section>
    </div>
    """
  end

  attr(:syncing_to_anki, :boolean, required: true)
  attr(:flashcard_fronts_by_page, :list, required: true)

  defp flashcards_panel(assigns) do
    ~H"""
    <div id="flashcards-panel">
      <div class="flex flex-col items-stretch">
        <.button type="button" phx-click="sync_to_anki" disabled={@syncing_to_anki}>
          <%= if @syncing_to_anki do %>
            <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Syncing...
          <% else %>
            <.icon name="hero-cloud-arrow-up" class="size-4" /> Sync
          <% end %>
        </.button>
      </div>

      <div
        :if={@flashcard_fronts_by_page == []}
        class="mt-4 rounded-xl border border-dashed border-base-300 bg-base-200/20 px-4 py-6 text-center text-sm text-base-content/65"
      >
        Mark an item as flashcard.
      </div>

      <div :if={@flashcard_fronts_by_page != []} class="mt-4 space-y-4">
        <section
          :for={page <- @flashcard_fronts_by_page}
          class="rounded-2xl border border-base-300 bg-base-100 p-3"
        >
          <p class="mb-2 text-sm font-semibold text-base-content">{page.title}</p>
          <ul class="list-disc space-y-1 pl-5 text-sm leading-6 text-base-content">
            <li :for={front <- page.fronts}>
              {if front == "", do: "(empty item)", else: front}
            </li>
          </ul>
        </section>
      </div>
    </div>
    """
  end

  attr(:generate_form, :any, required: true)
  attr(:generating_translation_practice, :boolean, required: true)
  attr(:page_options, :list, required: true)
  attr(:generate_ai_model_options, :list, required: true)
  attr(:generate_models_available, :boolean, required: true)
  attr(:generate_model_error, :string, default: nil)
  attr(:generate_source_item_label, :string, default: nil)
  attr(:generate_output_hint, :string, default: nil)

  defp generate_panel(assigns) do
    ~H"""
    <div id="unit-generate-panel" class="space-y-4">
      <p class="text-xs text-base-content/65">
        Generate notebook-native sentence translation practice with AI.
      </p>

      <div
        :if={!@generate_models_available}
        id="generate-model-unavailable-alert"
        class="alert alert-error"
      >
        <.icon name="hero-exclamation-triangle" class="size-4" />
        <span>
          {@generate_model_error ||
            "No available models for generation. Check provider connection and API key."}
        </span>
      </div>

      <.form
        for={@generate_form}
        id="unit-generate-form"
        phx-change="validate_generate"
        phx-submit="generate_translation_practice"
        class="space-y-3"
      >
        <.input
          field={@generate_form[:type]}
          type="select"
          label="Type"
          options={[{"Translation practice", "translation_practice"}]}
        />

        <.input
          field={@generate_form[:vocabulary]}
          type="text"
          label="Vocabulary"
          placeholder="e.g. 興味（きょうみ）"
          phx-debounce="250"
        />

        <.input
          field={@generate_form[:ai_model]}
          type="select"
          label="AI model"
          options={@generate_ai_model_options}
        />

        <.input
          field={@generate_form[:grammar_page_id]}
          type="select"
          label="Grammar page"
          options={@page_options}
        />

        <.input
          field={@generate_form[:output_mode]}
          type="select"
          label="Output location"
          options={generate_output_mode_options(@generate_source_item_label)}
        />

        <.input
          :if={@generate_form[:output_mode].value == "page_root"}
          field={@generate_form[:output_page_id]}
          type="select"
          label="Output page"
          options={@page_options}
        />

        <p class="rounded-lg border border-base-300 bg-base-200/20 px-3 py-2 text-[11px] text-base-content/70">
          {@generate_output_hint}
        </p>

        <.button
          id="generate-translation-practice-btn"
          type="submit"
          phx-disable-with="Generating..."
          disabled={@generating_translation_practice or not @generate_models_available}
          class="btn btn-primary w-full"
        >
          <%= if @generating_translation_practice do %>
            <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Generating...
          <% else %>
            <.icon name="hero-sparkles" class="size-4" /> Generate with AI
          <% end %>
        </.button>
      </.form>
    </div>
    """
  end

  attr(:import_form, :any, required: true)
  attr(:uploads, :map, required: true)
  attr(:parsing_import, :boolean, required: true)
  attr(:page_options, :list, required: true)
  attr(:import_ai_model_options, :list, required: true)
  attr(:import_ocr_model_options, :list, required: true)
  attr(:import_parse_models_available, :boolean, required: true)
  attr(:import_parse_model_error, :string, default: nil)
  attr(:import_ocr_models_available, :boolean, required: true)
  attr(:import_ocr_model_error, :string, default: nil)

  defp import_panel(assigns) do
    ~H"""
    <div id="unit-import-panel" class="space-y-4">
      <p class="text-xs text-base-content/65">
        Import vocabularies from image OCR or pasted text into a notebook page.
      </p>

      <div
        :if={!@import_parse_models_available}
        id="import-model-unavailable-alert"
        class="alert alert-error"
      >
        <.icon name="hero-exclamation-triangle" class="size-4" />
        <span>
          {@import_parse_model_error ||
            "No available models for import parsing. Check provider connection and API key."}
        </span>
      </div>

      <div
        :if={!@import_ocr_models_available}
        id="import-ocr-model-unavailable-alert"
        class="alert alert-error"
      >
        <.icon name="hero-exclamation-triangle" class="size-4" />
        <span>
          {@import_ocr_model_error ||
            "No available OCR models. You can still import from pasted text without image OCR."}
        </span>
      </div>

      <.form
        for={@import_form}
        id="unit-import-form"
        phx-change="validate_import"
        phx-submit="parse_import"
        class="space-y-3"
      >
        <section class="rounded-xl border border-base-300 bg-base-200/25 p-3">
          <p class="text-[11px] font-semibold uppercase tracking-wide text-base-content/70">
            Image OCR
          </p>
          <div class="mt-2 space-y-2">
            <.live_file_input
              upload={@uploads.import_image}
              class="w-full rounded-lg border border-base-300 bg-base-100 px-2 py-1.5 text-xs text-base-content file:mr-2 file:rounded-md file:border-0 file:bg-primary/15 file:px-2 file:py-1 file:text-xs file:font-medium file:text-primary"
            />
          </div>
        </section>

        <.input
          field={@import_form[:source]}
          type="textarea"
          rows="12"
          label="Source text"
          placeholder="Paste text or OCR output here..."
          phx-debounce="300"
        />

        <div class="rounded-lg border border-base-300 bg-base-200/20 p-2 text-[11px] leading-relaxed text-base-content/65">
          For Japanese from Traditional Chinese, include both Japanese (with kana when available) and
          Traditional Chinese translation.
        </div>

        <.input
          field={@import_form[:ai_model]}
          type="select"
          label="AI model (parse)"
          options={@import_ai_model_options}
        />

        <.input
          field={@import_form[:ocr_model]}
          type="select"
          label="AI model (OCR)"
          options={@import_ocr_model_options}
        />

        <.input
          field={@import_form[:type]}
          type="select"
          label="Import type"
          options={[{"Vocabularies", "vocabularies"}]}
        />

        <.input
          field={@import_form[:page_id]}
          type="select"
          label="Target page"
          options={@page_options}
        />

        <.button
          id="parse-import-btn"
          type="submit"
          phx-disable-with="Importing..."
          disabled={
            not @import_parse_models_available or
              @parsing_import or
              Enum.any?(@uploads.import_image.entries, fn entry -> not entry.done? end)
          }
          class="btn btn-primary w-full"
        >
          <%= if @parsing_import do %>
            <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Importing...
          <% else %>
            <.icon name="hero-sparkles" class="size-4" /> Import with AI
          <% end %>
        </.button>
      </.form>
    </div>
    """
  end

  attr(:node, :map, required: true)
  attr(:page_id, :integer, required: true)
  attr(:path, :list, required: true)
  attr(:parent_front, :boolean, required: true)
  attr(:in_front_branch, :boolean, required: true)
  attr(:actor_id, :string, required: true)
  attr(:item_locks, :map, required: true)

  defp node_editor(assigns) do
    lock_owner_actor_id =
      item_lock_owner(assigns.item_locks, assigns.page_id, path_to_string(assigns.path))

    assigns =
      assigns
      |> assign(:lock_owner_actor_id, lock_owner_actor_id)
      |> assign(
        :locked_by_other,
        is_binary(lock_owner_actor_id) and lock_owner_actor_id != assigns.actor_id
      )

    ~H"""
    <li
      id={"notebook-node-#{@page_id}-#{@node["id"]}"}
      data-dnd-item
      data-page-id={@page_id}
      data-path={path_to_string(@path)}
      data-node-id={@node["id"]}
    >
      <div class="group px-1 py-0.5">
        <div class="flex items-start gap-2">
          <details
            :if={!@locked_by_other}
            id={"item-options-#{@page_id}-#{path_to_dom_id(@path)}"}
            phx-hook="ItemOptionsBubble"
            data-path={path_to_string(@path)}
            data-page-id={@page_id}
            data-node-id={@node["id"]}
            class="relative mt-1"
          >
            <summary
              draggable="true"
              data-dnd-drag-handle
              data-page-id={@page_id}
              data-path={path_to_string(@path)}
              data-node-id={@node["id"]}
              class={[
                "inline-flex size-6 cursor-grab list-none items-center justify-center border text-[11px] font-bold transition marker:hidden active:cursor-grabbing",
                @node["front"] && @node["answer"] &&
                  "rounded-md border-accent/45 bg-accent/15 text-accent",
                @node["front"] && !@node["answer"] &&
                  "rounded-md border-primary/45 bg-primary/15 text-primary",
                !@node["front"] && @node["answer"] &&
                  "rounded-md border-secondary/45 bg-secondary/15 text-secondary",
                !@node["front"] && !@node["answer"] &&
                  "rounded-full border-base-300 text-base-content/60 hover:bg-base-200"
              ]}
              title="Drag to reorder or click for options"
            >
              <%= cond do %>
                <% @node["front"] && @node["answer"] -> %>
                  F
                <% @node["front"] -> %>
                  Q
                <% @node["answer"] -> %>
                  A
                <% true -> %>
                  <span class="size-2 rounded-full border border-base-content/45" />
              <% end %>
            </summary>

            <div class="absolute left-8 top-0 z-20 w-56 rounded-xl border border-base-300 bg-base-100 p-3 shadow-xl">
              <% answer_context = @parent_front or @in_front_branch %>
              <% hide_front_checkbox = !answer_context and Tree.has_front_descendant?(@node) %>
              <% show_answer_checkbox = answer_context or @node["front"] %>

              <div class="mb-3 grid grid-cols-2 gap-2">
                <button
                  type="button"
                  phx-click="item_indent"
                  phx-value-path={path_to_string(@path)}
                  phx-value-node_id={@node["id"]}
                  phx-value-page_id={@page_id}
                  class="inline-flex items-center justify-center gap-1 rounded-md border border-base-300 bg-base-200/35 px-2 py-1 text-xs font-semibold text-base-content transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-40"
                  disabled={!Tree.can_indent_path?(@path)}
                  title="Indent"
                >
                  <.icon name="hero-chevron-right" class="size-3.5" /> Indent
                </button>

                <button
                  type="button"
                  phx-click="item_outdent"
                  phx-value-path={path_to_string(@path)}
                  phx-value-node_id={@node["id"]}
                  phx-value-page_id={@page_id}
                  class="inline-flex items-center justify-center gap-1 rounded-md border border-base-300 bg-base-200/35 px-2 py-1 text-xs font-semibold text-base-content transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-40"
                  disabled={!Tree.can_outdent_path?(@path)}
                  title="Unindent"
                >
                  <.icon name="hero-chevron-left" class="size-3.5" /> Unindent
                </button>
              </div>

              <%= if !answer_context do %>
                <%= if hide_front_checkbox do %>
                  <p
                    id={"flashcard-disabled-hint-#{@page_id}-#{path_to_dom_id(@path)}"}
                    class="mb-2 text-[11px] text-base-content/60"
                  >
                    Has flashcard children.
                  </p>
                <% else %>
                  <label class="mb-2 flex cursor-pointer items-center gap-2 text-xs font-medium text-base-content">
                    <input
                      type="checkbox"
                      checked={@node["front"]}
                      phx-click="toggle_item_flag"
                      phx-value-path={path_to_string(@path)}
                      phx-value-node_id={@node["id"]}
                      phx-value-page_id={@page_id}
                      phx-value-flag="front"
                      class="checkbox checkbox-xs"
                    /> Flashcard
                  </label>
                <% end %>
              <% end %>

              <%= if show_answer_checkbox do %>
                <label class="mb-2 flex cursor-pointer items-center gap-2 text-xs font-medium text-base-content">
                  <input
                    type="checkbox"
                    checked={@node["answer"]}
                    phx-click="toggle_item_flag"
                    phx-value-path={path_to_string(@path)}
                    phx-value-node_id={@node["id"]}
                    phx-value-page_id={@page_id}
                    phx-value-flag="answer"
                    class="checkbox checkbox-xs"
                  /> Answer
                </label>
              <% end %>

              <button
                id={"generate-from-item-#{@page_id}-#{path_to_dom_id(@path)}"}
                type="button"
                phx-click="open_generate_from_item"
                phx-value-page_id={@page_id}
                phx-value-node_id={@node["id"]}
                class="mb-2 inline-flex w-full items-center justify-center gap-1 rounded-md border border-primary/35 bg-primary/10 px-2 py-1 text-xs font-semibold text-primary transition hover:bg-primary/15"
              >
                <.icon name="hero-sparkles" class="size-3.5" /> Generate
              </button>

              <form phx-change="edit_node_link" class="space-y-1">
                <input type="hidden" name="path" value={path_to_string(@path)} />
                <input type="hidden" name="node_id" value={@node["id"]} />
                <input type="hidden" name="page_id" value={@page_id} />
                <label class="block text-[11px] font-semibold uppercase tracking-wide text-base-content/55">
                  Link
                </label>
                <input
                  type="url"
                  name="link"
                  value={@node["link"]}
                  placeholder="https://..."
                  phx-debounce="250"
                  class="w-full rounded-lg border border-base-300 bg-base-100 px-2 py-1.5 text-xs text-base-content outline-hidden transition focus:border-primary"
                />
              </form>
            </div>
          </details>

          <div
            :if={@locked_by_other}
            id={"item-locked-badge-#{@page_id}-#{path_to_dom_id(@path)}"}
            class="mt-1 inline-flex size-6 items-center justify-center rounded-full border border-info/40 bg-info/12 text-info"
            title="Another collaborator is editing"
          >
            <.icon name="hero-ellipsis-horizontal" class="size-4 animate-pulse" />
          </div>

          <div class="flex min-w-56 grow items-start gap-2">
            <form phx-change="edit_node_text" class="grow">
              <input type="hidden" name="path" value={path_to_string(@path)} />
              <input type="hidden" name="node_id" value={@node["id"]} />
              <input type="hidden" name="page_id" value={@page_id} />
              <textarea
                id={"item-input-#{@page_id}-#{path_to_dom_id(@path)}"}
                name="text"
                rows="1"
                data-path={path_to_string(@path)}
                data-node-id={@node["id"]}
                data-page-id={@page_id}
                disabled={@locked_by_other}
                phx-hook="NotebookItem"
                placeholder="Write item..."
                class={[
                  "field-sizing-content min-h-8 w-full resize-none overflow-hidden border-0 border-b border-base-content/30 bg-transparent px-1.5 py-1 text-sm leading-6 text-base-content outline-hidden transition focus:border-primary/45",
                  external_link?(@node["link"]) &&
                    "underline decoration-base-content/55 underline-offset-2"
                ]}
              >{@node["text"]}</textarea>
            </form>

            <a
              :if={external_link?(@node["link"])}
              href={@node["link"]}
              target="_blank"
              rel="noopener noreferrer"
              class="mt-1 inline-flex size-7 shrink-0 items-center justify-center rounded-md border border-base-300 text-base-content/70 transition hover:border-primary/40 hover:bg-primary/10 hover:text-primary"
              title="Open external link"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            </a>
          </div>
        </div>
      </div>

      <ul :if={@node["children"] != []} class="space-y-2 pl-5 pt-2">
        <.node_editor
          :for={{child, child_idx} <- Enum.with_index(@node["children"])}
          node={child}
          page_id={@page_id}
          path={@path ++ [child_idx]}
          parent_front={@node["front"]}
          in_front_branch={@in_front_branch or @node["front"]}
          actor_id={@actor_id}
          item_locks={@item_locks}
        />
      </ul>
    </li>
    """
  end

  @impl true
  def handle_event("validate_meta", %{"unit" => unit_params}, socket) do
    changeset = Learning.change_unit(socket.assigns.unit, unit_params)

    socket =
      socket
      |> assign(:meta_form, to_form(changeset, action: :validate))
      |> assign(:meta_values, %{
        "title" => unit_params["title"],
        "from_target_lang" => unit_params["from_target_lang"]
      })

    if changeset.valid? do
      {:noreply, queue_auto_save_unit(socket, unit_params)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_drawer", %{"panel" => panel}, socket)
      when panel in ["flashcards", "generate", "options", "import"] do
    active_drawer = if socket.assigns.active_drawer == panel, do: nil, else: panel

    socket =
      if panel == "generate" and active_drawer == "generate" do
        socket
        |> assign(:generate_source_item, nil)
        |> assign_generate_values(%{"output_mode" => "page_root"})
      else
        socket
      end

    {:noreply, assign(socket, :active_drawer, active_drawer)}
  end

  def handle_event("close_drawer", _params, socket) do
    {:noreply, assign(socket, :active_drawer, nil)}
  end

  def handle_event("validate_import", %{"import" => import_params}, socket) do
    {:noreply, assign_import_values(socket, import_params)}
  end

  def handle_event("open_generate_from_item", params, socket) do
    with {:ok, page_id} <- parse_page_id(Map.get(params, "page_id")),
         state when not is_nil(state) <- Map.get(socket.assigns.page_states, page_id),
         node_id when is_binary(node_id) and node_id != "" <- Map.get(params, "node_id"),
         path when is_list(path) <- Tree.path_for_id(state.nodes, node_id),
         node when not is_nil(node) <- Tree.get_node(state.nodes, path) do
      vocabulary = String.trim(node["text"] || "")

      {:noreply,
       socket
       |> assign(:active_drawer, "generate")
       |> assign(:generate_source_item, %{page_id: page_id, node_id: node_id})
       |> assign_generate_values(%{
         "vocabulary" => vocabulary,
         "output_mode" => "source_item",
         "output_page_id" => to_string(page_id)
       })}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot open generator from this item")}
    end
  end

  def handle_event("validate_generate", %{"generate" => generate_params}, socket) do
    {:noreply, assign_generate_values(socket, generate_params)}
  end

  def handle_event("generate_translation_practice", %{"generate" => generate_params}, socket) do
    socket =
      socket
      |> assign_generate_values(generate_params)
      |> assign(:generating_translation_practice, true)

    vocabulary = String.trim(socket.assigns.generate_values["vocabulary"] || "")

    with "translation_practice" <- socket.assigns.generate_values["type"],
         true <- vocabulary != "",
         {:ok, provider, model} <- selected_generate_ai_model(socket),
         {:ok, grammar_page_id} <- selected_generate_grammar_page_id(socket),
         {:ok, grammar_context} <- random_deepest_grammar_branch(socket, grammar_page_id),
         {:ok, generated} <-
           translation_practice_generator_module().generate_translation_practice(
             vocabulary,
             grammar_context,
             socket.assigns.unit.from_target_lang,
             provider: provider,
             model: model
           ),
         {:ok, translation_from, translation_target} <- normalize_translation_result(generated),
         {:ok, output_page_id} <- selected_generate_output_page_id(socket) do
      generated_node = translation_practice_node(translation_from, translation_target)

      {:noreply,
       socket
       |> insert_generated_translation_practice(generated_node, output_page_id)
       |> assign(:generating_translation_practice, false)
       |> put_flash(:info, "Generated translation practice")}
    else
      false ->
        {:noreply,
         socket
         |> assign(:generating_translation_practice, false)
         |> put_flash(:error, "Vocabulary is required")}

      :error ->
        {:noreply,
         socket
         |> assign(:generating_translation_practice, false)
         |> put_flash(:error, "Unsupported generate type")}

      {:error, :empty_grammar_page} ->
        {:noreply,
         socket
         |> assign(:generating_translation_practice, false)
         |> put_flash(:error, "Selected grammar page has no usable items")}

      {:error, reason} when reason in [:missing_model, :invalid_model] ->
        {:noreply,
         socket
         |> assign(:generating_translation_practice, false)
         |> put_flash(:error, selected_model_error_message(reason))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:generating_translation_practice, false)
         |> put_flash(:error, "Failed to generate translation practice: #{inspect(reason)}")}

      _ ->
        {:noreply,
         socket
         |> assign(:generating_translation_practice, false)
         |> put_flash(:error, "Failed to generate translation practice")}
    end
  end

  def handle_event("parse_import", %{"import" => import_params}, socket) do
    socket =
      socket
      |> assign_import_values(import_params)
      |> assign(:parsing_import, true)

    source = String.trim(socket.assigns.import_values["source"] || "")

    has_pending_upload? =
      Enum.any?(socket.assigns.uploads.import_image.entries, fn entry -> not entry.done? end)

    if has_pending_upload? do
      {:noreply,
       socket
       |> assign(:parsing_import, false)
       |> put_flash(:error, "Image is still uploading")}
    else
      case consume_import_image_ocr(socket) do
        {:ok, socket, ocr_text} ->
          combined_source = ShowEditImportHelpers.combine_source_text(source, ocr_text)

          if combined_source == "" do
            {:noreply,
             socket
             |> assign(:parsing_import, false)
             |> put_flash(:error, "Enter source text or upload image before parsing")}
          else
            parse_import_source(socket, combined_source)
          end

        {:error, socket, reason} ->
          {:noreply,
           socket
           |> assign(:parsing_import, false)
           |> put_flash(:error, "OCR failed: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("item_lock_acquire", params, socket) do
    case parse_item_lock_target(params, socket) do
      {:ok, page_id, node_id} ->
        case ItemLockRegistry.acquire(
               socket.assigns.unit.id,
               page_id,
               node_id,
               socket.assigns.actor_id
             ) do
          :acquired ->
            {:noreply,
             socket
             |> refresh_item_locks()
             |> broadcast_item_locks_changed()}

          :renewed ->
            {:noreply, refresh_item_locks(socket)}

          {:locked, _owner_actor_id} ->
            {:noreply, refresh_item_locks(socket)}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("item_lock_heartbeat", params, socket) do
    case parse_item_lock_target(params, socket) do
      {:ok, page_id, node_id} ->
        _ =
          ItemLockRegistry.heartbeat(
            socket.assigns.unit.id,
            page_id,
            node_id,
            socket.assigns.actor_id
          )

        {:noreply, socket}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("item_lock_release", params, socket) do
    case parse_item_lock_target(params, socket) do
      {:ok, page_id, node_id} ->
        case ItemLockRegistry.release(
               socket.assigns.unit.id,
               page_id,
               node_id,
               socket.assigns.actor_id
             ) do
          :released ->
            {:noreply,
             socket
             |> refresh_item_locks()
             |> broadcast_item_locks_changed()}

          :noop ->
            {:noreply, refresh_item_locks(socket)}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("add_page", _params, socket) do
    attrs = %{
      "unit_id" => socket.assigns.unit.id,
      "title" => "Page #{length(socket.assigns.unit.pages) + 1}",
      "items" => [Tree.new_node()]
    }

    case Learning.create_page(attrs) do
      {:ok, _page} ->
        unit = Learning.get_unit!(socket.assigns.unit.id)

        {:noreply,
         socket
         |> assign(:unit, unit)
         |> assign(:page_states, build_page_states(unit, socket.assigns.page_states))
         |> sync_import_page_selection(unit)
         |> sync_generate_page_selection(unit)
         |> broadcast_unit_pages_changed("add")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add page")}
    end
  end

  def handle_event("delete_page", %{"page_id" => page_id}, socket) do
    page_id = String.to_integer(page_id)
    page = Enum.find(socket.assigns.unit.pages, fn candidate -> candidate.id == page_id end)

    if is_nil(page) do
      {:noreply, socket}
    else
      if length(socket.assigns.unit.pages) <= 1 do
        {:noreply, put_flash(socket, :error, "A unit must have at least one page")}
      else
        case Learning.delete_page(page) do
          {:ok, _page} ->
            unit = Learning.get_unit!(socket.assigns.unit.id)
            _ = ItemLockRegistry.release_page(socket.assigns.unit.id, page.id)
            _ = PageVersionRegistry.drop_page(socket.assigns.unit.id, page_version_key(page))

            {:noreply,
             socket
             |> clear_page_pending_save(page.id)
             |> assign(:unit, unit)
             |> assign(:page_states, drop_page_state(socket.assigns.page_states, page.id))
             |> sync_import_page_selection(unit)
             |> sync_generate_page_selection(unit)
             |> refresh_item_locks()
             |> refresh_unsaved_flag()
             |> broadcast_item_locks_changed()
             |> broadcast_unit_pages_changed("delete")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to delete page")}
        end
      end
    end
  end

  def handle_event("move_page", %{"page_id" => page_id, "direction" => direction}, socket) do
    page_id = String.to_integer(page_id)
    page = Enum.find(socket.assigns.unit.pages, fn candidate -> candidate.id == page_id end)

    if is_nil(page) do
      {:noreply, socket}
    else
      direction = if direction == "up", do: :up, else: :down

      case Learning.move_page(page, direction) do
        {:ok, :moved} ->
          unit = Learning.get_unit!(socket.assigns.unit.id)

          {:noreply,
           socket
           |> assign(:unit, unit)
           |> assign(:page_states, build_page_states(unit, socket.assigns.page_states))
           |> sync_import_page_selection(unit)
           |> sync_generate_page_selection(unit)
           |> broadcast_unit_pages_changed("reorder")}

        {:error, :boundary} ->
          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to move page")}
      end
    end
  end

  def handle_event("validate_page", %{"page_id" => page_id, "page" => page_params}, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      attrs = Map.put(page_params, "items", state.nodes)
      changeset = Learning.change_page(page, attrs)

      socket =
        update_page_state(socket, page.id, fn current ->
          current
          |> Map.put(:form, to_form(changeset, action: :validate))
          |> Map.put(:title, page_params["title"])
        end)

      if changeset.valid? do
        queue_auto_save_page(socket, page.id, attrs)
      else
        socket
      end
    end)
  end

  def handle_event(
        "edit_node_text",
        %{"text" => text, "page_id" => page_id} = params,
        socket
      ) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {:edit_text, editor_target(params), text})
    end)
  end

  def handle_event(
        "edit_node_link",
        %{"link" => link, "page_id" => page_id} = params,
        socket
      ) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {:edit_link, editor_target(params), link})
    end)
  end

  def handle_event(
        "toggle_item_flag",
        %{"flag" => flag, "page_id" => page_id} = params,
        socket
      ) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {:toggle_flag, editor_target(params), flag})
    end)
  end

  def handle_event("item_enter", %{"page_id" => page_id} = params, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {
        :item_enter,
        editor_target(params),
        params["text"]
      })
    end)
  end

  def handle_event("item_delete_empty", %{"page_id" => page_id} = params, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {
        :item_delete_empty,
        editor_target(params),
        params["text"]
      })
    end)
  end

  def handle_event("item_enter", params, socket) do
    handle_event("item_enter", Map.put(params, "page_id", default_page_id(socket)), socket)
  end

  def handle_event("item_delete_empty", params, socket) do
    handle_event("item_delete_empty", Map.put(params, "page_id", default_page_id(socket)), socket)
  end

  def handle_event("item_indent", %{"page_id" => page_id} = params, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {
        :item_indent,
        editor_target(params),
        params["text"]
      })
    end)
  end

  def handle_event("item_indent", params, socket) do
    handle_event("item_indent", Map.put(params, "page_id", default_page_id(socket)), socket)
  end

  def handle_event("item_outdent", %{"page_id" => page_id} = params, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {
        :item_outdent,
        editor_target(params),
        params["text"]
      })
    end)
  end

  def handle_event("item_outdent", params, socket) do
    handle_event("item_outdent", Map.put(params, "page_id", default_page_id(socket)), socket)
  end

  def handle_event("add_child", %{"page_id" => page_id} = params, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {:add_child, editor_target(params)})
    end)
  end

  def handle_event("add_sibling", %{"page_id" => page_id} = params, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {:add_sibling, editor_target(params)})
    end)
  end

  def handle_event("remove_node", %{"page_id" => page_id} = params, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, {:remove_node, editor_target(params)})
    end)
  end

  def handle_event("append_root", %{"page_id" => page_id}, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      apply_local_editor_command(socket, page, state, :append_root)
    end)
  end

  def handle_event("add_root_item", %{"page_id" => page_id, "position" => position}, socket) do
    with_page_state(socket, page_id, fn socket, page, state ->
      case position do
        "first" ->
          apply_local_editor_command(
            socket,
            page,
            state,
            {:insert_node, %{"parent_path" => [], "index" => 0}, Tree.new_node()}
          )

        "last" ->
          apply_local_editor_command(socket, page, state, :append_root)

        _ ->
          socket
      end
    end)
  end

  def handle_event("move_item", params, socket) do
    {:noreply, move_item(socket, params)}
  end

  def handle_event("sync_to_anki", _params, socket) do
    send(self(), :sync_to_anki_async)
    {:noreply, assign(socket, :syncing_to_anki, true)}
  end

  @impl true
  def handle_info({:notebook_operation, operation}, socket) do
    {:noreply, maybe_apply_remote_operation(socket, operation)}
  end

  @impl true
  def handle_info({:unit_pages_changed, message}, socket) do
    {:noreply, maybe_apply_remote_pages_changed(socket, message)}
  end

  @impl true
  def handle_info({:unit_meta_changed, message}, socket) do
    {:noreply, maybe_apply_remote_unit_meta_changed(socket, message)}
  end

  @impl true
  def handle_info({:item_locks_changed, %{unit_id: unit_id}}, socket)
      when unit_id == socket.assigns.unit.id do
    {:noreply, refresh_item_locks(socket)}
  end

  @impl true
  def handle_info({:item_locks_changed, _message}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:auto_save_unit, socket) do
    :ok = UnitSession.flush_unit(socket.assigns.unit.id)
    {:noreply, refresh_unsaved_flag(socket)}
  end

  @impl true
  def handle_info({:auto_save_page, page_id}, socket) do
    :ok = UnitSession.flush_page(socket.assigns.unit.id, page_id)
    {:noreply, refresh_unsaved_flag(socket)}
  end

  @impl true
  def handle_info(:unit_session_heartbeat, socket) do
    {:noreply, touch_unit_session(socket)}
  end

  @impl true
  def handle_info(:sync_to_anki_async, socket) do
    unit_id = socket.assigns.unit.id

    socket =
      with {:ok, _} <- SyncService.full_download_from_server(),
           {:ok, %{synced_count: count, deck_name: deck_name}} <-
             SyncService.sync_unit_to_anki(unit_id),
           {:ok, %{"status" => status}} <- SyncService.sync_to_server() do
        put_flash(
          socket,
          :info,
          "Synced #{count} notebook flashcard(s) to '#{deck_name}', server sync: #{status}"
        )
      else
        {:error, reason} ->
          put_flash(socket, :error, "Failed to sync to Anki: #{inspect(reason)}")
      end

    {:noreply, assign(socket, :syncing_to_anki, false)}
  end

  @impl true
  def terminate(_reason, socket) do
    has_lock_context? =
      Map.has_key?(socket.assigns, :unit) and Map.has_key?(socket.assigns, :actor_id)

    if has_lock_context? and
         ItemLockRegistry.release_actor(socket.assigns.unit.id, socket.assigns.actor_id) do
      Phoenix.PubSub.broadcast(
        Gakugo.PubSub,
        notebook_topic(socket.assigns.unit.id),
        {:item_locks_changed, %{unit_id: socket.assigns.unit.id}}
      )
    end

    :ok
  end

  defp touch_unit_session(socket) do
    :ok = UnitSession.heartbeat(socket.assigns.unit.id, socket.assigns.actor_id)
    Process.send_after(self(), :unit_session_heartbeat, @unit_session_heartbeat_ms)
    socket
  end

  defp ensure_unit_has_page(unit) do
    if unit.pages == [] do
      {:ok, _page} =
        Learning.create_page(%{
          "unit_id" => unit.id,
          "title" => "Page 1",
          "items" => [Tree.new_node()]
        })

      Learning.get_unit!(unit.id)
    else
      unit
    end
  end

  defp move_item(socket, params) when is_map(params) do
    ShowEditMoveHelpers.move_item(socket, params,
      parse_page_id: &parse_page_id/1,
      page_by_id: &page_by_id/2,
      normalize_path: &normalize_path/1,
      apply_local_editor_command_with_result: &apply_local_editor_command_with_result/4
    )
  end

  defp move_item(socket, _params), do: socket

  defp update_nodes_and_queue_save(socket, page_id, nodes, focus_path, version) do
    attrs = current_page_attrs(socket, page_id, nodes)

    socket
    |> update_page_state(page_id, fn state ->
      state
      |> Map.put(:nodes, nodes)
      |> maybe_put_page_version(version)
    end)
    |> maybe_focus_item(page_id, focus_path)
    |> queue_auto_save_page(page_id, attrs)
  end

  defp maybe_put_page_version(state, nil), do: state
  defp maybe_put_page_version(state, version), do: Map.put(state, :version, version)

  defp apply_local_editor_command(socket, page, state, command) do
    {_status, next_socket} = apply_local_editor_command_with_result(socket, page, state, command)
    next_socket
  end

  defp apply_local_editor_command_with_result(socket, page, state, command) do
    case UnitSession.apply_intent(
           socket.assigns.unit.id,
           socket.assigns.actor_id,
           page.id,
           page_version_key(page),
           state.nodes,
           state.version,
           command
         ) do
      {:ok, %{operation: operation, nodes: nodes, focus_path: focus_path, version: version}} ->
        next_socket =
          socket
          |> remember_seen_operation(operation.op_id)
          |> update_nodes_and_queue_save(page.id, nodes, focus_path, version)
          |> broadcast_notebook_operation(operation)

        {:ok, next_socket}

      :blocked ->
        {:blocked, refresh_item_locks(socket)}

      :noop ->
        {:noop, socket}

      :error ->
        {:error, socket}
    end
  end

  defp broadcast_notebook_operation(socket, operation) do
    Phoenix.PubSub.broadcast(
      Gakugo.PubSub,
      notebook_topic(socket.assigns.unit.id),
      {:notebook_operation, operation}
    )

    socket
  end

  defp notebook_topic(unit_id), do: "unit:notebook:#{unit_id}"

  defp broadcast_item_locks_changed(socket) do
    Phoenix.PubSub.broadcast(
      Gakugo.PubSub,
      notebook_topic(socket.assigns.unit.id),
      {:item_locks_changed, %{unit_id: socket.assigns.unit.id}}
    )

    socket
  end

  defp broadcast_unit_pages_changed(socket, action) do
    message = %{
      unit_id: socket.assigns.unit.id,
      actor_id: socket.assigns.actor_id,
      op_id: Ecto.UUID.generate(),
      action: action
    }

    Phoenix.PubSub.broadcast(
      Gakugo.PubSub,
      notebook_topic(socket.assigns.unit.id),
      {:unit_pages_changed, message}
    )

    socket
  end

  defp maybe_apply_remote_pages_changed(socket, %{unit_id: unit_id})
       when unit_id != socket.assigns.unit.id,
       do: socket

  defp maybe_apply_remote_pages_changed(socket, %{actor_id: actor_id})
       when actor_id == socket.assigns.actor_id,
       do: socket

  defp maybe_apply_remote_pages_changed(socket, %{op_id: op_id}) do
    if seen_operation?(socket, op_id) do
      socket
    else
      socket = remember_seen_operation(socket, op_id)
      unit = Learning.get_unit!(socket.assigns.unit.id)

      socket
      |> assign(:unit, unit)
      |> assign(:page_states, build_page_states(unit, socket.assigns.page_states))
      |> sync_import_page_selection(unit)
      |> sync_generate_page_selection(unit)
      |> refresh_item_locks()
      |> prune_page_auto_save_state(unit)
      |> refresh_unsaved_flag()
    end
  end

  defp maybe_apply_remote_pages_changed(socket, _message), do: socket

  defp maybe_apply_remote_unit_meta_changed(socket, %{unit_id: unit_id})
       when unit_id != socket.assigns.unit.id,
       do: socket

  defp maybe_apply_remote_unit_meta_changed(socket, %{op_id: op_id}) do
    if seen_operation?(socket, op_id) do
      socket
    else
      socket = remember_seen_operation(socket, op_id)
      unit = Learning.get_unit!(socket.assigns.unit.id)

      socket
      |> assign(:unit, unit)
      |> assign(:meta_form, to_form(Learning.change_unit(unit)))
      |> assign(:meta_values, %{
        "title" => unit.title,
        "from_target_lang" => unit.from_target_lang
      })
      |> assign(:page_states, build_page_states_from_db(unit, socket.assigns.page_states))
      |> sync_import_page_selection(unit)
      |> sync_generate_page_selection(unit)
      |> refresh_item_locks()
      |> prune_page_auto_save_state(unit)
      |> refresh_unsaved_flag()
    end
  end

  defp maybe_apply_remote_unit_meta_changed(socket, _message), do: socket

  defp maybe_apply_remote_operation(socket, %{unit_id: unit_id})
       when unit_id != socket.assigns.unit.id,
       do: socket

  defp maybe_apply_remote_operation(socket, %{actor_id: actor_id})
       when actor_id == socket.assigns.actor_id,
       do: socket

  defp maybe_apply_remote_operation(socket, %{op_id: op_id} = operation) do
    if seen_operation?(socket, op_id) do
      socket
    else
      apply_remote_operation(socket, operation)
    end
  end

  defp maybe_apply_remote_operation(socket, _operation), do: socket

  defp apply_remote_operation(socket, operation) do
    with {:ok, page_id} <- parse_page_id(operation.page_id),
         page when not is_nil(page) <- page_by_id(socket.assigns.unit, page_id),
         state when not is_nil(state) <- Map.get(socket.assigns.page_states, page_id) do
      operation_version = operation.version
      base_version = operation.base_version

      socket = remember_seen_operation(socket, operation.op_id)

      _ =
        PageVersionRegistry.observe(
          socket.assigns.unit.id,
          page_version_key(page),
          operation_version
        )

      cond do
        operation_version <= state.version ->
          socket

        base_version > state.version ->
          apply_remote_snapshot_or_reducer(socket, page.id, operation)

        true ->
          apply_remote_reducer_or_snapshot(socket, page.id, operation)
      end
    else
      _ ->
        socket
    end
  end

  defp reconcile_page_state(socket, page_id, min_version \\ nil) do
    try do
      page = Learning.get_page!(page_id)

      update_page_state(socket, page_id, fn state ->
        %{
          title: page.title,
          nodes: Tree.normalize_nodes(page.items),
          form: to_form(Learning.change_page(page)),
          version: reconciled_page_version(state.version, min_version)
        }
      end)
    rescue
      Ecto.NoResultsError ->
        socket
    end
  end

  defp reconciled_page_version(current_version, nil), do: current_version

  defp reconciled_page_version(current_version, min_version),
    do: max(current_version, min_version)

  defp apply_remote_snapshot_or_reducer(socket, page_id, operation) do
    case operation_snapshot_nodes(operation) do
      {:ok, nodes} ->
        update_nodes_and_queue_save(socket, page_id, nodes, nil, operation.version)

      :error ->
        socket
        |> reconcile_page_state(page_id, operation.base_version)
        |> apply_remote_reducer_or_snapshot(page_id, operation)
    end
  end

  defp apply_remote_reducer_or_snapshot(socket, page_id, operation) do
    operation_version = operation.version
    state = Map.get(socket.assigns.page_states, page_id)

    if is_nil(state) do
      socket
    else
      case Editor.apply(state.nodes, operation.command) do
        {:ok, result} ->
          update_nodes_and_queue_save(socket, page_id, result.nodes, nil, operation_version)

        :noop ->
          apply_remote_snapshot_fallback(socket, page_id, operation)

        :error ->
          apply_remote_snapshot_fallback(socket, page_id, operation)
      end
    end
  end

  defp apply_remote_snapshot_fallback(socket, page_id, operation) do
    case operation_snapshot_nodes(operation) do
      {:ok, nodes} ->
        update_nodes_and_queue_save(socket, page_id, nodes, nil, operation.version)

      :error ->
        reconcile_page_state(socket, page_id)
    end
  end

  defp operation_snapshot_nodes(%{nodes: nodes}) when is_list(nodes), do: {:ok, nodes}
  defp operation_snapshot_nodes(_operation), do: :error

  defp parse_page_id(page_id) when is_integer(page_id), do: {:ok, page_id}

  defp parse_page_id(page_id) when is_binary(page_id) do
    case Integer.parse(page_id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_page_id(_page_id), do: :error

  defp seen_operation?(socket, op_id), do: MapSet.member?(socket.assigns.seen_op_ids, op_id)

  defp remember_seen_operation(socket, op_id) do
    if seen_operation?(socket, op_id) do
      socket
    else
      seen_op_ids = MapSet.put(socket.assigns.seen_op_ids, op_id)
      seen_op_order = :queue.in(op_id, socket.assigns.seen_op_order)
      {seen_op_ids, seen_op_order} = trim_seen_operations(seen_op_ids, seen_op_order)

      socket
      |> assign(:seen_op_ids, seen_op_ids)
      |> assign(:seen_op_order, seen_op_order)
    end
  end

  defp trim_seen_operations(seen_op_ids, seen_op_order) do
    if :queue.len(seen_op_order) <= @max_seen_ops do
      {seen_op_ids, seen_op_order}
    else
      {{:value, removed_op_id}, seen_op_order} = :queue.out(seen_op_order)
      trim_seen_operations(MapSet.delete(seen_op_ids, removed_op_id), seen_op_order)
    end
  end

  defp maybe_focus_item(socket, _page_id, nil), do: socket

  defp maybe_focus_item(socket, page_id, path) do
    push_event(socket, "focus-item", %{path: path_to_string(path), page_id: page_id})
  end

  defp current_page_attrs(socket, page_id, nodes) do
    page_state = page_state(socket, page_id)

    %{
      "title" => page_state.title,
      "items" => nodes
    }
  end

  defp queue_auto_save_unit(socket, attrs) do
    :ok =
      UnitSession.queue_unit_save(
        socket.assigns.unit.id,
        attrs,
        socket.assigns.actor_id,
        @auto_save_ms
      )

    socket
    |> refresh_unsaved_flag()
  end

  defp queue_auto_save_page(socket, page_id, attrs) do
    :ok =
      UnitSession.queue_page_save(
        socket.assigns.unit.id,
        page_id,
        attrs,
        socket.assigns.actor_id,
        @auto_save_ms
      )

    socket
    |> refresh_unsaved_flag()
  end

  defp clear_page_pending_save(socket, page_id) do
    :ok = UnitSession.clear_page_save(socket.assigns.unit.id, page_id)

    socket
    |> refresh_unsaved_flag()
  end

  defp prune_page_auto_save_state(socket, unit) do
    existing_page_ids = Enum.map(unit.pages, & &1.id)
    :ok = UnitSession.prune_page_saves(socket.assigns.unit.id, existing_page_ids)
    socket
  end

  defp refresh_unsaved_flag(socket) do
    has_unsaved_changes = UnitSession.unsaved_changes?(socket.assigns.unit.id)

    assign(socket, :has_unsaved_changes, has_unsaved_changes)
  end

  defp parse_item_lock_target(%{"page_id" => page_id, "path" => path}, _socket)
       when is_binary(path) do
    with {:ok, parsed_page_id} <- parse_page_id(page_id),
         lock_path when is_binary(lock_path) <- normalize_lock_path(path) do
      {:ok, parsed_page_id, lock_path}
    else
      _ -> :error
    end
  end

  defp parse_item_lock_target(%{"page_id" => page_id, "node_id" => node_id}, socket)
       when is_binary(node_id) and node_id != "" do
    with {:ok, parsed_page_id} <- parse_page_id(page_id),
         state when not is_nil(state) <- Map.get(socket.assigns.page_states, parsed_page_id),
         path when is_list(path) <- Tree.path_for_id(state.nodes, node_id) do
      {:ok, parsed_page_id, path_to_string(path)}
    else
      _ -> :error
    end
  end

  defp parse_item_lock_target(_params, _socket), do: :error

  defp refresh_item_locks(socket) do
    assign(socket, :item_locks, ItemLockRegistry.locks_for_unit(socket.assigns.unit.id))
  end

  defp item_lock_owner(item_locks, page_id, lock_path)
       when is_integer(page_id) and is_binary(lock_path) do
    Map.get(item_locks, {page_id, lock_path})
  end

  defp item_lock_owner(_item_locks, _page_id, _lock_path), do: nil

  defp normalize_lock_path(path) when is_binary(path) do
    trimmed_path = String.trim(path)

    cond do
      trimmed_path == "" ->
        nil

      numeric_lock_path?(trimmed_path) ->
        case normalize_path(trimmed_path) do
          [] -> nil
          normalized_path -> path_to_string(normalized_path)
        end

      named_lock_path?(trimmed_path) ->
        trimmed_path

      true ->
        nil
    end
  end

  defp numeric_lock_path?(path), do: Regex.match?(~r/^\d+(\.\d+)*$/, path)
  defp named_lock_path?(path), do: Regex.match?(~r/^[a-zA-Z0-9_.:-]+$/, path)

  defp normalize_path(path) when is_binary(path) do
    Enum.reduce_while(String.split(path, ".", trim: true), [], fn segment, acc ->
      case Integer.parse(segment) do
        {index, ""} when index >= 0 -> {:cont, [index | acc]}
        _ -> {:halt, []}
      end
    end)
    |> Enum.reverse()
  end

  defp normalize_path(path) when is_list(path) do
    if Enum.all?(path, &(is_integer(&1) and &1 >= 0)), do: path, else: []
  end

  defp normalize_path(_path), do: []

  defp editor_target(%{"node_id" => node_id, "path" => path}) do
    %{"node_id" => node_id, "path" => path}
  end

  defp editor_target(%{"node_id" => node_id}) do
    %{"node_id" => node_id}
  end

  defp editor_target(%{"path" => path}), do: path

  defp editor_target(_params), do: nil

  defp path_to_string(path), do: Enum.join(path, ".")

  defp path_to_dom_id(path), do: Enum.join(path, "-")

  defp drawer_title(panel), do: ShowEditFormHelpers.drawer_title(panel)

  defp page_options(assigns), do: ShowEditFormHelpers.page_options(assigns)

  defp generate_output_mode_options(source_item_label),
    do: ShowEditFormHelpers.generate_output_mode_options(source_item_label)

  defp generate_source_item_label(assigns),
    do: ShowEditFormHelpers.generate_source_item_label(assigns)

  defp generate_output_hint(assigns), do: ShowEditFormHelpers.generate_output_hint(assigns)

  defp assign_import_values(socket, params),
    do: ShowEditFormHelpers.assign_import_values(socket, params)

  defp sync_import_page_selection(socket, unit),
    do: ShowEditFormHelpers.sync_import_page_selection(socket, unit)

  defp selected_import_page_id(socket), do: ShowEditFormHelpers.selected_import_page_id(socket)

  defp assign_generate_values(socket, params),
    do: ShowEditFormHelpers.assign_generate_values(socket, params)

  defp sync_generate_page_selection(socket, unit),
    do: ShowEditFormHelpers.sync_generate_page_selection(socket, unit)

  defp selected_generate_grammar_page_id(socket),
    do: ShowEditFormHelpers.selected_generate_grammar_page_id(socket)

  defp selected_generate_output_page_id(socket),
    do: ShowEditFormHelpers.selected_generate_output_page_id(socket)

  defp random_deepest_grammar_branch(socket, grammar_page_id) do
    ShowEditGenerateHelpers.random_deepest_grammar_branch(
      socket.assigns.page_states,
      grammar_page_id
    )
  end

  defp normalize_translation_result(%{"translation_from" => from, "translation_target" => target})
       when is_binary(from) and is_binary(target) do
    ShowEditGenerateHelpers.normalize_translation_result(%{
      "translation_from" => from,
      "translation_target" => target
    })
  end

  defp normalize_translation_result(_result),
    do: ShowEditGenerateHelpers.normalize_translation_result(nil)

  defp translation_practice_node(translation_from, translation_target) do
    ShowEditGenerateHelpers.translation_practice_node(translation_from, translation_target)
  end

  defp insert_generated_translation_practice(socket, generated_node, output_page_id) do
    source_item = socket.assigns.generate_source_item
    output_mode = socket.assigns.generate_values["output_mode"]

    if output_mode == "source_item" and is_map(source_item) do
      insert_generated_translation_at_source(socket, source_item, generated_node, output_page_id)
    else
      insert_generated_translation_at_page_root(socket, generated_node, output_page_id)
    end
  end

  defp insert_generated_translation_at_source(
         socket,
         %{page_id: page_id, node_id: node_id},
         generated_node,
         output_page_id
       ) do
    case parse_page_id(page_id) do
      {:ok, parsed_page_id} ->
        page = page_by_id(socket.assigns.unit, parsed_page_id)
        state = Map.get(socket.assigns.page_states, parsed_page_id)

        cond do
          is_nil(page) or is_nil(state) ->
            insert_generated_translation_at_page_root(socket, generated_node, output_page_id)

          true ->
            case ShowEditGenerateHelpers.build_insert_under_source_command(
                   state.nodes,
                   node_id,
                   generated_node
                 ) do
              :error ->
                insert_generated_translation_at_page_root(socket, generated_node, output_page_id)

              {:ok, command} ->
                apply_local_editor_command(socket, page, state, command)
            end
        end

      :error ->
        insert_generated_translation_at_page_root(socket, generated_node, output_page_id)
    end
  end

  defp insert_generated_translation_at_source(
         socket,
         _source_item,
         generated_node,
         output_page_id
       ) do
    insert_generated_translation_at_page_root(socket, generated_node, output_page_id)
  end

  defp insert_generated_translation_at_page_root(socket, generated_node, page_id) do
    with page when not is_nil(page) <- page_by_id(socket.assigns.unit, page_id),
         state when not is_nil(state) <- Map.get(socket.assigns.page_states, page_id) do
      apply_local_editor_command(socket, page, state, {:append_many, [generated_node]})
    else
      _ -> socket
    end
  end

  defp apply_imported_vocabularies(socket, page_id, vocabularies, opts) do
    imported_nodes = ShowEditImportHelpers.vocabulary_nodes(vocabularies)
    loading_assign = Keyword.fetch!(opts, :loading_assign)
    success_message = Keyword.fetch!(opts, :success_message)

    if imported_nodes == [] do
      {:noreply,
       socket
       |> assign(loading_assign, false)
       |> put_flash(:error, "No vocabularies were parsed")}
    else
      with_page_state(socket, page_id, fn socket, page, state ->
        socket
        |> apply_local_editor_command(page, state, {:append_many, imported_nodes})
        |> assign(loading_assign, false)
        |> put_flash(:info, success_message)
      end)
    end
  end

  defp parse_import_source(socket, source) do
    page_id = selected_import_page_id(socket)

    with {:ok, provider, model} <- selected_import_ai_model(socket) do
      case ShowEditImportHelpers.parse_source(
             socket.assigns.import_values["type"],
             source,
             socket.assigns.unit.from_target_lang,
             importer_module(),
             provider: provider,
             model: model
           ) do
        {:ok, vocabularies} ->
          apply_imported_vocabularies(socket, page_id, vocabularies,
            loading_assign: :parsing_import,
            success_message: "Imported #{length(vocabularies)} vocabularies"
          )

        {:error, :unsupported_import_type} ->
          {:noreply,
           socket
           |> assign(:parsing_import, false)
           |> put_flash(:error, "Unsupported import type")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:parsing_import, false)
           |> put_flash(:error, "Failed to parse: #{inspect(reason)}")}
      end
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:parsing_import, false)
         |> put_flash(:error, selected_model_error_message(reason))}
    end
  end

  defp consume_import_image_ocr(socket) do
    done_entries = uploaded_entries(socket, :import_image) |> elem(0)

    if done_entries == [] do
      {:ok, socket, ""}
    else
      with {:ok, provider, model} <- selected_import_ocr_model(socket) do
        consumed =
          consume_uploaded_entries(socket, :import_image, fn %{path: path}, _entry ->
            with {:ok, image_binary} <- File.read(path),
                 {:ok, text} <-
                   importer_module().extract_text_from_image(
                     image_binary,
                     provider: provider,
                     model: model,
                     from_target_lang: socket.assigns.unit.from_target_lang
                   ) do
              {:ok, {:ok, text}}
            else
              {:error, reason} -> {:ok, {:error, reason}}
            end
          end)

        case ShowEditImportHelpers.parse_ocr_consumed_result(consumed) do
          {:ok, text} -> {:ok, socket, text}
          {:error, reason} -> {:error, socket, reason}
        end
      else
        {:error, reason} ->
          {:error, socket, reason}
      end
    end
  end

  defp importer_module do
    Application.get_env(:gakugo, :notebook_importer, Importer)
  end

  defp translation_practice_generator_module do
    Application.get_env(
      :gakugo,
      :notebook_translation_practice_generator,
      TranslationPracticeGenerator
    )
  end

  defp selected_generate_ai_model(socket) do
    socket.assigns.generate_values
    |> Map.get("ai_model", "")
    |> parse_selected_model_value(:generation)
  end

  defp selected_import_ai_model(socket) do
    socket.assigns.import_values
    |> Map.get("ai_model", "")
    |> parse_selected_model_value(:parse)
  end

  defp selected_import_ocr_model(socket) do
    socket.assigns.import_values
    |> Map.get("ocr_model", "")
    |> parse_selected_model_value(:ocr)
  end

  defp generate_ai_model_options(_assigns, ai_runtime) do
    build_model_options(ai_runtime, :generation)
  end

  defp import_ai_model_options(_assigns, ai_runtime) do
    build_model_options(ai_runtime, :parse)
  end

  defp import_ocr_model_options(_assigns, ai_runtime) do
    build_model_options(ai_runtime, :ocr)
  end

  defp build_model_options(ai_runtime, usage) do
    all_models =
      ai_runtime.providers
      |> Enum.flat_map(fn {provider, check} ->
        Enum.map(check.models, fn model ->
          %{provider: provider, model: model}
        end)
      end)

    default_option =
      with provider when provider in [:ollama, :openai, :gemini] <-
             AIConfig.usage_provider(usage),
           model when is_binary(model) and model != "" <- AIConfig.usage_model(usage),
           true <- Enum.any?(all_models, &(&1.provider == provider and &1.model == model)) do
        %{provider: provider, model: model}
      else
        _ -> nil
      end

    [default_option | all_models]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.provider, &1.model})
    |> Enum.map(fn %{provider: provider, model: model} ->
      {"[#{provider_label(provider)}] #{model}", model_option_value(provider, model)}
    end)
  end

  defp models_available?(model_options), do: model_options != []

  defp usage_error(ai_runtime, model_options) do
    if model_options != [] do
      nil
    else
      errors =
        ai_runtime.providers
        |> Enum.filter(fn {_provider, check} ->
          check.status == :error and not is_nil(check.error)
        end)
        |> Enum.map(fn {provider, check} ->
          "#{provider_label(provider)}: #{inspect(check.error)}"
        end)

      case errors do
        [] -> "No models available yet. Check provider connection and API key."
        _ -> "Model discovery failed - " <> Enum.join(errors, " | ")
      end
    end
  end

  defp default_model_value(usage) do
    case {AIConfig.usage_provider(usage), AIConfig.usage_model(usage)} do
      {provider, model}
      when provider in [:ollama, :openai, :gemini] and is_binary(model) and model != "" ->
        model_option_value(provider, model)

      _ ->
        ""
    end
  end

  defp parse_selected_model_value(raw_value, usage) when is_binary(raw_value) do
    value = String.trim(raw_value)

    cond do
      value == "" ->
        {:error, :missing_model}

      String.contains?(value, "::") ->
        case String.split(value, "::", parts: 2) do
          [provider_raw, model] ->
            case parse_provider(provider_raw) do
              {:ok, provider} when model != "" -> {:ok, provider, model}
              _ -> {:error, :invalid_model}
            end

          _ ->
            {:error, :invalid_model}
        end

      true ->
        provider = AIConfig.usage_provider(usage) || :ollama
        {:ok, provider, value}
    end
  end

  defp parse_selected_model_value(_raw_value, _usage), do: {:error, :invalid_model}

  defp parse_provider("ollama"), do: {:ok, :ollama}
  defp parse_provider("openai"), do: {:ok, :openai}
  defp parse_provider("gemini"), do: {:ok, :gemini}
  defp parse_provider(_provider), do: :error

  defp provider_label(:openai), do: "OpenAI"
  defp provider_label(:gemini), do: "Gemini"
  defp provider_label(:ollama), do: "Ollama"
  defp provider_label(provider), do: provider |> to_string() |> String.capitalize()

  defp model_option_value(provider, model), do: "#{provider}::#{model}"

  defp selected_model_error_message(:missing_model), do: "Select an AI model before running"
  defp selected_model_error_message(:invalid_model), do: "Selected AI model is invalid"
  defp selected_model_error_message(_reason), do: "Selected AI model is invalid"

  defp pages_for_render(assigns) do
    last_index = length(assigns.unit.pages) - 1

    assigns.unit.pages
    |> Enum.with_index()
    |> Enum.map(fn {page, index} ->
      state = page_state(assigns, page.id)

      %{
        id: page.id,
        title: state.title,
        nodes: state.nodes,
        form: state.form,
        title_locked_by_other: page_title_locked_by_other?(assigns, page.id),
        can_move_up: index > 0,
        can_move_down: index < last_index
      }
    end)
  end

  defp unit_title_locked_by_other?(assigns) do
    lock_owner_actor_id =
      item_lock_owner(assigns.item_locks, @unit_title_lock_page_id, @unit_title_lock_path)

    is_binary(lock_owner_actor_id) and lock_owner_actor_id != assigns.actor_id
  end

  defp page_title_locked_by_other?(assigns, page_id) do
    lock_owner_actor_id = item_lock_owner(assigns.item_locks, page_id, @page_title_lock_path)
    is_binary(lock_owner_actor_id) and lock_owner_actor_id != assigns.actor_id
  end

  defp external_link?(link), do: ShowEditHelpers.external_link?(link)

  defp unit_for_flashcard_preview(assigns),
    do: ShowEditHelpers.unit_for_flashcard_preview(assigns)

  defp build_flashcard_fronts_by_page(unit),
    do: ShowEditHelpers.build_flashcard_fronts_by_page(unit)

  defp build_page_states(unit, existing_states \\ %{}),
    do: ShowEditHelpers.build_page_states(unit, existing_states)

  defp build_page_states_from_db(unit, existing_states),
    do: ShowEditHelpers.build_page_states_from_db(unit, existing_states)

  defp page_state(assigns_or_socket, page_id),
    do: ShowEditHelpers.page_state(assigns_or_socket, page_id)

  defp page_by_id(unit, page_id), do: ShowEditHelpers.page_by_id(unit, page_id)

  defp page_version_key(page), do: ShowEditHelpers.page_version_key(page)

  defp default_page_id(socket), do: ShowEditHelpers.default_page_id(socket)

  defp default_page_id_from_unit(unit), do: ShowEditHelpers.default_page_id_from_unit(unit)

  defp with_page_state(socket, page_id_param, fun),
    do: ShowEditHelpers.with_page_state(socket, page_id_param, fun)

  defp update_page_state(socket, page_id, fun),
    do: ShowEditHelpers.update_page_state(socket, page_id, fun)

  defp drop_page_state(page_states, page_id),
    do: ShowEditHelpers.drop_page_state(page_states, page_id)
end
