defmodule Gakugo.Repo do
  use Ecto.Repo,
    otp_app: :gakugo,
    adapter: Ecto.Adapters.SQLite3
end
