import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/gakugo start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :gakugo, GakugoWeb.Endpoint, server: true
end

config :gakugo, GakugoWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Ollama configuration
config :gakugo, :ollama,
  base_url: System.get_env("OLLAMA_BASE_URL", "http://localhost:11434"),
  model: System.get_env("OLLAMA_MODEL", "gpt-oss:20b"),
  host_header: System.get_env("OLLAMA_HOST_HEADER", "localhost")

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/gakugo/gakugo.db
      """

  config :gakugo, Gakugo.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # Anki sync configuration
  # ANKI_COLLECTION_PATH is required in production
  # ANKI_SYNC_* are optional - sync features disabled if not set
  anki_collection_path =
    System.get_env("ANKI_COLLECTION_PATH") ||
      raise """
      environment variable ANKI_COLLECTION_PATH is missing.
      For example: /var/lib/gakugo/anki/collection.anki2
      """

  anki_config = [collection_path: anki_collection_path]

  # Only add sync config if all sync env vars are present
  anki_config =
    case {System.get_env("ANKI_SYNC_ENDPOINT"), System.get_env("ANKI_SYNC_USERNAME"),
          System.get_env("ANKI_SYNC_PASSWORD")} do
      {endpoint, username, password}
      when is_binary(endpoint) and is_binary(username) and is_binary(password) ->
        anki_config ++
          [
            sync_endpoint: endpoint,
            sync_username: username,
            sync_password: password
          ]

      _ ->
        anki_config
    end

  config :gakugo, Gakugo.Anki, anki_config

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :gakugo, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :gakugo, GakugoWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :gakugo, GakugoWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :gakugo, GakugoWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :gakugo, Gakugo.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
