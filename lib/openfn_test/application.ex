defmodule OpenfnTest.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        OpenfnTestWeb.Telemetry,
        OpenfnTest.Repo
      ] ++
        service_children() ++
        [
          # Start to serve requests, typically the last entry
          OpenfnTestWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: OpenfnTest.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Processes talking to external services. Disabled in tests, which start (or mock) what they need.
  defp service_children do
    services = Application.get_env(:openfn_test, :services, [])

    [
      {:oidc_provider, OpenfnTest.Auth.OidccVerifier},
      {:redis, OpenfnTest.Auth.RedisRevocationStore},
      {:exchange_rates, OpenfnTest.ExchangeRates.Fetcher}
    ]
    |> Enum.filter(fn {service, _child} -> Keyword.get(services, service, false) end)
    |> Enum.map(fn {_service, child} -> child end)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OpenfnTestWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
