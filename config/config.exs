# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :openfn_test,
  ecto_repos: [OpenfnTest.Repo],
  generators: [timestamp_type: :utc_datetime]

config :openfn_test,
  token_verifier: OpenfnTest.Auth.OidccVerifier,
  revocation_store: OpenfnTest.Auth.RedisRevocationStore,
  # External service processes started by the application, see OpenfnTest.Application
  services: [oidc_provider: true, redis: true, exchange_rates: true]

config :openfn_test, OpenfnTest.Auth, signing_algs: ["RS256"]

config :openfn_test, OpenfnTest.ExchangeRates,
  # How often rates are fetched
  fetch_interval: :timer.minutes(5),
  # Rates fetched longer ago than this are never used
  max_age: :timer.hours(1),
  # How long old snapshots are kept around
  retention: :timer.hours(2)

config :openfn_test, OpenfnTest.ExchangeRates.Client,
  base_url: "https://api.frankfurter.dev",
  max_attempts: 3,
  backoff_base: 500,
  backoff_max: 5_000

# Configure the endpoint
config :openfn_test, OpenfnTestWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: OpenfnTestWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: OpenfnTest.PubSub,
  live_view: [signing_salt: "LtHNMAXS"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :openfn_test, OpenfnTest.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
