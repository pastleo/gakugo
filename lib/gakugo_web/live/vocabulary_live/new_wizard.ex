defmodule GakugoWeb.VocabularyLive.NewWizard do
  use GakugoWeb, :live_view

  alias Gakugo.Learning
  alias Gakugo.Learning.VocabularyParser

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Vocabulary Import Wizard
        <:subtitle>Import multiple vocabularies at once using AI-powered parsing</:subtitle>
      </.header>

      <div class="space-y-6">
        <%!-- Source Text Input --%>
        <div>
          <label for="source-input" class="block text-sm font-medium mb-2">
            Source Text
          </label>
          <textarea
            id="source-input"
            name="source"
            rows="8"
            class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            placeholder="Paste text containing vocabulary words here..."
            phx-blur="update_source"
          >{@source}</textarea>
          <p class="mt-1 text-sm text-gray-500">
            Enter text and click "Parse" to extract vocabulary automatically
          </p>
        </div>

        <%!-- Parse Button --%>
        <div class="flex gap-2">
          <.button
            id="parse-btn"
            phx-click="parse"
            phx-disable-with="Parsing..."
            disabled={@source == "" or @parsing}
          >
            Parse with AI
          </.button>
          <%= if @parsing do %>
            <span class="flex items-center text-sm text-gray-600">
              <svg class="animate-spin h-4 w-4 mr-2" viewBox="0 0 24 24">
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                  fill="none"
                >
                </circle>
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                >
                </path>
              </svg>
              Parsing...
            </span>
          <% end %>
        </div>

        <%!-- Vocabularies List --%>
        <div>
          <div class="flex justify-between items-center mb-2">
            <label class="block text-sm font-medium">
              Vocabularies ({length(@vocabularies)})
            </label>
            <.button id="add-vocabulary-btn" phx-click="add_vocabulary">
              + Add Vocabulary
            </.button>
          </div>

          <div id="vocabularies" class="space-y-4">
            <%= if @vocabularies == [] do %>
              <div class="text-center py-8 text-gray-500 border border-dashed border-gray-300 rounded-lg">
                No vocabularies yet. Add manually or parse from source text.
              </div>
            <% else %>
              <%= for {vocab, idx} <- Enum.with_index(@vocabularies) do %>
                <.form
                  :let={f}
                  for={to_form(vocab, as: "vocabulary_#{idx}")}
                  id={"vocabulary-form-#{idx}"}
                  phx-change="update_vocabulary_form"
                  phx-value-index={idx}
                >
                  <.vocabulary_card
                    id={"vocab-#{idx}"}
                    index={idx}
                    target_field={f[:target]}
                    from_field={f[:from]}
                    note_field={f[:note]}
                    on_remove="remove_vocabulary"
                  />
                </.form>
              <% end %>
            <% end %>
          </div>
        </div>

        <%!-- Actions --%>
        <footer class="flex gap-2 pt-4 border-t">
          <.button
            id="save-btn"
            phx-click="save"
            phx-disable-with="Saving..."
            disabled={@vocabularies == [] or @saving}
            variant="primary"
          >
            Save All Vocabularies
          </.button>
          <.button navigate={~p"/units/#{@unit_id}"}>
            Cancel
          </.button>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"unit_id" => unit_id}, _session, socket) do
    unit = Learning.get_unit!(unit_id)

    {:ok,
     socket
     |> assign(:unit_id, unit_id)
     |> assign(:from_target_lang, unit.from_target_lang)
     |> assign(:source, "")
     |> assign(:vocabularies, [])
     |> assign(:parsing, false)
     |> assign(:saving, false)}
  end

  @impl true
  def handle_event("update_source", %{"value" => source}, socket) do
    {:noreply, assign(socket, :source, source)}
  end

  def handle_event("add_vocabulary", _params, socket) do
    new_vocab = %{"target" => "", "from" => "", "note" => ""}
    vocabularies = socket.assigns.vocabularies ++ [new_vocab]

    {:noreply, assign(socket, :vocabularies, vocabularies)}
  end

  def handle_event("remove_vocabulary", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    vocabularies = List.delete_at(socket.assigns.vocabularies, index)

    {:noreply, assign(socket, :vocabularies, vocabularies)}
  end

  def handle_event("update_vocabulary", params, socket) do
    %{"index" => index_str, "field" => field, "value" => value} = params
    index = String.to_integer(index_str)

    vocabularies =
      List.update_at(socket.assigns.vocabularies, index, fn vocab ->
        Map.put(vocab, field, value)
      end)

    {:noreply, assign(socket, :vocabularies, vocabularies)}
  end

  def handle_event("update_vocabulary_form", params, socket) do
    %{"index" => index_str} = params
    index = String.to_integer(index_str)
    vocab_key = "vocabulary_#{index}"
    vocab_params = Map.get(params, vocab_key, %{})

    vocabularies =
      List.update_at(socket.assigns.vocabularies, index, fn _vocab ->
        vocab_params
      end)

    {:noreply, assign(socket, :vocabularies, vocabularies)}
  end

  def handle_event("parse", _params, socket) do
    socket = assign(socket, :parsing, true)

    case VocabularyParser.parse(socket.assigns.source, socket.assigns.from_target_lang) do
      {:ok, parsed_vocabs} ->
        existing = socket.assigns.vocabularies
        new_vocabularies = existing ++ parsed_vocabs

        {:noreply,
         socket
         |> assign(:vocabularies, new_vocabularies)
         |> assign(:parsing, false)
         |> put_flash(:info, "Successfully parsed #{length(parsed_vocabs)} vocabularies")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:parsing, false)
         |> put_flash(:error, "Failed to parse: #{inspect(reason)}")}
    end
  end

  def handle_event("save", _params, socket) do
    socket = assign(socket, :saving, true)
    unit_id = String.to_integer(socket.assigns.unit_id)

    results =
      socket.assigns.vocabularies
      |> Enum.with_index()
      |> Enum.map(fn {vocab, index} ->
        attrs = Map.put(vocab, "unit_id", unit_id)
        {index, Learning.create_vocabulary(attrs)}
      end)

    failed_indices =
      results
      |> Enum.filter(fn {_index, result} ->
        case result do
          {:error, _} -> true
          _ -> false
        end
      end)
      |> Enum.map(fn {index, _result} -> index end)

    socket =
      if failed_indices == [] do
        socket
        |> put_flash(:info, "Successfully saved #{length(results)} vocabularies")
        |> push_navigate(to: ~p"/units/#{socket.assigns.unit_id}")
      else
        # Keep only the failed vocabularies in the list
        failed_vocabularies =
          socket.assigns.vocabularies
          |> Enum.with_index()
          |> Enum.filter(fn {_vocab, index} -> index in failed_indices end)
          |> Enum.map(fn {vocab, _index} -> vocab end)

        success_count = length(results) - length(failed_indices)

        flash_message =
          if success_count > 0 do
            "Successfully saved #{success_count} vocabularies. #{length(failed_indices)} failed - please fix errors and try again."
          else
            "Failed to save vocabularies: #{length(failed_indices)} errors"
          end

        socket
        |> assign(:vocabularies, failed_vocabularies)
        |> assign(:saving, false)
        |> put_flash(:error, flash_message)
      end

    {:noreply, socket}
  end
end
