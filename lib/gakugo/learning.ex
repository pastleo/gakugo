defmodule Gakugo.Learning do
  @moduledoc """
  The Learning context.
  """

  import Ecto.Query, warn: false
  alias Gakugo.Repo

  alias Gakugo.Learning.Unit

  @doc """
  Returns the list of units.

  ## Examples

      iex> list_units()
      [%Unit{}, ...]

  """
  def list_units do
    Repo.all(Unit)
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
    do: Repo.get!(Unit, id) |> Repo.preload([:grammars, :vocabularies, :flashcards])

  @doc """
  Creates a unit.

  ## Examples

      iex> create_unit(%{field: value})
      {:ok, %Unit{}}

      iex> create_unit(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_unit(attrs) do
    %Unit{}
    |> Unit.changeset(attrs)
    |> Repo.insert()
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
  Deletes a unit.

  ## Examples

      iex> delete_unit(unit)
      {:ok, %Unit{}}

      iex> delete_unit(unit)
      {:error, %Ecto.Changeset{}}

  """
  def delete_unit(%Unit{} = unit) do
    Repo.delete(unit)
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

  alias Gakugo.Learning.Grammar

  @doc """
  Returns the list of grammars.

  ## Examples

      iex> list_grammars()
      [%Grammar{}, ...]

  """
  def list_grammars do
    Repo.all(Grammar)
  end

  @doc """
  Gets a single grammar.

  Raises `Ecto.NoResultsError` if the Grammar does not exist.

  ## Examples

      iex> get_grammar!(123)
      %Grammar{}

      iex> get_grammar!(456)
      ** (Ecto.NoResultsError)

  """
  def get_grammar!(id), do: Repo.get!(Grammar, id)

  @doc """
  Creates a grammar.

  ## Examples

      iex> create_grammar(%{field: value})
      {:ok, %Grammar{}}

      iex> create_grammar(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_grammar(attrs) do
    %Grammar{}
    |> Grammar.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a grammar.

  ## Examples

      iex> update_grammar(grammar, %{field: new_value})
      {:ok, %Grammar{}}

      iex> update_grammar(grammar, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_grammar(%Grammar{} = grammar, attrs) do
    grammar
    |> Grammar.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a grammar.

  ## Examples

      iex> delete_grammar(grammar)
      {:ok, %Grammar{}}

      iex> delete_grammar(grammar)
      {:error, %Ecto.Changeset{}}

  """
  def delete_grammar(%Grammar{} = grammar) do
    Repo.delete(grammar)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking grammar changes.

  ## Examples

      iex> change_grammar(grammar)
      %Ecto.Changeset{data: %Grammar{}}

  """
  def change_grammar(%Grammar{} = grammar, attrs \\ %{}) do
    Grammar.changeset(grammar, attrs)
  end

  alias Gakugo.Learning.Vocabulary

  @doc """
  Returns the list of vocabularies.

  ## Examples

      iex> list_vocabularies()
      [%Vocabulary{}, ...]

  """
  def list_vocabularies do
    Repo.all(Vocabulary)
  end

  @doc """
  Gets a single vocabulary.

  Raises `Ecto.NoResultsError` if the Vocabulary does not exist.

  ## Examples

      iex> get_vocabulary!(123)
      %Vocabulary{}

      iex> get_vocabulary!(456)
      ** (Ecto.NoResultsError)

  """
  def get_vocabulary!(id), do: Repo.get!(Vocabulary, id)

  @doc """
  Creates a vocabulary.

  ## Examples

      iex> create_vocabulary(%{field: value})
      {:ok, %Vocabulary{}}

      iex> create_vocabulary(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_vocabulary(attrs) do
    %Vocabulary{}
    |> Vocabulary.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a vocabulary.

  ## Examples

      iex> update_vocabulary(vocabulary, %{field: new_value})
      {:ok, %Vocabulary{}}

      iex> update_vocabulary(vocabulary, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_vocabulary(%Vocabulary{} = vocabulary, attrs) do
    vocabulary
    |> Vocabulary.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a vocabulary.

  ## Examples

      iex> delete_vocabulary(vocabulary)
      {:ok, %Vocabulary{}}

      iex> delete_vocabulary(vocabulary)
      {:error, %Ecto.Changeset{}}

  """
  def delete_vocabulary(%Vocabulary{} = vocabulary) do
    Repo.delete(vocabulary)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking vocabulary changes.

  ## Examples

      iex> change_vocabulary(vocabulary)
      %Ecto.Changeset{data: %Vocabulary{}}

  """
  def change_vocabulary(%Vocabulary{} = vocabulary, attrs \\ %{}) do
    Vocabulary.changeset(vocabulary, attrs)
  end

  alias Gakugo.Learning.Flashcard

  @doc """
  Returns the list of flashcards for a unit.

  ## Examples

      iex> list_flashcards_for_unit(unit_id)
      [%Flashcard{}, ...]

  """
  def list_flashcards_for_unit(unit_id) do
    from(f in Flashcard, where: f.unit_id == ^unit_id)
    |> Repo.all()
    |> Repo.preload(:vocabulary)
  end

  @doc """
  Gets a single flashcard.

  Raises `Ecto.NoResultsError` if the Flashcard does not exist.

  ## Examples

      iex> get_flashcard!(123)
      %Flashcard{}

      iex> get_flashcard!(456)
      ** (Ecto.NoResultsError)

  """
  def get_flashcard!(id), do: Repo.get!(Flashcard, id)

  @doc """
  Gets a flashcard by unit_id and vocabulary_id.

  Returns nil if not found.

  ## Examples

      iex> get_flashcard_by_unit_and_vocabulary(1, 2)
      %Flashcard{}

      iex> get_flashcard_by_unit_and_vocabulary(1, 999)
      nil

  """
  def get_flashcard_by_unit_and_vocabulary(unit_id, vocabulary_id) do
    Repo.get_by(Flashcard, unit_id: unit_id, vocabulary_id: vocabulary_id)
  end

  @doc """
  Creates a flashcard.

  ## Examples

      iex> create_flashcard(%{field: value})
      {:ok, %Flashcard{}}

      iex> create_flashcard(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_flashcard(attrs) do
    %Flashcard{}
    |> Flashcard.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates or updates a flashcard for a unit and vocabulary.

  If a flashcard already exists for the unit/vocabulary combination,
  it will be updated. Otherwise, a new one is created.

  ## Examples

      iex> upsert_flashcard(%{unit_id: 1, vocabulary_id: 2, front: "...", back: "..."})
      {:ok, %Flashcard{}}

  """
  def upsert_flashcard(attrs) do
    unit_id = attrs[:unit_id] || attrs["unit_id"]
    vocabulary_id = attrs[:vocabulary_id] || attrs["vocabulary_id"]

    case get_flashcard_by_unit_and_vocabulary(unit_id, vocabulary_id) do
      nil -> create_flashcard(attrs)
      flashcard -> update_flashcard(flashcard, attrs)
    end
  end

  @doc """
  Updates a flashcard.

  ## Examples

      iex> update_flashcard(flashcard, %{field: new_value})
      {:ok, %Flashcard{}}

      iex> update_flashcard(flashcard, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_flashcard(%Flashcard{} = flashcard, attrs) do
    flashcard
    |> Flashcard.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a flashcard.

  ## Examples

      iex> delete_flashcard(flashcard)
      {:ok, %Flashcard{}}

      iex> delete_flashcard(flashcard)
      {:error, %Ecto.Changeset{}}

  """
  def delete_flashcard(%Flashcard{} = flashcard) do
    Repo.delete(flashcard)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking flashcard changes.

  ## Examples

      iex> change_flashcard(flashcard)
      %Ecto.Changeset{data: %Flashcard{}}

  """
  def change_flashcard(%Flashcard{} = flashcard, attrs \\ %{}) do
    Flashcard.changeset(flashcard, attrs)
  end
end
