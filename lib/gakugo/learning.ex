defmodule Gakugo.Learning do
  @moduledoc """
  The Learning context.
  """

  import Ecto.Query, warn: false
  alias Gakugo.Repo

  alias Gakugo.Learning.Page
  alias Gakugo.Learning.Unit

  @doc """
  Returns the list of active units.

  ## Examples

      iex> list_units()
      [%Unit{}, ...]

  """
  def list_units do
    Unit
    |> where([u], is_nil(u.deleted_at))
    |> Repo.all()
  end

  @doc """
  Returns the list of soft-deleted units.
  """
  def list_deleted_units do
    Unit
    |> where([u], not is_nil(u.deleted_at))
    |> order_by([u], desc: u.deleted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single unit.

  Raises `Ecto.NoResultsError` if the Unit does not exist.

  ## Examples

      iex> get_unit!(123)
      %Unit{}

      iex> get_unit!(456)
      ** (Ecto.NoResultsError)

  """
  def get_unit!(id),
    do:
      get_unit_query(id, false)
      |> Repo.one!()
      |> Repo.preload(pages: pages_query())

  @doc """
  Gets a single unit, including soft-deleted units.

  Raises `Ecto.NoResultsError` if the Unit does not exist.
  """
  def get_unit_with_deleted!(id),
    do:
      get_unit_query(id, true)
      |> Repo.one!()
      |> Repo.preload(pages: pages_query())

  @doc """
  Creates a unit.

  ## Examples

      iex> create_unit(%{field: value})
      {:ok, %Unit{}}

      iex> create_unit(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_unit(attrs) do
    Repo.transaction(fn ->
      with {:ok, unit} <- %Unit{} |> Unit.changeset(attrs) |> Repo.insert(),
           {:ok, _page} <- create_default_page(unit) do
        unit
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates a unit.

  ## Examples

      iex> update_unit(unit, %{field: new_value})
      {:ok, %Unit{}}

      iex> update_unit(unit, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_unit(%Unit{} = unit, attrs) do
    unit
    |> Unit.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft deletes a unit.

  ## Examples

      iex> delete_unit(unit)
      {:ok, %Unit{}}

      iex> delete_unit(unit)
      {:error, %Ecto.Changeset{}}

  """
  def delete_unit(%Unit{} = unit) do
    unit
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Restores a soft-deleted unit.
  """
  def restore_unit(%Unit{} = unit) do
    unit
    |> Ecto.Changeset.change(deleted_at: nil)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking unit changes.

  ## Examples

      iex> change_unit(unit)
      %Ecto.Changeset{data: %Unit{}}

  """
  def change_unit(%Unit{} = unit, attrs \\ %{}) do
    Unit.changeset(unit, attrs)
  end

  @doc """
  Returns the list of pages for a unit.
  """
  def list_pages_for_unit(unit_id) do
    from(p in Page, where: p.unit_id == ^unit_id, order_by: [asc: p.position, asc: p.id])
    |> Repo.all()
  end

  @doc """
  Gets a single page.
  """
  def get_page!(id), do: Repo.get!(Page, id)

  @doc """
  Creates a page.
  """
  def create_page(attrs) do
    unit_id = attrs[:unit_id] || attrs["unit_id"]
    next_position = next_page_position(unit_id)

    %Page{}
    |> Page.changeset(attrs)
    |> Ecto.Changeset.put_change(:position, next_position)
    |> Repo.insert()
  end

  @doc """
  Updates a page.
  """
  def update_page(%Page{} = page, attrs) do
    page
    |> Page.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a page.
  """
  def delete_page(%Page{} = page) do
    Repo.delete(page)
  end

  @doc """
  Moves a page up or down within its unit ordering.
  """
  def move_page(%Page{} = page, direction) when direction in [:up, :down] do
    Repo.transaction(fn ->
      pages = list_pages_for_unit(page.unit_id)
      current_index = Enum.find_index(pages, fn candidate -> candidate.id == page.id end)

      target_index =
        case {direction, current_index} do
          {:up, nil} -> nil
          {:down, nil} -> nil
          {:up, index} when index <= 0 -> nil
          {:down, index} when index >= length(pages) - 1 -> nil
          {:up, index} -> index - 1
          {:down, index} -> index + 1
        end

      if is_nil(current_index) or is_nil(target_index) do
        Repo.rollback(:boundary)
      else
        source_page = Enum.at(pages, current_index)

        reordered_pages =
          pages
          |> List.delete_at(current_index)
          |> List.insert_at(target_index, source_page)

        Enum.with_index(reordered_pages)
        |> Enum.each(fn {reordered_page, index} ->
          {1, _} =
            from(p in Page, where: p.id == ^reordered_page.id)
            |> Repo.update_all(set: [position: index + 1])
        end)

        :moved
      end
    end)
    |> case do
      {:ok, :moved} -> {:ok, :moved}
      {:error, :boundary} -> {:error, :boundary}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking page changes.
  """
  def change_page(%Page{} = page, attrs \\ %{}) do
    Page.changeset(page, attrs)
  end

  defp get_unit_query(id, with_deleted?) do
    base_query = from(u in Unit, where: u.id == ^id)

    if with_deleted? do
      base_query
    else
      from(u in base_query, where: is_nil(u.deleted_at))
    end
  end

  defp pages_query do
    from(p in Page, order_by: [asc: p.position, asc: p.id])
  end

  defp next_page_position(unit_id) when is_integer(unit_id) do
    from(p in Page, where: p.unit_id == ^unit_id, select: max(p.position))
    |> Repo.one()
    |> case do
      nil -> 1
      current_max -> current_max + 1
    end
  end

  defp next_page_position(_), do: 1

  defp create_default_page(unit) do
    create_page(%{
      unit_id: unit.id,
      title: "Page 1",
      items: [%{"text" => "", "front" => false, "children" => []}]
    })
  end
end
