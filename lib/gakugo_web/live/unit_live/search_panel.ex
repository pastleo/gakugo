defmodule GakugoWeb.UnitLive.SearchPanel do
  use GakugoWeb, :live_component

  alias Gakugo.Db
  alias Gakugo.Notebook.Markdown.Preview, as: MarkdownPreview

  @impl true
  def update(%{async_search_progress: progress}, socket) do
    if socket.assigns[:search_ref] == progress.ref do
      {:ok, assign(socket, :search_progress, Map.delete(progress, :ref))}
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns[:initialized] do
      {:ok, socket}
    else
      {:ok,
       socket
       |> assign(:initialized, true)
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> assign(:search_form, search_form())
       |> assign(:searching, false)
       |> assign(:search_progress, initial_search_progress())
       |> assign(:search_ref, nil)
       |> assign(:search_error, nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="unit-search-panel" class="space-y-5">
      <p class="text-xs text-base-content/65">
        Search item text across all active notebook pages.
      </p>

      <.form
        for={@search_form}
        id="unit-search-form"
        phx-target={@myself}
        phx-submit="search_notebooks"
        class="space-y-3"
      >
        <.input
          field={@search_form[:query]}
          type="text"
          label="Keyword"
          placeholder="Search notebook items"
          autocomplete="off"
        />

        <button
          id="unit-search-submit-btn"
          type="submit"
          disabled={@searching}
          class="w-full rounded-xl border border-primary/30 bg-primary/12 px-3 py-2 text-sm font-medium text-primary transition hover:bg-primary/18"
        >
          <%= if @searching do %>
            Searching...
          <% else %>
            Search
          <% end %>
        </button>
      </.form>

      <%= if @searching do %>
        <div class="rounded-xl border border-base-300 bg-base-200/40 px-3 py-3 text-xs text-base-content/60">
          {search_progress_label(@search_progress)}
        </div>
      <% end %>

      <%= if @search_error do %>
        <div class="rounded-xl border border-error/30 bg-error/10 p-3 text-xs text-error">
          {@search_error}
        </div>
      <% end %>

      <section class="space-y-3">
        <div class="flex items-center justify-between">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
            Results
          </h3>
          <span class="text-xs text-base-content/55">
            {length(@search_results)} matches
          </span>
        </div>

        <div
          :if={@search_query == ""}
          class="rounded-xl border border-dashed border-base-300 px-3 py-6 text-center text-xs text-base-content/55"
        >
          Enter a keyword to search notebook items.
        </div>

        <div
          :if={@search_query != "" and @search_results == []}
          class="rounded-xl border border-dashed border-base-300 px-3 py-6 text-center text-xs text-base-content/55"
        >
          No notebook items matched "{@search_query}".
        </div>

        <div :if={@search_results != []} class="space-y-2">
          <.link
            :for={result <- @search_results}
            href={focused_unit_url(result)}
            target="_blank"
            rel="noopener noreferrer"
            class="block rounded-xl border border-base-300 bg-base-200/30 px-3 py-2 transition hover:border-base-content/20 hover:bg-base-200/60"
          >
            <div class="line-clamp-2 text-sm leading-6 text-base-content [&_a]:text-primary [&_code]:rounded [&_code]:bg-base-300/70 [&_code]:px-1 [&_p]:inline">
              {Phoenix.HTML.raw(result.preview_html)}
            </div>
            <div class="mt-2 truncate text-[11px] text-base-content/50">
              {result.unit_title} &gt; {result.page_title} &gt; {result.item_id}
            </div>
          </.link>
        </div>
      </section>
    </div>
    """
  end

  @impl true
  def handle_event("search_notebooks", %{"notebook_search" => %{"query" => query}}, socket) do
    query = String.trim(query || "")
    {:noreply, start_search(socket, query)}
  end

  @impl true
  def handle_async({:notebook_search, ref}, {:ok, {:ok, results}}, socket) do
    if socket.assigns.search_ref == ref do
      {:noreply,
       socket
       |> assign(:search_results, results)
       |> assign(:searching, false)
       |> assign(:search_progress, %{total: length(results), processed: length(results)})
       |> assign(:search_error, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:notebook_search, ref}, {:exit, reason}, socket) do
    if socket.assigns.search_ref == ref do
      {:noreply,
       socket
       |> assign(:search_results, [])
       |> assign(:searching, false)
       |> assign(:search_progress, initial_search_progress())
       |> assign(:search_error, inspect(reason))}
    else
      {:noreply, socket}
    end
  end

  defp search_form(query \\ "") do
    to_form(%{"query" => query}, as: :notebook_search)
  end

  defp start_search(socket, "") do
    socket
    |> assign(:search_query, "")
    |> assign(:search_results, [])
    |> assign(:search_form, search_form())
    |> assign(:searching, false)
    |> assign(:search_progress, initial_search_progress())
    |> assign(:search_ref, nil)
    |> assign(:search_error, nil)
  end

  defp start_search(socket, query) do
    ref = make_ref()
    panel_id = socket.assigns.id
    live_view_pid = self()

    socket
    |> assign(:search_query, query)
    |> assign(:search_results, [])
    |> assign(:search_form, search_form(query))
    |> assign(:searching, true)
    |> assign(:search_progress, initial_search_progress())
    |> assign(:search_ref, ref)
    |> assign(:search_error, nil)
    |> start_async({:notebook_search, ref}, fn ->
      results = Db.search_notebook_items(query)
      total = length(results)

      rendered_results =
        results
        |> Enum.with_index(1)
        |> Enum.map(fn {result, processed} ->
          Phoenix.LiveView.send_update(live_view_pid, __MODULE__,
            id: panel_id,
            async_search_progress: %{ref: ref, total: total, processed: processed}
          )

          Map.put(result, :preview_html, MarkdownPreview.search_html(result.item_text, query))
        end)

      {:ok, rendered_results}
    end)
  end

  defp initial_search_progress, do: %{total: nil, processed: 0}

  defp search_progress_label(%{total: total, processed: processed}) when is_integer(total) do
    "Rendered #{processed}/#{total} results"
  end

  defp search_progress_label(_progress), do: "Searching notebook items..."

  defp focused_unit_url(result) do
    ~p"/units/#{result.unit_id}?page_id=#{result.page_id}&item_id=#{result.item_id}"
  end
end
