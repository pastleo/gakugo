defmodule GakugoWeb.UnitLive.ShowEdit do
  use GakugoWeb, :live_view

  alias Gakugo.Learning
  alias Gakugo.Learning.FlashcardGenerator
  alias Gakugo.Learning.FromTargetLang
  alias Gakugo.Anki.SyncService

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Unit {@unit.id}
        <:subtitle>
          {if @has_unsaved_changes,
            do: "Unsaved changes - will auto-save in 5s",
            else: "This is a unit record from your database."}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/"}>
            <.icon name="hero-arrow-left" />
          </.button>
        </:actions>
      </.header>

      <div
        id="inline-edit-form"
        data-has-unsaved={@has_unsaved_changes}
      >
        <.form for={@form} id="unit-form" phx-change="validate">
          <div class="mt-6">
            <dl>
              <div class="items-center sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
                <dt class="text-sm font-medium leading-6">Title</dt>
                <dd class="mt-1 text-sm leading-6 sm:col-span-2 sm:mt-0">
                  <div class="inline-edit-field">
                    <.input
                      field={@form[:title]}
                      type="text"
                      class="w-full input input-ghost"
                      phx-debounce="300"
                    />
                  </div>
                </dd>
              </div>
              <div class="items-center sm:grid sm:grid-cols-3 sm:gap-4 sm:px-0">
                <dt class="text-sm font-medium leading-6">Language Pair</dt>
                <dd class="mt-1 text-sm leading-6 sm:col-span-2 sm:mt-0">
                  <div class="inline-edit-field">
                    <.input
                      field={@form[:from_target_lang]}
                      type="select"
                      options={@from_target_lang_options}
                      class="w-full select select-ghost"
                      phx-debounce="300"
                    />
                  </div>
                </dd>
              </div>
            </dl>
          </div>
        </.form>
      </div>

      <div class="mt-8">
        <.header>
          Grammars
          <:actions>
            <.button variant="primary" phx-click="add_grammar">
              <.icon name="hero-plus" /> Add Grammar
            </.button>
          </:actions>
        </.header>

        <div class="mt-4 space-y-4">
          <div :for={grammar <- @unit.grammars}>
            <.form
              :let={f}
              for={
                Map.get(
                  @grammar_forms,
                  grammar.id,
                  to_form(
                    Learning.change_grammar(grammar, %{details_json: encode_details(grammar.details)})
                  )
                )
              }
              id={"grammar-form-#{grammar.id}"}
              phx-change="validate_grammar"
              phx-value-grammar_id={grammar.id}
            >
              <.grammar_card
                id={"grammar-edit-#{grammar.id}"}
                title_field={f[:title]}
                details_field={f[:details_json]}
                on_remove="delete_grammar"
                phx-value-grammar_id={grammar.id}
              />
            </.form>
          </div>
        </div>
      </div>

      <div class="mt-8">
        <.header>
          Vocabularies
          <:actions>
            <.button variant="primary" navigate={~p"/units/#{@unit}/vocabularies/new"}>
              <.icon name="hero-plus" /> Add Vocabulary
            </.button>
          </:actions>
        </.header>

        <div class="mt-4 space-y-4">
          <div :for={vocabulary <- @unit.vocabularies}>
            <.form
              :let={f}
              for={
                Map.get(
                  @vocabulary_forms,
                  vocabulary.id,
                  to_form(Learning.change_vocabulary(vocabulary))
                )
              }
              id={"vocabulary-form-#{vocabulary.id}"}
              phx-change="validate_vocabulary"
              phx-value-vocabulary_id={vocabulary.id}
            >
              <.vocabulary_card
                id={"vocabulary-edit-#{vocabulary.id}"}
                target_field={f[:target]}
                from_field={f[:from]}
                note_field={f[:note]}
                on_remove="delete_vocabulary"
                phx-value-vocabulary_id={vocabulary.id}
              />
            </.form>
          </div>
        </div>
      </div>

      <div class="mt-8">
        <.header>
          Flashcards
          <:subtitle>
            Generate flashcards for Anki sync. Select vocabularies and click generate.
          </:subtitle>
        </.header>

        <div class="mt-4">
          <div class="flex items-center gap-4 mb-4">
            <.button
              type="button"
              phx-click="toggle_all_vocabularies"
              class="btn btn-sm btn-outline"
            >
              {if @all_selected, do: "Deselect All", else: "Select All"}
            </.button>
            <.button
              type="button"
              phx-click="generate_flashcards"
              variant="primary"
              disabled={@selected_vocabulary_ids == [] || @generating_flashcards}
            >
              <%= if @generating_flashcards do %>
                <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Generating...
              <% else %>
                <.icon name="hero-sparkles" class="size-4" />
                Generate Flashcards ({length(@selected_vocabulary_ids)})
              <% end %>
            </.button>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            <div
              :for={vocabulary <- @unit.vocabularies}
              class={[
                "border rounded-lg p-3 cursor-pointer transition-all bg-base-100",
                vocabulary.id in @selected_vocabulary_ids && "border-primary bg-primary/5",
                vocabulary.id not in @selected_vocabulary_ids &&
                  "border-base-300 hover:border-base-content/30"
              ]}
              phx-click="toggle_vocabulary_selection"
              phx-value-vocabulary_id={vocabulary.id}
            >
              <div class="flex items-start gap-2">
                <input
                  type="checkbox"
                  checked={vocabulary.id in @selected_vocabulary_ids}
                  class="checkbox checkbox-sm checkbox-primary mt-1"
                  phx-click="toggle_vocabulary_selection"
                  phx-value-vocabulary_id={vocabulary.id}
                />
                <div class="flex-1 min-w-0">
                  <div class="font-medium text-sm truncate">{vocabulary.target}</div>
                  <div class="text-sm text-base-content/60 truncate">{vocabulary.from}</div>
                  <%= if get_flashcard_for_vocabulary(@unit.flashcards, vocabulary.id) do %>
                    <div class="mt-2 text-xs text-success flex items-center gap-1">
                      <.icon name="hero-check-circle" class="size-3" /> Flashcard exists
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <%= if @unit.flashcards != [] do %>
            <div class="mt-6">
              <div class="flex items-center justify-between mb-3">
                <h4 class="text-sm font-medium">
                  Generated Flashcards ({length(@unit.flashcards)})
                </h4>
                <div class="flex gap-2">
                  <.button
                    type="button"
                    phx-click="sync_to_anki"
                    variant="primary"
                    disabled={@syncing_to_anki}
                  >
                    <%= if @syncing_to_anki do %>
                      <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Syncing...
                    <% else %>
                      <.icon name="hero-cloud-arrow-up" class="size-4" /> Sync to Anki
                    <% end %>
                  </.button>
                </div>
              </div>
              <div class="space-y-3">
                <div :for={flashcard <- @unit.flashcards}>
                  <.form
                    :let={f}
                    for={
                      Map.get(
                        @flashcard_forms,
                        flashcard.id,
                        to_form(Learning.change_flashcard(flashcard))
                      )
                    }
                    id={"flashcard-form-#{flashcard.id}"}
                    phx-change="validate_flashcard"
                    phx-value-flashcard_id={flashcard.id}
                  >
                    <.flashcard_card
                      id={"flashcard-edit-#{flashcard.id}"}
                      front_field={f[:front]}
                      back_field={f[:back]}
                      on_remove="delete_flashcard"
                      phx-value-flashcard_id={flashcard.id}
                    />
                  </.form>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp get_flashcard_for_vocabulary(flashcards, vocabulary_id) do
    Enum.find(flashcards, fn f -> f.vocabulary_id == vocabulary_id end)
  end

  defp encode_details(nil), do: ""
  defp encode_details([]), do: ""
  defp encode_details(details) when is_list(details), do: Jason.encode!(details, pretty: true)
  defp encode_details(_), do: ""

  defp decode_details(""), do: nil
  defp decode_details(nil), do: nil

  defp decode_details(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, details} -> details
      {:error, _} -> nil
    end
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    unit = Learning.get_unit!(id)

    {:ok,
     socket
     |> assign(:page_title, "Show Unit")
     |> assign(:unit, unit)
     |> assign(:form, to_form(Learning.change_unit(unit)))
     |> assign(:from_target_lang_options, FromTargetLang.options())
     |> assign(:has_unsaved_changes, false)
     |> assign(:auto_save_timer, nil)
     |> assign(:vocabulary_forms, %{})
     |> assign(:grammar_forms, %{})
     |> assign(:flashcard_forms, %{})
     |> assign(:unsaved_changes, %{})
     |> assign(:auto_save_timers, %{})
     |> assign(:selected_vocabulary_ids, [])
     |> assign(:all_selected, false)
     |> assign(:generating_flashcards, false)
     |> assign(:syncing_to_anki, false)}
  end

  @impl true
  def handle_event("validate", %{"unit" => unit_params}, socket) do
    changeset = Learning.change_unit(socket.assigns.unit, unit_params)

    # Cancel existing timer if any
    if socket.assigns.auto_save_timer do
      Process.cancel_timer(socket.assigns.auto_save_timer)
    end

    # Check if changeset is valid
    if changeset.valid? do
      # Schedule auto-save in 5 seconds
      timer = Process.send_after(self(), {:auto_save, unit_params}, 5000)

      {:noreply,
       socket
       |> assign(:form, to_form(changeset, action: :validate))
       |> assign(:has_unsaved_changes, true)
       |> assign(:auto_save_timer, timer)}
    else
      {:noreply,
       socket
       |> assign(:form, to_form(changeset, action: :validate))
       |> assign(:has_unsaved_changes, true)
       |> assign(:auto_save_timer, nil)}
    end
  end

  def handle_event(
        "validate_vocabulary",
        %{"vocabulary" => vocabulary_params, "vocabulary_id" => vocabulary_id},
        socket
      ) do
    vocabulary_id = String.to_integer(vocabulary_id)
    vocabulary = Enum.find(socket.assigns.unit.vocabularies, &(&1.id == vocabulary_id))
    changeset = Learning.change_vocabulary(vocabulary, vocabulary_params)

    # Cancel existing timer if any
    timer_key = "vocabulary_#{vocabulary_id}"

    if socket.assigns.auto_save_timers[timer_key] do
      Process.cancel_timer(socket.assigns.auto_save_timers[timer_key])
    end

    # Check if changeset is valid
    if changeset.valid? do
      # Schedule auto-save in 5 seconds
      timer =
        Process.send_after(
          self(),
          {:auto_save_vocabulary, vocabulary_id, vocabulary_params},
          5000
        )

      {:noreply,
       socket
       |> assign(
         :vocabulary_forms,
         Map.put(
           socket.assigns.vocabulary_forms,
           vocabulary_id,
           to_form(changeset, action: :validate)
         )
       )
       |> assign(:unsaved_changes, Map.put(socket.assigns.unsaved_changes, timer_key, true))
       |> assign(:auto_save_timers, Map.put(socket.assigns.auto_save_timers, timer_key, timer))}
    else
      {:noreply,
       socket
       |> assign(
         :vocabulary_forms,
         Map.put(
           socket.assigns.vocabulary_forms,
           vocabulary_id,
           to_form(changeset, action: :validate)
         )
       )
       |> assign(:unsaved_changes, Map.put(socket.assigns.unsaved_changes, timer_key, true))
       |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))}
    end
  end

  def handle_event("delete_vocabulary", %{"vocabulary_id" => vocabulary_id}, socket) do
    vocabulary_id = String.to_integer(vocabulary_id)
    vocabulary = Enum.find(socket.assigns.unit.vocabularies, &(&1.id == vocabulary_id))
    timer_key = "vocabulary_#{vocabulary_id}"

    if socket.assigns.auto_save_timers[timer_key] do
      Process.cancel_timer(socket.assigns.auto_save_timers[timer_key])
    end

    case Learning.delete_vocabulary(vocabulary) do
      {:ok, _vocabulary} ->
        unit = Learning.get_unit!(socket.assigns.unit.id)

        {:noreply,
         socket
         |> assign(:unit, unit)
         |> assign(:vocabulary_forms, Map.delete(socket.assigns.vocabulary_forms, vocabulary_id))
         |> assign(:unsaved_changes, Map.delete(socket.assigns.unsaved_changes, timer_key))
         |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))
         |> put_flash(:info, "Vocabulary deleted successfully")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete vocabulary")}
    end
  end

  def handle_event("add_grammar", _params, socket) do
    attrs = %{unit_id: socket.assigns.unit.id, title: "New Grammar", details: nil}

    case Learning.create_grammar(attrs) do
      {:ok, _grammar} ->
        unit = Learning.get_unit!(socket.assigns.unit.id)
        {:noreply, socket |> assign(:unit, unit) |> put_flash(:info, "Grammar added")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to add grammar")}
    end
  end

  def handle_event(
        "validate_grammar",
        %{"grammar" => grammar_params, "grammar_id" => grammar_id},
        socket
      ) do
    grammar_id = String.to_integer(grammar_id)
    grammar = Enum.find(socket.assigns.unit.grammars, &(&1.id == grammar_id))

    details = decode_details(grammar_params["details_json"])
    grammar_params = Map.put(grammar_params, "details", details)

    changeset = Learning.change_grammar(grammar, grammar_params)

    timer_key = "grammar_#{grammar_id}"

    if socket.assigns.auto_save_timers[timer_key] do
      Process.cancel_timer(socket.assigns.auto_save_timers[timer_key])
    end

    if changeset.valid? do
      timer =
        Process.send_after(
          self(),
          {:auto_save_grammar, grammar_id, grammar_params},
          5000
        )

      {:noreply,
       socket
       |> assign(
         :grammar_forms,
         Map.put(
           socket.assigns.grammar_forms,
           grammar_id,
           to_form(changeset, action: :validate)
         )
       )
       |> assign(:unsaved_changes, Map.put(socket.assigns.unsaved_changes, timer_key, true))
       |> assign(:auto_save_timers, Map.put(socket.assigns.auto_save_timers, timer_key, timer))}
    else
      {:noreply,
       socket
       |> assign(
         :grammar_forms,
         Map.put(
           socket.assigns.grammar_forms,
           grammar_id,
           to_form(changeset, action: :validate)
         )
       )
       |> assign(:unsaved_changes, Map.put(socket.assigns.unsaved_changes, timer_key, true))
       |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))}
    end
  end

  def handle_event("delete_grammar", %{"grammar_id" => grammar_id}, socket) do
    grammar_id = String.to_integer(grammar_id)
    grammar = Enum.find(socket.assigns.unit.grammars, &(&1.id == grammar_id))
    timer_key = "grammar_#{grammar_id}"

    if socket.assigns.auto_save_timers[timer_key] do
      Process.cancel_timer(socket.assigns.auto_save_timers[timer_key])
    end

    case Learning.delete_grammar(grammar) do
      {:ok, _grammar} ->
        unit = Learning.get_unit!(socket.assigns.unit.id)

        {:noreply,
         socket
         |> assign(:unit, unit)
         |> assign(:grammar_forms, Map.delete(socket.assigns.grammar_forms, grammar_id))
         |> assign(:unsaved_changes, Map.delete(socket.assigns.unsaved_changes, timer_key))
         |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))
         |> put_flash(:info, "Grammar deleted successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete grammar")}
    end
  end

  def handle_event(
        "validate_flashcard",
        %{"flashcard" => flashcard_params, "flashcard_id" => flashcard_id},
        socket
      ) do
    flashcard_id = String.to_integer(flashcard_id)
    flashcard = Enum.find(socket.assigns.unit.flashcards, &(&1.id == flashcard_id))
    changeset = Learning.change_flashcard(flashcard, flashcard_params)

    timer_key = "flashcard_#{flashcard_id}"

    if socket.assigns.auto_save_timers[timer_key] do
      Process.cancel_timer(socket.assigns.auto_save_timers[timer_key])
    end

    if changeset.valid? do
      timer =
        Process.send_after(
          self(),
          {:auto_save_flashcard, flashcard_id, flashcard_params},
          5000
        )

      {:noreply,
       socket
       |> assign(
         :flashcard_forms,
         Map.put(
           socket.assigns.flashcard_forms,
           flashcard_id,
           to_form(changeset, action: :validate)
         )
       )
       |> assign(:unsaved_changes, Map.put(socket.assigns.unsaved_changes, timer_key, true))
       |> assign(:auto_save_timers, Map.put(socket.assigns.auto_save_timers, timer_key, timer))}
    else
      {:noreply,
       socket
       |> assign(
         :flashcard_forms,
         Map.put(
           socket.assigns.flashcard_forms,
           flashcard_id,
           to_form(changeset, action: :validate)
         )
       )
       |> assign(:unsaved_changes, Map.put(socket.assigns.unsaved_changes, timer_key, true))
       |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))}
    end
  end

  def handle_event("toggle_vocabulary_selection", %{"vocabulary_id" => vocabulary_id}, socket) do
    vocabulary_id = String.to_integer(vocabulary_id)
    selected = socket.assigns.selected_vocabulary_ids

    new_selected =
      if vocabulary_id in selected do
        List.delete(selected, vocabulary_id)
      else
        [vocabulary_id | selected]
      end

    all_vocabulary_ids = Enum.map(socket.assigns.unit.vocabularies, & &1.id)
    all_selected = length(new_selected) == length(all_vocabulary_ids) and new_selected != []

    {:noreply,
     socket
     |> assign(:selected_vocabulary_ids, new_selected)
     |> assign(:all_selected, all_selected)}
  end

  def handle_event("toggle_all_vocabularies", _params, socket) do
    all_vocabulary_ids = Enum.map(socket.assigns.unit.vocabularies, & &1.id)

    {new_selected, all_selected} =
      if socket.assigns.all_selected do
        {[], false}
      else
        {all_vocabulary_ids, true}
      end

    {:noreply,
     socket
     |> assign(:selected_vocabulary_ids, new_selected)
     |> assign(:all_selected, all_selected)}
  end

  def handle_event("generate_flashcards", _params, socket) do
    if socket.assigns.selected_vocabulary_ids == [] do
      {:noreply, put_flash(socket, :error, "Please select at least one vocabulary")}
    else
      send(self(), :generate_flashcards_async)
      {:noreply, assign(socket, :generating_flashcards, true)}
    end
  end

  def handle_event("delete_flashcard", %{"flashcard_id" => flashcard_id}, socket) do
    flashcard_id = String.to_integer(flashcard_id)
    flashcard = Learning.get_flashcard!(flashcard_id)
    timer_key = "flashcard_#{flashcard_id}"

    if socket.assigns.auto_save_timers[timer_key] do
      Process.cancel_timer(socket.assigns.auto_save_timers[timer_key])
    end

    case Learning.delete_flashcard(flashcard) do
      {:ok, _} ->
        unit = Learning.get_unit!(socket.assigns.unit.id)

        {:noreply,
         socket
         |> assign(:unit, unit)
         |> assign(:flashcard_forms, Map.delete(socket.assigns.flashcard_forms, flashcard_id))
         |> assign(:unsaved_changes, Map.delete(socket.assigns.unsaved_changes, timer_key))
         |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))
         |> put_flash(:info, "Flashcard deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete flashcard")}
    end
  end

  def handle_event("sync_to_anki", _params, socket) do
    send(self(), :sync_to_anki_async)
    {:noreply, assign(socket, :syncing_to_anki, true)}
  end

  @impl true
  def handle_info({:auto_save, unit_params}, socket) do
    case Learning.update_unit(socket.assigns.unit, unit_params) do
      {:ok, unit} ->
        {:noreply,
         socket
         |> assign(:unit, unit)
         |> assign(:form, to_form(Learning.change_unit(unit)))
         |> assign(:has_unsaved_changes, false)
         |> assign(:auto_save_timer, nil)
         |> put_flash(:info, "Unit saved successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> assign(:auto_save_timer, nil)}
    end
  end

  @impl true
  def handle_info({:auto_save_vocabulary, vocabulary_id, vocabulary_params}, socket) do
    vocabulary = Enum.find(socket.assigns.unit.vocabularies, &(&1.id == vocabulary_id))
    timer_key = "vocabulary_#{vocabulary_id}"

    case Learning.update_vocabulary(vocabulary, vocabulary_params) do
      {:ok, _vocabulary} ->
        unit = Learning.get_unit!(socket.assigns.unit.id)

        {:noreply,
         socket
         |> assign(:unit, unit)
         |> assign(:vocabulary_forms, Map.delete(socket.assigns.vocabulary_forms, vocabulary_id))
         |> assign(:unsaved_changes, Map.put(socket.assigns.unsaved_changes, timer_key, false))
         |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))
         |> put_flash(:info, "Vocabulary saved successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(
           :vocabulary_forms,
           Map.put(socket.assigns.vocabulary_forms, vocabulary_id, to_form(changeset))
         )
         |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))}
    end
  end

  @impl true
  def handle_info({:auto_save_grammar, grammar_id, grammar_params}, socket) do
    grammar = Enum.find(socket.assigns.unit.grammars, &(&1.id == grammar_id))
    timer_key = "grammar_#{grammar_id}"

    case Learning.update_grammar(grammar, grammar_params) do
      {:ok, _grammar} ->
        unit = Learning.get_unit!(socket.assigns.unit.id)

        {:noreply,
         socket
         |> assign(:unit, unit)
         |> assign(:grammar_forms, Map.delete(socket.assigns.grammar_forms, grammar_id))
         |> assign(:unsaved_changes, Map.put(socket.assigns.unsaved_changes, timer_key, false))
         |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))
         |> put_flash(:info, "Grammar saved successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(
           :grammar_forms,
           Map.put(socket.assigns.grammar_forms, grammar_id, to_form(changeset))
         )
         |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))}
    end
  end

  @impl true
  def handle_info({:auto_save_flashcard, flashcard_id, flashcard_params}, socket) do
    flashcard = Enum.find(socket.assigns.unit.flashcards, &(&1.id == flashcard_id))
    timer_key = "flashcard_#{flashcard_id}"

    case Learning.update_flashcard(flashcard, flashcard_params) do
      {:ok, _flashcard} ->
        unit = Learning.get_unit!(socket.assigns.unit.id)

        {:noreply,
         socket
         |> assign(:unit, unit)
         |> assign(:flashcard_forms, Map.delete(socket.assigns.flashcard_forms, flashcard_id))
         |> assign(:unsaved_changes, Map.put(socket.assigns.unsaved_changes, timer_key, false))
         |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))
         |> put_flash(:info, "Flashcard saved successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(
           :flashcard_forms,
           Map.put(socket.assigns.flashcard_forms, flashcard_id, to_form(changeset))
         )
         |> assign(:auto_save_timers, Map.delete(socket.assigns.auto_save_timers, timer_key))}
    end
  end

  @impl true
  def handle_info(:generate_flashcards_async, socket) do
    unit = socket.assigns.unit
    selected_ids = socket.assigns.selected_vocabulary_ids

    selected_vocabularies =
      unit.vocabularies
      |> Enum.filter(fn v -> v.id in selected_ids end)

    results =
      Enum.map(selected_vocabularies, fn vocabulary ->
        case FlashcardGenerator.generate_and_save_flashcard(vocabulary, unit) do
          {:ok, flashcard} -> {:ok, vocabulary.id, flashcard}
          {:error, reason} -> {:error, vocabulary.id, reason}
        end
      end)

    success_count = Enum.count(results, fn r -> match?({:ok, _, _}, r) end)
    error_count = Enum.count(results, fn r -> match?({:error, _, _}, r) end)

    unit = Learning.get_unit!(unit.id)

    socket =
      socket
      |> assign(:unit, unit)
      |> assign(:generating_flashcards, false)
      |> assign(:selected_vocabulary_ids, [])
      |> assign(:all_selected, false)

    socket =
      cond do
        error_count == 0 ->
          put_flash(socket, :info, "Generated #{success_count} flashcard(s) successfully")

        success_count == 0 ->
          put_flash(socket, :error, "Failed to generate flashcards")

        true ->
          put_flash(
            socket,
            :info,
            "Generated #{success_count} flashcard(s), #{error_count} failed"
          )
      end

    {:noreply, socket}
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
          "Synced #{count} flashcard(s) to deck '#{deck_name}', server sync: #{status}"
        )
      else
        {:error, reason} ->
          put_flash(socket, :error, "Failed to sync to Anki: #{inspect(reason)}")
      end

    {:noreply, assign(socket, :syncing_to_anki, false)}
  end
end
