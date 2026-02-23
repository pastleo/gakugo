defmodule GakugoWeb.UnitLive.Form do
  use GakugoWeb, :live_view

  alias Gakugo.Learning
  alias Gakugo.Learning.Unit
  alias Gakugo.Learning.FromTargetLang

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Create a notebook-style unit for linked line learning.</:subtitle>
      </.header>

      <.form for={@form} id="unit-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="Title" />
        <.input
          field={@form[:from_target_lang]}
          type="select"
          label="Language Pair"
          options={@from_target_lang_options}
        />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Unit</.button>
          <.button navigate={return_path(@return_to, @unit)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(:from_target_lang_options, FromTargetLang.options())
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    unit = Learning.get_unit!(id)

    socket
    |> assign(:page_title, "Edit Unit")
    |> assign(:unit, unit)
    |> assign(:form, to_form(Learning.change_unit(unit)))
  end

  defp apply_action(socket, :new, _params) do
    unit = %Unit{}

    socket
    |> assign(:page_title, "New Unit")
    |> assign(:unit, unit)
    |> assign(:form, to_form(Learning.change_unit(unit)))
  end

  @impl true
  def handle_event("validate", %{"unit" => unit_params}, socket) do
    changeset = Learning.change_unit(socket.assigns.unit, unit_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"unit" => unit_params}, socket) do
    save_unit(socket, socket.assigns.live_action, unit_params)
  end

  defp save_unit(socket, :edit, unit_params) do
    case Learning.update_unit(socket.assigns.unit, unit_params) do
      {:ok, unit} ->
        {:noreply,
         socket
         |> put_flash(:info, "Unit updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, unit))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_unit(socket, :new, unit_params) do
    case Learning.create_unit(unit_params) do
      {:ok, unit} ->
        {:noreply,
         socket
         |> put_flash(:info, "Unit created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, unit))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _unit), do: ~p"/"
  defp return_path("show", unit), do: ~p"/units/#{unit}"
end
