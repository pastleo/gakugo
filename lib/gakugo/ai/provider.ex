defmodule Gakugo.AI.Provider do
  @moduledoc false

  @callback list_models(keyword()) :: {:ok, [String.t()]} | {:error, term()}

  @callback structured(
              provider_config :: keyword(),
              model :: String.t(),
              content :: String.t(),
              system :: String.t(),
              format_schema :: map()
            ) :: {:ok, map()} | {:error, term()}

  @callback ocr(
              provider_config :: keyword(),
              model :: String.t(),
              image_binary :: binary(),
              prompt :: String.t()
            ) ::
              {:ok, String.t()} | {:error, term()}
end
