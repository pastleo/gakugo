defmodule Gakugo.AI.Config do
  @moduledoc """
  Centralized AI config access plus runtime model discovery cache.

  This process periodically checks configured providers and keeps discovered
  model lists in memory for fast UI reads.
  """

  use GenServer

  alias Gakugo.AI.Client

  @type usage :: :generation | :parse | :ocr
  @type provider :: :ollama | :openai | :gemini

  @providers [:ollama, :openai, :gemini]
  @default_refresh_interval_ms :timer.minutes(5)

  defstruct provider_checks: %{},
            refresh_interval_ms: @default_refresh_interval_ms,
            discovery_enabled?: true

  @type provider_check :: %{
          status: :loading | :ok | :error,
          models: [String.t()],
          error: term() | nil,
          checked_at: DateTime.t() | nil
        }

  @type t :: %__MODULE__{
          provider_checks: %{optional(provider()) => provider_check()},
          refresh_interval_ms: pos_integer(),
          discovery_enabled?: boolean()
        }

  # ---------------------------------------------------------------------------
  # Static config API
  # ---------------------------------------------------------------------------

  @spec raw() :: keyword()
  def raw, do: Application.get_env(:gakugo, :ai, [])

  @spec providers() :: keyword()
  def providers, do: Keyword.get(raw(), :providers, [])

  @spec provider_config(provider()) :: keyword()
  def provider_config(provider) when provider in @providers do
    providers() |> Keyword.get(provider, [])
  end

  @spec defaults() :: keyword()
  def defaults, do: Keyword.get(raw(), :defaults, [])

  @spec usage_default(usage()) :: keyword()
  def usage_default(usage) when usage in [:generation, :parse, :ocr] do
    defaults() |> Keyword.get(usage, [])
  end

  @spec usage_provider(usage()) :: provider() | nil
  def usage_provider(usage) when usage in [:generation, :parse, :ocr] do
    usage_default(usage) |> Keyword.get(:provider)
  end

  @spec usage_model(usage()) :: String.t() | nil
  def usage_model(usage) when usage in [:generation, :parse, :ocr] do
    usage_default(usage) |> Keyword.get(:model)
  end

  @spec effective() :: map()
  def effective do
    %{
      providers: %{
        ollama: sanitize_provider(provider_config(:ollama)),
        openai: sanitize_provider(provider_config(:openai)),
        gemini: sanitize_provider(provider_config(:gemini))
      },
      defaults: %{
        generation: sanitize_defaults(usage_default(:generation)),
        parse: sanitize_defaults(usage_default(:parse)),
        ocr: sanitize_defaults(usage_default(:ocr))
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Runtime model discovery API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec refresh() :: :ok
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  catch
    :exit, _ -> :ok
  end

  @spec runtime_snapshot() :: map()
  def runtime_snapshot do
    safe_call(:runtime_snapshot, default_runtime_snapshot())
  end

  @spec usage_models(usage()) :: [String.t()]
  def usage_models(usage) when usage in [:generation, :parse, :ocr] do
    runtime_snapshot().usages[usage].models
  end

  @spec usage_model_options(usage()) :: [{String.t(), String.t()}]
  def usage_model_options(usage) when usage in [:generation, :parse, :ocr] do
    usage
    |> usage_models()
    |> Enum.map(&{&1, &1})
  end

  @spec usage_available?(usage()) :: boolean()
  def usage_available?(usage) when usage in [:generation, :parse, :ocr] do
    usage_models(usage) != []
  end

  @spec usage_error(usage()) :: String.t() | nil
  def usage_error(usage) when usage in [:generation, :parse, :ocr] do
    runtime_snapshot().usages[usage].error
  end

  @impl true
  def init(_opts) do
    refresh_interval_ms =
      Keyword.get(raw(), :model_refresh_interval_ms, @default_refresh_interval_ms)

    discovery_enabled? = Keyword.get(raw(), :model_discovery_enabled, true)

    state = %__MODULE__{
      provider_checks:
        if(discovery_enabled?, do: default_provider_checks(), else: disabled_provider_checks()),
      refresh_interval_ms: refresh_interval_ms,
      discovery_enabled?: discovery_enabled?
    }

    if discovery_enabled? do
      send(self(), :refresh)
    end

    {:ok, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, maybe_discover_models(state)}
  end

  @impl true
  def handle_info(:refresh, state) do
    state = maybe_discover_models(state)
    Process.send_after(self(), :refresh, state.refresh_interval_ms)
    {:noreply, state}
  end

  defp maybe_discover_models(%__MODULE__{discovery_enabled?: true} = state),
    do: discover_models(state)

  defp maybe_discover_models(%__MODULE__{} = state),
    do: %{state | provider_checks: disabled_provider_checks()}

  @impl true
  def handle_call(:runtime_snapshot, _from, state) do
    {:reply, runtime_snapshot_from_state(state), state}
  end

  defp discover_models(state) do
    checks =
      Enum.into(@providers, %{}, fn provider ->
        {provider, safe_discover_provider(provider)}
      end)

    %{state | provider_checks: checks}
  end

  defp safe_discover_provider(provider) do
    discover_provider(provider)
  rescue
    error -> provider_error({:exception, Exception.message(error)})
  catch
    :exit, reason -> provider_error({:exit, reason})
    kind, reason -> provider_error({kind, reason})
  end

  defp discover_provider(provider) do
    case Client.list_models(provider) do
      {:ok, model_names} -> provider_ok(model_names)
      {:error, reason} -> provider_error(reason)
    end
  end

  defp runtime_snapshot_from_state(state) do
    %{
      providers: state.provider_checks,
      usages: %{
        generation: usage_runtime(:generation, state.provider_checks),
        parse: usage_runtime(:parse, state.provider_checks),
        ocr: usage_runtime(:ocr, state.provider_checks)
      }
    }
  end

  defp default_runtime_snapshot do
    checks = default_provider_checks()

    %{
      providers: checks,
      usages: %{
        generation: usage_runtime(:generation, checks),
        parse: usage_runtime(:parse, checks),
        ocr: usage_runtime(:ocr, checks)
      }
    }
  end

  defp usage_runtime(usage, checks) do
    provider = usage_provider(usage)
    default_model = usage_model(usage)

    check =
      case provider do
        selected when selected in @providers -> Map.get(checks, selected, provider_loading())
        _ -> provider_error_entry(:missing_provider)
      end

    models = prioritize_default_model(check.models, default_model)

    %{
      provider: provider,
      status: usage_status(check.status, models),
      models: models,
      error: usage_error_message(provider, check, models)
    }
  end

  defp usage_status(:loading, _models), do: :loading
  defp usage_status(_status, []), do: :error
  defp usage_status(_status, _models), do: :ok

  defp usage_error_message(_provider, %{status: :loading}, _models), do: nil

  defp usage_error_message(provider, %{error: reason}, _models) when not is_nil(reason) do
    provider_label = provider |> to_string() |> String.capitalize()
    "#{provider_label} model check failed: #{inspect(reason)}"
  end

  defp usage_error_message(_provider, _check, []),
    do: "No models available for this provider"

  defp usage_error_message(_provider, _check, _models), do: nil

  defp provider_loading do
    %{status: :loading, models: [], error: nil, checked_at: nil}
  end

  defp provider_error_entry(reason) do
    %{status: :error, models: [], error: reason, checked_at: DateTime.utc_now()}
  end

  defp provider_ok(models) do
    %{status: :ok, models: models, error: nil, checked_at: DateTime.utc_now()}
  end

  defp provider_error(reason), do: provider_error_entry(reason)

  defp default_provider_checks do
    Enum.into(@providers, %{}, fn provider -> {provider, provider_loading()} end)
  end

  defp disabled_provider_checks do
    Enum.into(@providers, %{}, fn provider -> {provider, provider_error_entry(:disabled)} end)
  end

  defp prioritize_default_model(models, default_model) do
    cond do
      not is_binary(default_model) or default_model == "" -> models
      default_model in models -> [default_model | Enum.reject(models, &(&1 == default_model))]
      true -> models
    end
  end

  defp safe_call(message, fallback) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, message)
    else
      fallback
    end
  catch
    :exit, _ -> fallback
  end

  defp sanitize_provider(config) do
    %{
      base_url: Keyword.get(config, :base_url),
      host_header: Keyword.get(config, :host_header),
      api_key_present?: present?(Keyword.get(config, :api_key)),
      api_key_preview: api_key_preview(Keyword.get(config, :api_key))
    }
  end

  defp sanitize_defaults(config) do
    %{
      provider: Keyword.get(config, :provider),
      model: Keyword.get(config, :model)
    }
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp api_key_preview(value) when is_binary(value) and byte_size(value) > 8 do
    prefix = binary_part(value, 0, 4)
    suffix = binary_part(value, byte_size(value) - 4, 4)
    "#{prefix}...#{suffix}"
  end

  defp api_key_preview(value) when is_binary(value) and value != "", do: "***"
  defp api_key_preview(_value), do: nil
end
