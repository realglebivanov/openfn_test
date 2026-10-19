defmodule OpenfnTest.Fixtures do
  @moduledoc """
  Test data helpers.
  """

  alias OpenfnTest.Accounts.Account
  alias OpenfnTest.ExchangeRates.Snapshot
  alias OpenfnTest.Repo

  def account_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    Repo.insert!(%Account{
      user_id: Map.get_lazy(attrs, :user_id, &Ecto.UUID.generate/0),
      balance: Decimal.new(Map.get(attrs, :balance, "1000.00"))
    })
  end

  def snapshot_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    rates =
      attrs
      |> Map.get(:rates, %{"EUR" => "0.92", "JPY" => "151.23", "GBP" => "0.7891"})
      |> Map.new(fn {currency, rate} -> {currency, Decimal.new(rate)} end)
      |> Map.put("USD", Decimal.new(1))

    %Snapshot{
      base: "USD",
      date: Map.get(attrs, :date, ~D[2026-10-16]),
      rates: rates,
      fetched_at: Map.get_lazy(attrs, :fetched_at, &DateTime.utc_now/0)
    }
  end

  def unique_table_name, do: :"exchange_rates_#{System.unique_integer([:positive])}"
end
