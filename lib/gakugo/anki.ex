defmodule Gakugo.Anki do
  @moduledoc """
  Anki integration layer for managing flashcard decks via PythonX.

  This module provides a GenServer that serializes access to the Anki collection
  file, supporting CRUD operations for decks, models (note types), and notes.

  The collection file is opened on-demand and closed after each operation to
  minimize lock contention with the Anki sync server.
  """
  use GenServer

  require Logger

  @type deck_id :: integer()
  @type note_id :: integer()
  @type model_id :: integer()

  @type note :: %{
          id: note_id() | nil,
          model_name: String.t(),
          fields: %{String.t() => String.t()},
          tags: [String.t()],
          deck_name: String.t()
        }

  @type model :: %{
          name: String.t(),
          fields: [String.t()],
          templates: [%{name: String.t(), qfmt: String.t(), afmt: String.t()}],
          css: String.t()
        }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Ensures a deck exists, creating it if necessary.
  Returns `{:ok, deck_id}` or `{:error, reason}`.
  """
  @spec ensure_deck(String.t()) :: {:ok, deck_id()} | {:error, term()}
  def ensure_deck(deck_name) do
    GenServer.call(__MODULE__, {:ensure_deck, deck_name})
  end

  @doc """
  Lists all deck names.
  """
  @spec list_decks() :: {:ok, [String.t()]} | {:error, term()}
  def list_decks do
    GenServer.call(__MODULE__, :list_decks)
  end

  @doc """
  Ensures a model (note type) exists with the given configuration.
  Creates or updates as needed.
  """
  @spec ensure_model(model()) :: {:ok, model_id()} | {:error, term()}
  def ensure_model(model) do
    GenServer.call(__MODULE__, {:ensure_model, model})
  end

  @doc """
  Lists all model names.
  """
  @spec list_models() :: {:ok, [String.t()]} | {:error, term()}
  def list_models do
    GenServer.call(__MODULE__, :list_models)
  end

  @doc """
  Adds a new note to the collection.
  Returns `{:ok, note_id}` or `{:error, reason}`.
  """
  @spec add_note(note()) :: {:ok, note_id()} | {:error, term()}
  def add_note(note) do
    GenServer.call(__MODULE__, {:add_note, note})
  end

  @doc """
  Updates an existing note.
  """
  @spec update_note(note()) :: :ok | {:error, term()}
  def update_note(note) do
    GenServer.call(__MODULE__, {:update_note, note})
  end

  @doc """
  Deletes a note by ID.
  """
  @spec delete_note(note_id()) :: :ok | {:error, term()}
  def delete_note(note_id) do
    GenServer.call(__MODULE__, {:delete_note, note_id})
  end

  @doc """
  Finds notes matching a query string (Anki search syntax).
  Returns list of note IDs.
  """
  @spec find_notes(String.t()) :: {:ok, [note_id()]} | {:error, term()}
  def find_notes(query) do
    GenServer.call(__MODULE__, {:find_notes, query})
  end

  @doc """
  Gets a note by ID with all its fields.
  """
  @spec get_note(note_id()) :: {:ok, note()} | {:error, term()}
  def get_note(note_id) do
    GenServer.call(__MODULE__, {:get_note, note_id})
  end

  @doc """
  Syncs the local collection with the remote sync server.
  Returns sync status information.
  """
  @spec sync() :: {:ok, map()} | {:error, term()}
  def sync do
    GenServer.call(__MODULE__, :sync, :infinity)
  end

  @doc """
  Performs a full upload, replacing the server's collection with local.
  """
  @spec full_upload() :: {:ok, map()} | {:error, term()}
  def full_upload do
    GenServer.call(__MODULE__, :full_upload, :infinity)
  end

  @doc """
  Performs a full download, replacing local collection with server's.
  """
  @spec full_download() :: {:ok, map()} | {:error, term()}
  def full_download do
    GenServer.call(__MODULE__, :full_download, :infinity)
  end

  @impl true
  def init(_opts) do
    {:ok, %{python_globals: nil}}
  end

  @impl true
  def handle_call(request, _from, state) do
    state = ensure_python_initialized(state)

    case execute_request(request, state) do
      {:ok, result, new_state} ->
        {:reply, {:ok, result}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}

      {:ok_no_result, new_state} ->
        {:reply, :ok, new_state}
    end
  end

  defp ensure_python_initialized(%{python_globals: nil} = state) do
    Logger.debug("Gakugo.Anki: initializing python_globals...")

    Application.app_dir(:gakugo, "priv/anki/anki.py")
    |> File.read!()
    |> Pythonx.eval(%{})
    |> then(fn {_, python_globals} ->
      %{state | python_globals: python_globals}
    end)
  end

  defp ensure_python_initialized(state), do: state

  defp execute_request({:ensure_deck, deck_name}, state) do
    collection_path = get_collection_path()

    try do
      {result, _} =
        Pythonx.eval(
          ~s|ensure_deck("#{escape(collection_path)}", "#{escape(deck_name)}")|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.ensure_deck failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request(:list_decks, state) do
    collection_path = get_collection_path()

    try do
      {result, _} =
        Pythonx.eval(
          ~s|list_decks("#{escape(collection_path)}")|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.list_decks failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request({:ensure_model, model}, state) do
    collection_path = get_collection_path()
    model_json = Jason.encode!(model)

    try do
      {result, _} =
        Pythonx.eval(
          ~s|ensure_model("#{escape(collection_path)}", '#{escape_json(model_json)}')|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.ensure_model failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request(:list_models, state) do
    collection_path = get_collection_path()

    try do
      {result, _} =
        Pythonx.eval(
          ~s|list_models("#{escape(collection_path)}")|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.list_models failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request({:add_note, note}, state) do
    collection_path = get_collection_path()
    note_json = Jason.encode!(note)

    try do
      {result, _} =
        Pythonx.eval(
          ~s|add_note("#{escape(collection_path)}", '#{escape_json(note_json)}')|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.add_note failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request({:update_note, note}, state) do
    collection_path = get_collection_path()
    note_json = Jason.encode!(note)

    try do
      Pythonx.eval(
        ~s|update_note("#{escape(collection_path)}", '#{escape_json(note_json)}')|,
        state.python_globals
      )

      {:ok_no_result, state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.update_note failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request({:delete_note, note_id}, state) do
    collection_path = get_collection_path()

    try do
      Pythonx.eval(
        ~s|delete_note("#{escape(collection_path)}", #{note_id})|,
        state.python_globals
      )

      {:ok_no_result, state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.delete_note failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request({:find_notes, query}, state) do
    collection_path = get_collection_path()

    try do
      {result, _} =
        Pythonx.eval(
          ~s|find_notes("#{escape(collection_path)}", "#{escape(query)}")|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.find_notes failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request({:get_note, note_id}, state) do
    collection_path = get_collection_path()

    try do
      {result, _} =
        Pythonx.eval(
          ~s|get_note("#{escape(collection_path)}", #{note_id})|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.get_note failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request(:sync, state) do
    collection_path = get_collection_path()
    {username, password, endpoint} = get_sync_credentials()

    try do
      {result, _} =
        Pythonx.eval(
          ~s|sync_collection("#{escape(collection_path)}", "#{escape(username)}", "#{escape(password)}", "#{escape(endpoint)}")|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.sync failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request(:full_upload, state) do
    collection_path = get_collection_path()
    {username, password, endpoint} = get_sync_credentials()

    try do
      {result, _} =
        Pythonx.eval(
          ~s|full_upload("#{escape(collection_path)}", "#{escape(username)}", "#{escape(password)}", "#{escape(endpoint)}")|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.full_upload failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp execute_request(:full_download, state) do
    collection_path = get_collection_path()
    {username, password, endpoint} = get_sync_credentials()

    try do
      {result, _} =
        Pythonx.eval(
          ~s|full_download("#{escape(collection_path)}", "#{escape(username)}", "#{escape(password)}", "#{escape(endpoint)}")|,
          state.python_globals
        )

      {:ok, Pythonx.decode(result), state}
    rescue
      error ->
        Logger.error("Gakugo.Anki.full_download failed: #{inspect(error)}")
        {:error, error, state}
    end
  end

  defp get_collection_path do
    Application.get_env(:gakugo, __MODULE__)[:collection_path] ||
      raise "Anki collection_path not configured"
  end

  defp get_sync_credentials do
    config = Application.get_env(:gakugo, __MODULE__)

    username = config[:sync_username] || raise "Anki sync_username not configured"
    password = config[:sync_password] || raise "Anki sync_password not configured"
    endpoint = config[:sync_endpoint] || raise "Anki sync_endpoint not configured"

    {username, password, endpoint}
  end

  defp escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp escape_json(json) do
    json
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
  end
end
