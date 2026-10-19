defmodule OpenfnTestWeb.HealthcheckController do
  use OpenfnTestWeb, :controller

  alias OpenfnTest.ExchangeRates

  action_fallback OpenfnTestWeb.FallbackController

  @doc """
  Healthy only while a fresh exchange rate dictionary is cached.
  """
  def show(conn, _params) do
    with {:ok, snapshot} <- ExchangeRates.latest() do
      json(conn, %{
        status: "ok",
        exchange_rates: %{
          base: snapshot.base,
          date: Date.to_iso8601(snapshot.date),
          currencies: map_size(snapshot.rates),
          fetched_at: DateTime.to_iso8601(snapshot.fetched_at)
        }
      })
    end
  end
end
