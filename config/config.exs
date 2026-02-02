# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :gakugo,
  ecto_repos: [Gakugo.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :gakugo, GakugoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GakugoWeb.ErrorHTML, json: GakugoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Gakugo.PubSub,
  live_view: [signing_salt: "0TKaAUlN"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :gakugo, Gakugo.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  gakugo: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  gakugo: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :pythonx, :uv_init,
  pyproject_toml: """
  [project]
  name = "project"
  version = "0.0.0"
  requires-python = "==3.13.*"
  dependencies = [
    "anki==25.7.5"
  ]
  """

config :gakugo, :ollama,
  base_url: "http://localhost:11434",
  model: "gpt-oss:20b",
  host_header: "localhost"

config :gakugo, Gakugo.Anki,
  collection_path: Path.expand("../priv/anki/collection.anki2", __DIR__),
  sync_endpoint: "http://localhost:8080/",
  sync_username: "dev",
  sync_password: "asdfasdf"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

local_config = "#{config_env()}.local.exs"

if File.exists?(Path.expand(local_config, __DIR__)) do
  import_config local_config
end
