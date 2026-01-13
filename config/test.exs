import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :gakugo, Gakugo.Repo,
  database: Path.expand("../gakugo_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :gakugo, GakugoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3kDgAo39d6FFG/EckN4ulzpZhlF7bw7aQtcRG5ZflmDVfKs4B+qVpWBJcAgTxjt3",
  server: false

# In test we don't send emails
config :gakugo, Gakugo.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :gakugo, Gakugo.Anki,
  collection_path:
    System.get_env(
      "ANKI_COLLECTION_PATH",
      Path.expand("../priv/anki/test_collection.anki2", __DIR__)
    ),
  sync_endpoint: "http://localhost:8080/",
  sync_username: "test",
  sync_password: "test"
